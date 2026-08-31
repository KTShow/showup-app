-- Powers the new search bar on the room-picker screen ("Your Living
-- Rooms"), which searches shows/platforms across every room the caller
-- belongs to, not just whichever single room they have open (that's
-- what crew-search inside a room already does). For each person the
-- caller shares ANY room with, returns their name, the list of room
-- names they overlap in, and their non-hidden shows. security definer
-- + explicit owner-union logic (matching get_living_room_data) since a
-- room owner has no living_room_members row for their own room.
create or replace function get_my_all_rooms_search_data()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    raise exception 'Not authenticated';
  end if;

  return (
    select coalesce(jsonb_agg(x), '[]'::jsonb)
    from (
      select
        p.user_id,
        u.first_name,
        u.last_initial,
        jsonb_agg(distinct p.room_name) as room_names,
        (
          select coalesce(jsonb_agg(to_jsonb(s)), '[]'::jsonb)
          from shows s
          where s.user_id = p.user_id and s.hidden = false
        ) as shows
      from (
        select m.user_id as user_id, r.name as room_name
        from living_rooms r
        join living_room_members m on m.living_room_id = r.id and m.status = 'active'
        where r.owner_id = v_user_id
           or r.id in (select living_room_id from living_room_members where user_id = v_user_id and status = 'active')
        union
        select r.owner_id as user_id, r.name as room_name
        from living_rooms r
        where r.owner_id = v_user_id
           or r.id in (select living_room_id from living_room_members where user_id = v_user_id and status = 'active')
      ) p
      join users u on u.id = p.user_id
      where p.user_id <> v_user_id
      group by p.user_id, u.first_name, u.last_initial
    ) x
  );
end;
$$;

grant execute on function get_my_all_rooms_search_data() to authenticated;
