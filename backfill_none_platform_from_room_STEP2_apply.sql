-- STEP 2: applies the backfill reviewed in STEP1. Run STEP1 first and
-- eyeball the results before running this. Shows with no match anywhere
-- else in the room (nobody else has that title tagged with a real
-- platform) are left as 'None' -- there's nothing to backfill from.
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
    title_key, platform as best_platform
  from candidates
  order by title_key, n desc, platform asc
)
update shows s
set platform = b.best_platform
from best b
where b.title_key = lower(trim(s.title))
  and s.platform = 'None';
