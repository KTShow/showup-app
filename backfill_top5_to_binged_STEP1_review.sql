-- STEP 1 of 2: REVIEW ONLY, makes no changes.
--
-- Context: adding a show to "Top 5 of All Time" is supposed to also auto-add it to
-- Binged with a 5-remote rating (so it counts toward Friends' Favorites). That wiring
-- was missing from the Profile screen's Top 5 widget, so anyone who added their Top 5
-- there (e.g. Kathleen, Elizabeth) before the fix has top5_shows rows with no matching
-- rated Binged entry. This script finds exactly those rows so we can see who's affected
-- before touching any data. Run backfill_top5_to_binged_STEP2_apply.sql after reviewing.

select
  u.username,
  u.first_name,
  u.last_initial,
  t.rank,
  t.title,
  t.platform,
  s.id as existing_show_id,
  s.status as existing_status,
  s.rating as existing_rating
from top5_shows t
join users u on u.id = t.user_id
left join shows s
  on s.user_id = t.user_id
  and lower(s.title) = lower(t.title)
  and s.status in ('watched', 'dnf')
where s.id is null or coalesce(s.rating, 0) <> 5
order by u.username, t.rank;
