-- Adds tmdb_id to top5_shows so Top 5 poster thumbnails can open the new
-- show-details popup (matches the tmdb_id already stored on the shows table).
-- Safe to run any time: additive column, nullable, no data loss.

ALTER TABLE top5_shows ADD COLUMN IF NOT EXISTS tmdb_id integer;

-- Backfill existing Top 5 rows by matching title against the shows table
-- (Top 5 picks are always auto-mirrored into Binged, so a matching shows
-- row with the same title/user should already exist and carry tmdb_id).
UPDATE top5_shows t
SET tmdb_id = s.tmdb_id
FROM shows s
WHERE t.user_id = s.user_id
  AND lower(trim(t.title)) = lower(trim(s.title))
  AND t.tmdb_id IS NULL
  AND s.tmdb_id IS NOT NULL;
