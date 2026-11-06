-- Speed: the Living Room search asks the server about what was typed, instead of
-- downloading every rating on ShowUp first. Returns ratings for up to 20 matching
-- shows: exact title first, then titles starting with the search, then most rated.
-- Same privacy as get_prime_time_rankings: names and real ids only for the viewer
-- and people in the viewer's rooms; blocked people left out. Safe to run again.
create or replace function search_show_ratings(p_query text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_user_id uuid := auth.uid();
  v_network_ids uuid[];
  v_salt text := gen_random_uuid()::text;
  v_query text := lower(trim(coalesce(p_query, '')));
  v_like text;
begin
  if v_user_id is null then
    raise exception 'Not authenticated';
  end if;
  if length(v_query) < 2 then
    return jsonb_build_object('shows', '[]'::jsonb, 'people', '[]'::jsonb, 'network_ids', '[]'::jsonb);
  end if;
  -- Treat % and _ in what was typed as ordinary characters.
  v_like := replace(replace(replace(v_query, '\', '\\'), '%', '\%'), '_', '\_');

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
    with matching as (
      select s.*, lower(trim(s.title)) as show_key
      from shows s
      where s.hidden = false and s.rating > 0
        and lower(trim(s.title)) like '%' || v_like || '%' escape '\'
        and not exists (
          select 1 from blocked_users b
          where b.user_id = v_user_id and b.blocked_user_id = s.user_id
        )
    ),
    top_matches as (
      select show_key
      from matching
      group by show_key
      order by (show_key = v_query) desc,
               (show_key like v_like || '%' escape '\') desc,
               count(*) desc,
               show_key
      limit 20
    )
    select jsonb_build_object(
      'shows', (
        select coalesce(jsonb_agg(
          case when m.user_id = v_user_id or m.user_id = any(v_network_ids) then
            jsonb_build_object('id', m.id, 'user_id', m.user_id, 'title', m.title, 'rating', m.rating,
              'platform', m.platform, 'poster_path', m.poster_path, 'tmdb_id', m.tmdb_id)
          else
            jsonb_build_object('id', null,
              'user_id', md5(v_salt || m.user_id::text || m.show_key),
              'title', m.title, 'rating', m.rating,
              'platform', m.platform, 'poster_path', m.poster_path, 'tmdb_id', m.tmdb_id)
          end
        ), '[]'::jsonb)
        from matching m
        where m.show_key in (select show_key from top_matches)
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

grant execute on function search_show_ratings(text) to authenticated;
