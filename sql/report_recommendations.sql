-- Read-only. Run in the Supabase SQL Editor: how much "Recommend to a friend" gets
-- used, all time and in the last 30 days, split between admins and other members.
-- Each recipient counts as one recommendation. Leaves out accounts flagged
-- exclude_from_reports.

with recs as (
  select
    r.from_user_id,
    r.status,
    r.created_at,
    case when coalesce(u.is_admin, false) then 'Admins' else 'Members' end as who
  from recommendations r
  join users u on u.id = r.from_user_id
  where coalesce(u.exclude_from_reports, false) = false
),
periods as (
  select 'All time' as period, r.* from recs r
  union all
  select 'Last 30 days' as period, r.* from recs r
  where r.created_at > now() - interval '30 days'
)
select
  period,
  who,
  count(*) as recommendations_sent,
  count(distinct from_user_id) as people_who_sent,
  count(*) filter (where status = 'added') as added,
  count(*) filter (where status = 'dismissed') as dismissed,
  count(*) filter (where status = 'pending') as no_answer_yet,
  round(100.0 * count(*) filter (where status = 'added') / count(*)) as percent_added
from periods
group by period, who
order by period, who;
