-- STEP 1: REVIEW ONLY — this does not delete anything.
-- Adjust the WHERE clause below if it doesn't catch the right accounts
-- (e.g. change 'tracey%' or 'showup%' to match your actual test usernames).
-- Run this first and check the results before running STEP 2.

select id, username, first_name, last_initial, email
from users
where username ilike 'tracey%'
   or username ilike 'showup%'
   or first_name ilike 'tracey%'
   or first_name ilike 'showup%'
order by username;
