-- ============================================================
-- add_show_counts_rpc.sql  (2026-10-12)
-- ============================================================
-- 1. get_show_counts(items) -- for the "Trending in the US" tab: how many
--    people on ShowUp have each trending show, plus its ShowUp rating.
--    Matched by TMDB id OR by title, and NOT limited to shows the daily
--    season job has registered -- a brand-new show (2026-10-12: "Carrie",
--    on 1 list) showed no count because it wasn't in tracked_seasons yet.
--    items = [{"tmdb_id": 123, "title": "..."}, ...]  (max 100)
--    Aggregates only -- never returns who.
--
-- 2. get_hot_right_now() -- same as add_hot_right_now_rpc.sql, plus the
--    show's first-air year so Hot on ShowUp rows can say "Since 2025".
--
-- Run in the Supabase SQL editor. Safe to re-run.
-- ============================================================

create or replace function get_show_counts(p_items jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) > 100 then
    raise exception 'Bad request';
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'tmdb_id', (i ->> 'tmdb_id')::int,
      'people', c.people,
      'avg_rating', c.avg_rating,
      'rating_count', c.rating_count))
    from jsonb_array_elements(p_items) i
    cross join lateral (
      select count(distinct s.user_id) as people,
             round(avg(s.rating) filter (where s.rating > 0), 1) as avg_rating,
             count(*) filter (where s.rating > 0) as rating_count
        from shows s
       where s.hidden = false
         and coalesce(s.media_type, 'tv') = 'tv'
         and (s.tmdb_id = (i ->> 'tmdb_id')::int
              or lower(trim(s.title)) = lower(trim(i ->> 'title')))
    ) c
    where c.people > 0
  ), '[]'::jsonb);
end;
$$;
grant execute on function get_show_counts(jsonb) to authenticated;

create or replace function get_hot_right_now()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  return jsonb_build_object(
    'shows', (
      select coalesce(jsonb_agg(t order by t.people desc, t.avg_rating desc nulls last, t.title), '[]'::jsonb)
      from (
        select
          (array_agg(s.title))[1] as title,
          (array_agg(s.platform) filter (where s.platform is not null and s.platform <> '' and s.platform <> 'None'))[1] as platform,
          (array_agg(s.poster_path) filter (where s.poster_path is not null))[1] as poster_path,
          (array_agg(s.first_air_year) filter (where s.first_air_year is not null))[1] as first_air_year,
          s.tmdb_id,
          round(avg(s.rating) filter (where s.rating > 0), 1) as avg_rating,
          count(*) filter (where s.rating > 0) as rating_count,
          count(distinct s.user_id) as people
        from shows s
        join tracked_seasons ts on ts.tmdb_id = s.tmdb_id
        where s.hidden = false
          and s.media_type = 'tv'
          and ts.latest_season_air_date::date >= current_date - 365
        group by s.tmdb_id
        order by count(distinct s.user_id) desc
        limit 500
      ) t
    )
  );
end;
$$;

grant execute on function get_hot_right_now() to authenticated;
