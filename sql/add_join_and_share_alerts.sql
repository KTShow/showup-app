-- ============================================================
-- add_join_and_share_alerts.sql  (2026-10-27)
-- ============================================================
-- 1. Admins (users.is_admin) get a phone alert when someone new joins
--    ShowUp (finishes the profile form) and when a Living Room is created.
--    Push only, not the bell -- same as bug reports.
-- 2. When someone joins a room, its owner and the person who invited them
--    get a bell item + phone alert ("Kerstin R. joined Family"). Settings
--    switch: notification_prefs.room_join.
-- 3. notification_prefs.shared_add: the daily "Nick added a show you
--    shared" bell item (written by scripts/check-new-seasons.mjs from
--    shows.source / influenced_by).
--
-- join_living_room(room, inviter username) is a NEW two-argument version;
-- the old one-argument function is left as it is, so nothing breaks.
--
-- Run in the Supabase SQL editor. Safe to re-run.
-- ============================================================

alter table notification_prefs add column if not exists room_join boolean not null default true;
alter table notification_prefs add column if not exists shared_add boolean not null default true;

-- Adds now record where they came from ('living_room', 'lounge',
-- 'show_talk'); drop any old check on shows.source that would refuse them.
do $$
declare c record;
begin
  for c in
    select conname from pg_constraint
     where conrelid = 'shows'::regclass and contype = 'c'
       and pg_get_constraintdef(oid) ilike '%source%'
  loop
    execute format('alter table shows drop constraint %I', c.conname);
  end loop;
end $$;

-- ---------- 1a. new member -> admins ------------------------------------
create or replace function notify_admins_new_user()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_name text := coalesce(new.first_name, 'Someone') || coalesce(' ' || nullif(new.last_initial, '') || '.', '');
  v_where text := nullif(concat_ws(', ', nullif(new.city, ''), nullif(new.state, '')), '');
begin
  insert into notifications (user_id, type, title, body, entity_id, push_pending, created_at)
  select u.id, 'admin_new_user', 'New member: ' || v_name,
         coalesce(v_where || ' · ', '') || 'just joined ShowUp',
         new.id, true, now()
    from users u
   where u.is_admin = true and u.id <> new.id;
  return new;
exception when others then
  -- An alert must never block the sign-up / room / join itself.
  raise warning '%: %', tg_name, sqlerrm;
  return new;
end;
$$;

drop trigger if exists users_notify_admins on users;
create trigger users_notify_admins
  after insert on users
  for each row execute function notify_admins_new_user();

-- ---------- 1b. new room -> admins --------------------------------------
create or replace function notify_admins_new_room()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare v_owner text;
begin
  select first_name || coalesce(' ' || nullif(last_initial, '') || '.', '') into v_owner
    from users where id = new.owner_id;
  insert into notifications (user_id, type, title, body, entity_id, room_id, push_pending, created_at)
  select u.id, 'admin_new_room', 'New room: ' || coalesce(new.name, 'Living Room'),
         'Created by ' || coalesce(v_owner, 'someone'),
         new.id, new.id, true, now()
    from users u
   where u.is_admin = true and u.id <> new.owner_id;
  return new;
exception when others then
  -- An alert must never block the sign-up / room / join itself.
  raise warning '%: %', tg_name, sqlerrm;
  return new;
end;
$$;

drop trigger if exists living_rooms_notify_admins on living_rooms;
create trigger living_rooms_notify_admins
  after insert on living_rooms
  for each row execute function notify_admins_new_room();

-- ---------- 2. someone joins a room -> owner + inviter ------------------
create or replace function join_living_room(p_room_id uuid, p_inviter text)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare v_inviter uuid;
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  -- Only credit an inviter who is actually in that room.
  select u.id into v_inviter
    from users u
    join living_room_members m on m.user_id = u.id and m.living_room_id = p_room_id and m.status = 'active'
   where lower(u.username) = lower(p_inviter)
   limit 1;
  if v_inviter is null then
    select owner_id into v_inviter from living_rooms where id = p_room_id;
  end if;
  insert into living_room_members (living_room_id, user_id, status, invited_by)
  values (p_room_id, auth.uid(), 'active', v_inviter)
  on conflict (living_room_id, user_id) do update
    set status = 'active',
        invited_by = coalesce(living_room_members.invited_by, excluded.invited_by);
end;
$$;

grant execute on function join_living_room(uuid, text) to authenticated;

create or replace function notify_room_join()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_room record;
  v_name text;
begin
  if new.status <> 'active' then return new; end if;
  if tg_op = 'UPDATE' and old.status = 'active' then return new; end if;
  select id, name, owner_id into v_room from living_rooms where id = new.living_room_id;
  if v_room.id is null or v_room.owner_id = new.user_id then return new; end if;
  select first_name || coalesce(' ' || nullif(last_initial, '') || '.', '') into v_name
    from users where id = new.user_id;
  -- No profile yet (mid sign-up): skip rather than say "Someone joined".
  if v_name is null then return new; end if;

  insert into notifications (user_id, type, title, body, entity_id, room_id, push_pending, created_at)
  select r.uid, 'room_join', v_name || ' joined ' || coalesce(v_room.name, 'your Living Room'),
         'Say hi in the Lounge?', new.user_id, v_room.id, true, now()
    from (select distinct x as uid from unnest(array[v_room.owner_id, new.invited_by]) x) r
    left join notification_prefs p on p.user_id = r.uid
   where r.uid is not null
     and r.uid <> new.user_id
     and coalesce(p.room_join, true);
  return new;
exception when others then
  -- An alert must never block the sign-up / room / join itself.
  raise warning '%: %', tg_name, sqlerrm;
  return new;
end;
$$;

drop trigger if exists living_room_members_notify_join on living_room_members;
create trigger living_room_members_notify_join
  after insert or update of status on living_room_members
  for each row execute function notify_room_join();
