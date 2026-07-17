-- Adds waiting_for_season to shows, so "Waiting for New Season" (currently
-- a client-side-only prototype) can persist across reloads.
-- Kept separate from `status` on purpose: a waiting show is still
-- structurally status='watching' underneath, so existing status-based
-- queries (Friends' Favorites, Living Room "On Right Now") don't need to
-- change or risk breaking.
-- Safe to run any time: additive column, defaults to false, no data loss.

ALTER TABLE shows ADD COLUMN IF NOT EXISTS waiting_for_season boolean NOT NULL DEFAULT false;
