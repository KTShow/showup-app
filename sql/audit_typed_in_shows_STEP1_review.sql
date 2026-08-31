-- ============================================================================
-- AUDIT: hand-typed shows with no TMDB match  --  STEP 1, REVIEW ONLY
-- ============================================================================
-- Read-only. Changes nothing. Run in the Supabase SQL editor.
--
-- Every row this surfaces was typed into the add box by hand rather than
-- picked from the TMDB search dropdown (tmdb_id is null), so this is where
-- the test rows ("v", "w", "x", "z"), misspellings, and movies live -- mixed
-- in with a few legitimate obscure shows that were typed in correctly.
--
-- Review EVERY row before deleting anything (see feedback_destructive_sql_verify).
-- The reaction_count / in_top5 / rating columns flag rows that someone
-- actually engaged with -- do NOT blanket-delete.
--
-- Once reviewed, hand the kept/deleted split back and STEP 2 deletes by an
-- explicit id list (reactions first, then the show rows).
-- ============================================================================


-- 1. SUMMARY ----------------------------------------------------------------
select
  count(*)                                                as total_shows,
  count(*) filter (where tmdb_id is not null)             as with_tmdb,
  count(*) filter (where tmdb_id is null)                 as typed_in_no_tmdb,
  count(*) filter (where tmdb_id is null
                   and char_length(btrim(title)) <= 2)    as junk_1_2_chars
from shows;


-- 2. THE REVIEW LIST ------------------------------------------------------
--   len                    -> shortest titles (most junk-like) sort first
--   reaction_count         -> comments/reactions on this exact row
--   in_top5                -> this user also has the title in their Top 5
--   same_title_done_right  -> N other users added the SAME title properly via
--                             TMDB, so this typed-in copy is a redundant dupe
select
  s.id,
  s.title,
  char_length(btrim(s.title))                         as len,
  s.platform,
  s.status,
  s.rating,
  s.hidden,
  s.source,
  s.added_at::date                                    as added,
  u.email                                             as added_by,
  (select count(*) from reactions r where r.show_id = s.id)    as reaction_count,
  exists (select 1 from top5_shows t
          where t.user_id = s.user_id
            and lower(btrim(t.title)) = lower(btrim(s.title))) as in_top5,
  (select count(*) from shows s2
     where s2.tmdb_id is not null
       and lower(btrim(s2.title)) = lower(btrim(s.title)))     as same_title_done_right
from shows s
join auth.users u on u.id = s.user_id
where s.tmdb_id is null
order by char_length(btrim(s.title)) asc, lower(btrim(s.title)) asc;


-- 3. OPTIONAL -- likely misspellings (near-miss of a real TMDB title) -------
-- Only runs if the pg_trgm extension is enabled. Safe to skip if it errors.
-- Lists each typed-in title next to the closest properly-added title so you
-- can spot "Severence" -> "Severance" style typos.
--
--   create extension if not exists pg_trgm;   -- run once if needed
--
-- select
--   bad.id,
--   bad.title                       as typed_in,
--   good.title                      as closest_real_title,
--   round(similarity(lower(bad.title), lower(good.title))::numeric, 2) as score
-- from shows bad
-- cross join lateral (
--   select g.title
--   from shows g
--   where g.tmdb_id is not null
--     and g.title <> bad.title
--   order by similarity(lower(bad.title), lower(g.title)) desc
--   limit 1
-- ) good
-- where bad.tmdb_id is null
--   and char_length(btrim(bad.title)) >= 3
--   and similarity(lower(bad.title), lower(good.title)) >= 0.45
-- order by score desc;
