-- Forgiving search, server side. Safe to run again.
-- 1) norm_title: case, apostrophes, punctuation, "&" vs "and" and a leading
--    The / A / An don't count (same rules as _normQ in the app).
-- 2) search_show_ratings also takes the TMDB ids TMDB found for the search, so
--    ratings show up even when the spelling is off. Same privacy rules as before.
-- The last query is a read-only check.

create or replace function norm_title(t text)
returns text
language sql
immutable
as $f$
  select regexp_replace(
           trim(regexp_replace(
             replace(regexp_replace(lower(coalesce(t, '')), '[''‘’ʼ`´]', '', 'g'), '&', ' and '),
             '[^[:alnum:]]+', ' ', 'g')),
         '^(the|a|an) ', '')
$f$;

drop function if exists search_show_ratings(text);

create or replace function search_show_ratings(p_query text, p_tmdb_ids integer[] default null)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_user_id uuid := auth.uid();
  v_network_ids uuid[];
  v_salt text := gen_random_uuid()::text;
  v_query text := norm_title(p_query);
  v_ids text[] := coalesce(p_tmdb_ids::text[], '{}');
  v_like text;
begin
  if v_user_id is null then
    raise exception 'Not authenticated';
  end if;
  if length(v_query) < 2 and cardinality(v_ids) = 0 then
    return jsonb_build_object('shows', '[]'::jsonb, 'people', '[]'::jsonb, 'network_ids', '[]'::jsonb);
  end if;
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
      select s.*, norm_title(s.title) as show_key,
             (s.tmdb_id is not null and s.tmdb_id::text = any(v_ids)) as id_hit
      from shows s
      where s.hidden = false and s.rating > 0
        and ((length(v_query) >= 2 and norm_title(s.title) like '%' || v_like || '%' escape '\')
             or (s.tmdb_id is not null and s.tmdb_id::text = any(v_ids)))
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
               bool_or(id_hit) desc,
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

grant execute on function search_show_ratings(text, integer[]) to authenticated;

-- Check (read-only): each pair should match, so every row should say true.
select saved, typed, norm_title(saved) like '%' || norm_title(typed) || '%' as matches
from (values
  ('The Queen''s Gambit', 'queens gambit'),
  ('Law & Order: Special Victims Unit', 'law and order special'),
  ('Grey''s Anatomy', 'greys anatomy'),
  ('The Office', 'the office'),
  ('Mr. Robot', 'mr robot')
) as t(saved, typed);
