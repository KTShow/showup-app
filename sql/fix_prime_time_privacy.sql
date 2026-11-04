-- Privacy fix before public App Store launch. Prime Time and the show search
-- still pool ratings across ShowUp, but each phone now only receives names and
-- real ids for the viewer and people in the viewer's rooms.
--
-- Everyone else arrives with no name, no show id, and a throwaway id that is
-- different for every show and every load, so a stranger's shows can't be
-- linked together or traced back to a person. Only the columns the app needs
-- are sent. Shows from people the viewer has blocked are left out here,
-- because the app can no longer recognize them once their id is masked.
create or replace function get_prime_time_rankings()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_user_id uuid := auth.uid();
  v_network_ids uuid[];
  v_salt text := gen_random_uuid()::text;
begin
  if v_user_id is null then
    raise exception 'Not authenticated';
  end if;

  with my_rooms as (
    select id from living_rooms where owner_id = v_user_id
    union
    select living_room_id from living_room_members where user_id = v_user_id and status = 'active'
  )
  select coalesce(array_agg(distinct uid), '{}')
    into v_network_ids
    from (
      select owner_id as uid from living_rooms where id in (select id from my_rooms)
      union
      select user_id as uid from living_room_members
      where status = 'active' and living_room_id in (select id from my_rooms)
    ) participants;

  return jsonb_build_object(
    'shows', (
      select coalesce(jsonb_agg(
        case when s.user_id = v_user_id or s.user_id = any(v_network_ids) then
          jsonb_build_object('id', s.id, 'user_id', s.user_id, 'title', s.title, 'rating', s.rating,
            'platform', s.platform, 'poster_path', s.poster_path, 'tmdb_id', s.tmdb_id)
        else
          jsonb_build_object('id', null,
            'user_id', md5(v_salt || s.user_id::text || lower(trim(s.title))),
            'title', s.title, 'rating', s.rating,
            'platform', s.platform, 'poster_path', s.poster_path, 'tmdb_id', s.tmdb_id)
        end
      ), '[]'::jsonb)
      from shows s
      where s.hidden = false and s.rating > 0
        and not exists (
          select 1 from blocked_users b
          where b.user_id = v_user_id and b.blocked_user_id = s.user_id
        )
    ),
    'people', (
      select coalesce(jsonb_agg(jsonb_build_object('id', u.id, 'first_name', u.first_name, 'last_initial', u.last_initial)), '[]'::jsonb)
      from users u
      where u.id = v_user_id or u.id = any(v_network_ids)
    ),
    'network_ids', to_jsonb(coalesce(v_network_ids, '{}'::uuid[]))
  );
end;
$$;

grant execute on function get_prime_time_rankings() to authenticated;
