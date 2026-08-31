-- Third occurrence of the same regression. Root cause each time: two
-- migration files on disk (add_admin_room_viewing.sql, which first
-- created get_all_living_rooms_admin(), and add_living_room_theme.sql,
-- which later rewrote it to add the theme field) both stored an
-- unfiltered copy of this function. Any time either file gets re-run --
-- intentionally or by accident, e.g. re-running the wrong SQL editor tab
-- -- it silently drops the "member_count > 0" filter again, and every
-- beta1 user's empty auto-created personal room floods back into Admin
-- Browse All Rooms.
--
-- This time, both source files have been corrected in the repo to
-- include the filter, so re-running either one is now safe. This script
-- just re-applies the correct, filtered version to the live database
-- right now.
create or replace function get_all_living_rooms_admin()
returns jsonb
language plpgsql
as $$
begin
  if not user_is_admin() then
    raise exception 'Admin only';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', room_id,
      'name', room_name,
      'theme', room_theme,
      'owner_name', owner_name,
      'member_count', member_count
    ) order by room_name), '[]'::jsonb)
    from (
      select r.id as room_id, r.name as room_name, r.theme as room_theme, u.first_name as owner_name,
             (select count(*) from living_room_members m
              where m.living_room_id = r.id and m.status = 'active' and m.user_id <> r.owner_id) as member_count
      from living_rooms r
      join users u on u.id = r.owner_id
    ) x
    where member_count > 0
  );
end;
$$;
