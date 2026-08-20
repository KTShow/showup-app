-- A single row holding the current "room picker" announcement banner --
-- update it directly with the UPDATE statement below whenever you want to
-- change the message. No admin UI needed; this is meant to be edited via
-- the Supabase SQL editor by whoever's a founder.

create table if not exists app_announcements (
  id int primary key default 1,
  message text not null,
  emoji text,
  updated_at timestamptz not null default now(),
  constraint app_announcements_singleton check (id = 1)
);

insert into app_announcements (id, message, emoji)
values (1, 'Rate 3 shows this week 🍿', '📢')
on conflict (id) do nothing;

alter table app_announcements enable row level security;

drop policy if exists "Anyone can read the announcement" on app_announcements;
create policy "Anyone can read the announcement" on app_announcements
  for select using (true);

-- No insert/update/delete policy for regular users -- founders change the
-- message via the Supabase SQL editor (which runs as the service role and
-- bypasses RLS), not through the app itself. To change the message later:
--
-- update app_announcements
--   set message = 'Check out all the new shows added this week 🎬', emoji = '📢', updated_at = now()
--   where id = 1;
