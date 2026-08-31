-- Backs the "Recommend to a friend" feature: a targeted, personal nudge
-- ("John recommended Full Swing to you") distinct from a regular comment.
-- One recipient per recommendation (not a broadcast). Status tracks
-- whether the recipient has acted on it yet, so the sender can find out
-- when it was added (not on dismissal -- that stays quiet, same as
-- other soft/no-drama actions in this app like hiding or muting).

create table if not exists recommendations (
  id uuid primary key default gen_random_uuid(),
  from_user_id uuid not null references auth.users(id) on delete cascade,
  to_user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  tmdb_id integer,
  poster_path text,
  note text,
  status text not null default 'pending' check (status in ('pending','added','dismissed')),
  created_at timestamptz not null default now(),
  resolved_at timestamptz
);

alter table recommendations enable row level security;

create policy "select own recommendations" on recommendations
  for select using (auth.uid() = from_user_id or auth.uid() = to_user_id);

create policy "send recommendations" on recommendations
  for insert with check (auth.uid() = from_user_id);

create policy "recipient resolves recommendations" on recommendations
  for update using (auth.uid() = to_user_id) with check (auth.uid() = to_user_id);
