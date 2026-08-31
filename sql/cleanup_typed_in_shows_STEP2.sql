-- ============================================================================
-- CLEANUP: hand-typed shows with no TMDB match  --  STEP 2
-- ============================================================================
-- Follows sql/audit_typed_in_shows_STEP1_review.sql. Reviewed 2026-08-31.
--
-- Plan (Tracey's call, "backfill real shows, delete the rest"):
--   2C  DELETE 13 rows   -> 4 test rows (v/w/x/z) + 4 movies + 5 non-shows
--   2B  RENAME 5 rows    -> spelling / "The" / apostrophe fixes
--   2A  BACKFILL ~40 rows-> copy tmdb_id + poster from the copy other users
--                           added properly, so ratings / Top 5 / list all
--                           survive and the show merges with everyone else's
--   2D  BACKFILL top5_shows the same way (cosmetic: Top 5 posters)
--
-- Run the PREVIEW select in each section FIRST and eyeball it, THEN run the
-- mutation right below it. Recommended order: 2C, 2B, 2A, 2D.
-- Everything is scoped by explicit id list or by "tmdb_id is null" + exact
-- title match -- no fuzzy pattern DELETE (see feedback_destructive_sql_verify).
-- ============================================================================


-- ============================================================================
-- 2C. DELETE -- 13 rows: test junk, movies, unrecognizable titles
-- ============================================================================
-- 4 test : v / w / x / z            (traceytklein@gmail.com)
-- 4 movie: Red Lights / Project Hail Mary / A Complete Unknown /
--          The devil wears Prada
-- 5 non-show: The whisper man / Pompeii out of time / Voicemails for Isabelle /
--          Shipwrecked nightmare at sea / Something Really Bad is Going to Happen

-- --- PREVIEW: confirm these are the 13 rows, and how many reactions go with them
select s.id, s.title, u.email as owner, s.status, s.rating,
       (select count(*) from reactions r where r.show_id = s.id) as reactions_removed
from shows s
join auth.users u on u.id = s.user_id
where s.id in (
  '06d7d6b0-2151-445a-861d-5dcc8a70aad9',  -- v
  '11241e64-645c-4867-a3b0-8bce958bd68f',  -- w
  '30bff1ad-9e3f-4ed3-8982-67a1799078a9',  -- x
  '8528625b-d955-46dc-89d7-6addafd32c96',  -- z
  'ad80afbb-04f4-4117-ad44-459f93009538',  -- Red Lights (movie)
  '0d3b2e23-900e-4dd0-a54c-4de5d5d60f2d',  -- Project Hail Mary (movie/book)
  '7494c985-9d3b-415c-b976-1337a7d1a717',  -- A Complete Unknown (movie)
  'a1a1ddfe-20a6-406f-bd8b-ac293680b4b1',  -- The devil wears Prada (movie)
  'f56b3588-2c38-4a7f-ac77-77e1131861c6',  -- The whisper man
  '92258f59-cc3c-42dd-8f9b-37f8aec475d6',  -- Pompeii out of time
  'f1253abe-c5e3-40df-b461-b02d5d0bc37a',  -- Voicemails for Isabelle
  '40c45936-1191-41c6-ad5c-1253291e4fc9',  -- Shipwrecked nightmare at sea
  '766926af-193d-4332-887e-f0ddb8742126'   -- Something Really Bad is Going to Happen
)
order by s.title;

-- --- RUN: reactions first (FK), then the show rows
delete from reactions where show_id in (
  '06d7d6b0-2151-445a-861d-5dcc8a70aad9','11241e64-645c-4867-a3b0-8bce958bd68f',
  '30bff1ad-9e3f-4ed3-8982-67a1799078a9','8528625b-d955-46dc-89d7-6addafd32c96',
  'ad80afbb-04f4-4117-ad44-459f93009538','0d3b2e23-900e-4dd0-a54c-4de5d5d60f2d',
  '7494c985-9d3b-415c-b976-1337a7d1a717','a1a1ddfe-20a6-406f-bd8b-ac293680b4b1',
  'f56b3588-2c38-4a7f-ac77-77e1131861c6','92258f59-cc3c-42dd-8f9b-37f8aec475d6',
  'f1253abe-c5e3-40df-b461-b02d5d0bc37a','40c45936-1191-41c6-ad5c-1253291e4fc9',
  '766926af-193d-4332-887e-f0ddb8742126'
);

delete from shows where id in (
  '06d7d6b0-2151-445a-861d-5dcc8a70aad9','11241e64-645c-4867-a3b0-8bce958bd68f',
  '30bff1ad-9e3f-4ed3-8982-67a1799078a9','8528625b-d955-46dc-89d7-6addafd32c96',
  'ad80afbb-04f4-4117-ad44-459f93009538','0d3b2e23-900e-4dd0-a54c-4de5d5d60f2d',
  '7494c985-9d3b-415c-b976-1337a7d1a717','a1a1ddfe-20a6-406f-bd8b-ac293680b4b1',
  'f56b3588-2c38-4a7f-ac77-77e1131861c6','92258f59-cc3c-42dd-8f9b-37f8aec475d6',
  'f1253abe-c5e3-40df-b461-b02d5d0bc37a','40c45936-1191-41c6-ad5c-1253291e4fc9',
  '766926af-193d-4332-887e-f0ddb8742126'
);


-- ============================================================================
-- 2B. RENAME -- 5 rows: spelling / article / apostrophe fixes
-- ============================================================================
-- These do not exact-match a canonical title as typed, so fix the title
-- first; section 2A then backfills them if a proper copy exists.

-- --- PREVIEW
select id, title, tmdb_id from shows where id in (
  '1f1a697d-154a-4d0a-a59c-b1e1d7e7adde',  -- Breaking bad       -> Breaking Bad
  '43f6d8f3-726c-44ae-b058-1f75e12e49ad',  -- Gilded Age         -> The Gilded Age
  '833e2b44-3879-4932-b01c-1fbd5b91a83c',  -- Schitts Creek      -> Schitt's Creek
  'b2e5f83c-a29c-4b3f-93ad-d0886d4b3390',  -- The Black Rabbit   -> Black Rabbit
  '55828486-ae88-41ca-a1bb-314e2493702f'   -- Friends & Neighbors-> Your Friends & Neighbors
);

-- --- RUN
update shows set title = 'Breaking Bad'             where id = '1f1a697d-154a-4d0a-a59c-b1e1d7e7adde';
update shows set title = 'The Gilded Age'           where id = '43f6d8f3-726c-44ae-b058-1f75e12e49ad';
update shows set title = 'Schitt''s Creek'          where id = '833e2b44-3879-4932-b01c-1fbd5b91a83c';
update shows set title = 'Black Rabbit'             where id = 'b2e5f83c-a29c-4b3f-93ad-d0886d4b3390';
update shows set title = 'Your Friends & Neighbors' where id = '55828486-ae88-41ca-a1bb-314e2493702f';


-- ============================================================================
-- 2A. BACKFILL shows -- every remaining tmdb_id-null row whose exact title
--     matches a show other users added properly from the TMDB search.
-- ============================================================================
-- canon_id  : most common tmdb_id per (lower/trimmed) title
-- canon_meta: richest metadata row for that tmdb_id (prefers rows that have
--             a poster + overview)

-- --- PREVIEW: this is the full list of rows that will be touched. Eyeball
--     every title against new_poster / new_tmdb_id before running the UPDATE.
with canon_id as (
  select lower(btrim(title)) as k,
         mode() within group (order by tmdb_id) as tmdb_id
  from shows where tmdb_id is not null
  group by lower(btrim(title))
),
canon_meta as (
  select distinct on (tmdb_id)
    tmdb_id, poster_path, genre, original_network, first_air_year,
    number_of_seasons, show_status, overview, vote_average
  from shows where tmdb_id is not null
  order by tmdb_id, (poster_path is not null) desc, (overview is not null) desc, added_at desc
)
select s.id, s.title, s.added_at::date as added, u.email as owner,
       ci.tmdb_id as new_tmdb_id, cm.poster_path as new_poster
from shows s
join auth.users u on u.id = s.user_id
join canon_id ci on ci.k = lower(btrim(s.title))
join canon_meta cm on cm.tmdb_id = ci.tmdb_id
where s.tmdb_id is null
order by s.title;

-- --- RUN
with canon_id as (
  select lower(btrim(title)) as k,
         mode() within group (order by tmdb_id) as tmdb_id
  from shows where tmdb_id is not null
  group by lower(btrim(title))
),
canon_meta as (
  select distinct on (tmdb_id)
    tmdb_id, poster_path, genre, original_network, first_air_year,
    number_of_seasons, show_status, overview, vote_average
  from shows where tmdb_id is not null
  order by tmdb_id, (poster_path is not null) desc, (overview is not null) desc, added_at desc
)
update shows s
set tmdb_id           = ci.tmdb_id,
    poster_path       = coalesce(s.poster_path, cm.poster_path),
    genre             = coalesce(s.genre, cm.genre),
    original_network  = coalesce(s.original_network, cm.original_network),
    first_air_year    = coalesce(s.first_air_year, cm.first_air_year),
    number_of_seasons = coalesce(s.number_of_seasons, cm.number_of_seasons),
    show_status       = coalesce(s.show_status, cm.show_status),
    overview          = coalesce(s.overview, cm.overview),
    vote_average      = coalesce(s.vote_average, cm.vote_average)
from canon_id ci
join canon_meta cm on cm.tmdb_id = ci.tmdb_id
where s.tmdb_id is null
  and ci.k = lower(btrim(s.title));

-- --- LEFTOVERS: rows still with no tmdb_id after the backfill (no proper
--     copy exists anywhere yet). Expected: maybe Black Rabbit / Your Friends
--     & Neighbors / a couple of obscure ones. Titles are fixed; they just
--     won't have a poster until someone adds them from search.
select s.id, s.title, u.email as owner
from shows s join auth.users u on u.id = s.user_id
where s.tmdb_id is null
order by s.title;


-- ============================================================================
-- 2D. BACKFILL top5_shows -- same idea, cosmetic (Top 5 poster + link)
-- ============================================================================

-- --- PREVIEW
with canon_id as (
  select lower(btrim(title)) as k,
         mode() within group (order by tmdb_id) as tmdb_id
  from shows where tmdb_id is not null
  group by lower(btrim(title))
),
canon_meta as (
  select distinct on (tmdb_id) tmdb_id, poster_path
  from shows where tmdb_id is not null and poster_path is not null
  order by tmdb_id, added_at desc
)
select t.user_id, t.title, ci.tmdb_id as new_tmdb_id, cm.poster_path as new_poster
from top5_shows t
join canon_id ci on ci.k = lower(btrim(t.title))
join canon_meta cm on cm.tmdb_id = ci.tmdb_id
where t.tmdb_id is null
order by t.title;

-- --- RUN
with canon_id as (
  select lower(btrim(title)) as k,
         mode() within group (order by tmdb_id) as tmdb_id
  from shows where tmdb_id is not null
  group by lower(btrim(title))
),
canon_meta as (
  select distinct on (tmdb_id) tmdb_id, poster_path
  from shows where tmdb_id is not null and poster_path is not null
  order by tmdb_id, added_at desc
)
update top5_shows t
set tmdb_id     = ci.tmdb_id,
    poster_path = coalesce(t.poster_path, cm.poster_path)
from canon_id ci
join canon_meta cm on cm.tmdb_id = ci.tmdb_id
where t.tmdb_id is null
  and ci.k = lower(btrim(t.title));


-- ============================================================================
-- 2E. VERIFY -- re-run the STEP 1 summary; typed_in_no_tmdb should drop from
--     58 to a small single-digit number (the genuine leftovers from 2A).
-- ============================================================================
select
  count(*)                                              as total_shows,
  count(*) filter (where tmdb_id is not null)            as with_tmdb,
  count(*) filter (where tmdb_id is null)                as typed_in_no_tmdb
from shows;
