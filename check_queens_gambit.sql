-- Diagnostic, read-only. Shows every Binged row that looks like "Queen's Gambit"
-- across all users, with the exact title text, status, rating, and hidden flag,
-- so we can see the exact spelling/punctuation variants splitting it into separate
-- Friends' Favorites entries instead of merging into one.

select
  u.username,
  u.first_name,
  u.last_initial,
  s.title,
  s.status,
  s.rating,
  s.hidden
from shows s
join users u on u.id = s.user_id
where s.title ilike '%gambit%'
order by lower(s.title), u.username;
