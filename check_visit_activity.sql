-- Run this in Supabase SQL Editor to see how often each beta user has
-- visited the app and when they were last here. Uses the sessions table
-- (one row is logged automatically every time someone opens the app) —
-- NOT the users.last_active field, which only updates when someone saves
-- their profile and is not a reliable "last visited" signal.
-- If this errors on "column s.created_at does not exist," tell Claude the
-- exact error/column name so the query can be adjusted.

select
  u.username,
  u.first_name,
  u.last_initial,
  count(s.id) as total_visits,
  max(s.created_at) as last_visit,
  now() - max(s.created_at) as time_since_last_visit
from users u
left join sessions s on s.user_id = u.id
group by u.id, u.username, u.first_name, u.last_initial
order by last_visit desc nulls last;
