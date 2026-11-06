-- Speed: Prime Time gets only its top 25 shows from the server, instead of every
-- rating on ShowUp. Same rules as the app's own ranking: one rating per person per
-- show, at least 3 raters, highest average first (to one decimal), then most raters.
-- Same privacy as get_prime_time_rankings: names and real ids only for the viewer
-- and people in the viewer's rooms; blocked people left out. Safe to run again.
-- get_prime_time_rankings stays in place for now.
create or replace function get_prime_time_top()
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

  return (
    with visible as (
      select s.*, lower(trim(s.title)) as show_key
      from shows s
      where s.hidden = false and s.rating > 0 and coalesce(s.title, '') <> ''
        and not exists (
          select 1 from blocked_users b
          where b.user_id = v_user_id and b.blocked_user_id = s.user_id
        )
    ),
    one_each as (
      select distinct on (show_key, user_id) show_key, user_id, rating
      from visible
      order by show_key, user_id, id
    ),
    top_shows as (
      select show_key
      from one_each
      group by show_key
      having count(*) >= 3
      order by round(avg(rating)::numeric, 1) desc, count(*) desc, show_key
      limit 25
    )
    select jsonb_build_object(
      'shows', (
        select coalesce(jsonb_agg(
          case when v.user_id = v_user_id or v.user_id = any(v_network_ids) then
            jsonb_build_object('id', v.id, 'user_id', v.user_id, 'title', v.title, 'rating', v.rating,
              'platform', v.platform, 'poster_path', v.poster_path, 'tmdb_id', v.tmdb_id)
          else
            jsonb_build_object('id', null,
              'user_id', md5(v_salt || v.user_id::text || v.show_key),
              'title', v.title, 'rating', v.rating,
              'platform', v.platform, 'poster_path', v.poster_path, 'tmdb_id', v.tmdb_id)
          end
        ), '[]'::jsonb)
        from visible v
        where v.show_key in (select show_key from top_shows)
      ),
      'people', (
        select coalesce(jsonb_agg(jsonb_build_object('id', u.id, 'first_name', u.first_name, 'last_initial', u.last_initial)), '[]'::jsonb)
        from users u
        where u.id = v_user_id or u.id = any(v_network_ids)
      ),
      'network_ids', to_jsonb(coalesce(v_network_ids, '{}'::uuid[]))
    )
  );
end;
$$;

grant execute on function get_prime_time_top() to authenticated;
