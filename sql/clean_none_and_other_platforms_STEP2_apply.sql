-- STEP 2: applies the backfill reviewed in STEP1. Run STEP1 first and
-- eyeball the results before running this.
update shows s
set platform = b.best_platform
from (
  select distinct on (title_key)
    title_key, platform as best_platform
  from (
    select
      lower(trim(title)) as title_key,
      platform,
      count(*) as n
    from shows
    where platform is not null and platform <> '' and platform not in ('None','Other')
    group by lower(trim(title)), platform
  ) candidates
  order by title_key, n desc, platform asc
) b
where b.title_key = lower(trim(s.title))
  and s.platform in ('None','Other');
