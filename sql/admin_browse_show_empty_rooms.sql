-- admin_browse_show_empty_rooms.sql  (2026-11-03)
-- Admin Browse All Rooms now lists EVERY room, including ones where no one
-- but the owner has joined yet (the app shows those in their own
-- "No one joined yet" section). The old "member_count > 0" filter hid the
-- auto-created "{FirstName}'s Living Room" rooms; those were deleted in
-- cleanup_legacy_personal_rooms_STEP2_apply.sql and rooms are only made on
-- purpose now, so the filter just hid real new rooms (e.g. after an
-- admin_new_room alert). Admin only, still gated by user_is_admin().
--
-- NOTE: add_admin_room_viewing.sql, add_living_room_theme.sql and the
-- fix_admin_browse_* files hold older copies of this function. Re-running
-- any of them would hide empty rooms again; re-run this file to undo that.
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
      'member_count', member_count,
      'created_at', created_at
    ) order by room_name), '[]'::jsonb)
    from (
      select r.id as room_id, r.name as room_name, r.theme as room_theme,
             u.first_name || coalesce(' ' || nullif(u.last_initial, '') || '.', '') as owner_name,
             to_jsonb(r) ->> 'created_at' as created_at,
             (select count(*) from living_room_members m
              where m.living_room_id = r.id and m.status = 'active' and m.user_id <> r.owner_id) as member_count
      from living_rooms r
      join users u on u.id = r.owner_id
    ) x
  );
end;
$$;
