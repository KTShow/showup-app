-- ShowUp Multi-Living-Room, Phase 1 migration.
-- Run this whole script at once in the Supabase SQL Editor.

-- ============================================================
-- 1. Schema: per-room muting
-- ============================================================
alter table muted_friends add column if not exists living_room_id uuid references living_rooms(id);

-- Drop whatever the existing (user_id, muted_user_id) unique constraint is
-- named -- it must go, since it would otherwise block muting the same
-- person independently in two different rooms.
do $$
declare
  c record;
begin
  for c in
    select conname from pg_constraint
    where conrelid = 'muted_friends'::regclass and contype = 'u'
  loop
    execute format('alter table muted_friends drop constraint %I', c.conname);
  end loop;
end $$;

alter table muted_friends add constraint muted_friends_user_muted_room_key
  unique (user_id, muted_user_id, living_room_id);

-- ============================================================
-- 2. Security fix: "shows" and "reactions" visibility currently only
-- covers relationships that go through a room one of the two people
-- OWNS. It doesn't cover two people who are both just invited MEMBERS
-- of a third person's room -- which the new multi-room model needs.
-- top5_shows already uses the correct general pattern; bringing shows
-- and reactions in line with it.
-- ============================================================

-- New helper: everyone who shares ANY active room membership with me,
-- regardless of who owns the room. Mirrors the existing top5_read_friends
-- policy's join pattern.
create or replace function room_mates()
returns setof uuid
language sql
security definer
set search_path to 'public'
as $$
  select distinct lrm2.user_id
  from living_room_members lrm1
  join living_room_members lrm2 on lrm1.living_room_id = lrm2.living_room_id
  where lrm1.user_id = auth.uid()
    and lrm1.status = 'active'
    and lrm2.status = 'active'
    and lrm2.user_id <> auth.uid();
$$;

alter policy shows_read_friends on shows
  using ((auth.uid() = user_id) or (user_id in (select room_mates())));

create or replace function friend_show_ids()
returns setof uuid
language sql
security definer
set search_path to 'public'
as $$
  select s.id
  from shows s
  where s.hidden = false
    and s.user_id in (select room_mates());
$$;

-- ============================================================
-- 3. New/rewritten room functions
-- ============================================================

create or replace function get_my_living_rooms()
returns jsonb
language sql
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', r.id,
    'name', r.name,
    'is_owner', (r.owner_id = auth.uid()),
    'member_count', (
      select count(*) from living_room_members m
      where m.living_room_id = r.id and m.status = 'active'
    )
  )), '[]'::jsonb)
  from living_rooms r
  where r.owner_id = auth.uid() or user_is_in_room(r.id);
$$;

create or replace function create_living_room(p_name text)
returns uuid
language plpgsql
as $$
declare
  v_id uuid;
begin
  insert into living_rooms (owner_id, name, is_public)
  values (auth.uid(), p_name, false)
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function join_living_room(p_room_id uuid)
returns void
language plpgsql
as $$
begin
  insert into living_room_members (living_room_id, user_id, status, invited_by)
  values (p_room_id, auth.uid(), 'active', null)
  on conflict (living_room_id, user_id) do update set status = 'active';
end;
$$;

drop function if exists get_living_room_data();

create or replace function get_living_room_data(p_room_id uuid)
returns jsonb
language plpgsql
as $$
declare
  v_user_id uuid := auth.uid();
  v_all_ids uuid[];
  v_empty jsonb := jsonb_build_object(
    'friends', '[]'::jsonb, 'shows', '[]'::jsonb,
    'reactions', '[]'::jsonb, 'top5', '[]'::jsonb, 'muted', '[]'::jsonb
  );
begin
  if v_user_id is null then
    raise exception 'Not authenticated';
  end if;

  if not (user_owns_room(p_room_id) or user_is_in_room(p_room_id)) then
    raise exception 'Not a member of this room';
  end if;

  select coalesce(array_agg(user_id), '{}')
    into v_all_ids
    from living_room_members
    where living_room_id = p_room_id and status = 'active' and user_id <> v_user_id;

  if v_all_ids is null or array_length(v_all_ids, 1) is null then
    return v_empty;
  end if;

  return jsonb_build_object(
    'friends', (
      select coalesce(jsonb_agg(to_jsonb(u)), '[]'::jsonb)
      from (
        select id, first_name, last_initial, city, state, room
        from users where id = any(v_all_ids)
      ) u
    ),
    'shows', (
      select coalesce(jsonb_agg(to_jsonb(s)), '[]'::jsonb)
      from shows s
      where s.user_id = any(v_all_ids) and s.hidden = false
    ),
    'reactions', (
      select coalesce(jsonb_agg(to_jsonb(r)), '[]'::jsonb)
      from reactions r
      where r.show_id in (
        select id from shows where user_id = any(v_all_ids) and hidden = false
      )
    ),
    'top5', (
      select coalesce(jsonb_agg(to_jsonb(t) order by t.rank), '[]'::jsonb)
      from top5_shows t
      where t.user_id = any(v_all_ids)
    ),
    'muted', (
      select coalesce(jsonb_agg(muted_user_id), '[]'::jsonb)
      from muted_friends
      where user_id = v_user_id and living_room_id = p_room_id
    )
  );
end;
$$;

grant execute on function get_my_living_rooms() to authenticated;
grant execute on function create_living_room(text) to authenticated;
grant execute on function join_living_room(uuid) to authenticated;
grant execute on function get_living_room_data(uuid) to authenticated;
