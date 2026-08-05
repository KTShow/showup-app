-- STEP 2: applies the backfill reviewed in STEP1. Run STEP1 first and
-- eyeball the results before running this.
update shows s
set source = 'recommendation',
    influenced_by = r.from_user_id
from (
  select distinct on (rec.to_user_id, lower(trim(rec.title)))
    rec.to_user_id, lower(trim(rec.title)) as title_key, rec.from_user_id
  from recommendations rec
  where rec.status = 'added'
  order by rec.to_user_id, lower(trim(rec.title)), rec.resolved_at asc
) r
where r.to_user_id = s.user_id
  and lower(trim(s.title)) = r.title_key
  and s.status in ('watchlist', 'watching')
  and (s.source is distinct from 'recommendation');
