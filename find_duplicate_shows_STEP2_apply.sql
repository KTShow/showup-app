-- Keeps the most recently added row per (user, show title), deletes the
-- older duplicate(s). Only affects the 17 pairs found in STEP1 -- any show
-- with just one row is untouched (row_number() = 1, never deleted).
delete from shows
where id in (
  select id from (
    select id,
           row_number() over (partition by user_id, title order by added_at desc) as rn
    from shows
  ) ranked
  where rn > 1
);
