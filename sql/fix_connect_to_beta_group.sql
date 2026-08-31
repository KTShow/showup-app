CREATE OR REPLACE FUNCTION connect_to_beta_group(p_inviter_username text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_joiner_id uuid;
  v_inviter_id uuid;
  v_inviter_room_id uuid;
  v_joiner_room_id uuid;
  v_friend_id uuid;
  v_friend_room_id uuid;
BEGIN
  v_joiner_id := auth.uid();
  IF v_joiner_id IS NULL THEN RETURN; END IF;

  SELECT id INTO v_inviter_id FROM users WHERE username = p_inviter_username;
  IF v_inviter_id IS NULL THEN RETURN; END IF;
  IF v_joiner_id = v_inviter_id THEN RETURN; END IF;

  SELECT id INTO v_inviter_room_id FROM living_rooms WHERE owner_id = v_inviter_id;
  SELECT id INTO v_joiner_room_id FROM living_rooms WHERE owner_id = v_joiner_id;
  IF v_inviter_room_id IS NULL OR v_joiner_room_id IS NULL THEN RETURN; END IF;

  -- connect joiner <-> inviter (both directions)
  INSERT INTO living_room_members (living_room_id, user_id, status, invited_by)
    VALUES (v_inviter_room_id, v_joiner_id, 'active', v_inviter_id)
    ON CONFLICT (living_room_id, user_id) DO UPDATE SET status = 'active';
  INSERT INTO living_room_members (living_room_id, user_id, status, invited_by)
    VALUES (v_joiner_room_id, v_inviter_id, 'active', v_inviter_id)
    ON CONFLICT (living_room_id, user_id) DO UPDATE SET status = 'active';

  -- fan out: connect joiner to everyone already linked to the inviter
  FOR v_friend_id IN (
    SELECT DISTINCT lrm.user_id
      FROM living_room_members lrm
      WHERE lrm.living_room_id = v_inviter_room_id AND lrm.status = 'active'
    UNION
    SELECT DISTINCT lr.owner_id
      FROM living_room_members lrm2
      JOIN living_rooms lr ON lr.id = lrm2.living_room_id
      WHERE lrm2.user_id = v_inviter_id AND lrm2.status = 'active'
  )
  LOOP
    IF v_friend_id = v_joiner_id OR v_friend_id = v_inviter_id THEN CONTINUE; END IF;

    SELECT id INTO v_friend_room_id FROM living_rooms WHERE owner_id = v_friend_id;
    IF v_friend_room_id IS NULL THEN CONTINUE; END IF;

    INSERT INTO living_room_members (living_room_id, user_id, status, invited_by)
      VALUES (v_friend_room_id, v_joiner_id, 'active', v_inviter_id)
      ON CONFLICT (living_room_id, user_id) DO UPDATE SET status = 'active';
    INSERT INTO living_room_members (living_room_id, user_id, status, invited_by)
      VALUES (v_joiner_room_id, v_friend_id, 'active', v_inviter_id)
      ON CONFLICT (living_room_id, user_id) DO UPDATE SET status = 'active';
  END LOOP;
END;
$$;
