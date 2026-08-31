-- Run this in Supabase SQL Editor to sanity-check the beta invite mesh.
-- Each beta member should show the same connection count (total beta members minus 1)
-- if everyone is fully connected to everyone else. Anyone lower is missing connections
-- and should be investigated (had them re-click the invite link, or check for errors).

select
  u.username,
  u.first_name,
  u.last_initial,
  count(*) filter (where lrm.status = 'active') as connections
from users u
left join living_room_members lrm on lrm.user_id = u.id
group by u.id, u.username, u.first_name, u.last_initial
order by connections asc;
