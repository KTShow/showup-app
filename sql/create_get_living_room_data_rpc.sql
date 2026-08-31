-- Consolidates the ~5 sequential client-side round trips inside
-- getFriendsWithShows() into a single server-side call. Runs as the calling
-- user (no SECURITY DEFINER), so all existing Row Level Security policies on
-- users/shows/reactions/top5_shows/muted_friends apply exactly as they do
-- today for direct table queries -- this does not grant access to anything
-- a user couldn't already read before.
create or replace function get_living_room_data()
returns jsonb
language plpgsql
as $$
declare
  v_user_id uuid := auth.uid();
  v_room_id uuid;
  v_dir1_ids uuid[];
  v_owner_ids uuid[];
  v_all_ids uuid[];
  v_empty jsonb := jsonb_build_object(
    'friends', '[]'::jsonb, 'shows', '[]'::jsonb,
    'reactions', '[]'::jsonb, 'top5', '[]'::jsonb, 'muted', '[]'::jsonb
  );
begin
  if v_user_id is null then
    raise exception 'Not authenticated';
  end if;

  select id into v_room_id from living_rooms where owner_id = v_user_id;
  if v_room_id is null then
    return v_empty;
  end if;

  -- Direction 1: other active members of MY room
  select coalesce(array_agg(user_id), '{}')
    into v_dir1_ids
    from living_room_members
    where living_room_id = v_room_id and status = 'active' and user_id <> v_user_id;

  -- Direction 2: owners of other rooms I'm an active member of
  select coalesce(array_agg(distinct lr.owner_id), '{}')
    into v_owner_ids
    from living_room_members lrm
    join living_rooms lr on lr.id = lrm.living_room_id
    where lrm.user_id = v_user_id and lrm.status = 'active'
      and lrm.living_room_id <> v_room_id
      and lr.owner_id <> v_user_id;

  select array(select distinct unnest(v_dir1_ids || v_owner_ids)) into v_all_ids;
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
      where user_id = v_user_id
    )
  );
end;
$$;

grant execute on function get_living_room_data() to authenticated;
