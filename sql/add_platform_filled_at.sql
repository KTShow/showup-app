-- Monday service job fills in shows saved as None, once. This stamps when,
-- so a show someone sets back to None is left alone. Safe to run any time.
alter table shows add column if not exists platform_filled_at timestamptz;
