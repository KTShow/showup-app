-- Rebuilds the room accidentally deleted by
-- cleanup_legacy_personal_rooms_STEP2_apply.sql, which wrongly treated it
-- as pre-multiroom debris. Confirmed with Tracey: owner is Lora
-- (lora-l-skax), members are Tracy A, Patricia M, Gina B, Ethel K, new
-- name is "Lora L's".
--
-- This restores the room and its membership list. It does NOT restore the
-- original room id, created_at, or the deleted conversations_last_seen
-- rows (trivial per-user "last read" markers, safe to lose) -- shows,
-- reactions, and top5s were never tied to living_room_id and were
-- unaffected by the original delete.

with new_room as (
  insert into living_rooms (owner_id, name, is_public)
  select id, 'Lora L''s', false
  from users where username = 'lora-l-skax'
  returning id, owner_id
)
insert into living_room_members (living_room_id, user_id, status, invited_by)
select new_room.id, m.user_id, 'active', new_room.owner_id
from new_room
cross join (
  select id as user_id from users where username = 'tracy-a-v1da'
  union all
  select id from users where username = 'patricia-m-5x55'
  union all
  select id from users where username = 'gina-b-nx98'
  union all
  select id from users where username = 'ethel-k-kocn'
) m;

-- Sanity check -- should show the new room with all 4 members
select
  r.id as room_id, r.name, owner.first_name as owner_name,
  string_agg(mem.first_name || ' (' || mem.username || ')', ', ') as members
from living_rooms r
join users owner on owner.id = r.owner_id
join living_room_members lrm on lrm.living_room_id = r.id and lrm.status = 'active'
join users mem on mem.id = lrm.user_id
where r.name = 'Lora L''s'
group by r.id, r.name, owner.first_name;
