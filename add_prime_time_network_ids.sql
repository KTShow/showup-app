-- Adds network_ids to Prime Time's data: everyone in the viewer's own
-- rooms (same computation the network-only version used before it was
-- widened to platform-wide). The "shows"/"people" data stays platform-wide;
-- network_ids is used purely client-side to decide whether to show a
-- rater's real name or anonymize them as "Neighbor".
create or replace function get_prime_time_rankings()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_user_id uuid := auth.uid();
  v_network_ids uuid[];
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
    into v_network_ids
    from (
      select owner_id as uid from living_rooms where id in (select id from my_rooms)
      union
      select user_id as uid from living_room_members
      where status = 'active' and living_room_id in (select id from my_rooms)
    ) participants;

  return jsonb_build_object(
    'shows', (
      select coalesce(jsonb_agg(to_jsonb(s)), '[]'::jsonb)
      from shows s
      where s.hidden = false and s.rating > 0
    ),
    'people', (
      select coalesce(jsonb_agg(to_jsonb(u)), '[]'::jsonb)
      from (select id, first_name, last_initial from users) u
    ),
    'network_ids', to_jsonb(coalesce(v_network_ids, '{}'::uuid[]))
  );
end;
$$;

grant execute on function get_prime_time_rankings() to authenticated;
