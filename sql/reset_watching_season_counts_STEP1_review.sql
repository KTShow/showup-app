-- Companion to reset_waiting_season_counts -- the new-season check now also
-- covers shows still sitting in Currently Watching (not just ones flagged
-- Waiting for New Season), since people often finish a show without ever
-- flipping that flag. Those rows can carry the same legacy problem: a
-- number_of_seasons captured before today's fix, which may already include
-- a season that was only announced (not aired) at the time it was added.
-- Lists the shows in scope before resetting. Read-only.

select s.id, s.title, s.tmdb_id, s.number_of_seasons, s.added_at, u.email as owner
from shows s
join users u on u.id = s.user_id
where s.status = 'watching' and s.tmdb_id is not null
order by s.title;
