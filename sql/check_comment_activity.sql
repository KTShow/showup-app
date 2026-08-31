-- Run this in Supabase SQL Editor to see how many comments each beta user
-- has posted, plus what share of ALL comments that is (pct_of_all_comments) —
-- this tells you if commenting is spread across the group or carried by
-- just a couple of people.

select
  u.username,
  u.first_name,
  u.last_initial,
  count(r.id) as total_comments,
  round(100.0 * count(r.id) / nullif(sum(count(r.id)) over (), 0), 1) as pct_of_all_comments,
  max(r.reacted_at) as last_comment_at
from users u
left join reactions r on r.user_id = u.id
group by u.id, u.username, u.first_name, u.last_initial
order by total_comments desc;
