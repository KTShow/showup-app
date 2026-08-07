create or replace function rename_living_room(p_room_id uuid, p_name text)
returns void
language plpgsql
as $$
begin
  if not user_owns_room(p_room_id) then
    raise exception 'Only the room owner can rename it';
  end if;
  update living_rooms set name = p_name where id = p_room_id;
end;
$$;

grant execute on function rename_living_room(uuid, text) to authenticated;
