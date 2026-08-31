-- Backs the new "Conversations" tab in Living Room (activity feed of
-- new shows + comments since you last looked, replacing the old
-- per-tile "new" badge). One timestamp per user, updated the moment
-- they open the Conversations tab.

alter table users add column if not exists conversations_last_seen_at timestamptz;
