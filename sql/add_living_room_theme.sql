-- Per-room theming: a light accent (banner color + emoji), not a full
-- app reskin -- distinct from the existing personal profile theme
-- (users.room, which still drives the full color system via the
-- body.room-X CSS classes). The room creator picks a theme at
-- creation; the owner can change it later, same pattern as rename.

alter table living_rooms add column if not exists theme text not null default 'tuscany';

create or replace function create_living_room(p_name text, p_theme text default 'tuscany')
returns uuid
language plpgsql
as $$
declare
  v_id uuid;
begin
  insert into living_rooms (owner_id, name, is_public, theme)
  values (auth.uid(), p_name, false, coalesce(p_theme, 'tuscany'))
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function update_living_room_theme(p_room_id uuid, p_theme text)
returns void
language plpgsql
as $$
begin
  if not user_owns_room(p_room_id) then
    raise exception 'Only the room owner can change its theme';
  end if;
  update living_rooms set theme = p_theme where id = p_room_id;
end;
$$;

create or replace function get_my_living_rooms()
returns jsonb
language sql
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', r.id,
    'name', r.name,
    'theme', r.theme,
    'is_owner', (r.owner_id = auth.uid()),
    'member_count', (
      select count(*) from living_room_members m
      where m.living_room_id = r.id and m.status = 'active'
    )
  )), '[]'::jsonb)
  from living_rooms r
  where r.owner_id = auth.uid() or user_is_in_room(r.id);
$$;

-- member_count > 0 filter is load-bearing: it hides every beta1 user's
-- empty auto-created personal room from Admin Browse All Rooms. This
-- function has been accidentally rewritten from a stale, unfiltered copy
-- twice already (see fix_admin_browse_empty_rooms_regression.sql) --
-- keep the filter here so re-running this migration can't drop it again.
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

grant execute on function create_living_room(text, text) to authenticated;
grant execute on function update_living_room_theme(uuid, text) to authenticated;
