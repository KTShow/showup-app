-- Run this in Supabase SQL Editor to see every distinct platform label
-- currently stored, and how many shows use each. Look for near-duplicates
-- (like the "Amazon Prime Video" / "Amazon Prime" split that was just
-- fixed) -- most likely suspect here is "PBS+" vs "PBS Passport", renamed
-- in the same commit as the Amazon one but never confirmed to have shipped
-- to any live rows.
select
  platform,
  count(*) as times_used
from shows
where platform is not null and platform <> ''
group by platform
order by platform;
