-- Records when a show was marked "Waiting for New Season", so the new-season
-- check can tell whether a season that already aired dropped before or after
-- the user started waiting on it (instead of only ever comparing season
-- *counts*, which breaks for shows added without a season count on record --
-- see checkForNewSeasons() in index.html).
-- Safe to run any time: additive column, defaults to null, no data loss.

ALTER TABLE shows ADD COLUMN IF NOT EXISTS waiting_since timestamptz;
