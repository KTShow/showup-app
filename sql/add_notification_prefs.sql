-- ============================================================
-- add_notification_prefs.sql  (2026-09-03)
-- ============================================================
-- Per-user on/off for notification types. Surfaced as toggles under
-- Settings > Notifications. The daily checker (scripts/check-new-seasons.mjs)
-- is what honours them -- a muted type stops producing bell rows (and,
-- later, phone push). The "New season!" card badge is passive state, not
-- an alert, so it still shows.
--
-- One row per user; NO row = everything on (the client and checker both
-- treat absence / null as enabled). First toggle upserts the row.
--
-- Today there's one real type ('new_season', which covers both the dated
-- heads-up and the day-of alert). Recommendation / comment / invite
-- columns get added here as those senders get built.
--
-- Run in the Supabase SQL editor. Safe to re-run.
-- ============================================================

create table if not exists notification_prefs (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  new_season boolean not null default true,
  updated_at timestamptz not null default now()
);

alter table notification_prefs enable row level security;

do $$ begin
  create policy "read own notification prefs" on notification_prefs
    for select using (auth.uid() = user_id);
exception when duplicate_object then null; end $$;

do $$ begin
  create policy "insert own notification prefs" on notification_prefs
    for insert with check (auth.uid() = user_id);
exception when duplicate_object then null; end $$;

do $$ begin
  create policy "update own notification prefs" on notification_prefs
    for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
exception when duplicate_object then null; end $$;

-- The checker reads every row with the service-role key (bypasses RLS).
