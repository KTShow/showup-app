-- STEP 2 of 2: APPLIES CHANGES. Run STEP1 first and review the rows it lists.
--
-- For every top5_shows row (excluding test accounts) that lacks a matching rated
-- Binged entry:
--   - if the person already has that show in Binged (watched/dnf) with a different
--     rating, bump it to 5 remotes
--   - otherwise, insert a new Binged (status='watched') row rated 5 remotes
-- This mirrors what the app now does automatically going forward (see autoAddTop5ToBinged
-- in index.html) — this script is only for the Top 5 entries added before that fix shipped.
--
-- Test accounts (Show U, Tracey-test with AA/BB/CC shows) are excluded below —
-- update EXCLUDED_USERNAMES if that list changes.

-- Bump existing show ratings to 5 where they already exist under a different rating.
update shows s
set rating = 5
from top5_shows t
join users u on u.id = t.user_id
where s.user_id = t.user_id
  and lower(s.title) = lower(t.title)
  and s.status in ('watched', 'dnf')
  and coalesce(s.rating, 0) <> 5
  and u.username not in ('show-u-96ez', 'tracey-k-5nfz');

-- Insert new Binged rows (rated 5) for Top 5 picks with no matching show at all.
insert into shows (user_id, title, platform, status, rating, source)
select
  t.user_id,
  t.title,
  coalesce(nullif(t.platform, ''), 'Other'),
  'watched',
  5,
  'manual'
from top5_shows t
join users u on u.id = t.user_id
where u.username not in ('show-u-96ez', 'tracey-k-5nfz')
  and not exists (
  select 1 from shows s
  where s.user_id = t.user_id
    and lower(s.title) = lower(t.title)
    and s.status in ('watched', 'dnf')
);
