-- Adds a platform column to recommendations so the streaming service
-- carries over when a friend's recommendation is accepted into My List.
alter table recommendations add column if not exists platform text;
