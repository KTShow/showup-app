-- Diagnostic, read-only. Shows the real current status/waiting_for_season
-- value in the database for your account's shows, most recently added
-- first, so we can see whether "Waiting for New Season" actually persisted
-- or reverted back to status='watched'.

select s.title, s.status, s.dnf, s.waiting_for_season, s.added_at
from shows s
join auth.users au on au.id = s.user_id
where au.email = 'tklein2027@gmail.com'
order by s.added_at desc
limit 30;
