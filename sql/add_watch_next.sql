-- Watch Next: up to 5 My List shows pinned to the top of My List.
-- Safe to run any time: adds one column, everything starts unpinned.
alter table shows add column if not exists watch_next boolean not null default false;
