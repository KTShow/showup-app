-- STEP 1: review only, no changes made.
-- Shows this identifies where you already accepted a recommendation
-- (before the credit-tracking fix shipped) but the show's row never
-- got tagged with source='recommendation' / influenced_by. Only counts
-- toward Tastemakers if status is 'watchlist' or 'watching' -- matches
-- the "accepted = My List or Watching, nothing else" rule.
-- Where more than one friend recommended the same title to the same
-- person, credits whichever recommendation was accepted first.
select
  s.id as show_id,
  s.user_id as recipient_user_id,
  s.title,
  s.status,
  s.source as current_source,
  r.from_user_id as would_credit_to,
  r.resolved_at as recommendation_accepted_at
from shows s
join lateral (
  select r.from_user_id, r.resolved_at
  from recommendations r
  where r.to_user_id = s.user_id
    and r.status = 'added'
    and lower(trim(r.title)) = lower(trim(s.title))
  order by r.resolved_at asc
  limit 1
) r on true
where s.status in ('watchlist', 'watching')
  and (s.source is distinct from 'recommendation')
order by s.user_id, s.title;
