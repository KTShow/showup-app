-- Review-only: finds every (user, show title) pair with more than one row.
-- Doesn't change anything. Run STEP2 (a separate script) only after
-- reviewing this and deciding it's safe to clean up.
select user_id, title, count(*) as row_count,
       array_agg(status order by added_at) as statuses,
       array_agg(added_at order by added_at) as added_dates
from shows
group by user_id, title
having count(*) > 1
order by row_count desc;
