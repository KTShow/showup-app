-- ============================================================
-- exclude_from_reports.sql  (2026-10-27)
-- ============================================================
-- Leaves admins (Tracey, George) and test / duplicate accounts out of
-- Settings > Admin > Members and the Monday email. Nothing else about
-- these accounts changes. To leave someone else out later:
--   update users set exclude_from_reports = true where lower(email) = '...';
--
-- Run in the Supabase SQL editor. Safe to re-run.
-- ============================================================

alter table users add column if not exists exclude_from_reports boolean not null default false;

-- Tracey's and George's extra accounts, the beta test account, the App
-- Store reviewer login, and Patricia A.'s second account.
update users set exclude_from_reports = true
 where lower(email) in (
   'tracey@kleinadvisor.com',
   'traceytklein@gmail.com',
   'showupbeta1@gmail.com',
   'gslanzano@outlook.com',
   'reviewer@showuproom.com',
   'patriciaallister923@comcast.net'
 );

create or replace function _admin_members()
returns jsonb
language sql
security definer
set search_path to 'public'
as $$
  select coalesce(jsonb_agg(row_to_json(t) order by t.last_visit desc nulls last), '[]'::jsonb)
  from (
    select
      u.id,
      u.first_name || coalesce(' ' || nullif(u.last_initial, '') || '.', '') as name,
      coalesce(u.email, a.email) as email,
      coalesce(u.created_at, a.created_at) as joined,
      (select count(*) from shows sh where sh.user_id = u.id) as shows,
      (select count(*) from sessions s where s.user_id = u.id) as visits,
      (select max(s.created_at) from sessions s where s.user_id = u.id) as last_visit,
      -- days they came back after the day they joined
      (select count(distinct s.created_at::date) from sessions s
        where s.user_id = u.id and s.created_at::date > coalesce(u.created_at, a.created_at)::date) as return_days,
      exists (select 1 from native_push_tokens t where t.user_id = u.id)
        or exists (select 1 from sessions s where s.user_id = u.id and s.how = 'iPhone app') as uses_app,
      exists (select 1 from sessions s where s.user_id = u.id and s.how = 'Home Screen')
        or exists (select 1 from push_subscriptions p where p.user_id = u.id and p.user_agent ~ '(iPhone|iPad)') as home_screen,
      exists (select 1 from push_subscriptions p where p.user_id = u.id)
        or exists (select 1 from native_push_tokens t where t.user_id = u.id) as alerts_on,
      (select s.how from sessions s where s.user_id = u.id and s.how is not null
        order by s.created_at desc limit 1) as last_how,
      (select iu.first_name || coalesce(' ' || nullif(iu.last_initial, '') || '.', '')
         from living_room_members m join users iu on iu.id = m.invited_by
        where m.user_id = u.id and m.invited_by is not null and m.invited_by <> u.id
        order by coalesce(m.accepted_at, m.invited_at) asc nulls last limit 1) as invited_by
    from users u
    left join auth.users a on a.id = u.id
    where coalesce(u.first_name, '') <> ''
      and coalesce(u.is_admin, false) = false
      and coalesce(u.exclude_from_reports, false) = false
  ) t;
$$;

revoke execute on function _admin_members() from public, anon, authenticated;
grant execute on function _admin_members() to service_role;

-- Check: should list exactly the 6 accounts above.
select first_name, last_initial, email from users where exclude_from_reports order by email;
