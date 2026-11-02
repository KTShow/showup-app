-- ============================================================
-- report_onboarding_impact.sql  (2026-11-02)
-- ============================================================
-- Is the new-member show picker (First Shows, live 2026-10-22) and the
-- daily show question (live 2026-10-26) getting people to add/rate more?
-- Read-only. Leaves out admins and test/duplicate accounts.
--
-- Limit: shows has no "rated at" time, so a rating given to a show that
-- was already on someone's list can't be dated. Only shows ADDED in each
-- period (and whether they're rated now) are counted.
--
-- Run each query on its own in the Supabase SQL editor.
-- ============================================================

-- ---------- 1. New members: first 2 days, before vs after the picker ----
with m as (
  select u.id, coalesce(u.created_at, a.created_at) as joined
  from users u join auth.users a on a.id = u.id
  where coalesce(u.first_name, '') <> ''
    and not coalesce(u.exclude_from_reports, false)
    and not coalesce(u.is_admin, false)
), x as (
  select m.joined,
         (select count(*) from shows s where s.user_id = m.id
           and s.added_at < m.joined + interval '2 days') as n_shows,
         (select count(*) from shows s where s.user_id = m.id
           and s.added_at < m.joined + interval '2 days' and coalesce(s.rating, 0) > 0) as n_rated
  from m
  where m.joined >= timestamptz '2026-09-22'
)
select case when joined >= timestamptz '2026-10-22 15:35+00'
            then '2. Joined Oct 22 or later (with picker)'
            else '1. Joined Sep 22 - Oct 21 (before)' end as grp,
       count(*) as members,
       round(avg(n_shows), 1) as avg_shows_first_2_days,
       round(avg(n_rated), 1) as avg_rated_first_2_days,
       count(*) filter (where n_shows = 0) as added_nothing
from x
group by 1
order by 1;

-- ---------- 2. Existing members: shows added per day, before vs after ---
with p(period, starts, ends) as (
  values ('1. Before: Oct 12 - Oct 26', timestamptz '2026-10-12 04:00+00', timestamptz '2026-10-26 16:27+00'),
         ('2. After: Oct 26 - now (daily question on)', timestamptz '2026-10-26 16:27+00', now())
), members as (
  select u.id, coalesce(u.created_at, timestamptz '2000-01-01') as joined
  from users u
  where coalesce(u.first_name, '') <> ''
    and not coalesce(u.exclude_from_reports, false)
    and not coalesce(u.is_admin, false)
)
select p.period,
       round((extract(epoch from p.ends - p.starts) / 86400)::numeric, 1) as days,
       count(s.id) as shows_added,
       round(count(s.id) / (extract(epoch from p.ends - p.starts) / 86400)::numeric, 1) as added_per_day,
       count(s.id) filter (where coalesce(s.rating, 0) > 0) as of_those_rated_now,
       count(distinct s.user_id) as members_adding,
       (select count(distinct se.user_id) from sessions se join members mm on mm.id = se.user_id
         where se.created_at >= p.starts and se.created_at < p.ends) as members_who_visited
from p
left join shows s
  on s.added_at >= p.starts and s.added_at < p.ends
 and s.user_id in (select mm.id from members mm where mm.joined < p.starts)
group by p.period, p.starts, p.ends
order by p.period;

-- ---------- 3. From 2026-11-02 on: adds and ratings by screen -----------
-- Needs sql/add_rated_at.sql. Adds from the show pickers carry a source;
-- ratings carry a date, so a rating given to a show already on someone's
-- list now counts too. Change the date to look at a different stretch.
select coalesce(s.source, 'manual') as came_from,
       count(*) filter (where s.added_at >= timestamptz '2026-11-02') as shows_added,
       count(*) filter (where s.rated_at >= timestamptz '2026-11-02') as ratings_given,
       count(distinct s.user_id) filter (where s.added_at >= timestamptz '2026-11-02'
                                            or s.rated_at >= timestamptz '2026-11-02') as members
from shows s
join users u on u.id = s.user_id
where not coalesce(u.exclude_from_reports, false)
  and not coalesce(u.is_admin, false)
  and (s.added_at >= timestamptz '2026-11-02' or s.rated_at >= timestamptz '2026-11-02')
group by 1
order by shows_added desc;
