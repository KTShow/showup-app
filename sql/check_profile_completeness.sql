-- Run this in Supabase SQL Editor to see who has fully filled out "Tell Us More"
-- vs. left it partial. "complete" = all 6 fields have something in them.
-- If this errors on a type mismatch for hobbies/household/discovery, tell Claude
-- the exact error — those columns may be a different type than expected.

select
  username,
  first_name,
  last_initial,
  (career is not null and career <> '') as has_career,
  coalesce(jsonb_array_length(to_jsonb(hobbies)), 0) > 0 as has_hobbies,
  coalesce(jsonb_array_length(to_jsonb(household)), 0) > 0 as has_household,
  (watch_when is not null and watch_when <> '') as has_watch_when,
  (watch_freq is not null and watch_freq <> '') as has_watch_freq,
  coalesce(jsonb_array_length(to_jsonb(discovery)), 0) > 0 as has_discovery,
  (
    (career is not null and career <> '')
    and coalesce(jsonb_array_length(to_jsonb(hobbies)), 0) > 0
    and coalesce(jsonb_array_length(to_jsonb(household)), 0) > 0
    and (watch_when is not null and watch_when <> '')
    and (watch_freq is not null and watch_freq <> '')
    and coalesce(jsonb_array_length(to_jsonb(discovery)), 0) > 0
  ) as fully_complete
from users
order by fully_complete asc, username;
