-- Diagnostic, read-only. Shows every Binged row that looks like "Game of Thrones"
-- across all users, with the exact title text, status, rating, and hidden flag,
-- so we can see why only some of them are merging into one Friends' Favorites entry.

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
where s.title ilike '%thrones%'
order by lower(s.title), u.username;
