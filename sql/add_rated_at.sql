-- ============================================================
-- add_rated_at.sql  (2026-11-02)
-- ============================================================
-- Records WHEN a show was rated, so reports can tell whether the daily
-- show question / catch-up screens get people rating. shows.source already
-- says where an add came from; the app now also tags adds from its show
-- pickers ('first_shows', 'daily_prompt', 'finish_setup', 'welcome_back').
--
--   * shows.rated_at -- set by a trigger whenever a rating is given or
--     changed, however it was saved. Cleared when a rating is removed.
--     Older ratings stay blank (their date was never kept).
--
-- Run in the Supabase SQL editor. Safe to re-run.
-- ============================================================

alter table shows add column if not exists rated_at timestamptz;

create or replace function set_show_rated_at()
returns trigger
language plpgsql
as $$
begin
  if coalesce(new.rating, 0) = 0 then
    new.rated_at := null;
  elsif tg_op = 'INSERT' or new.rating is distinct from old.rating then
    new.rated_at := now();
  end if;
  return new;
end;
$$;

drop trigger if exists shows_set_rated_at on shows;
create trigger shows_set_rated_at
  before insert or update of rating on shows
  for each row execute function set_show_rated_at();
