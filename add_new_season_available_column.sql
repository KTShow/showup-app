-- Supports the "New season!" badge on Waiting-for-New-Season shows.
-- Persists until the user taps the badge and moves the show to Watching
-- (tapNewSeasonBadge() clears it), so it survives across app visits.
alter table shows add column if not exists new_season_available boolean not null default false;
