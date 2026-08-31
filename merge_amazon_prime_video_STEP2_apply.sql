-- STEP 2: applies the change reviewed in STEP1.
-- Merges the legacy "Amazon Prime Video" label into "Amazon Prime" so all
-- shows on Amazon's platform group together, matching the current dropdown.
update shows
set platform = 'Amazon Prime'
where platform = 'Amazon Prime Video';
