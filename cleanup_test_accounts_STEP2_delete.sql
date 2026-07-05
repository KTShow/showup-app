-- STEP 2: DELETE — targets these 3 specific confirmed test accounts only:
--   tracey-k-2yqw  (5cd5752b-4c02-4044-a155-f1d130f921c3)
--   tracey-k-5nfz  (5c3c930e-f9be-4937-9d6e-61a36ee85086)
--   show-u-96ez    (baa32ebf-3ac6-41c9-bb33-294c20550060)
-- Your real account (tracey-k-b6tt) is intentionally NOT in this list.
--
-- This removes each of these 3 accounts from every Living Room they're in,
-- AND removes everyone else from these accounts' own Living Rooms — a full,
-- symmetric cleanup. It does not delete the accounts themselves, only their
-- mesh connections.

with test_users as (
  select id from users
  where id in (
    '5cd5752b-4c02-4044-a155-f1d130f921c3',
    '5c3c930e-f9be-4937-9d6e-61a36ee85086',
    'baa32ebf-3ac6-41c9-bb33-294c20550060'
  )
),
test_rooms as (
  select id from living_rooms where owner_id in (select id from test_users)
)
delete from living_room_members
where user_id in (select id from test_users)
   or living_room_id in (select id from test_rooms);
