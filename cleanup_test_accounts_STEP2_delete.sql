-- STEP 2: DELETE — only run this after reviewing STEP 1's results and
-- confirming those are exactly the test accounts you want removed from
-- everyone's Living Room mesh. This does NOT delete the user accounts
-- themselves — only their connections/memberships in the beta mesh.
--
-- This removes each matched test account from every Living Room they're
-- in, AND removes everyone else from that test account's own Living Room —
-- a full, symmetric cleanup regardless of who they got connected to.

with test_users as (
  select id from users
  where username ilike 'tracey%'
     or username ilike 'showup%'
     or first_name ilike 'tracey%'
     or first_name ilike 'showup%'
),
test_rooms as (
  select id from living_rooms where owner_id in (select id from test_users)
)
delete from living_room_members
where user_id in (select id from test_users)
   or living_room_id in (select id from test_rooms);
