-- Lets admins (users.is_admin = true) update the announcement banner
-- directly from the app (Settings > Admin > Edit Announcement Banner),
-- instead of needing the Supabase SQL editor. Reuses the same is_admin
-- flag that already gates "Browse All Rooms".

drop policy if exists "Admins can update the announcement" on app_announcements;
create policy "Admins can update the announcement" on app_announcements
  for update
  using (exists (select 1 from users where id = auth.uid() and is_admin = true))
  with check (exists (select 1 from users where id = auth.uid() and is_admin = true));
