-- Clears the false "New season!" flags found by
-- audit_false_new_season_flags_STEP1_review.sql. These were set by the old
-- checkForNewSeasons() logic, which compared TMDB's raw number_of_seasons --
-- a count that includes announced-but-unaired seasons -- so the badge could
-- fire months before a season actually aired.
--
-- Resets both new_season_available and number_of_seasons to null so the
-- corrected client-side logic (released seasons only) recomputes a clean
-- baseline the next time each affected user opens the app, instead of
-- comparing against the old inflated count.

update shows
set new_season_available = false, number_of_seasons = null
where waiting_for_season = true and new_season_available = true;
