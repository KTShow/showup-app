-- ============================================================
-- add_media_type_to_shows.sql  (2026-09-03)
-- ============================================================
-- Lets documentary FILMS be tracked alongside TV. Docuseries already
-- worked (TMDB files them as TV); standalone doc films are TMDB "movies"
-- on a separate id namespace and a separate detail endpoint, so a row
-- has to record which it is.
--
-- Deliberately just 'tv' | 'documentary' -- NOT a general movie flag.
-- No general movies in ShowUp (that's Letterboxd's lane); a doc is the
-- only non-TV thing allowed in, gated by TMDB genre 99 at search time.
--
-- Run in the Supabase SQL editor. Safe to re-run.
-- ============================================================

alter table shows
  add column if not exists media_type text not null default 'tv';

do $$ begin
  alter table shows
    add constraint shows_media_type_chk check (media_type in ('tv', 'documentary'));
exception
  when duplicate_object then null;
end $$;

-- The daily new-season checker filters to media_type = 'tv'; keep that
-- lookup cheap.
create index if not exists shows_tv_tmdb_idx
  on shows (tmdb_id)
  where media_type = 'tv' and tmdb_id is not null;
