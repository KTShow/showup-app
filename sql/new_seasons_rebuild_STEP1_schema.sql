-- ============================================================
-- New-season detection, rebuilt server-side (2026-09-01)
-- ============================================================
-- Replaces the old in-browser checkForNewSeasons(), which re-checked TMDB
-- from every user's client on every app load, had no shared source of
-- truth, and kept mis-firing off an inflated season baseline (TMDB counts
-- announced-but-unaired seasons).
--
-- New model:
--   * tracked_seasons  -- one row per unique TMDB show anyone is tracking,
--                         written only by the scheduled checker.
--   * notifications    -- per-user feed; new_season is the first type,
--                         comment / invite types can reuse this table later.
--
-- Run this in the Supabase SQL editor, then run STEP 2.
-- ============================================================

-- ---------- tracked_seasons -------------------------------------------------
create table if not exists tracked_seasons (
  tmdb_id                integer primary key,
  title                  text,
  released_season_count  integer not null default 0,
  latest_season_number   integer,
  latest_season_air_date date,
  last_checked_at        timestamptz not null default now(),
  last_change_at         timestamptz,
  created_at             timestamptz not null default now()
);

-- Only the scheduled checker (service_role, which bypasses RLS) touches this.
alter table tracked_seasons enable row level security;

-- ---------- notifications --------------------------------------------------
create table if not exists notifications (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references auth.users(id) on delete cascade,
  type          text not null,               -- 'new_season'
  title         text not null,               -- show title
  body          text,                        -- e.g. "Season 4 is out"
  show_id       uuid references shows(id) on delete set null,
  tmdb_id       integer,
  season_count  integer,                     -- released-season total at fire time (dedup key)
  season_number integer,                     -- latest season's own number (display)
  seen_at       timestamptz,                 -- bell panel opened past it (clears the dot)
  read_at       timestamptz,                 -- user clicked into it
  created_at    timestamptz not null default now()
);

create index if not exists notifications_user_created_idx
  on notifications (user_id, created_at desc);

-- One notification per user per show per season milestone, so the daily
-- job can re-run / backfill without ever double-notifying.
create unique index if not exists notifications_dedup_idx
  on notifications (user_id, type, tmdb_id, season_count);

alter table notifications enable row level security;

create policy "read own notifications" on notifications
  for select using (auth.uid() = user_id);

create policy "update own notifications" on notifications
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- No insert / delete policy on purpose: rows are created by the scheduled
-- checker using the service_role key (bypasses RLS). Users only ever read
-- their feed and stamp seen_at / read_at.
