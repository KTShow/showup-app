-- Read-only. Run in the Supabase SQL Editor: one row per age range, showing how
-- many members are in it and how active they are. Leaves out admins and accounts
-- flagged exclude_from_reports, and anyone who never finished the profile form.

with members as (
  select id, coalesce(nullif(age_range, ''), 'Not given') as age
  from users
  where coalesce(is_admin, false) = false
    and coalesce(exclude_from_reports, false) = false
    and coalesce(first_name, '') <> ''
),
per_person as (
  select
    m.age,
    (select count(*) from sessions s where s.user_id = m.id and s.created_at > now() - interval '7 days') as visits_7d,
    (select count(*) from sessions s where s.user_id = m.id and s.created_at > now() - interval '30 days') as visits_30d,
    (select count(*) from shows sh where sh.user_id = m.id) as shows,
    (select count(*) from shows sh where sh.user_id = m.id and coalesce(sh.rating, 0) > 0) as rated,
    (select count(*) from reactions r where r.user_id = m.id) as comments
  from members m
)
select
  age,
  count(*) as members,
  count(*) filter (where visits_7d > 0) as active_last_7_days,
  count(*) filter (where visits_30d > 0) as active_last_30_days,
  sum(visits_30d) as visits_last_30_days,
  round(avg(visits_30d), 1) as visits_per_member_30d,
  round(avg(shows), 1) as shows_per_member,
  round(avg(rated), 1) as ratings_per_member,
  sum(comments) as total_comments
from per_person
group by age
order by age;
