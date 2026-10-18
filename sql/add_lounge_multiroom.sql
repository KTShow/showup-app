-- ============================================================
-- add_lounge_multiroom.sql  (2026-10-18)
-- ============================================================
-- Post to The Lounge in several rooms at once. The app inserts one copy
-- per chosen room; copies share a group_id so the author's edit/delete
-- applies to all of them. Replies stay inside each room's copy (people
-- in different rooms never see each other's replies).
--
--   * lounge_posts.group_id -- null for a single-room post.
--   * get_lounge also returns group_id, and group_count (author only:
--     how many rooms the post went to).
--   * notify_lounge_post: the one-alert-an-hour limit is now per poster
--     across ALL rooms, so a friend who shares three rooms with you gets
--     one alert for a three-room post, not three.
--
-- Run in the Supabase SQL editor BEFORE deploying the app change.
-- Safe to re-run.
-- ============================================================

alter table lounge_posts add column if not exists group_id uuid;
create index if not exists lounge_posts_group_idx on lounge_posts (group_id) where group_id is not null;

-- ---------- get_lounge (adds group_id / group_count) -----------------
create or replace function get_lounge(p_room_id uuid)
returns jsonb language plpgsql as $$
declare
  v_uid  uuid := auth.uid();
  v_seen timestamptz;
begin
  if v_uid is null then raise exception 'Not authenticated'; end if;
  if not (user_owns_room(p_room_id) or user_is_in_room(p_room_id) or user_is_admin()) then
    raise exception 'Not a member of this room';
  end if;

  select lounge_seen_at into v_seen
    from room_last_seen where user_id = v_uid and living_room_id = p_room_id;

  return jsonb_build_object(
    'lounge_seen_at', v_seen,
    'posts', (
      select coalesce(jsonb_agg(to_jsonb(row) order by row.last_activity_at desc), '[]'::jsonb)
      from (
        select p.id, p.user_id, p.body, p.created_at, p.updated_at, p.last_activity_at,
               p.group_id,
               case when p.group_id is not null and p.user_id = v_uid
                    then (select count(*) from lounge_posts g where g.group_id = p.group_id) end as group_count,
               u.first_name, u.last_initial
        from lounge_posts p
        join users u on u.id = p.user_id
        where p.living_room_id = p_room_id
      ) row
    ),
    'replies', (
      select coalesce(jsonb_agg(to_jsonb(row) order by row.created_at), '[]'::jsonb)
      from (
        select r.id, r.post_id, r.user_id, r.body, r.created_at, r.updated_at,
               u.first_name, u.last_initial
        from lounge_replies r
        join lounge_posts p on p.id = r.post_id
        join users u on u.id = r.user_id
        where p.living_room_id = p_room_id
      ) row
    )
  );
end;
$$;

grant execute on function get_lounge(uuid) to authenticated;

-- ---------- notify_lounge_post (limit now across rooms) --------------
create or replace function notify_lounge_post()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_name      text;
  v_room_name text;
  v_snippet   text;
  t           record;
  v_existing  uuid;
begin
  select first_name || coalesce(' ' || nullif(last_initial, '') || '.', '') into v_name
    from users where id = new.user_id;
  v_name := coalesce(v_name, 'Someone');
  select name into v_room_name from living_rooms where id = new.living_room_id;
  v_snippet := left(regexp_replace(coalesce(new.body, ''), '\s+', ' ', 'g'), 90);

  for t in
    select distinct p.user_id as tgt from (
      select user_id from living_room_members where living_room_id = new.living_room_id and status = 'active'
      union
      select owner_id from living_rooms where id = new.living_room_id
    ) p
    where p.user_id is not null and p.user_id <> new.user_id
      and not exists (select 1 from muted_friends m where m.user_id = p.user_id and m.muted_user_id = new.user_id)
      and not exists (select 1 from blocked_users bu where bu.user_id = p.user_id and bu.blocked_user_id = new.user_id)
      and coalesce((select np.lounge from notification_prefs np where np.user_id = p.user_id), true)
  loop
    select id into v_existing from notifications
     where user_id = t.tgt and type = 'lounge_post'
       and meta -> 'actors' @> to_jsonb(new.user_id::text)
       and created_at > now() - interval '1 hour'
     order by created_at desc limit 1;

    if found then
      update notifications set room_id = new.living_room_id, entity_id = new.id,
             title = coalesce(v_room_name, 'The Lounge'), body = v_name || ' posted: ' || v_snippet,
             seen_at = null, read_at = null
       where id = v_existing;
    else
      insert into notifications (user_id, type, title, body, room_id, entity_id, meta, push_pending, created_at)
      values (t.tgt, 'lounge_post', coalesce(v_room_name, 'The Lounge'), v_name || ' posted: ' || v_snippet,
              new.living_room_id, new.id, jsonb_build_object('actors', jsonb_build_array(new.user_id::text)),
              true, now());
    end if;
  end loop;
  return new;
end;
$$;
