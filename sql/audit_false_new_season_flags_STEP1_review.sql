-- Finds shows currently flagged new_season_available = true so we can see
-- how many exist before deciding whether to reset them. These were flagged
-- by the old checkForNewSeasons() logic, which compared TMDB's raw
-- number_of_seasons -- a count that includes announced-but-unaired seasons,
-- so some of these are false positives (flagged before the season actually
-- aired). Read-only, changes nothing.

select s.id, s.title, s.tmdb_id, s.number_of_seasons, s.waiting_since, u.email as owner
from shows s
join users u on u.id = s.user_id
where s.waiting_for_season = true and s.new_season_available = true
order by s.title;
