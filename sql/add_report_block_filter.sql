-- ============================================================
-- add_report_block_filter.sql  (2026-10-12)
-- ============================================================
-- Apple App Review guideline 1.2 (apps with user-generated content) needs:
-- a way to report offensive content, a way to block abusive users, and a
-- filter on objectionable material. This adds all three on the database side.
--
--   * reports        -- one row per report. Written only via submit_report()
--                       (which snapshots the reported text, so the report
--                       survives the content being removed). Admins read and
--                       resolve them via get_reports() / resolve_report().
--   * blocked_users  -- one-way block: the blocker stops seeing the blocked
--                       person's content (filtered in the app) and gets no
--                       comment alerts from them (notify_show_comment below).
--                       The blocked person is not told.
--   * Word filter    -- a trigger on comments, Lounge posts and replies that
--                       refuses slurs and sexually explicit terms (everyday
--                       swearing is allowed). The app checks the same list
--                       first so people get a friendly message; this is the
--                       backstop that can't be bypassed.
--
-- Run in the Supabase SQL editor. Safe to re-run.
-- ============================================================

-- ---------- reports ----------------------------------------------------
create table if not exists reports (
  id               uuid primary key default gen_random_uuid(),
  reporter_id      uuid not null references auth.users(id) on delete cascade,
  target_type      text not null check (target_type in ('comment', 'lounge_post', 'lounge_reply', 'user')),
  target_id        uuid not null,
  target_user_id   uuid references auth.users(id) on delete set null,
  reason           text not null,
  note             text,
  content_snapshot text,
  status           text not null default 'open' check (status in ('open', 'removed', 'dismissed')),
  created_at       timestamptz not null default now(),
  resolved_at      timestamptz,
  resolved_by      uuid references auth.users(id) on delete set null
);
create index if not exists reports_status_idx on reports (status, created_at desc);

alter table reports enable row level security;
do $$ begin
  create policy "read own reports" on reports for select using (auth.uid() = reporter_id);
exception when duplicate_object then null; end $$;

-- What did I report? (the app hides those items for the reporter)
create or replace function submit_report(p_target_type text, p_target_id uuid, p_reason text, p_note text, p_target_user_id uuid default null)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_uid uuid := auth.uid();
  v_owner uuid := p_target_user_id;
  v_text text;
  v_id uuid;
begin
  if v_uid is null then raise exception 'Not authenticated'; end if;
  if p_target_type = 'comment' then
    select user_id, text into v_owner, v_text from reactions where id = p_target_id;
  elsif p_target_type = 'lounge_post' then
    select user_id, body into v_owner, v_text from lounge_posts where id = p_target_id;
  elsif p_target_type = 'lounge_reply' then
    select user_id, body into v_owner, v_text from lounge_replies where id = p_target_id;
  elsif p_target_type = 'user' then
    v_owner := p_target_id;
  else
    raise exception 'Unknown report type';
  end if;
  if v_owner = v_uid then raise exception 'You can''t report yourself'; end if;

  insert into reports (reporter_id, target_type, target_id, target_user_id, reason, note, content_snapshot)
  values (v_uid, p_target_type, p_target_id, v_owner, left(coalesce(p_reason, 'other'), 60), left(p_note, 1000), left(v_text, 4000))
  returning id into v_id;
  return v_id;
end;
$$;
grant execute on function submit_report(text, uuid, text, text, uuid) to authenticated;

-- Admin: reports with names, newest first.
create or replace function get_reports(p_status text default 'open')
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if not user_is_admin() then raise exception 'Admin only'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', r.id, 'target_type', r.target_type, 'target_id', r.target_id,
      'reason', r.reason, 'note', r.note, 'content', r.content_snapshot,
      'status', r.status, 'created_at', r.created_at,
      'reporter', coalesce(ru.first_name || ' ' || coalesce(ru.last_initial, ''), 'Someone'),
      'reported_user_id', r.target_user_id,
      'reported', coalesce(tu.first_name || ' ' || coalesce(tu.last_initial, ''), 'Unknown')
    ) order by r.created_at desc)
    from reports r
    left join users ru on ru.id = r.reporter_id
    left join users tu on tu.id = r.target_user_id
    where p_status is null or r.status = p_status
  ), '[]'::jsonb);
end;
$$;
grant execute on function get_reports(text) to authenticated;

