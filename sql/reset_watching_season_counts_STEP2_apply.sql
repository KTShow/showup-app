-- Resets number_of_seasons to null for every show currently in Watching, so
-- the new-season check (now covering Watching too, see checkForNewSeasons in
-- index.html) recomputes a clean, correctly-released-only baseline for each
-- one on next check -- instead of possibly carrying forward a count that
-- already included a season which hadn't aired yet when it was added.
--
-- Safe: does not touch status, ratings, or anything else. A null baseline
-- just makes the client re-fetch TMDB and set a fresh count.

update shows
set number_of_seasons = null
where status = 'watching';
