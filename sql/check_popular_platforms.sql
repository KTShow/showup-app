-- Run this in Supabase SQL Editor to see which streaming platforms show up
-- most often across your whole beta group's shows.

select
  platform,
  count(*) as times_used
from shows
where platform is not null and platform <> ''
group by platform
order by times_used desc;
