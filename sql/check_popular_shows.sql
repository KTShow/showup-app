-- Run this in Supabase SQL Editor to see the most-added shows across your
-- whole beta group, with their average rating. Useful for spotting trends
-- and as a data point for affiliate/brand partnership conversations.

select
  title,
  count(*) as times_added,
  round(avg(rating) filter (where rating > 0), 1) as avg_rating
from shows
group by title
order by times_added desc
limit 20;
