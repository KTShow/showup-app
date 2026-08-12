-- The reactions query included "or it's your own comment" so genuine room
-- participants always see their own comments (since v_all_ids deliberately
-- excludes yourself). For an ADMIN viewing a room they don't actually
-- belong to, that same clause incorrectly pulled in the admin's own
-- comments from elsewhere -- on shows owned by people in THIS room, but
-- via a totally different room context. Now that inclusion only applies
-- if the viewer is a genuine owner/member of the room being viewed.
create or replace function get_living_room_data(p_room_id uuid)
returns jsonb
language plpgsql
as $$
declare
  v_user_id uuid := auth.uid();
  v_all_ids uuid[];
  v_last_seen timestamptz;
  v_is_participant boolean;
begin
  if v_user_id is null then
    raise exception 'Not authenticated';
  end if;

  v_is_participant := (user_owns_room(p_room_id) or user_is_in_room(p_room_id));

  if not (v_is_participant or user_is_admin()) then
    raise exception 'Not a member of this room';
  end if;

  select last_seen_at into v_last_seen
  from room_last_seen
  where user_id = v_user_id and living_room_id = p_room_id;

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
    return jsonb_build_object(
      'friends', '[]'::jsonb, 'shows', '[]'::jsonb,
      'reactions', '[]'::jsonb, 'top5', '[]'::jsonb, 'muted', '[]'::jsonb,
      'conversations_last_seen_at', v_last_seen
    );
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
      and (
        r.user_id = any(v_all_ids)
        or (r.user_id = v_user_id and v_is_participant)
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
    ),
    'conversations_last_seen_at', v_last_seen
  );
end;
$$;
