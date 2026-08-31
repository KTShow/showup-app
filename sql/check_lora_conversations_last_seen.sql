-- Read-only. Shows Tracey's stored "last seen Conversations" timestamp for
-- Lora's Book Club specifically, plus the most recent activity in that room,
-- so we can tell whether the mark-seen write is actually landing for this
-- room or getting stuck (e.g. still null after she's opened Conversations
-- there and left).
with me as (
  select id from auth.users where email = 'tklein2027@gmail.com'
),
room as (
  select id, name from living_rooms where name ilike 'lora%book club%'
)
select
  room.name as room_name,
  room.id as room_id,
  rls.last_seen_at as my_last_seen,
  rls.user_id as last_seen_row_user_id,
  now() as query_time
from room
left join room_last_seen rls on rls.living_room_id = room.id
  and rls.user_id = (select id from me);
