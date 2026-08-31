-- Per-room "since you last looked" tracking for Conversations. The old
-- conversations_last_seen_at column on users is global (one flag across
-- every room), which under multi-room means switching rooms shows stale
-- or wrong unread state. This table tracks it per (user, room) instead.
-- The old users column is left in place, just no longer read/written.
create table if not exists room_last_seen (
  user_id uuid not null references users(id) on delete cascade,
  living_room_id uuid not null references living_rooms(id) on delete cascade,
  last_seen_at timestamptz not null default now(),
  primary key (user_id, living_room_id)
);

alter table room_last_seen enable row level security;

create policy room_last_seen_own on room_last_seen
  for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create or replace function get_living_room_data(p_room_id uuid)
returns jsonb
language plpgsql
as $$
declare
  v_user_id uuid := auth.uid();
  v_all_ids uuid[];
  v_last_seen timestamptz;
begin
  if v_user_id is null then
    raise exception 'Not authenticated';
  end if;

  if not (user_owns_room(p_room_id) or user_is_in_room(p_room_id) or user_is_admin()) then
    raise exception 'Not a member of this room';
  end if;

  select last_seen_at into v_last_seen
  from room_last_seen
  where user_id = v_user_id and living_room_id = p_room_id;

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
    return jsonb_build_object(
      'friends', '[]'::jsonb, 'shows', '[]'::jsonb,
      'reactions', '[]'::jsonb, 'top5', '[]'::jsonb, 'muted', '[]'::jsonb,
      'conversations_last_seen_at', v_last_seen
    );
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
    ),
    'conversations_last_seen_at', v_last_seen
  );
end;
$$;