-- Admin: 'remove' deletes the reported content (comments/posts only) and
-- closes every open report about it; 'dismiss' just closes this report.
create or replace function resolve_report(p_report_id uuid, p_action text)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  r record;
begin
  if not user_is_admin() then raise exception 'Admin only'; end if;
  select * into r from reports where id = p_report_id;
  if not found then raise exception 'Report not found'; end if;

  if p_action = 'remove' then
    if r.target_type = 'comment' then delete from reactions where id = r.target_id;
    elsif r.target_type = 'lounge_post' then delete from lounge_posts where id = r.target_id;
    elsif r.target_type = 'lounge_reply' then delete from lounge_replies where id = r.target_id;
    end if;
    update reports set status = 'removed', resolved_at = now(), resolved_by = auth.uid()
     where target_type = r.target_type and target_id = r.target_id and status = 'open';
  elsif p_action = 'dismiss' then
    update reports set status = 'dismissed', resolved_at = now(), resolved_by = auth.uid() where id = p_report_id;
  else
    raise exception 'Unknown action';
  end if;
end;
$$;
grant execute on function resolve_report(uuid, text) to authenticated;

-- ---------- blocked_users ----------------------------------------------
create table if not exists blocked_users (
  user_id         uuid not null references auth.users(id) on delete cascade,
  blocked_user_id uuid not null references auth.users(id) on delete cascade,
  created_at      timestamptz not null default now(),
  primary key (user_id, blocked_user_id),
  check (user_id <> blocked_user_id)
);

alter table blocked_users enable row level security;
do $$ begin
  create policy "read own blocks" on blocked_users for select using (auth.uid() = user_id);
exception when duplicate_object then null; end $$;
do $$ begin
  create policy "add own blocks" on blocked_users for insert with check (auth.uid() = user_id);
exception when duplicate_object then null; end $$;
do $$ begin
  create policy "remove own blocks" on blocked_users for delete using (auth.uid() = user_id);
exception when duplicate_object then null; end $$;

-- Settings > Blocked people: names for the people I've blocked.
create or replace function get_blocked_users()
returns jsonb
language sql
security definer
set search_path to 'public'
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', b.blocked_user_id,
    'name', coalesce(u.first_name || ' ' || coalesce(u.last_initial, '') || '.', 'Someone')
  ) order by b.created_at desc), '[]'::jsonb)
  from blocked_users b
  left join users u on u.id = b.blocked_user_id
  where b.user_id = auth.uid();
$$;
grant execute on function get_blocked_users() to authenticated;

-- ---------- word filter --------------------------------------------------
-- Slurs and sexually explicit terms only; everyday swearing is allowed.
-- Keep in sync with OBJECTIONABLE_RE in index.html.
create or replace function objectionable_text(p_text text)
returns boolean
language sql
immutable
as $$
  select coalesce(p_text, '') ~* ('\m(' ||
    'n[i1]gg(er|a|ah|az|ers|as)|ch[i1]nks?|g[o0][o0]ks?|sp[i1]cs?|k[i1]kes?|wetbacks?|beaners?|ragheads?|towelheads?|' ||
    'f[a@]gg?[o0]ts?|f[a@]gs|trann(y|ies)|retards?|retarded|' ||
    'c[u\*]nts?|cocksuckers?|motherfuckin|whores?|sluts?|blowjobs?|cumshots?|gangbangs?|' ||
    'porn(o|hub)?' ||
  ')\M');
$$;

create or replace function reject_objectionable_text()
returns trigger
language plpgsql
as $$
declare
  v_text text;
begin
  if tg_table_name = 'reactions' then v_text := new.text; else v_text := new.body; end if;
  if objectionable_text(v_text) then
    raise exception 'objectionable_content' using hint = 'Let''s keep it friendly. Please edit your comment.';
  end if;
  return new;
end;
$$;

drop trigger if exists reactions_word_filter on reactions;
create trigger reactions_word_filter before insert or update of text on reactions
  for each row execute function reject_objectionable_text();
drop trigger if exists lounge_posts_word_filter on lounge_posts;
create trigger lounge_posts_word_filter before insert or update of body on lounge_posts
  for each row execute function reject_objectionable_text();
drop trigger if exists lounge_replies_word_filter on lounge_replies;
create trigger lounge_replies_word_filter before insert or update of body on lounge_replies
  for each row execute function reject_objectionable_text();

-- ---------- no comment alerts from people you've blocked ----------------
-- Same as add_push_alerts.sql's notify_show_comment, plus one line: skip
-- anyone who has blocked the commenter.
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
      and not exists (select 1 from blocked_users bu where bu.user_id = c.tgt and bu.blocked_user_id = v_uid)
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
