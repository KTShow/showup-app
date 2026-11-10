-- ============================================================
-- add_daily_prompt_events.sql  (2026-11-10)
-- ============================================================
-- Records what happens in the daily show popup, so we can prove whether
-- it works: how often it opens, how often people answer vs tap Not now,
-- and the ratings, adds and comments it produces.
--
-- event: shown (value = number of shows), rate (value = 1-5),
--        add_binged, add_list, snooze, comment (value = length),
--        done / not_now (value = how many shows were answered)
-- kind:  own (one of their shows) / friend (a friend's show)
--
-- Members can only add their own rows; only admins can read them.
-- Run in the Supabase SQL editor. Safe to re-run.
-- ============================================================

create table if not exists daily_prompt_events (
  id bigserial primary key,
  user_id uuid not null default auth.uid() references users(id) on delete cascade,
  event text not null,
  kind text,
  show_id text,
  show_title text,
  value int,
  created_at timestamptz not null default now()
);

create index if not exists daily_prompt_events_created on daily_prompt_events (created_at);

alter table daily_prompt_events enable row level security;

do $$ begin
  create policy dpe_insert_own on daily_prompt_events for insert with check (auth.uid() = user_id);
exception when duplicate_object then null; end $$;

do $$ begin
  create policy dpe_admin_read on daily_prompt_events for select using (user_is_admin());
exception when duplicate_object then null; end $$;
