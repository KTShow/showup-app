-- ============================================================
-- hot_right_now_recent.sql  (2026-10-27)
-- ============================================================
-- "On ShowUp" (Hot Right Now) now ranks by what people did in the LAST 30
-- DAYS instead of how many people have ever added a show, so it moves.
-- A person counts toward a show's "recent" number if, in the last 30 days,
-- they added it, moved it to Binged, or commented on it. (Ratings have no
-- timestamp, and shows.updated_at is also bumped by the daily season job,
-- so neither is used.) "people" (everyone with it on a list) is still
-- returned for the "On 5 lists" labels.
--
-- Run in the Supabase SQL editor. Safe to re-run.
-- ============================================================
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
      select coalesce(jsonb_agg(t order by t.recent desc, t.people desc, t.avg_rating desc nulls last, t.title), '[]'::jsonb)
      from (
        select
          (array_agg(s.title))[1] as title,
          (array_agg(s.platform) filter (where s.platform is not null and s.platform <> '' and s.platform <> 'None'))[1] as platform,
          (array_agg(s.poster_path) filter (where s.poster_path is not null))[1] as poster_path,
          s.tmdb_id,
          round(avg(s.rating) filter (where s.rating > 0), 1) as avg_rating,
          count(*) filter (where s.rating > 0) as rating_count,
          count(distinct s.user_id) as people,
          count(distinct s.user_id) filter (where
            s.added_at >= now() - interval '30 days'
            or s.moved_to_binged_at >= now() - interval '30 days'
            or exists (select 1 from reactions r
                       where r.show_id = s.id and r.reacted_at >= now() - interval '30 days')
          ) as recent
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
