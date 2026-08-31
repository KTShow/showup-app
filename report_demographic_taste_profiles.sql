-- REPORT: Demographic Taste Profiles
-- Matches the exact kind of stat our privacy policy says we may share:
-- "ShowUp users aged 40-49 who list cooking as a hobby rate prestige dramas
--  an average of 4.2 remotes" (privacy 0528.html, "Data Sharing" section).
--
-- Both queries below:
--   - only use rated shows (rating > 0) so unrated adds don't dilute averages
--   - exclude Tracey/test accounts (same filter used in cleanup_test_accounts_STEP1_review.sql)
--   - suppress any group smaller than 5 users (HAVING count >= 5) so no
--     small group can be traced back to an individual person
--
-- Run this in the Supabase SQL Editor. Read-only, changes nothing.


-- QUERY A: Genre taste by age range + gender
-- "Which demo segments rate which genres highest"
select
  u.age_range,
  u.gender,
  s.genre,
  count(*) as rating_count,
  round(avg(s.rating)::numeric, 2) as avg_rating
from shows s
join users u on u.id = s.user_id
where s.rating > 0
  and s.genre is not null
  and u.age_range is not null
  and u.gender is not null
  and u.username not ilike 'tracey%'
  and u.username not ilike 'showup%'
group by u.age_range, u.gender, s.genre
having count(*) >= 5
order by u.age_range, u.gender, avg_rating desc;


-- QUERY B: Genre taste by hobby
-- Same idea as Query A but cut by hobby instead of age/gender — this is the
-- exact combination used in the privacy policy's own example.
-- hobbies is stored as an array (jsonb or text[] depending on how it was
-- created) — to_jsonb() + jsonb_array_elements_text() handles either. If this
-- errors on a type mismatch, tell Claude the exact error.
select
  hobby.value as hobby,
  s.genre,
  count(*) as rating_count,
  round(avg(s.rating)::numeric, 2) as avg_rating
from shows s
join users u on u.id = s.user_id
cross join lateral jsonb_array_elements_text(to_jsonb(u.hobbies)) as hobby(value)
where s.rating > 0
  and s.genre is not null
  and u.username not ilike 'tracey%'
  and u.username not ilike 'showup%'
group by hobby.value, s.genre
having count(*) >= 5
order by hobby.value, avg_rating desc;


-- QUERY C: Over-indexing by age range + gender
-- Same cut as Query A, but compares each genre average against that same
-- group's OWN overall average rating (across all genres). This separates
-- "this demo just rates everything generously" from "this demo specifically
-- loves this genre." over_index > 0 means they rate that genre above their
-- own baseline; over_index < 0 means below.
-- Baseline requires at least 10 total ratings for the group to be trusted.
with baseline as (
  select
    u.age_range,
    u.gender,
    count(*) as group_total_ratings,
    round(avg(s.rating)::numeric, 2) as baseline_avg
  from shows s
  join users u on u.id = s.user_id
  where s.rating > 0
    and u.age_range is not null
    and u.gender is not null
    and u.username not ilike 'tracey%'
    and u.username not ilike 'showup%'
  group by u.age_range, u.gender
),
genre_stats as (
  select
    u.age_range,
    u.gender,
    s.genre,
    count(*) as rating_count,
    round(avg(s.rating)::numeric, 2) as avg_rating
  from shows s
  join users u on u.id = s.user_id
  where s.rating > 0
    and s.genre is not null
    and u.age_range is not null
    and u.gender is not null
    and u.username not ilike 'tracey%'
    and u.username not ilike 'showup%'
  group by u.age_range, u.gender, s.genre
  having count(*) >= 5
)
select
  g.age_range,
  g.gender,
  g.genre,
  g.rating_count,
  g.avg_rating,
  b.baseline_avg,
  b.group_total_ratings,
  round((g.avg_rating - b.baseline_avg)::numeric, 2) as over_index
from genre_stats g
join baseline b on b.age_range = g.age_range and b.gender = g.gender
where b.group_total_ratings >= 10
order by g.age_range, g.gender, over_index desc;


-- QUERY D: Over-indexing by hobby
-- Same idea as Query C, cut by hobby instead of age/gender.
with baseline as (
  select
    hobby.value as hobby,
    count(*) as group_total_ratings,
    round(avg(s.rating)::numeric, 2) as baseline_avg
  from shows s
  join users u on u.id = s.user_id
  cross join lateral jsonb_array_elements_text(to_jsonb(u.hobbies)) as hobby(value)
  where s.rating > 0
    and u.username not ilike 'tracey%'
    and u.username not ilike 'showup%'
  group by hobby.value
),
genre_stats as (
  select
    hobby.value as hobby,
    s.genre,
    count(*) as rating_count,
    round(avg(s.rating)::numeric, 2) as avg_rating
  from shows s
  join users u on u.id = s.user_id
  cross join lateral jsonb_array_elements_text(to_jsonb(u.hobbies)) as hobby(value)
  where s.rating > 0
    and s.genre is not null
    and u.username not ilike 'tracey%'
    and u.username not ilike 'showup%'
  group by hobby.value, s.genre
  having count(*) >= 5
)
select
  g.hobby,
  g.genre,
  g.rating_count,
  g.avg_rating,
  b.baseline_avg,
  b.group_total_ratings,
  round((g.avg_rating - b.baseline_avg)::numeric, 2) as over_index
