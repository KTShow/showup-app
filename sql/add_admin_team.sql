-- ============================================================
-- add_admin_team.sql  (2026-11-16)
-- ============================================================
-- A "Team" box at the top of Settings > Admin > Members, so Tracey can see
-- at a glance when George was last in. Team accounts stay OUT of every
-- count, the member list and the Monday email (nothing about
-- _admin_members() changes). Read-only for the app; admins only.
--
-- Run in the Supabase SQL editor. Safe to re-run.
-- ============================================================

alter table users add column if not exists on_team boolean not null default false;

-- George's main account (fill in from the check query).
update users set on_team = true where lower(email) = 'GEORGE_EMAIL_HERE';

create or replace function get_admin_team()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if not user_is_admin() then raise exception 'Admin only'; end if;
  return (
    select coalesce(jsonb_agg(row_to_json(t) order by t.last_visit desc nulls last), '[]'::jsonb)
    from (
      select
        u.id,
        u.first_name || coalesce(' ' || nullif(u.last_initial, '') || '.', '') as name,
        (select max(s.created_at) from sessions s where s.user_id = u.id) as last_visit,
        (select count(*) from sessions s where s.user_id = u.id
           and s.created_at > now() - interval '7 days') as visits_7d,
        (select s.how from sessions s where s.user_id = u.id and s.how is not null
          order by s.created_at desc limit 1) as last_how
      from users u
      where u.on_team and u.id <> auth.uid()
    ) t
  );
end;
$$;

grant execute on function get_admin_team() to authenticated;

-- Check: should show George.
select first_name, email, on_team from users where on_team;
