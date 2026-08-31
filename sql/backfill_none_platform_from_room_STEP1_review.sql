-- STEP 1: review only, no changes made.
-- For every show currently tagged platform='None', looks across ALL
-- users' shows for the same title (case-insensitive/trimmed) that
-- already has a real platform set, and shows which platform would be
-- used to backfill it (most users agreeing wins; alphabetical is just
-- the tiebreaker for an exact split, not a preference).
with candidates as (
  select
    lower(trim(title)) as title_key,
    platform,
    count(*) as n
  from shows
  where platform is not null and platform <> '' and platform <> 'None'
  group by lower(trim(title)), platform
),
best as (
  select distinct on (title_key)
    title_key, platform as best_platform, n
  from candidates
  order by title_key, n desc, platform asc
)
select
  s.id as show_id,
  s.user_id,
  s.title,
  s.platform as current_platform,
  b.best_platform as would_set_to,
  b.n as agreement_count
from shows s
join best b on b.title_key = lower(trim(s.title))
where s.platform = 'None'
order by s.user_id, s.title;
