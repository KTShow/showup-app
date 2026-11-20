-- Settings > My services: which streaming services each person has.
-- Used when a show is added (label it with one you have) and by the
-- Monday job scripts/refresh-platforms.mjs. Safe to run any time.
alter table users add column if not exists my_services text[] not null default '{}';
