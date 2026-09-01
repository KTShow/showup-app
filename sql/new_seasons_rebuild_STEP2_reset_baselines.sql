-- ============================================================
-- New-season rebuild, STEP 2: full baseline reset (2026-09-01)
-- ============================================================
-- Every shows.number_of_seasons stored before today may be inflated (the
-- old add-flow briefly stored TMDB's raw count, which includes
-- announced-but-unaired seasons) and every new_season_available flag was
-- set by the retired client logic. Rather than try to sort good from bad,
-- we wipe both. The next run of the scheduled checker re-establishes
-- number_of_seasons for every tracked show from a released-only count
-- WITHOUT notifying (baseline pass); only increases seen after that fire a
-- notification.
--
-- Tradeoff (accepted): if a real new season already dropped for a show
-- someone is waiting on, they won't get a one-time notification for it --
-- it just becomes their new baseline. Clean slate over carried-forward
-- uncertainty.
--
-- Run this AFTER STEP 1, then trigger the "Check for new seasons" workflow
-- once manually (GitHub -> Actions -> Run workflow) to lay down baselines.
-- ============================================================

update shows
set number_of_seasons  = null,
    new_season_available = false
where number_of_seasons is not null
   or new_season_available = true;

-- Sanity check: should return zero rows.
select id, title, number_of_seasons, new_season_available
from shows
where number_of_seasons is not null or new_season_available = true;
