-- Read-only. Two parts:
--
-- 1. Every room whose name does NOT match the old auto-generated
--    "{FirstName}'s Living Room" pattern -- this should surface the real
--    Beta1 room plus the handful of rooms deliberately created since
--    Friday (Tracey's, George's, Lora's, John L.'s), and show exactly
--    who's really in each.
--
-- 2. The full user record for the "Tracy" account (tracy-a-v1da) that
--    showed 24 members this morning, so we can see what it actually is --
--    when it was created, whether it's flagged admin, etc.

select
  r.id as room_id,
  r.name as room_name,
  owner.first_name as owner_name,
  owner.username as owner_username,
  count(m.user_id) filter (where m.status = 'active') as active_member_count,
  string_agg(mem_user.first_name || ' (' || mem_user.username || ')', ', ') filter (where m.status = 'active') as members
from living_rooms r
join users owner on owner.id = r.owner_id
left join living_room_members m on m.living_room_id = r.id
left join users mem_user on mem_user.id = m.user_id
where r.name <> owner.first_name || '''s Living Room'
group by r.id, r.name, owner.first_name, owner.username
order by owner_name;

select id, username, first_name, last_initial, is_admin, created_at
from users
where username = 'tracy-a-v1da';
