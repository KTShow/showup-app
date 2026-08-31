-- Deletes the debris confirmed by diagnose_individual_rooms_STEP1_review.sql:
-- the 24 leftover "{FirstName}'s Living Room" rows from the old one-room-
-- per-person model (retired when multi-room shipped, commit c5e9ff8).
--
-- Confirmed via diagnose_beta1_and_new_rooms_STEP1_review.sql that every
-- real, currently-used room (Beta1, Lora's Book Club, Lora's HES Friends,
-- Pool Chair, John Lanzano's Living Room, strategy 2, Prosecco, Strategy 1,
-- Watching, The Trinkles) has a custom name and will NOT match the pattern
-- below -- those are untouched.
--
-- Order matters: memberships first (FK), then the rooms themselves.

delete from living_room_members
where living_room_id in (
  select r.id
  from living_rooms r
  join users owner on owner.id = r.owner_id
  where r.name = owner.first_name || '''s Living Room'
);

delete from living_rooms r
using users owner
where owner.id = r.owner_id
  and r.name = owner.first_name || '''s Living Room';
