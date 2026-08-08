-- Admin room-viewing, read-only. Tracey and George already have this level
-- of visibility today via direct Supabase access -- this just adds a proper
-- in-app way to see it, gated by a real is_admin flag rather than a
-- client-side elevated key.

alter table users add column if not exists is_admin boolean not null default false;

update users set is_admin = true
where id in ('f5f85874-5f90-4383-ba22-5bd013358afb', '3f401268-959a-41ce-a306-0e2e7c5a156a');

create or replace function user_is_admin()
returns boolean
language sql
security definer
set search_path to 'public'
as $$
  select exists (select 1 from users where id = auth.uid() and is_admin = true);
$$;

alter policy living_rooms_member_read on living_rooms
  using (user_is_in_room(id) or user_is_admin());

alter policy members_read_roommates on living_room_members
  using (user_is_in_room(living_room_id) or user_is_admin());

alter policy shows_read_friends on shows
  using ((auth.uid() = user_id) or (user_id in (select room_mates())) or user_is_admin());

alter policy top5_read_friends on top5_shows
  using (
    (user_id in (select room_mates()))
    or (user_id in (select id from users where is_public = true or account_type = 'celebrity'))
    or user_is_admin()
  );

alter policy reactions_read_friends on reactions
  using (
    (show_id in (select id from shows where user_id = auth.uid()))
    or (show_id in (select friend_show_ids()))
    or user_is_admin()
  );

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

  if not (user_owns_room(p_room_id) or user_is_in_room(p_room_id) or user_is_admin()) then
    raise exception 'Not a member of this room';
  end if;

  select coalesce(array_agg(distinct uid), '{}')
    into v_all_ids
    from (
      select user_id as uid from living_room_members
      where living_room_id = p_room_id and status = 'active'
      union
      select owner_id as uid from living_rooms where id = p_room_id
    ) participants
    where uid <> v_user_id;

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
      and (r.user_id = any(v_all_ids) or r.user_id = v_user_id)
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

create or replace function get_all_living_rooms_admin()
returns jsonb
language plpgsql
as $$
begin
  if not user_is_admin() then
    raise exception 'Admin only';
  end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'id', r.id,
      'name', r.name,
      'owner_name', u.first_name,
      'member_count', (
        select count(*) from living_room_members m
        where m.living_room_id = r.id and m.status = 'active' and m.user_id <> r.owner_id
      )
    ) order by r.name), '[]'::jsonb)
    from living_rooms r
    join users u on u.id = r.owner_id
  );
end;
$$;

grant execute on function get_all_living_rooms_admin() to authenticated;