from genre_stats g
join baseline b on b.hobby = g.hobby
where b.group_total_ratings >= 10
order by g.hobby, over_index desc;


-- QUERY E: Over-indexing by household type
-- Same idea as Query D, cut by "who you watch with" (household is stored as
-- an array — Couple, Empty nester, Family with teens, Family with young kids,
-- Friends, Myself, Roommates) instead of hobby.
with baseline as (
  select
    household.value as household,
    count(*) as group_total_ratings,
    round(avg(s.rating)::numeric, 2) as baseline_avg
  from shows s
  join users u on u.id = s.user_id
  cross join lateral jsonb_array_elements_text(to_jsonb(u.household)) as household(value)
  where s.rating > 0
    and u.username not ilike 'tracey%'
    and u.username not ilike 'showup%'
  group by household.value
),
genre_stats as (
  select
    household.value as household,
    s.genre,
    count(*) as rating_count,
    round(avg(s.rating)::numeric, 2) as avg_rating
  from shows s
  join users u on u.id = s.user_id
  cross join lateral jsonb_array_elements_text(to_jsonb(u.household)) as household(value)
  where s.rating > 0
    and s.genre is not null
    and u.username not ilike 'tracey%'
    and u.username not ilike 'showup%'
  group by household.value, s.genre
  having count(*) >= 5
)
select
  g.household, g.genre, g.rating_count, g.avg_rating,
  b.baseline_avg, b.group_total_ratings,
  round((g.avg_rating - b.baseline_avg)::numeric, 2) as over_index
from genre_stats g
join baseline b on b.household = g.household
where b.group_total_ratings >= 10
order by g.household, over_index desc;


-- QUERY F: Discovery channel vs. satisfaction
-- Different shape than the others: this isn't genre affinity, it's "does how
-- someone found a show predict how much they end up liking it." Two signals:
--   - avg_rating vs. the site-wide baseline (rating_vs_baseline)
--   - dnf_rate_pct: % of everything that discovery channel added that got
--     marked Didn't Finish (a second satisfaction signal independent of rating)
-- Both cuts require at least 10 shows for that discovery channel to appear.
with baseline as (
  select round(avg(s.rating)::numeric, 2) as overall_avg
  from shows s
  join users u on u.id = s.user_id
  where s.rating > 0
    and u.username not ilike 'tracey%'
    and u.username not ilike 'showup%'
),
exploded as (
  select u.id as user_id, discovery.value as discovery
  from users u
  cross join lateral jsonb_array_elements_text(to_jsonb(u.discovery)) as discovery(value)
  where u.username not ilike 'tracey%'
    and u.username not ilike 'showup%'
),
rating_stats as (
  select
    e.discovery,
    count(*) as rating_count,
    round(avg(s.rating)::numeric, 2) as avg_rating
  from exploded e
  join shows s on s.user_id = e.user_id
  where s.rating > 0
  group by e.discovery
  having count(*) >= 10
),
dnf_stats as (
  select
    e.discovery,
    count(*) as shows_added,
    sum(case when s.dnf then 1 else 0 end) as dnf_count,
    round(100.0 * sum(case when s.dnf then 1 else 0 end) / count(*), 1) as dnf_rate_pct
  from exploded e
  join shows s on s.user_id = e.user_id
  group by e.discovery
  having count(*) >= 10
)
select
  r.discovery,
  r.rating_count,
  r.avg_rating,
  b.overall_avg,
  round((r.avg_rating - b.overall_avg)::numeric, 2) as rating_vs_baseline,
  d.shows_added,
  d.dnf_count,
  d.dnf_rate_pct
from rating_stats r
join dnf_stats d on d.discovery = r.discovery
cross join baseline b
order by rating_vs_baseline desc;


-- QUERY G: Discovery channel DNF rate, fair version
-- Query F's dnf_rate_pct divided by EVERYTHING a channel ever added, including
-- shows still sitting in Watching or Watchlist that haven't been resolved
-- either way yet. If channels differ in how much of their volume is still
-- "in limbo," that alone can fake a DNF-rate difference that has nothing to
-- do with recommendation quality. This version divides by RESOLVED shows only
-- (status = 'watched' or 'dnf') so every channel is compared on the same
-- basis: of what's actually been finished or abandoned, how much was abandoned?
with exploded as (
  select u.id as user_id, discovery.value as discovery
  from users u
  cross join lateral jsonb_array_elements_text(to_jsonb(u.discovery)) as discovery(value)
  where u.username not ilike 'tracey%'
    and u.username not ilike 'showup%'
)
select
  e.discovery,
  count(*) filter (where s.status in ('watched','dnf')) as resolved_count,
  count(*) filter (where s.status = 'dnf') as dnf_count,
  round(
    100.0 * count(*) filter (where s.status = 'dnf')
    / nullif(count(*) filter (where s.status in ('watched','dnf')), 0)
  , 1) as dnf_rate_of_resolved_pct,
  count(*) as shows_added,
  round(
    100.0 * count(*) filter (where s.status in ('watching','watchlist'))
    / count(*)
  , 1) as still_unresolved_pct
from exploded e
join shows s on s.user_id = e.user_id
group by e.discovery
having count(*) filter (where s.status in ('watched','dnf')) >= 10
order by dnf_rate_of_resolved_pct asc;
