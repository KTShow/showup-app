-- STEP 1: review only, no changes made.
-- "Amazon Prime Video" was the dropdown's old label for Amazon's platform,
-- renamed to "Amazon Prime" on 2026-07-08. Shows added before that date
-- still carry the old label. This shows exactly what STEP2 would update.
select
  id as show_id,
  user_id,
  title,
  platform as current_platform,
  'Amazon Prime' as would_set_to
from shows
where platform = 'Amazon Prime Video'
order by user_id, title;
