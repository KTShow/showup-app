-- ============================================================
-- add_lounge_shared_replies.sql  (2026-10-18)
-- ============================================================
-- A post sent to several rooms is one conversation: every reply shows on
-- every room's copy (copies share lounge_posts.group_id, see
-- sql/add_lounge_multiroom.sql).
--
--   * Names: you see a replier's name if you share ANY room with them
--     (same rule as Prime Time); anyone else shows as "Neighbor", and
--     their user id is withheld too, so the name can't be dug out.
--   * get_lounge is now SECURITY DEFINER (it reads replies on copies in
--     rooms you're not in) and checks membership itself, as before.
--     It also returns seen_by_rooms (the post's rooms that you're in) and
--     seen_by_others (how many more rooms) for multi-room posts, and per
--     reply own_copy (written in this room's copy -- a room owner can only
--     delete those).
--   * add_lounge_reply: alerts go to the post author + everyone who
--     replied on ANY copy; each person's alert points at a copy in a room
--     they're in, and says "Neighbor" if they don't share a room with the
--     replier.
--
-- Run in the Supabase SQL editor BEFORE deploying the app change.
-- Safe to re-run.
-- ============================================================

-- ---------- helper: do two people share any room? ----------------------
create or replace function users_share_room(a uuid, b uuid)
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $$
  with ra as (
    select living_room_id as r from living_room_members where user_id = a and status = 'active'
    union select id from living_rooms where owner_id = a
  ),
  rb as (
    select living_room_id as r from living_room_members where user_id = b and status = 'active'
    union select id from living_rooms where owner_id = b
  )
  select exists (select 1 from ra join rb using (r));
$$;

revoke execute on function users_share_room(uuid, uuid) from public, anon, authenticated;

-- ---------- helper: rooms a person is in --------------------------------
create or replace function _user_room_ids(u uuid)
returns setof uuid
language sql
stable
security definer
set search_path to 'public'
as $$
  select living_room_id from living_room_members where user_id = u and status = 'active'
  union select id from living_rooms where owner_id = u;
$$;

revoke execute on function _user_room_ids(uuid) from public, anon, authenticated;

-- ---------- get_lounge --------------------------------------------------
create or replace function get_lounge(p_room_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_uid   uuid := auth.uid();
  v_admin boolean := user_is_admin();
  v_seen  timestamptz;
begin
  if v_uid is null then raise exception 'Not authenticated'; end if;
  if not (user_owns_room(p_room_id) or user_is_in_room(p_room_id) or v_admin) then
    raise exception 'Not a member of this room';
  end if;

  select lounge_seen_at into v_seen
    from room_last_seen where user_id = v_uid and living_room_id = p_room_id;

  return jsonb_build_object(
    'lounge_seen_at', v_seen,
    'posts', (
      select coalesce(jsonb_agg(to_jsonb(row) order by row.last_activity_at desc), '[]'::jsonb)
      from (
        select p.id, p.user_id, p.body, p.created_at, p.updated_at,
               -- a reply on any copy bumps every copy
               greatest(p.last_activity_at, coalesce((select max(g.last_activity_at) from lounge_posts g where g.group_id = p.group_id), p.last_activity_at)) as last_activity_at,
               p.group_id,
               case when p.group_id is not null and p.user_id = v_uid
                    then (select count(*) from lounge_posts g where g.group_id = p.group_id) end as group_count,
               case when p.group_id is not null then (
                 select coalesce(jsonb_agg(lr.name order by (g.living_room_id <> p_room_id), lr.name), '[]'::jsonb)
                 from lounge_posts g join living_rooms lr on lr.id = g.living_room_id
                 where g.group_id = p.group_id and g.living_room_id in (select _user_room_ids(v_uid))
               ) end as seen_by_rooms,
               case when p.group_id is not null then (
                 select count(*) from lounge_posts g
                 where g.group_id = p.group_id and g.living_room_id not in (select _user_room_ids(v_uid))
               ) end as seen_by_others,
               u.first_name, u.last_initial
        from lounge_posts p
        join users u on u.id = p.user_id
        where p.living_room_id = p_room_id
      ) row
    ),
    'replies', (
      select coalesce(jsonb_agg(to_jsonb(row) order by row.created_at), '[]'::jsonb)
      from (
        select r.id, lp.id as post_id,
               case when x.known then r.user_id end as user_id,
               r.body, r.created_at, r.updated_at, r.reply_to_id,
               (src.living_room_id = p_room_id) as own_copy,
               case when x.known then u.first_name else 'Neighbor' end as first_name,
               case when x.known then u.last_initial else '' end as last_initial
        from lounge_posts lp
        join lounge_posts src
          on src.id = lp.id or (lp.group_id is not null and src.group_id = lp.group_id)
        join lounge_replies r on r.post_id = src.id
        join users u on u.id = r.user_id
        cross join lateral (
          select (r.user_id = v_uid or v_admin or users_share_room(v_uid, r.user_id)) as known
        ) x
        where lp.living_room_id = p_room_id
      ) row
    )
  );
end;
$$;

grant execute on function get_lounge(uuid) to authenticated;

-- ---------- add_lounge_reply --------------------------------------------
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
  v_group       uuid;
  v_reply_id    uuid;
  v_to_user     uuid;
  v_now         timestamptz := now();
  v_name        text;
  v_snippet     text;
begin
  if v_uid is null then raise exception 'Not authenticated'; end if;
  if p_body is null or char_length(btrim(p_body)) = 0 then raise exception 'Empty reply'; end if;
  if char_length(p_body) > 4000 then raise exception 'Reply too long'; end if;

  select p.living_room_id, p.user_id, p.group_id into v_room, v_post_author, v_group
    from lounge_posts p where p.id = p_post_id;
  if v_room is null then raise exception 'Post not found'; end if;
  if not (user_owns_room(v_room) or user_is_in_room(v_room)) then
    raise exception 'Not a member of this room';
  end if;

  -- Only a reply in this same conversation (any copy) can be answered.
  if p_reply_to is not null then
    select r.user_id into v_to_user
      from lounge_replies r join lounge_posts g on g.id = r.post_id
     where r.id = p_reply_to
       and (g.id = p_post_id or (v_group is not null and g.group_id = v_group));
    if v_to_user is null then p_reply_to := null; end if;
  end if;

  insert into lounge_replies (post_id, user_id, body, reply_to_id, created_at)
  values (p_post_id, v_uid, p_body, p_reply_to, v_now)
  returning id into v_reply_id;

  update lounge_posts set last_activity_at = v_now
   where id = p_post_id or (v_group is not null and group_id = v_group);

  select first_name || coalesce(' ' || nullif(last_initial, '') || '.', '') into v_name from users where id = v_uid;
  v_name := coalesce(v_name, 'Someone');
  v_snippet := left(regexp_replace(p_body, '\s+', ' ', 'g'), 90);

  -- Notify the post author + everyone who replied on any copy, minus the
  -- replier (and anyone who muted/blocked them or switched Lounge alerts
  -- off). Each person's alert points at a copy in a room they're in.
  -- Collapse to one unseen alert per conversation per person.
  with copies as (
    select g.id, g.living_room_id from lounge_posts g
    where g.id = p_post_id or (v_group is not null and g.group_id = v_group)
  ),
  people as (
    select v_post_author as tgt
    union
    select r.user_id from lounge_replies r where r.post_id in (select id from copies)
  ),
  targets as (
    select x.tgt, c.id as copy_id, c.living_room_id as room_id,
           users_share_room(x.tgt, v_uid) as known
    from people x
    cross join lateral (
      select c.id, c.living_room_id from copies c
      where c.living_room_id in (select _user_room_ids(x.tgt))
      order by (c.id = p_post_id) desc
      limit 1
    ) c
    where x.tgt is not null and x.tgt <> v_uid
      and not exists (select 1 from muted_friends m where m.user_id = x.tgt and m.muted_user_id = v_uid)
      and not exists (select 1 from blocked_users bu where bu.user_id = x.tgt and bu.blocked_user_id = v_uid)
      and coalesce((select np.lounge from notification_prefs np where np.user_id = x.tgt), true)
  ),
  cleared as (
    delete from notifications n
    using targets t
    where n.type = 'lounge_reply' and n.entity_id in (select id from copies)
      and n.user_id = t.tgt and n.seen_at is null
    returning 1
  )
  insert into notifications (user_id, type, title, body, room_id, entity_id, push_pending, created_at)
  select t.tgt, 'lounge_reply',
         coalesce((select name from living_rooms where id = t.room_id), 'The Lounge'),
         case when t.known then v_name else 'A neighbor' end
           || case when t.tgt = v_to_user then ' replied to you: ' else ' replied: ' end || v_snippet,
         t.room_id, t.copy_id, true, v_now
  from targets t;

  return jsonb_build_object('id', v_reply_id, 'created_at', v_now);
end;
$$;

grant execute on function add_lounge_reply(uuid, text, uuid) to authenticated;
