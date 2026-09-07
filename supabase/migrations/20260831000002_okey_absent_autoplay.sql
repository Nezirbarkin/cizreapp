-- =============================================================================
-- 101 Okey Plus — Bağlantısı kopan / çıkan oyuncu için otomatik oynatma
-- -----------------------------------------------------------------------------
-- Sorun: bir oyuncu uygulamayı kapatır, bağlantısı kopar veya odadan çıkarsa
-- sıra ona geldiğinde masa sonsuza kadar kilitleniyordu.
--
-- Çözüm: her istemci periyodik olarak `okey_touch_presence` çağırıp kendi
-- `last_seen_at` damgasını tazeler. Sıra, uzun süredir görünmeyen bir koltuğa
-- geldiğinde masadaki HERHANGİ bir aktif oyuncunun istemcisi
-- `okey_auto_play_absent` çağırır; sunucu o koltuk adına desteden taş çekip
-- ÇEKTİĞİ TAŞI DOĞRUDAN ATAR (böylece oyuncunun eli değişmez, oyun akar).
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '5s';

ALTER TABLE public.okey_room_players
  ADD COLUMN IF NOT EXISTS last_seen_at timestamptz;

COMMENT ON COLUMN public.okey_room_players.last_seen_at IS
  'İstemcinin son "buradayım" damgası. Bu damga eskimişse oyuncu bağlantısı kopmuş sayılır ve sırası otomatik oynanır.';

-- -----------------------------------------------------------------------------
-- okey_touch_presence: "buradayım" damgası (istemci ~10 sn'de bir çağırır)
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.okey_touch_presence(uuid);

CREATE FUNCTION public.okey_touch_presence(p_room_id uuid)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  UPDATE public.okey_room_players
  SET last_seen_at = now()
  WHERE room_id = p_room_id AND user_id = (SELECT auth.uid());
$$;
REVOKE ALL ON FUNCTION public.okey_touch_presence(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_touch_presence(uuid) TO authenticated;

-- -----------------------------------------------------------------------------
-- okey_seat_is_absent: koltuk oyuncusu yok/kopmuş mu?
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.okey_seat_is_absent(
  p_room_id uuid,
  p_seat smallint,
  p_timeout_seconds int DEFAULT 30
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT COALESCE(
    (
      SELECT
        rp.user_id IS NULL              -- koltuk boş (çıkmış) — bot değilse
        AND NOT rp.is_bot
        OR (
          rp.user_id IS NOT NULL
          AND (
            rp.last_seen_at IS NULL
            OR rp.last_seen_at < now() - make_interval(secs => p_timeout_seconds)
          )
        )
      FROM public.okey_room_players AS rp
      WHERE rp.room_id = p_room_id AND rp.seat_no = p_seat
    ),
    false
  );
$$;
REVOKE ALL ON FUNCTION public.okey_seat_is_absent(uuid, smallint, int)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_seat_is_absent(uuid, smallint, int)
  TO authenticated;

-- -----------------------------------------------------------------------------
-- okey_auto_play_absent: sırası gelen koltuk yoksa/kopmuşsa onun adına oyna
-- Davranış: desteden taş çek, ÇEKTİĞİ TAŞI DOĞRUDAN AT (el değişmez).
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.okey_auto_play_absent(uuid);

CREATE FUNCTION public.okey_auto_play_absent(p_match_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid CONSTANT uuid := (SELECT auth.uid());
  v_match public.okey_matches%ROWTYPE;
  v_seat smallint;
  v_drawn jsonb;
  v_tiles jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'APP:auth_required' USING ERRCODE = '42501';
  END IF;

  SELECT m.* INTO v_match FROM public.okey_matches AS m
  WHERE m.id = p_match_id FOR UPDATE;
  IF v_match.id IS NULL OR v_match.status <> 'in_progress' THEN
    RETURN false;
  END IF;

  -- Çağıran bu masada oturuyor olmalı
  IF NOT EXISTS (
    SELECT 1 FROM public.okey_room_players AS rp
    WHERE rp.room_id = v_match.room_id AND rp.user_id = v_uid
  ) THEN
    RAISE EXCEPTION 'APP:not_seated' USING ERRCODE = '42501';
  END IF;

  v_seat := v_match.turn_seat;

  -- Sırası gelen koltuk gerçekten yok/kopmuş mu? (sunucu bağımsız doğrular)
  IF NOT public.okey_seat_is_absent(v_match.room_id, v_seat, 30) THEN
    RETURN false;
  END IF;

  -- Çekme aşamasındaysa desteden çek
  IF v_match.turn_phase = 'draw' THEN
    IF v_match.deck_remaining <= 0 THEN
      PERFORM public.okey_internal_finalize_hand(p_match_id, NULL, NULL);
      RETURN true;
    END IF;
    v_drawn := public.okey_internal_draw_for_seat(p_match_id, v_seat, 'deck');
    -- ÇEKTİĞİ TAŞI DOĞRUDAN AT (oyuncunun eli olduğu gibi kalır)
    IF v_drawn IS NOT NULL THEN
      PERFORM public.okey_internal_discard_for_seat(p_match_id, v_seat, v_drawn);
      RETURN true;
    END IF;
    RETURN false;
  END IF;

  -- Atma aşamasında kalmışsa elin ilk taşını at
  SELECT h.tiles INTO v_tiles FROM public.okey_player_hands AS h
  WHERE h.match_id = p_match_id AND h.seat_no = v_seat;
  IF v_tiles IS NOT NULL AND jsonb_array_length(v_tiles) > 0 THEN
    PERFORM public.okey_internal_discard_for_seat(p_match_id, v_seat, v_tiles -> 0);
    RETURN true;
  END IF;

  RETURN false;
END;
$$;
REVOKE ALL ON FUNCTION public.okey_auto_play_absent(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_auto_play_absent(uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';
