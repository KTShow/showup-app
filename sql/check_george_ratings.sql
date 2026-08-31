-- Diagnostic, read-only. George reports: shows he's rated (e.g. Detectorists)
-- show up as rated in The Full Lineup, but appear unrated in his own Binged tab.
--
-- Full Lineup's rating average (get_full_lineup RPC) aggregates every row in
-- `shows` with rating > 0, grouped by lower(title), across ALL users and ALL
-- statuses (watching/watchlist/watched/dnf) -- not just the one row that
-- shows up in a given user's own Binged tab. So this checks two things at
-- once: (1) does George have more than one row for the same title (a
-- pre-dedup-fix duplicate, one rated / one not), and (2) does George have
-- more than one account (a rating sitting under an orphaned duplicate
-- profile instead of his real one).

-- Part 1: every row for every title George has touched, across all his
-- accounts if he has more than one -- reveals duplicate rows per title.
select
  u.username,
  u.first_name,
  u.last_initial,
  u.id as user_id,
  s.id as show_id,
  s.title,
  s.status,
  s.dnf,
  s.rating,
  s.hidden,
  s.added_at
from shows s
join users u on u.id = s.user_id
where u.first_name ilike 'george%'
order by lower(s.title), u.username, s.added_at;

-- Part 2: specifically Detectorists, across everyone, to see the exact
-- rows Full Lineup is averaging together for that title.
select
  u.username,
  u.first_name,
  u.last_initial,
  s.title,
  s.status,
  s.dnf,
  s.rating,
  s.hidden
from shows s
join users u on u.id = s.user_id
where s.title ilike '%detectorists%'
order by lower(s.title), u.username;
