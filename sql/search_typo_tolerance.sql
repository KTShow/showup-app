-- Search: typo tolerance ("quens gambet" finds The Queen's Gambit, "stranger thngs"
-- finds Stranger Things). Only used when no title contains what was typed, so
-- normal searches are unchanged. Same privacy rules as before. Safe to run again.
create extension if not exists pg_trgm with schema extensions;

create or replace function search_show_ratings(p_query text, p_tmdb_ids integer[] default null)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $$
declare
  v_user_id uuid := auth.uid();
  v_network_ids uuid[];
  v_salt text := gen_random_uuid()::text;
  v_query text := norm_title(p_query);
  v_ids text[] := coalesce(p_tmdb_ids::text[], '{}');
  v_like text;
  v_fuzzy boolean;
begin
  if v_user_id is null then
    raise exception 'Not authenticated';
  end if;
  if length(v_query) < 2 and cardinality(v_ids) = 0 then
    return jsonb_build_object('shows', '[]'::jsonb, 'people', '[]'::jsonb, 'network_ids', '[]'::jsonb);
  end if;
  v_like := replace(replace(replace(v_query, '\', '\\'), '%', '\%'), '_', '\_');
  -- Typos: only when no title contains what was typed.
  v_fuzzy := length(v_query) >= 4 and not exists (
    select 1 from shows s
    where s.hidden = false and s.rating > 0
      and norm_title(s.title) like '%' || v_like || '%' escape '\');

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
             or (s.tmdb_id is not null and s.tmdb_id::text = any(v_ids))
             or (v_fuzzy and word_similarity(v_query, norm_title(s.title)) >= 0.6))
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
               max(word_similarity(v_query, show_key)) desc,
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

-- Check (read-only): each typo should score 0.6 or more against the real title.
select word_similarity(norm_title('quens gambet'), norm_title('The Queen''s Gambit')) as gambit_score,
       word_similarity(norm_title('stranger thngs'), norm_title('Stranger Things')) as stranger_score;
