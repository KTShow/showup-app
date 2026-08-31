-- Diagnostic, read-only. Maps your login email to the actual profile row(s) it owns,
-- so we can tell which "Tracey" account (b6tt / 2yqw / 5nfz) you're really logged in as.

select au.email, u.username, u.first_name, u.last_initial, u.id, au.created_at
from auth.users au
join users u on u.id = au.id
where au.email = 'tklein2027@gmail.com';
