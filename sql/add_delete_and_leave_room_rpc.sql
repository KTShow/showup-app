-- Owner-only room deletion. Explicitly deletes membership/mute rows first
-- rather than relying on any FK cascade behavior, so this works regardless
-- of how those constraints are configured.
create or replace function delete_living_room(p_room_id uuid)
returns void
language plpgsql
as $$
begin
  if not user_owns_room(p_room_id) then
    raise exception 'Only the room owner can delete it';
  end if;
  delete from living_room_members where living_room_id = p_room_id;
  delete from muted_friends where living_room_id = p_room_id;
  delete from living_rooms where id = p_room_id;
end;
$$;

grant execute on function delete_living_room(uuid) to authenticated;
