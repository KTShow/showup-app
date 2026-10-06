-- ============================================================
-- add_push_alerts.sql  (2026-10-06)
-- ============================================================
-- Phone / desktop alerts (Web Push), first alert type: comments.
--
--   * push_subscriptions -- one row per device that tapped "Turn on alerts".
--     Written only through save_/delete_push_subscription (so a shared
--     device that switches accounts re-homes cleanly). Read by /api/push
--     with the service role.
--   * notification_prefs.comments -- Settings toggle; off = no bell row and
--     no alert for comments.
--   * notifications.push_pending / pushed_at -- the hand-off to /api/push.
--     The database decides WHO gets alerted; /api/push only delivers rows
--     marked pending, claiming them atomically (claim_pending_pushes) so a
--     row is never pushed twice.
--   * notify_show_comment(reaction_id) -- called by the app right after a
--     comment is posted. Fans out to everyone who can see that comment:
--     the show's owner + every participant of a room the commenter and the
--     owner share (mirrors get_living_room_data's visibility rule), minus
--     the commenter, anyone who muted them, and anyone with comment alerts
--     off. Bundles: one alert per person per show per hour -- later
--     comments in that hour update the same bell row ("Janet S. and 2
--     others commented") without pushing again.
--
-- Run in the Supabase SQL editor. Safe to re-run.
-- ============================================================

-- ---------- push_subscriptions -----------------------------------------
create table if not exists push_subscriptions (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  endpoint    text not null unique,
  p256dh      text not null,
  auth        text not null,
  user_agent  text,
  created_at  timestamptz not null default now()
);

create index if not exists push_subscriptions_user_idx on push_subscriptions (user_id);

alter table push_subscriptions enable row level security;

do $$ begin
  create policy "read own push subscriptions" on push_subscriptions
    for select using (auth.uid() = user_id);
exception when duplicate_object then null; end $$;

create or replace function save_push_subscription(p_endpoint text, p_p256dh text, p_auth text, p_user_agent text)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  insert into push_subscriptions (user_id, endpoint, p256dh, auth, user_agent)
  values (auth.uid(), p_endpoint, p_p256dh, p_auth, left(p_user_agent, 300))
  on conflict (endpoint) do update
    set user_id = auth.uid(), p256dh = excluded.p256dh, auth = excluded.auth,
        user_agent = excluded.user_agent, created_at = now();
end;
$$;

create or replace function delete_push_subscription(p_endpoint text)
returns void
language sql
security definer
set search_path to 'public'
as $$
  delete from push_subscriptions where endpoint = p_endpoint and user_id = auth.uid();
$$;

grant execute on function save_push_subscription(text, text, text, text) to authenticated;
grant execute on function delete_push_subscription(text) to authenticated;

-- ---------- prefs + notification columns -------------------------------
alter table notification_prefs add column if not exists comments boolean not null default true;

alter table notifications add column if not exists push_pending boolean not null default false;
alter table notifications add column if not exists pushed_at    timestamptz;
alter table notifications add column if not exists meta         jsonb;

create index if not exists notifications_push_pending_idx
  on notifications (created_at) where push_pending;

-- Guards against the app (or a retry) notifying for the same comment twice.
alter table reactions add column if not exists notified_at timestamptz;

-- ---------- notify_show_comment ----------------------------------------
create or replace function notify_show_comment(p_reaction_id uuid)
returns integer
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_uid      uuid := auth.uid();
  v_r        record;
  v_show     record;
  v_name     text;
  v_snippet  text;
  v_now      timestamptz := now();
  t          record;
  v_existing record;
  v_actors   jsonb;
  v_others   integer;
  v_count    integer := 0;
begin
  if v_uid is null then raise exception 'Not authenticated'; end if;

  -- Only your own, fresh, not-yet-notified comment.
  update reactions set notified_at = v_now
   where id = p_reaction_id and user_id = v_uid and notified_at is null
     and reacted_at > v_now - interval '10 minutes'
  returning id, show_id, text into v_r;
  if not found then return 0; end if;

  select id, user_id, title, hidden, tmdb_id into v_show from shows where id = v_r.show_id;
  if not found then return 0; end if;

  select first_name || coalesce(' ' || nullif(last_initial, '') || '.', '') into v_name
    from users where id = v_uid;
  v_name := coalesce(v_name, 'Someone');
  v_snippet := left(regexp_replace(coalesce(v_r.text, ''), '\s+', ' ', 'g'), 90);

  for t in
    with parts as (
      select living_room_id as room_id, user_id from living_room_members where status = 'active'
      union
      select id, owner_id from living_rooms
    ),
    shared as (
      select a.room_id from parts a join parts b on a.room_id = b.room_id
      where a.user_id = v_uid and b.user_id = v_show.user_id
    ),
    cands as (
      select p.user_id as tgt, p.room_id from parts p
      where not v_show.hidden and p.room_id in (select room_id from shared)
      union all
      select v_show.user_id, null::uuid
    )
    select c.tgt, (array_agg(c.room_id) filter (where c.room_id is not null))[1] as room_id
    from cands c
    where c.tgt is not null and c.tgt <> v_uid
      and not exists (select 1 from muted_friends m where m.user_id = c.tgt and m.muted_user_id = v_uid)
      and coalesce((select np.comments from notification_prefs np where np.user_id = c.tgt), true)
    group by c.tgt
  loop
    select id, meta into v_existing from notifications
     where user_id = t.tgt and type = 'comment' and dismissed_at is null
       and lower(title) = lower(v_show.title)
       and created_at > v_now - interval '1 hour'
     order by created_at desc limit 1;

    if found then
      v_actors := coalesce(v_existing.meta -> 'actors', '[]'::jsonb);
      if not v_actors @> to_jsonb(v_uid::text) then
        v_actors := v_actors || jsonb_build_array(v_uid::text);
      end if;
      v_others := jsonb_array_length(v_actors) - 1;
      update notifications set
        body = case when v_others = 0 then v_name || ': ' || v_snippet
                    else v_name || ' and ' || v_others || case when v_others = 1 then ' other' else ' others' end || ' commented' end,
        meta = jsonb_build_object('actors', v_actors),
        room_id = coalesce(room_id, t.room_id),
        seen_at = null,
        read_at = null
      where id = v_existing.id;
    else
      insert into notifications (user_id, type, title, body, show_id, tmdb_id, room_id, entity_id, meta, push_pending, created_at)
      values (t.tgt, 'comment', v_show.title, v_name || ': ' || v_snippet, v_show.id, v_show.tmdb_id,
              t.room_id, v_r.id, jsonb_build_object('actors', jsonb_build_array(v_uid::text)), true, v_now);
    end if;
    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$$;

grant execute on function notify_show_comment(uuid) to authenticated;

-- ---------- claim_pending_pushes (service role only) -------------------
-- Rows older than 15 minutes are dropped rather than pushed late.
create or replace function claim_pending_pushes()
returns setof notifications
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  update notifications set push_pending = false
   where push_pending and created_at <= now() - interval '15 minutes';
  return query
    with claimed as (
      update notifications set push_pending = false, pushed_at = now()
       where push_pending
      returning *
    )
    select * from claimed;
end;
$$;

revoke execute on function claim_pending_pushes() from public, anon, authenticated;
grant execute on function claim_pending_pushes() to service_role;
