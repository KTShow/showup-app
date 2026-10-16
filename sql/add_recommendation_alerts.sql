-- ============================================================
-- add_recommendation_alerts.sql  (2026-10-16)
-- ============================================================
-- Alert the recipient when a friend recommends them a show: a bell row
-- (type 'recommendation') plus a phone/desktop alert via the same
-- push_pending hand-off comments use (sql/add_push_alerts.sql ->
-- /api/push).
--
--   * Shares the Comments switch (notification_prefs.comments, shown in
--     Settings as "Comments & recommendations") -- off = no bell row, no
--     alert.
--   * Skipped if the recipient muted the sender.
--   * entity_id = the recommendation id, so the app can clear the bell
--     row once the recommendation is added or dismissed.
--
-- A trigger (not an app-called function) so every recommendation gets
-- its alert however it was inserted. Run in the Supabase SQL editor.
-- Safe to re-run.
-- ============================================================

create or replace function notify_recommendation()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_name text;
  v_note text;
begin
  if new.to_user_id is null or new.to_user_id = new.from_user_id then return new; end if;
  if not coalesce((select np.comments from notification_prefs np where np.user_id = new.to_user_id), true) then
    return new;
  end if;
  if exists (select 1 from muted_friends m where m.user_id = new.to_user_id and m.muted_user_id = new.from_user_id) then
    return new;
  end if;

  select first_name || coalesce(' ' || nullif(last_initial, '') || '.', '') into v_name
    from users where id = new.from_user_id;
  v_name := coalesce(v_name, 'Someone');
  v_note := nullif(left(regexp_replace(coalesce(new.note, ''), '\s+', ' ', 'g'), 90), '');

  insert into notifications (user_id, type, title, body, tmdb_id, entity_id, meta, push_pending, created_at)
  values (new.to_user_id, 'recommendation', new.title,
          v_name || ' recommended this to you' || coalesce(': "' || v_note || '"', ''),
          new.tmdb_id, new.id, jsonb_build_object('actors', jsonb_build_array(new.from_user_id::text)),
          true, now());
  return new;
end;
$$;

drop trigger if exists recommendations_notify on recommendations;
create trigger recommendations_notify
  after insert on recommendations
  for each row execute function notify_recommendation();
