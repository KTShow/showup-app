-- One-time migration: Waiting for New Season used to live under
-- status='watching'. It now lives under status='watchlist' (My List),
-- same waiting_for_season flag. Existing rows need to move over once so
-- they render in their new home instead of looking like active Watching
-- cards. Safe to re-run — it only touches rows still sitting in the old
-- location.

update shows
set status = 'watchlist'
where status = 'watching'
  and waiting_for_season = true;
