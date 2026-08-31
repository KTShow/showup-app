-- Powers "The Full Lineup" -- a platform-wide browse view of every show
-- anyone on ShowUp has added, rated or not, with just its aggregate
-- rating. Deliberately more restrictive than Prime Time: aggregation
-- happens server-side, so this never returns a user_id or any rater
-- identity at all (not even anonymized as "Neighbor") -- just a title,
-- platform, and an average. No comments, no per-person detail, ever.
--
-- SECURITY DEFINER for the same reason as Prime Time's widen: normal RLS
-- only lets a user see someone else's shows if they share a room, which
-- is exactly the restriction this needs to bypass to be genuinely
-- platform-wide. Same beta-stage placeholder framing as Prime Time --
-- revisit before public App Store launch.
create or replace function get_full_lineup()
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
      select coalesce(jsonb_agg(t), '[]'::jsonb)
      from (
        select
          (array_agg(title))[1] as title,
          (array_agg(platform) filter (where platform is not null and platform <> ''))[1] as platform,
          (array_agg(poster_path) filter (where poster_path is not null))[1] as poster_path,
          (array_agg(tmdb_id) filter (where tmdb_id is not null))[1] as tmdb_id,
          round(avg(rating) filter (where rating > 0), 1) as avg_rating,
          count(*) filter (where rating > 0) as rating_count
        from shows
        where hidden = false
        group by lower(title)
      ) t
    )
  );
end;
$$;

grant execute on function get_full_lineup() to authenticated;
