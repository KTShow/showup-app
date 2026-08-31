-- Run this in Supabase SQL Editor for a quick retention snapshot: how many
-- of your beta users have actually come back recently. "Active" means at
-- least one visit logged in that window. This is the number that matters
-- more than any single "last visited" list -- it shows the trend, not just
-- a point-in-time snapshot.

select
  count(distinct u.id) as total_beta_users,
  count(distinct u.id) filter (
    where exists (select 1 from sessions s where s.user_id = u.id and s.created_at > now() - interval '7 days')
  ) as active_last_7_days,
  count(distinct u.id) filter (
    where exists (select 1 from sessions s where s.user_id = u.id and s.created_at > now() - interval '14 days')
  ) as active_last_14_days,
  count(distinct u.id) filter (
    where exists (select 1 from sessions s where s.user_id = u.id and s.created_at > now() - interval '30 days')
  ) as active_last_30_days
from users u;
