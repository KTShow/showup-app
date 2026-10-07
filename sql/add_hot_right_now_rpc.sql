-- ============================================================
-- add_hot_right_now_rpc.sql  (2026-10-07)
-- ============================================================
-- Powers "Hot Right Now" (replaces The Full Lineup in the Living Room hub):
-- shows people on ShowUp have that are CURRENT -- the latest season aired in
-- the last 12 months -- so the classics everyone rates at sign-up (Sopranos,
-- Mad Men) don't crowd out today's hits.
--
-- "Current" comes from tracked_seasons.latest_season_air_date, which the
-- daily new-season job (scripts/check-new-seasons.mjs) keeps up to date for
-- every TV show on anyone's lists.
--
-- Same privacy shape as get_full_lineup(): aggregated server-side, never a
-- user_id or rater identity -- just title, platform, poster, and counts.
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
      select coalesce(jsonb_agg(t order by t.people desc, t.avg_rating desc nulls last), '[]'::jsonb)
      from (
        select
          (array_agg(s.title))[1] as title,
          (array_agg(s.platform) filter (where s.platform is not null and s.platform <> '' and s.platform <> 'None'))[1] as platform,
          (array_agg(s.poster_path) filter (where s.poster_path is not null))[1] as poster_path,
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
        limit 25
      ) t
    )
  );
end;
$$;

grant execute on function get_hot_right_now() to authenticated;
