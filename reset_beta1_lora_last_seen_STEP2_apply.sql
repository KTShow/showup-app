-- Clears the "last seen" mark on Lora's Book Club for Tracey, so the
-- Conversations backlog that got wiped by the old own-comment-click bug
-- (fixed 2026-08-10) reappears as unread -- matching the other rooms,
-- which were never marked seen at all. Beta1 already fixed separately.
-- Uses ilike instead of an exact name match -- the room name has a curly
-- apostrophe (Lora's Book Club), which a straight-quote match silently
-- skips (no error, just zero rows deleted).
delete from room_last_seen
where user_id = (select id from auth.users where email = 'tklein2027@gmail.com')
  and living_room_id in (
    select id from living_rooms where name ilike 'lora%book club%'
  );
