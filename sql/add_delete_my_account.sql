-- ============================================================
-- add_delete_my_account.sql  (2026-10-08)
-- ============================================================
-- Settings > Delete My Data, done properly (Apple requires apps to let
-- people delete their whole ACCOUNT, not just their profile).
--
-- The old client-side delete only removed the public.users row, which
--   * failed outright for anyone who'd ever invited someone or had a show
--     they recommended added (living_room_members.invited_by and
--     shows.influenced_by block the delete),
--   * when it did work, cascaded living_rooms.owner_id -> deleted any room
--     they created FOR EVERY MEMBER, and
--   * left the login (auth.users) plus everything hanging off it: Lounge
--     posts/replies, notifications, push devices, prefs, recommendations.
--
-- delete_my_account(), in order:
--   1. Rooms you own: handed to the member who joined earliest (active
--      members only); a room with no other members is deleted.
--   2. Clears you from invited_by / influenced_by so they can't block.
--   3. Deletes public.users -> cascades shows (+ comments on them), your
--      comments, top 5, memberships, room_last_seen, sessions, followers.
--   4. Deletes auth.users -> cascades the login itself, Lounge posts and
--      replies, notifications, push devices, prefs, recommendations, mutes.
--
-- Run in the Supabase SQL editor. Safe to re-run.
-- ============================================================

create or replace function delete_my_account()
returns void
language plpgsql
security definer
set search_path to 'public', 'auth'
as $$
declare
  v_uid uuid := auth.uid();
  v_col text;
  r     record;
  v_new uuid;
begin
  if v_uid is null then raise exception 'Not authenticated'; end if;

  -- "Joined earliest": use a join timestamp column if the table has one.
  select column_name into v_col
    from information_schema.columns
   where table_schema = 'public' and table_name = 'living_room_members'
     and column_name in ('joined_at', 'created_at')
   order by column_name desc   -- prefer joined_at
   limit 1;

  -- 1. Rooms I own: hand over, or delete if no one else is in them.
  for r in select id from public.living_rooms where owner_id = v_uid loop
    v_new := null;
    if v_col is not null then
      execute format(
        'select user_id from public.living_room_members
          where living_room_id = $1 and status = ''active'' and user_id <> $2
          order by %I asc nulls last limit 1', v_col)
        into v_new using r.id, v_uid;
    else
      select user_id into v_new from public.living_room_members
       where living_room_id = r.id and status = 'active' and user_id <> v_uid
       limit 1;
    end if;

    if v_new is not null then
      update public.living_rooms set owner_id = v_new where id = r.id;
      -- Owners aren't stored as members; drop the new owner's member row.
      delete from public.living_room_members where living_room_id = r.id and user_id = v_new;
    else
      delete from public.living_room_members where living_room_id = r.id;
      delete from public.muted_friends where living_room_id = r.id;
      delete from public.living_rooms where id = r.id;
    end if;
  end loop;

  -- 2. References that would otherwise block the delete.
  update public.living_room_members set invited_by = null where invited_by = v_uid;
  update public.shows set influenced_by = null where influenced_by = v_uid;

  -- 3. Profile + everything linked to it.
  delete from public.users where id = v_uid;

  -- 4. The login itself + everything linked to it.
  delete from auth.users where id = v_uid;
end;
$$;

revoke execute on function delete_my_account() from public, anon;
grant execute on function delete_my_account() to authenticated;
