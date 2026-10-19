-- ============================================================
-- add_feedback.sql  (2026-10-19)
-- ============================================================
-- In-app "Report a bug or share an idea" (Settings), read in Settings >
-- Admin > Feedback inbox.
--
--   * feedback: kind (bug | idea), the message (required), an optional
--     screenshot (shrunk in the app, stored as a data: URL -- no separate
--     file storage at beta volumes), and context the app adds on its own
--     (device, iPhone app vs website, screen size, last tab, text size).
--   * Anyone signed in can send; only the sender and admins can read it.
--   * get_feedback / get_feedback_screenshot / set_feedback_status are
--     admin-only. The list leaves screenshots out (loaded on tap).
--   * A new item alerts every admin's phone (push_pending hand-off, see
--     sql/add_push_alerts.sql -> /api/push). Not in the bell.
--
-- Run in the Supabase SQL editor BEFORE deploying the app change.
-- Safe to re-run.
-- ============================================================

create table if not exists feedback (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null default auth.uid(),
  kind        text not null check (kind in ('bug', 'idea')),
  body        text not null check (char_length(btrim(body)) between 1 and 4000),
  screenshot  text check (screenshot is null or (screenshot like 'data:image/%' and char_length(screenshot) <= 2000000)),
  context     jsonb not null default '{}'::jsonb,
  status      text not null default 'open' check (status in ('open', 'done')),
  created_at  timestamptz not null default now(),
  resolved_at timestamptz
);

create index if not exists feedback_status_idx on feedback (status, created_at desc);

alter table feedback enable row level security;

do $$ begin
  create policy feedback_insert_own on feedback for insert with check (auth.uid() = user_id);
exception when duplicate_object then null; end $$;
do $$ begin
  create policy feedback_read on feedback for select using (auth.uid() = user_id or user_is_admin());
exception when duplicate_object then null; end $$;

-- ---------- admin: list (no screenshots) --------------------------------
create or replace function get_feedback(p_status text default 'open')
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if not user_is_admin() then raise exception 'Admin only'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', f.id, 'kind', f.kind, 'body', f.body, 'context', f.context,
      'status', f.status, 'created_at', f.created_at,
      'has_screenshot', f.screenshot is not null,
      'sender', coalesce(u.first_name || coalesce(' ' || nullif(u.last_initial, '') || '.', ''), 'Someone')
    ) order by f.created_at desc)
    from feedback f
    left join users u on u.id = f.user_id
    where p_status is null or f.status = p_status
  ), '[]'::jsonb);
end;
$$;
grant execute on function get_feedback(text) to authenticated;

create or replace function get_feedback_screenshot(p_id uuid)
returns text
language plpgsql
security definer
set search_path to 'public'
as $$
declare v text;
begin
  if not user_is_admin() then raise exception 'Admin only'; end if;
  select screenshot into v from feedback where id = p_id;
  return v;
end;
$$;
grant execute on function get_feedback_screenshot(uuid) to authenticated;

create or replace function set_feedback_status(p_id uuid, p_status text)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if not user_is_admin() then raise exception 'Admin only'; end if;
  if p_status not in ('open', 'done') then raise exception 'Bad status'; end if;
  update feedback set status = p_status,
         resolved_at = case when p_status = 'done' then now() end
   where id = p_id;
end;
$$;
grant execute on function set_feedback_status(uuid, text) to authenticated;

-- ---------- alert admins ------------------------------------------------
create or replace function notify_feedback()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_name text;
begin
  select first_name || coalesce(' ' || nullif(last_initial, '') || '.', '') into v_name
    from users where id = new.user_id;
  v_name := coalesce(v_name, 'Someone');

  insert into notifications (user_id, type, title, body, entity_id, push_pending, created_at)
  select u.id, 'feedback',
         case when new.kind = 'bug' then 'Bug report' else 'New idea' end,
         v_name || ': ' || left(regexp_replace(new.body, '\s+', ' ', 'g'), 90)
           || case when new.screenshot is not null then ' [screenshot]' else '' end,
         new.id, true, now()
    from users u
   where u.is_admin = true and u.id <> new.user_id;
  return new;
end;
$$;

drop trigger if exists feedback_notify on feedback;
create trigger feedback_notify
  after insert on feedback
  for each row execute function notify_feedback();
