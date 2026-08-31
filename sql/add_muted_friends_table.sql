-- New table backing the "grey out a friend you're not paying attention
-- to, without removing them" feature. Kept separate from
-- living_room_members because a friend relationship can be represented
-- by either direction of that table (they're in your room, or you're
-- in theirs) — muting is keyed on the friend's user id directly so it
-- works regardless of which direction the membership row is in.

create table if not exists muted_friends (
  user_id uuid not null references auth.users(id) on delete cascade,
  muted_user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, muted_user_id)
);

alter table muted_friends enable row level security;

create policy "select own mutes" on muted_friends
  for select using (auth.uid() = user_id);

create policy "insert own mutes" on muted_friends
  for insert with check (auth.uid() = user_id);

create policy "delete own mutes" on muted_friends
  for delete using (auth.uid() = user_id);
