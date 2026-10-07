-- ============================================================
-- add_comment_digest.sql  (2026-10-06)
-- ============================================================
-- Weekly email recap of comments, for people who don't get phone alerts.
-- Sent Sundays by scripts/send-comment-digest.mjs (GitHub Actions).
--
--   * notification_prefs.email_digest -- Settings toggle + the email's
--     unsubscribe link; off = no recap emails.
--   * notifications.emailed_at -- stamped once a comment bell row has gone
--     out in a recap, so it's never emailed twice.
--   * get_comment_digest() -- who gets a recap this week and what's in it:
--     comment bell rows from the last 7 days that the person hasn't seen in
--     the app yet (bell never opened past them), not already emailed, for
--     people with NO device signed up for phone alerts, comment alerts on,
--     and the recap on.
--   * mark_digest_sent(ids) / digest_unsubscribe(user) -- bookkeeping.
--
-- All three functions are service-role only (the weekly job and
-- /api/unsubscribe); the app never calls them.
--
-- Run in the Supabase SQL editor. Safe to re-run.
-- ============================================================

alter table notification_prefs add column if not exists email_digest boolean not null default true;
alter table notifications add column if not exists emailed_at timestamptz;

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
     and n.seen_at is null
     and n.dismissed_at is null
     and n.emailed_at is null
     and au.email is not null
     and coalesce(np.email_digest, true)
     and coalesce(np.comments, true)
     and not exists (select 1 from push_subscriptions ps where ps.user_id = n.user_id)
   group by n.user_id, au.email, u.first_name;
$$;

create or replace function mark_digest_sent(p_ids uuid[])
returns void
language sql
security definer
set search_path to 'public'
as $$
  update notifications set emailed_at = now() where id = any(p_ids);
$$;

create or replace function digest_unsubscribe(p_user_id uuid)
returns void
language sql
security definer
set search_path to 'public'
as $$
  insert into notification_prefs (user_id, email_digest, updated_at)
  values (p_user_id, false, now())
  on conflict (user_id) do update set email_digest = false, updated_at = now();
$$;

revoke execute on function get_comment_digest()      from public, anon, authenticated;
revoke execute on function mark_digest_sent(uuid[])  from public, anon, authenticated;
revoke execute on function digest_unsubscribe(uuid)  from public, anon, authenticated;
grant  execute on function get_comment_digest()      to service_role;
grant  execute on function mark_digest_sent(uuid[])  to service_role;
grant  execute on function digest_unsubscribe(uuid)  to service_role;
