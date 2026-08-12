-- Correction to the previous fix: a show carries into every room its owner
-- belongs to (by design), but that doesn't mean every comment ever left on
-- that show should surface in every one of those rooms too. Conversations
-- should only show activity FROM people who are actually in the room being
-- viewed -- a comment from someone outside this room (e.g. left back in a
-- different shared room) shouldn't appear here at all, not even with their
-- name resolved. Filters reactions down to room participants (+ yourself).
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
      and (r.user_id = any(v_all_ids) or r.user_id = v_user_id)
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
