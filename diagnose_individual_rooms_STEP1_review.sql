-- Read-only. Finds every leftover auto-created personal room -- the ones
-- named exactly "{FirstName}'s Living Room", which is the pattern
-- createUserProfile() used to generate before it stopped doing that
-- (commit c5e9ff8). These are pure debris from the old invite-mesh model:
-- nobody should own one anymore, and nobody should be a member of one.
--
-- Rooms with a custom name (Lora's Bookclub, my Prosecco, George's pool
-- chair, Beta1, etc.) will NOT match this pattern and are correctly
-- excluded -- those are real rooms and should stay untouched.

select
  r.id as room_id,
  r.name as room_name,
  owner.first_name as owner_name,
  owner.username as owner_username,
  count(m.user_id) filter (where m.status = 'active') as active_member_count,
  string_agg(mem_user.first_name, ', ') filter (where m.status = 'active') as members
from living_rooms r
join users owner on owner.id = r.owner_id
left join living_room_members m on m.living_room_id = r.id
left join users mem_user on mem_user.id = m.user_id
where r.name = owner.first_name || '''s Living Room'
group by r.id, r.name, owner.first_name, owner.username
order by owner_name;
