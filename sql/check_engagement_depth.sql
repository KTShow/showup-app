-- Run this in Supabase SQL Editor to see how deeply each beta user is
-- actually using the app: not just "did they log in" but "did they add
-- shows, rate anything, build a Top 5." A user who visits often but shows
-- 0 everywhere else is a warning sign a visit-count-only view won't catch.

select
  u.username,
  u.first_name,
  u.last_initial,
  count(*) filter (where s.status = 'watching') as watching_count,
  count(*) filter (where s.status = 'watchlist') as watchlist_count,
  count(*) filter (where s.status = 'watched' and not s.dnf) as binged_count,
  count(*) filter (where s.dnf) as dnf_count,
  count(*) filter (where s.rating > 0) as rated_count,
  (select count(*) from top5_shows t5 where t5.user_id = u.id) as top5_count,
  count(s.id) as total_shows_added
from users u
left join shows s on s.user_id = u.id
group by u.id, u.username, u.first_name, u.last_initial
order by total_shows_added desc;
