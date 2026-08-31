-- Widens Prime Time from "your own network" to every living room that
-- exists, platform-wide. Deliberate, considered decision for the current
-- beta stage (every beta2 room-creator is already a Beta1 member, so this
-- doesn't meaningfully expose anyone new right now) -- explicitly a
-- placeholder, not permanent; revisit before public App Store launch when
-- true strangers can join.
--
-- SECURITY DEFINER is required here: normal RLS only lets a user see
-- someone else's shows if they share a room, which is exactly the
-- restriction this feature needs to bypass to be genuinely platform-wide.
-- Still only exposes show title/rating/platform-level data and first
-- names -- nothing more sensitive than what per-room Friends Favorites
-- already shows.
create or replace function get_prime_time_rankings()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    raise exception 'Not authenticated';
  end if;

  return jsonb_build_object(
    'shows', (
      select coalesce(jsonb_agg(to_jsonb(s)), '[]'::jsonb)
      from shows s
      where s.hidden = false and s.rating > 0
    ),
    'people', (
      select coalesce(jsonb_agg(to_jsonb(u)), '[]'::jsonb)
      from (select id, first_name, last_initial from users) u
    )
  );
end;
$$;

grant execute on function get_prime_time_rankings() to authenticated;
