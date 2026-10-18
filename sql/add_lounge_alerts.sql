-- ============================================================
-- add_lounge_alerts.sql  (2026-10-18)
-- ============================================================
-- Phone/desktop alerts for The Lounge, via the same push_pending
-- hand-off comments use (sql/add_push_alerts.sql -> /api/push).
--
--   * New post  -> everyone in that room (type 'lounge_post'). At most
--     one alert per poster per room per hour: a second post within the
--     hour just refreshes the existing row (points it at the newest
--     post) without pushing again.
--   * New reply -> the post's author + everyone who already replied
--     (type 'lounge_reply', as before -- now also pushed).
--   * Both honour a new Settings switch, notification_prefs.lounge
--     ("Lounge posts & replies"), plus mutes and blocks.
--
-- Run in the Supabase SQL editor BEFORE deploying the app change (the
-- Settings toggles save the new 'lounge' column). Safe to re-run.
-- ============================================================

alter table notification_prefs add column if not exists lounge boolean not null default true;

-- ---------- new post -> whole room (insert trigger) ------------------
create or replace function notify_lounge_post()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_name      text;
  v_room_name text;
  v_snippet   text;
  t           record;
  v_existing  uuid;
begin
  select first_name || coalesce(' ' || nullif(last_initial, '') || '.', '') into v_name
    from users where id = new.user_id;
  v_name := coalesce(v_name, 'Someone');
  select name into v_room_name from living_rooms where id = new.living_room_id;
  v_snippet := left(regexp_replace(coalesce(new.body, ''), '\s+', ' ', 'g'), 90);

  for t in
    select distinct p.user_id as tgt from (
      select user_id from living_room_members where living_room_id = new.living_room_id and status = 'active'
      union
      select owner_id from living_rooms where id = new.living_room_id
    ) p
    where p.user_id is not null and p.user_id <> new.user_id
      and not exists (select 1 from muted_friends m where m.user_id = p.user_id and m.muted_user_id = new.user_id)
      and not exists (select 1 from blocked_users bu where bu.user_id = p.user_id and bu.blocked_user_id = new.user_id)
      and coalesce((select np.lounge from notification_prefs np where np.user_id = p.user_id), true)
  loop
    select id into v_existing from notifications
     where user_id = t.tgt and type = 'lounge_post' and room_id = new.living_room_id
       and meta -> 'actors' @> to_jsonb(new.user_id::text)
       and created_at > now() - interval '1 hour'
     order by created_at desc limit 1;

    if found then
      update notifications set entity_id = new.id, body = v_name || ' posted: ' || v_snippet,
             seen_at = null, read_at = null
       where id = v_existing;
    else
      insert into notifications (user_id, type, title, body, room_id, entity_id, meta, push_pending, created_at)
      values (t.tgt, 'lounge_post', coalesce(v_room_name, 'The Lounge'), v_name || ' posted: ' || v_snippet,
              new.living_room_id, new.id, jsonb_build_object('actors', jsonb_build_array(new.user_id::text)),
              true, now());
    end if;
  end loop;
  return new;
end;
$$;

drop trigger if exists lounge_posts_notify on lounge_posts;
create trigger lounge_posts_notify
  after insert on lounge_posts
  for each row execute function notify_lounge_post();

-- ---------- new reply -> thread (replaces sql/add_lounge.sql version) --
create or replace function add_lounge_reply(p_post_id uuid, p_body text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_uid         uuid := auth.uid();
  v_room        uuid;
  v_post_author uuid;
  v_reply_id    uuid;
  v_now         timestamptz := now();
  v_name        text;
  v_room_name   text;
begin
  if v_uid is null then raise exception 'Not authenticated'; end if;
  if p_body is null or char_length(btrim(p_body)) = 0 then raise exception 'Empty reply'; end if;
  if char_length(p_body) > 4000 then raise exception 'Reply too long'; end if;

  select p.living_room_id, p.user_id into v_room, v_post_author
    from lounge_posts p where p.id = p_post_id;
  if v_room is null then raise exception 'Post not found'; end if;
  if not (user_owns_room(v_room) or user_is_in_room(v_room)) then
    raise exception 'Not a member of this room';
  end if;

  insert into lounge_replies (post_id, user_id, body, created_at)
  values (p_post_id, v_uid, p_body, v_now)
  returning id into v_reply_id;

  update lounge_posts set last_activity_at = v_now where id = p_post_id;

  select first_name || coalesce(' ' || nullif(last_initial, '') || '.', '') into v_name from users where id = v_uid;
  v_name := coalesce(v_name, 'Someone');
  select name into v_room_name from living_rooms where id = v_room;

  -- Notify the post author + everyone who has already replied, minus the
  -- person replying now (and anyone who muted/blocked them or switched
  -- Lounge alerts off). Collapse to one unseen notification per thread
  -- per person (clear the prior unseen one, drop in a fresh one).
  with targets as (
    select x.tgt from (
      select v_post_author as tgt
      union
      select user_id from lounge_replies where post_id = p_post_id
    ) x
    where x.tgt is not null and x.tgt <> v_uid
      and not exists (select 1 from muted_friends m where m.user_id = x.tgt and m.muted_user_id = v_uid)
      and not exists (select 1 from blocked_users bu where bu.user_id = x.tgt and bu.blocked_user_id = v_uid)
      and coalesce((select np.lounge from notification_prefs np where np.user_id = x.tgt), true)
  ),
  cleared as (
    delete from notifications n
    using targets t
    where n.type = 'lounge_reply' and n.entity_id = p_post_id
      and n.user_id = t.tgt and n.seen_at is null
    returning 1
  )
  insert into notifications (user_id, type, title, body, room_id, entity_id, push_pending, created_at)
  select t.tgt, 'lounge_reply',
         coalesce(v_room_name, 'The Lounge'),
         v_name || ' replied: ' || left(regexp_replace(p_body, '\s+', ' ', 'g'), 90),
         v_room, p_post_id, true, v_now
  from targets t;

  return jsonb_build_object('id', v_reply_id, 'created_at', v_now);
end;
$$;

grant execute on function add_lounge_reply(uuid, text) to authenticated;
