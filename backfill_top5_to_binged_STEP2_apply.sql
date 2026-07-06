-- STEP 2 of 2: APPLIES CHANGES. Run STEP1 first and review the rows it lists.
--
-- For every top5_shows row that lacks a matching rated Binged entry:
--   - if the person already has that show in Binged (watched/dnf) with a different
--     rating, bump it to 5 remotes
--   - otherwise, insert a new Binged (status='watched') row rated 5 remotes
-- This mirrors what the app now does automatically going forward (see autoAddTop5ToBinged
-- in index.html) — this script is only for the Top 5 entries added before that fix shipped.

-- Bump existing show ratings to 5 where they already exist under a different rating.
update shows s
set rating = 5
from top5_shows t
where s.user_id = t.user_id
  and lower(s.title) = lower(t.title)
  and s.status in ('watched', 'dnf')
  and coalesce(s.rating, 0) <> 5;

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
where not exists (
  select 1 from shows s
  where s.user_id = t.user_id
    and lower(s.title) = lower(t.title)
    and s.status in ('watched', 'dnf')
);
