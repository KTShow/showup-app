-- Search: apostrophes don't count, so "queens gambit" finds The Queen's Gambit.
-- Only changes the title-matching helper used by search_show_ratings. Safe to run again.
-- The last query is a read-only check: it should say the queens gambit both times.
create or replace function norm_title(t text)
returns text
language sql
immutable
as $f$
  select regexp_replace(
           regexp_replace(
             regexp_replace(lower(trim(coalesce(t, ''))), '[''‘’ʼ`´]', '', 'g'),
           '[“”]', '"', 'g'),
         '\s+', ' ', 'g')
$f$;

select norm_title('The Queen''s Gambit') as saved_title, norm_title('the queens gambit') as typed;
