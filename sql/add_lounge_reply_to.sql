-- ============================================================
-- add_lounge_reply_to.sql  (2026-10-18)
-- ============================================================
-- Reply to a specific reply in The Lounge. Threads stay one level deep;
-- a reply can point at the reply it answers (shown as "to George L.").
--
--   * lounge_replies.reply_to_id -- the reply being answered (null = a
--     reply to the post). Cleared if that reply is deleted.
--   * get_lounge also returns reply_to_id.
--   * add_lounge_reply takes an optional p_reply_to. The person being
--     answered gets "X replied to you: ..."; everyone else in the thread
--     still gets "X replied: ...".
--
-- Run in the Supabase SQL editor BEFORE deploying the app change. Old
-- app versions keep working (p_reply_to is optional). Safe to re-run.
-- ============================================================

alter table lounge_replies add column if not exists reply_to_id uuid
  references lounge_replies(id) on delete set null;

-- ---------- get_lounge (adds reply_to_id) -----------------------------
create or replace function get_lounge(p_room_id uuid)
returns jsonb language plpgsql as $$
declare
  v_uid  uuid := auth.uid();
  v_seen timestamptz;
begin
  if v_uid is null then raise exception 'Not authenticated'; end if;
  if not (user_owns_room(p_room_id) or user_is_in_room(p_room_id) or user_is_admin()) then
    raise exception 'Not a member of this room';
  end if;

  select lounge_seen_at into v_seen
    from room_last_seen where user_id = v_uid and living_room_id = p_room_id;

  return jsonb_build_object(
    'lounge_seen_at', v_seen,
    'posts', (
      select coalesce(jsonb_agg(to_jsonb(row) order by row.last_activity_at desc), '[]'::jsonb)
      from (
        select p.id, p.user_id, p.body, p.created_at, p.updated_at, p.last_activity_at,
               p.group_id,
               case when p.group_id is not null and p.user_id = v_uid
                    then (select count(*) from lounge_posts g where g.group_id = p.group_id) end as group_count,
               u.first_name, u.last_initial
        from lounge_posts p
        join users u on u.id = p.user_id
        where p.living_room_id = p_room_id
      ) row
    ),
    'replies', (
      select coalesce(jsonb_agg(to_jsonb(row) order by row.created_at), '[]'::jsonb)
      from (
        select r.id, r.post_id, r.user_id, r.body, r.created_at, r.updated_at, r.reply_to_id,
               u.first_name, u.last_initial
        from lounge_replies r
        join lounge_posts p on p.id = r.post_id
        join users u on u.id = r.user_id
        where p.living_room_id = p_room_id
      ) row
    )
  );
end;
$$;

grant execute on function get_lounge(uuid) to authenticated;

-- ---------- add_lounge_reply (adds p_reply_to) ------------------------
drop function if exists add_lounge_reply(uuid, text);

create or replace function add_lounge_reply(p_post_id uuid, p_body text, p_reply_to uuid default null)
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
  v_to_user     uuid;
  v_now         timestamptz := now();
  v_name        text;
  v_room_name   text;
  v_snippet     text;
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

  -- Only a reply in this same thread can be answered.
  if p_reply_to is not null then
    select user_id into v_to_user from lounge_replies where id = p_reply_to and post_id = p_post_id;
    if v_to_user is null then p_reply_to := null; end if;
  end if;

  insert into lounge_replies (post_id, user_id, body, reply_to_id, created_at)
  values (p_post_id, v_uid, p_body, p_reply_to, v_now)
  returning id into v_reply_id;

  update lounge_posts set last_activity_at = v_now where id = p_post_id;

  select first_name || coalesce(' ' || nullif(last_initial, '') || '.', '') into v_name from users where id = v_uid;
  v_name := coalesce(v_name, 'Someone');
  select name into v_room_name from living_rooms where id = v_room;
  v_snippet := left(regexp_replace(p_body, '\s+', ' ', 'g'), 90);

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
         v_name || case when t.tgt = v_to_user then ' replied to you: ' else ' replied: ' end || v_snippet,
         v_room, p_post_id, true, v_now
  from targets t;

  return jsonb_build_object('id', v_reply_id, 'created_at', v_now);
end;
$$;

grant execute on function add_lounge_reply(uuid, text, uuid) to authenticated;
