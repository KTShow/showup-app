-- ============================================================
-- add_notification_dismissed_at.sql  (2026-09-03)
-- ============================================================
-- Lets a user dismiss ("delete") a notification from the bell dropdown.
--
-- Soft delete, not a real DELETE, on purpose:
--   * scripts/check-new-seasons.mjs re-inserts season_upcoming rows with
--     INSERT ... ON CONFLICT DO NOTHING -- that only suppresses a re-insert
--     while the row still EXISTS. A hard-deleted heads-up would silently
--     come back on the next daily run. Keeping the row (with dismissed_at
--     set) keeps it dismissed.
--   * Reuses the existing "update own notifications" RLS policy -- no new
--     delete policy / permission surface.
--   * Recoverable if someone fat-fingers it.
--
-- Run in the Supabase SQL editor. Safe to re-run.
-- ============================================================

alter table notifications
  add column if not exists dismissed_at timestamptz;

-- The bell feed query filters on (user_id, dismissed_at is null) -- keep that
-- lookup cheap as the table accumulates dismissed rows.
create index if not exists notifications_user_active_idx
  on notifications (user_id, created_at desc)
  where dismissed_at is null;
