-- Any show added before today's fix could have a number_of_seasons that
-- includes an announced-but-unaired season (the old add-flow code used
-- TMDB's raw count, which counts those). If a show's stored count is
-- already inflated this way, the new-season check can never detect a real
-- increase once that season actually airs (count <= stored, so it never
-- fires) -- a silent, permanent miss. This just lists every currently-
-- waiting show so we know the scope before resetting. Read-only.

select s.id, s.title, s.tmdb_id, s.number_of_seasons, s.waiting_since, u.email as owner
from shows s
join users u on u.id = s.user_id
where s.waiting_for_season = true
order by s.title;
