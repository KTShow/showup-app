-- ============================================================
-- The Lounge — free-form per-room discussion (2026-09-08)
-- ============================================================
-- A place in each Living Room for questions/thoughts that aren't about
-- one specific show ("what should I watch this weekend?", "watch party
-- Friday?"). Text posts with threaded replies, scoped to a single room,
-- visible to that room's active members + owner (+ admins, read-only).
-- Distinct from Show Talk (per-show comments) and Conversations (the
-- room's activity log).
--
-- Run this WHOLE script once in the Supabase SQL Editor.
--
-- Relies on helpers that already exist: user_owns_room(uuid),
-- user_is_in_room(uuid), user_is_admin().
-- ============================================================

-- ---------- tables ------------------------------------------------------
create table if not exists lounge_posts (
  id               uuid primary key default gen_random_uuid(),
  living_room_id   uuid not null references living_rooms(id) on delete cascade,
  user_id          uuid not null references auth.users(id) on delete cascade,
  body             text not null check (char_length(body) between 1 and 4000),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz,
  last_activity_at timestamptz not null default now()
);
create index if not exists lounge_posts_room_idx
  on lounge_posts (living_room_id, last_activity_at desc);

create table if not exists lounge_replies (
  id          uuid primary key default gen_random_uuid(),
  post_id     uuid not null references lounge_posts(id) on delete cascade,
  user_id     uuid not null references auth.users(id) on delete cascade,
  body        text not null check (char_length(body) between 1 and 4000),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz
);
create index if not exists lounge_replies_post_idx
  on lounge_replies (post_id, created_at);

alter table lounge_posts   enable row level security;
alter table lounge_replies enable row level security;

-- ---------- RLS: lounge_posts -----------------------------------------
create policy lounge_posts_read on lounge_posts
  for select using (
    user_owns_room(living_room_id) or user_is_in_room(living_room_id) or user_is_admin()
  );

create policy lounge_posts_insert on lounge_posts
  for insert with check (
    auth.uid() = user_id
    and (user_owns_room(living_room_id) or user_is_in_room(living_room_id))
  );

create policy lounge_posts_update_own on lounge_posts
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- Your own post, or any post in a room you own.
create policy lounge_posts_delete on lounge_posts
  for delete using (auth.uid() = user_id or user_owns_room(living_room_id));

-- ---------- RLS: lounge_replies -------------------------------------
create policy lounge_replies_read on lounge_replies
  for select using (
    exists (
      select 1 from lounge_posts p
      where p.id = lounge_replies.post_id
        and (user_owns_room(p.living_room_id) or user_is_in_room(p.living_room_id) or user_is_admin())
    )
  );

-- Replies normally go through add_lounge_reply() (which also fans out
-- notifications); this policy is a backstop for a direct insert.
create policy lounge_replies_insert on lounge_replies
  for insert with check (
    auth.uid() = user_id
    and exists (
      select 1 from lounge_posts p
      where p.id = lounge_replies.post_id
        and (user_owns_room(p.living_room_id) or user_is_in_room(p.living_room_id))
    )
  );

create policy lounge_replies_update_own on lounge_replies
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy lounge_replies_delete on lounge_replies
  for delete using (
    auth.uid() = user_id
    or exists (
      select 1 from lounge_posts p
      where p.id = lounge_replies.post_id and user_owns_room(p.living_room_id)
    )
  );

-- ---------- notifications: generic reference columns -----------------
-- The table was built "so comment / invite types can be added without a
-- rework" -- these two columns are that. room_id + entity_id (a post id
-- for 'lounge_reply') let openNotification() route the tap.
alter table notifications add column if not exists room_id   uuid references living_rooms(id) on delete cascade;
alter table notifications add column if not exists entity_id uuid;

-- ---------- room_last_seen: a separate Lounge marker ---------------
-- room_last_seen already tracks Conversations' last_seen_at per (user,
-- room); the Lounge needs its own so one doesn't clear the other.
alter table room_last_seen add column if not exists lounge_seen_at timestamptz;

create or replace function mark_lounge_seen(p_room_id uuid)
returns void language plpgsql as $$
begin
  insert into room_last_seen (user_id, living_room_id, last_seen_at, lounge_seen_at)
  values (auth.uid(), p_room_id, now(), now())
  on conflict (user_id, living_room_id)
  do update set lounge_seen_at = now();
end;
$$;

-- ---------- get_lounge -------------------------------------------------
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
               u.first_name, u.last_initial
        from lounge_posts p
        join users u on u.id = p.user_id
        where p.living_room_id = p_room_id
      ) row
    ),
    'replies', (
      select coalesce(jsonb_agg(to_jsonb(row) order by row.created_at), '[]'::jsonb)
      from (
        select r.id, r.post_id, r.user_id, r.body, r.created_at, r.updated_at,
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

-- ---------- add_lounge_reply (insert + notify) --------------------
-- SECURITY DEFINER so it can write the notifications feed (which has no
-- user-facing insert policy on purpose). Validates room membership first.
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

  select first_name || ' ' || last_initial || '.' into v_name from users where id = v_uid;
  select name into v_room_name from living_rooms where id = v_room;

  -- Notify the post author + everyone who has already replied, minus the
  -- person replying now. Collapse to one unseen notification per thread
  -- per person (clear the prior unseen one, drop in a fresh one).
  with targets as (
    select v_post_author as tgt
    union
    select user_id from lounge_replies where post_id = p_post_id
  ),
  cleared as (
    delete from notifications n
    using targets t
    where n.type = 'lounge_reply' and n.entity_id = p_post_id
      and n.user_id = t.tgt and n.seen_at is null and t.tgt <> v_uid
    returning 1
  )
  insert into notifications (user_id, type, title, body, room_id, entity_id, created_at)
  select t.tgt, 'lounge_reply',
         coalesce(v_room_name, 'The Lounge'),
         v_name || ': ' || left(regexp_replace(p_body, '\s+', ' ', 'g'), 90),
         v_room, p_post_id, v_now
  from targets t
  where t.tgt is not null and t.tgt <> v_uid;

  return jsonb_build_object('id', v_reply_id, 'created_at', v_now);
end;
$$;

grant execute on function get_lounge(uuid)            to authenticated;
grant execute on function add_lounge_reply(uuid, text) to authenticated;
grant execute on function mark_lounge_seen(uuid)      to authenticated;
