-- get_living_room_data() only ever gathered people from living_room_members
-- (explicit member rows) and never included the room's OWNER, who is
-- tracked separately via living_rooms.owner_id and has no membership row
-- of their own. This meant nobody could see the room owner's tile,
-- shows, or comments in any room they didn't personally own -- e.g. George
-- never saw Tracey in Beta1 or Family, even though she owns both.
create or replace function get_living_room_data(p_room_id uuid)
returns jsonb
language plpgsql
as $$
declare
  v_user_id uuid := auth.uid();
  v_all_ids uuid[];
  v_empty jsonb := jsonb_build_object(
    'friends', '[]'::jsonb, 'shows', '[]'::jsonb,
    'reactions', '[]'::jsonb, 'top5', '[]'::jsonb, 'muted', '[]'::jsonb
  );
begin
  if v_user_id is null then
    raise exception 'Not authenticated';
  end if;

  if not (user_owns_room(p_room_id) or user_is_in_room(p_room_id)) then
    raise exception 'Not a member of this room';
  end if;

  select coalesce(array_agg(distinct uid), '{}')
    into v_all_ids
    from (
      select user_id as uid from living_room_members
      where living_room_id = p_room_id and status = 'active'
      union
      select owner_id as uid from living_rooms where id = p_room_id
    ) participants
    where uid <> v_user_id;

  if v_all_ids is null or array_length(v_all_ids, 1) is null then
    return v_empty;
  end if;

  return jsonb_build_object(
    'friends', (
      select coalesce(jsonb_agg(to_jsonb(u)), '[]'::jsonb)
      from (
        select id, first_name, last_initial, city, state, room
        from users where id = any(v_all_ids)
      ) u
    ),
    'shows', (
      select coalesce(jsonb_agg(to_jsonb(s)), '[]'::jsonb)
      from shows s
      where s.user_id = any(v_all_ids) and s.hidden = false
    ),
    'reactions', (
      select coalesce(jsonb_agg(to_jsonb(r)), '[]'::jsonb)
      from reactions r
      where r.show_id in (
        select id from shows where user_id = any(v_all_ids) and hidden = false
      )
    ),
    'top5', (
      select coalesce(jsonb_agg(to_jsonb(t) order by t.rank), '[]'::jsonb)
      from top5_shows t
      where t.user_id = any(v_all_ids)
    ),
    'muted', (
      select coalesce(jsonb_agg(muted_user_id), '[]'::jsonb)
      from muted_friends
      where user_id = v_user_id and living_room_id = p_room_id
    )
  );
end;
$$;
