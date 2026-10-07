-- ============================================================
-- update_comment_digest_seen.sql  (2026-10-07)
-- ============================================================
-- The bell now shows new seasons only, so "opened the bell" no longer means
-- someone saw a comment. get_comment_digest() now treats a comment as seen
-- when the person opened it (tapped the phone alert -> read_at) or has
-- viewed that room's conversations since it was posted (room_last_seen).
-- Everything else is unchanged from add_comment_digest.sql.
--
-- Run in the Supabase SQL editor. Safe to re-run.
-- ============================================================

create or replace function get_comment_digest()
returns table (user_id uuid, email text, first_name text, items jsonb)
language sql
security definer
set search_path to 'public'
as $$
  select n.user_id,
         au.email::text,
         u.first_name,
         jsonb_agg(jsonb_build_object('id', n.id, 'title', n.title, 'body', n.body)
                   order by n.created_at desc) as items
    from notifications n
    join auth.users au on au.id = n.user_id
    left join users u on u.id = n.user_id
    left join notification_prefs np on np.user_id = n.user_id
   where n.type = 'comment'
     and n.created_at > now() - interval '7 days'
     and n.read_at is null
     and not exists (
       select 1 from room_last_seen rls
        where rls.user_id = n.user_id
          and rls.living_room_id = n.room_id
          and rls.last_seen_at >= n.created_at
     )
     and n.dismissed_at is null
     and n.emailed_at is null
     and au.email is not null
     and coalesce(np.email_digest, true)
     and coalesce(np.comments, true)
     and not exists (select 1 from push_subscriptions ps where ps.user_id = n.user_id)
   group by n.user_id, au.email, u.first_name;
$$;

revoke execute on function get_comment_digest() from public, anon, authenticated;
grant  execute on function get_comment_digest() to service_role;
