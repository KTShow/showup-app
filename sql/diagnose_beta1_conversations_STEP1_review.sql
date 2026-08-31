-- Read-only diagnostic. For every room Tracey belongs to, shows:
--   - when she last marked Conversations "seen" in that room
--   - the most recent show added by anyone in that room
--   - the most recent comment (reaction) by anyone in that room
-- If beta1's "my_last_seen" is very close to now (today/yesterday) while
-- the other rooms' is null or old, that confirms the "unread feed, not a
-- persistent log" theory -- frequent visits to beta1 are what's trimming
-- it down, not data loss.
with me as (
  select id from auth.users where email = 'tklein2027@gmail.com'
),
my_rooms as (
  select lr.id, lr.name
  from living_rooms lr
  join me on true
  where lr.owner_id = me.id
     or exists (
       select 1 from living_room_members m
       where m.living_room_id = lr.id and m.user_id = me.id and m.status = 'active'
     )
),
room_participants as (
  select mr.id as room_id, p.uid as participant_id
  from my_rooms mr
  cross join lateral (
    select user_id as uid from living_room_members
    where living_room_id = mr.id and status = 'active'
    union
    select owner_id as uid from living_rooms where id = mr.id
  ) p
)
select
  mr.name as room_name,
  rls.last_seen_at as my_last_seen,
  (select count(distinct rp.participant_id) from room_participants rp where rp.room_id = mr.id) as member_count,
  (select max(s.added_at) from shows s
   where s.user_id in (select rp.participant_id from room_participants rp where rp.room_id = mr.id)
  ) as most_recent_show_added,
  (select max(r.reacted_at) from reactions r
   join shows s on s.id = r.show_id
   where s.user_id in (select rp.participant_id from room_participants rp where rp.room_id = mr.id)
  ) as most_recent_comment
from my_rooms mr
join me on true
left join room_last_seen rls on rls.living_room_id = mr.id and rls.user_id = me.id
order by rls.last_seen_at desc nulls last;
