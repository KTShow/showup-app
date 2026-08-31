-- Regression fix: add_living_room_theme.sql accidentally rewrote
-- get_all_living_rooms_admin() from a version that predated
-- filter_empty_rooms_admin_browse.sql, dropping the "member_count > 0"
-- filter. That brought back every beta1 user's empty auto-created
-- personal room into Admin Browse All Rooms. Restoring the filter,
-- keeping the theme field this time.
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
