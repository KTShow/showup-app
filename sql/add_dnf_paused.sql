-- Didn't Finish split: Paused (I'll go back) vs Not for me.
-- Safe to run any time: adds one column, every existing Didn't Finish show starts as Not for me.
alter table shows add column if not exists dnf_paused boolean not null default false;
