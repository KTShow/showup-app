-- ============================================================
-- add_native_push.sql  (2026-10-19)
-- ============================================================
-- Phone alerts inside the iPhone app (TestFlight / App Store).
--
-- Web Push (push_subscriptions) only reaches the Home Screen web app. The
-- native app instead hands us an Apple (APNs) device token; /api/push sends
-- the same pending notification rows to these tokens through Apple.
--
--   * native_push_tokens -- one row per iPhone app install that allowed
--     alerts. Written only through save_/delete_native_push_token (a phone
--     that switches accounts re-homes cleanly). Read by /api/push with the
--     service role.
--
-- Run in the Supabase SQL editor BEFORE deploying the app change.
-- Safe to re-run.
-- ============================================================

create table if not exists native_push_tokens (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  token       text not null unique,
  platform    text not null default 'ios',
  created_at  timestamptz not null default now()
);

create index if not exists native_push_tokens_user_idx on native_push_tokens (user_id);

alter table native_push_tokens enable row level security;

do $$ begin
  create policy "read own native push tokens" on native_push_tokens
    for select using (auth.uid() = user_id);
exception when duplicate_object then null; end $$;

create or replace function save_native_push_token(p_token text, p_platform text default 'ios')
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  if p_token is null or p_token !~ '^[0-9a-fA-F]{32,200}$' then raise exception 'Bad token'; end if;
  insert into native_push_tokens (user_id, token, platform)
  values (auth.uid(), lower(p_token), coalesce(p_platform, 'ios'))
  on conflict (token) do update
    set user_id = auth.uid(), platform = excluded.platform, created_at = now();
end;
$$;

create or replace function delete_native_push_token(p_token text)
returns void
language sql
security definer
set search_path to 'public'
as $$
  delete from native_push_tokens where token = lower(p_token) and user_id = auth.uid();
$$;

grant execute on function save_native_push_token(text, text) to authenticated;
grant execute on function delete_native_push_token(text) to authenticated;
