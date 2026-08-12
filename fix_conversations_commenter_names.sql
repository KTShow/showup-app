-- Comments/reactions stay global (visible in every room a show's owner
-- belongs to, per design), so the person who LEFT a comment might not be a
-- member of the room being viewed. The "friends" profile lookup only ever
-- covered room participants, so an out-of-room commenter's name fell back
-- to "Someone" in Conversations. Widens the lookup to also include anyone
-- who reacted on a returned show, regardless of room membership -- safe
-- since users_select_authenticated already allows any logged-in user to
-- read any basic profile.
create or replace function get_living_room_data(p_room_id uuid)
returns jsonb
language plpgsql
as $$
declare
  v_user_id uuid := auth.uid();
  v_all_ids uuid[];
  v_friend_ids uuid[];
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

  select coalesce(array_agg(distinct uid), '{}')
    into v_friend_ids
    from (
      select unnest(v_all_ids) as uid
      union
      select r.user_id as uid
      from reactions r
      where r.show_id in (select id from shows where user_id = any(v_all_ids) and hidden = false)
    ) x
    where uid <> v_user_id;

  return jsonb_build_object(
    'friends', (
      select coalesce(jsonb_agg(to_jsonb(u)), '[]'::jsonb)
      from (
        select id, first_name, last_initial, city, state, room
        from users where id = any(v_friend_ids)
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
