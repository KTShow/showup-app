-- Weekly "service moved" check (scripts/refresh-platforms.mjs).
-- One row per show + old service that looked like it moved last week.
-- A show's saved service is only changed when the SAME move shows up two
-- weekly checks in a row, so TMDB flip-flops don't cause churn.
-- Only the server job (service role) touches this table; RLS on, no policies.
-- Safe to run any time.
create table if not exists platform_moves (
  tmdb_id       integer not null,
  media_type    text    not null default 'tv',
  from_platform text    not null,
  to_platform   text    not null,
  first_seen    timestamptz not null default now(),
  primary key (tmdb_id, media_type, from_platform)
);
alter table platform_moves enable row level security;
