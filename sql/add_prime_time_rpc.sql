-- Powers the "Prime Time" cross-room leaderboard tile in the room picker.
-- Returns rated shows + basic profiles for everyone across every room the
-- caller owns or belongs to (deduped) -- scoped to the caller's own
-- network, not platform-wide. Aggregation/dedup-by-person happens
-- client-side, same as the per-room Friends Favorites leaderboard.
create or replace function get_prime_time_rankings()
returns jsonb
language plpgsql
as $$
declare
  v_user_id uuid := auth.uid();
  v_all_ids uuid[];
begin
  if v_user_id is null then
    raise exception 'Not authenticated';
  end if;

  with my_rooms as (
    select id from living_rooms where owner_id = v_user_id
    union
    select living_room_id from living_room_members where user_id = v_user_id and status = 'active'
  )
  select coalesce(array_agg(distinct uid), '{}')
    into v_all_ids
    from (
      select owner_id as uid from living_rooms where id in (select id from my_rooms)
      union
      select user_id as uid from living_room_members
      where status = 'active' and living_room_id in (select id from my_rooms)
    ) participants;

  if v_all_ids is null or array_length(v_all_ids, 1) is null then
    return jsonb_build_object('shows', '[]'::jsonb, 'people', '[]'::jsonb);
  end if;

  return jsonb_build_object(
    'shows', (
      select coalesce(jsonb_agg(to_jsonb(s)), '[]'::jsonb)
      from shows s
      where s.user_id = any(v_all_ids) and s.hidden = false and s.rating > 0
    ),
    'people', (
      select coalesce(jsonb_agg(to_jsonb(u)), '[]'::jsonb)
      from (
        select id, first_name, last_initial from users where id = any(v_all_ids)
      ) u
    )
  );
end;
$$;

grant execute on function get_prime_time_rankings() to authenticated;
