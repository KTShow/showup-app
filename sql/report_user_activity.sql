-- Run this in Supabase SQL Editor: one row per person who ever got a login
-- code, with email, whether they finished the profile form, how many shows
-- they've added, how many times they've opened the app, and when they were
-- last here. Combines check_visit_activity.sql + check_engagement_depth.sql
-- and adds people who never finished the profile (they have a login but no
-- name saved). Filter on profile_done = 'NO' to see profile-form dropouts.

select
  a.email,
  u.first_name,
  u.last_initial,
  case when u.first_name is null or u.first_name = '' then 'NO' else 'yes' end as profile_done,
  u.city,
  u.state,
  a.created_at::date as signed_up,
  (select count(*) from shows sh where sh.user_id = a.id) as shows_added,
  (select count(*) from sessions s where s.user_id = a.id) as total_visits,
  (select max(s.created_at) from sessions s where s.user_id = a.id)::date as last_visit,
  current_date - (select max(s.created_at) from sessions s where s.user_id = a.id)::date as days_since_last_visit
from auth.users a
left join users u on u.id = a.id
order by last_visit desc nulls last, a.created_at desc;
