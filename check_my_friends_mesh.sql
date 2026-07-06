-- Diagnostic, read-only. Replicates exactly what getFriendsWithShows() does for
-- tracey-k-b6tt (id f5f85874-5f90-4383-ba22-5bd013358afb): who joined HER room
-- (direction 1) plus whose rooms SHE joined (direction 2). This is the full list
-- of "friends" the app should be pulling shows/ratings from for her account.

-- Her own living room id, for reference.
select id as my_room_id from living_rooms where owner_id = 'f5f85874-5f90-4383-ba22-5bd013358afb';

-- Direction 1: who is an active member of HER room.
select u.username, u.first_name, u.last_initial, lrm.status
from living_room_members lrm
join users u on u.id = lrm.user_id
where lrm.living_room_id = (select id from living_rooms where owner_id = 'f5f85874-5f90-4383-ba22-5bd013358afb')
order by u.username;

-- Direction 2: rooms SHE actively joined, and who owns them.
select u.username as room_owner, u.first_name, u.last_initial, lrm.status
from living_room_members lrm
join living_rooms lr on lr.id = lrm.living_room_id
join users u on u.id = lr.owner_id
where lrm.user_id = 'f5f85874-5f90-4383-ba22-5bd013358afb'
order by u.username;
