-- ============================================================
-- add_admin_members.sql  (2026-10-27)
-- ============================================================
-- Settings > Admin > Members (and the Monday admin email): one row per
-- person with a profile -- how they use ShowUp, whether alerts are on,
-- shows, visits, last visit, who invited them.
--
--   * sessions.how: 'iPhone app' | 'Home Screen' | 'Website', recorded by
--     the app on each visit from 2026-10-27. Older visits have none, so for
--     the past: an iPhone app push token = iPhone app; an iPhone/iPad web
--     push subscription = Home Screen (iOS only allows web alerts there).
--   * alerts_on: any web push subscription or iPhone app token.
--   * invited_by: whoever invited them into their first room (recorded
--     from 2026-10-27 invite links; older joins have none).
--   * get_admin_members(): admins only. _admin_members(): the same data
--     for the Monday email script (service role only).
--
-- Run in the Supabase SQL editor. Safe to re-run.
-- ============================================================

alter table sessions add column if not exists how text;

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
  ) t;
$$;

revoke execute on function _admin_members() from public, anon, authenticated;
grant execute on function _admin_members() to service_role;

create or replace function get_admin_members()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if not user_is_admin() then raise exception 'Admin only'; end if;
  return _admin_members();
end;
$$;

grant execute on function get_admin_members() to authenticated;
