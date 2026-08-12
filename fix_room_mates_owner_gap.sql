-- Fixes a gap in yesterday's multi-room RLS update: room_mates() and
-- top5_read_friends only recognized people with an explicit active
-- living_room_members row. A room's OWNER has no such row for their own
-- room (ownership is tracked via living_rooms.owner_id instead), so an
-- owner could see their own shows (separate rule) but nobody else's
-- friends'/top5 shows in a room they own. This makes "participant of a
-- room" correctly mean owner OR active member, in both directions.

create or replace function room_mates()
returns setof uuid
language sql
security definer
set search_path to 'public'
as $$
  with my_rooms as (
    select id from living_rooms where owner_id = auth.uid()
    union
    select living_room_id from living_room_members where user_id = auth.uid() and status = 'active'
  )
  select distinct person_id from (
    select owner_id as person_id from living_rooms where id in (select id from my_rooms)
    union
    select user_id as person_id from living_room_members
    where status = 'active' and living_room_id in (select id from my_rooms)
  ) p
  where person_id <> auth.uid();
$$;

alter policy top5_read_friends on top5_shows
  using (
    (user_id in (select room_mates()))
    or (user_id in (select id from users where is_public = true or account_type = 'celebrity'))
  );
