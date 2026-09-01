-- Resets number_of_seasons to null for every currently-waiting show, so the
-- corrected client-side logic (checkForNewSeasons in index.html, which
-- counts only actually-aired seasons) recomputes a clean baseline for each
-- one the next time its owner opens the app -- instead of possibly carrying
-- forward an inflated count from before today's fix that included a season
-- which hadn't aired yet at add time.
--
-- Safe: a null baseline just makes the client re-fetch TMDB and set a fresh,
-- correct count on the next check (see checkForNewSeasons). It does not
-- change waiting_for_season, new_season_available, or anything else.

update shows
set number_of_seasons = null
where waiting_for_season = true;
