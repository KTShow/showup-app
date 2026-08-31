-- Tracy A's membership in "Lora L's" (restored by
-- restore_lora_deleted_room_STEP2_apply.sql) was leftover debris from the
-- old beta1 mesh, not a real invite -- confirmed with Lora. She was the
-- sole member in all 23 other legacy debris rooms deleted earlier today,
-- same fingerprint. Removing her here; Patricia M, Gina B, and Ethel K stay.

delete from living_room_members
where living_room_id = (select id from living_rooms where name = 'Lora L''s')
  and user_id = (select id from users where username = 'tracy-a-v1da');

-- Sanity check -- should show only Patricia M, Gina B, Ethel K
select
  r.name, string_agg(mem.first_name || ' (' || mem.username || ')', ', ') as members
from living_rooms r
join living_room_members lrm on lrm.living_room_id = r.id and lrm.status = 'active'
join users mem on mem.id = lrm.user_id
where r.name = 'Lora L''s'
group by r.name;
