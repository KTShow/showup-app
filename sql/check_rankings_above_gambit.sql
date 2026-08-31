-- Diagnostic, read-only. Mirrors the client-side buildRankings() logic in index.html
-- (group by lower(trim(title)), average rating, sort by avg desc then rater count desc)
-- to see exactly how many shows currently outrank The Queen's Gambit, and where it
-- actually lands in the order. If it's beyond position 25, that's the 25-cap in
-- buildRankings() cutting it off; if it lands inside the top 25, the bug is somewhere
-- else (e.g. it's not being pooled into state.friends for the account checking it).

with ratings as (
  select lower(trim(s.title)) as title_key, s.title, s.rating
  from shows s
  where s.hidden = false and s.rating > 0 and s.status in ('watched','dnf')
),
grouped as (
  select
    (array_agg(title))[1] as title,
    round(avg(rating)::numeric, 1) as avg_rating,
    count(*) as rater_count
  from ratings
  group by title_key
),
ranked as (
  select
    row_number() over (order by avg_rating desc, rater_count desc) as rank,
    title, avg_rating, rater_count
  from grouped
)
select * from ranked
where rank <= 30
   or title ilike '%gambit%'
order by rank;
