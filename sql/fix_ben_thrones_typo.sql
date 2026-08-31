-- One-time fix: Ben (ben-c-yabm) typed "Games of thrones" instead of "Game of Thrones",
-- which created a second, separate entry in Friends' Favorites instead of merging with
-- everyone else's. This corrects the title in both tables so it merges into the one
-- correctly-spelled entry going forward.

update shows
set title = 'Game of Thrones'
where user_id = (select id from users where username = 'ben-c-yabm')
  and title ilike 'games of thrones';

update top5_shows
set title = 'Game of Thrones'
where user_id = (select id from users where username = 'ben-c-yabm')
  and title ilike 'games of thrones';
