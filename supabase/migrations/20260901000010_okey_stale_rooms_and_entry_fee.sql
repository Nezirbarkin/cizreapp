-- =============================================================================
-- 101 Okey Plus — BİTMİŞ/ÖLÜ MASALARIN TEMİZLENMESİ + İSTEĞE BAĞLI MASA PUANI
-- -----------------------------------------------------------------------------
-- 1) ÖLÜ MASALAR
--    Bir oda `in_progress` kalıp maçı bitmişse (yeni el başlamamışsa) lobide
--    "Devam Et" olarak görünmeye devam ediyor ve oyuncuyu ölü bir masaya
--    götürüyordu. Artık böyle odalar kapatılır.
--    Ayrıca uzun süredir bekleyen ve kimsenin oturmadığı boş odalar da
--    temizlenir — lobi ölü masalarla dolmasın.
--
-- 2) MASA PUANI GERİ GELDİ (İSTEĞE BAĞLI)
--    Bahis daha önce tamamen kaldırılmıştı. Kullanıcı isteği üzerine geri
--    geliyor ama ZORUNLU DEĞİL: oda kurulurken 0 seçilirse masa ücretsizdir.
--    Ücretli masada her oyuncudan giriş puanı alınır ve pot kazanan(lar)a
--    dağıtılır; pottan komisyon kesilir (admin panelinden ayarlanır).
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '10s';

-- -----------------------------------------------------------------------------
-- 1) okey_cleanup_stale_rooms: ölü masaları kapat
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.okey_cleanup_stale_rooms()
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_closed int := 0;
  v_n int;
BEGIN
  -- (a) Maçı BİTMİŞ ama odası hâlâ açık görünenler
  UPDATE public.okey_rooms AS r
  SET status = 'finished', updated_at = now()
  WHERE r.status = 'in_progress'
    AND r.current_match_id IS NOT NULL
    AND EXISTS (
      SELECT 1 FROM public.okey_matches AS m
      WHERE m.id = r.current_match_id AND m.status = 'finished'
    );
  GET DIAGNOSTICS v_n = ROW_COUNT;
  v_closed := v_closed + COALESCE(v_n, 0);

  -- (b) Uzun süredir bekleyen ve İÇİNDE KİMSE OLMAYAN odalar
  UPDATE public.okey_rooms AS r
  SET status = 'abandoned', updated_at = now()
  WHERE r.status = 'waiting'
    AND r.created_at < now() - interval '2 hours'
    AND NOT EXISTS (
      SELECT 1 FROM public.okey_room_players AS rp
      WHERE rp.room_id = r.id AND (rp.user_id IS NOT NULL OR rp.is_bot)
    );
  GET DIAGNOSTICS v_n = ROW_COUNT;
  v_closed := v_closed + COALESCE(v_n, 0);

  RETURN v_closed;
END;
$$;
REVOKE ALL ON FUNCTION public.okey_cleanup_stale_rooms() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_cleanup_stale_rooms() TO authenticated;

COMMENT ON FUNCTION public.okey_cleanup_stale_rooms() IS
  'Maçı bitmiş ama açık kalmış odaları ve uzun süredir boş bekleyen odaları kapatır. Lobi her açıldığında çağrılır.';

-- -----------------------------------------------------------------------------
-- okey_my_active_room: GERÇEKTEN devam eden odam
--
-- Odanın durumu yetmez; maçı bitmişse o oda "devam ediyor" sayılmaz.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.okey_my_active_room()
RETURNS SETOF public.okey_rooms
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT r.*
  FROM public.okey_rooms AS r
  JOIN public.okey_room_players AS rp
    ON rp.room_id = r.id AND rp.user_id = (SELECT auth.uid())
  WHERE (SELECT auth.uid()) IS NOT NULL
    AND r.status IN ('waiting', 'in_progress')
    -- Maçı bitmiş oda "devam eden oyun" değildir
    AND (
      r.current_match_id IS NULL
      OR EXISTS (
        SELECT 1 FROM public.okey_matches AS m
        WHERE m.id = r.current_match_id AND m.status = 'in_progress'
      )
    )
  ORDER BY r.updated_at DESC
  LIMIT 1;
$$;
REVOKE ALL ON FUNCTION public.okey_my_active_room() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_my_active_room() TO authenticated;

-- -----------------------------------------------------------------------------
-- 2) create_okey_room: MASA PUANI (giriş ücreti) geri geldi — isteğe bağlı
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.create_okey_room(boolean, text, text, text, int);

CREATE FUNCTION public.create_okey_room(
  p_is_private boolean DEFAULT false,
  p_game_mode text DEFAULT 'katlamasiz',
  p_team_mode text DEFAULT 'essiz',
  p_assist_mode text DEFAULT 'yardimli',
  p_total_hands int DEFAULT 3,
  p_entry_fee int DEFAULT 0
)
RETURNS public.okey_rooms
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
  v_uid CONSTANT uuid := (SELECT auth.uid());
  v_room public.okey_rooms%ROWTYPE;
  v_join_code text;
  v_settings public.okey_settings%ROWTYPE;
  v_wallet public.okey_wallets%ROWTYPE;
  v_room_fee int;
  v_entry int;
  v_needed bigint;
  v_seat smallint;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'APP:auth_required' USING ERRCODE = '42501';
  END IF;
  IF public.okey_is_banned(v_uid) THEN
    RAISE EXCEPTION 'APP:okey_banned' USING ERRCODE = '42501';
  END IF;
  IF p_game_mode NOT IN ('katlamasiz', 'katlamali') THEN
    RAISE EXCEPTION 'APP:invalid_game_mode' USING ERRCODE = '22023';
  END IF;
  IF p_team_mode NOT IN ('essiz', 'esli') THEN
    RAISE EXCEPTION 'APP:invalid_team_mode' USING ERRCODE = '22023';
  END IF;
  IF p_assist_mode NOT IN ('yardimli', 'yardimsiz') THEN
    RAISE EXCEPTION 'APP:invalid_assist_mode' USING ERRCODE = '22023';
  END IF;
  IF COALESCE(p_total_hands, 3) < 1 OR COALESCE(p_total_hands, 3) > 20 THEN
    RAISE EXCEPTION 'APP:invalid_total_hands' USING ERRCODE = '22023';
  END IF;

  v_entry := GREATEST(COALESCE(p_entry_fee, 0), 0);

  SELECT s.* INTO v_settings FROM public.okey_settings AS s WHERE s.id = true;
  v_room_fee := COALESCE(v_settings.room_creation_fee, 0);

  -- Kurucu hem oda ücretini hem KENDİ giriş ücretini karşılayabilmeli
  v_needed := v_room_fee::bigint + v_entry::bigint;
  IF v_needed > 0 THEN
    v_wallet := public.okey_internal_ensure_wallet(v_uid);
    IF v_wallet.points < v_needed THEN
      RAISE EXCEPTION 'APP:insufficient_points | mevcut: %, gerekli: %',
        v_wallet.points, v_needed USING ERRCODE = 'P0001';
    END IF;
  END IF;

  IF p_is_private THEN
    v_join_code := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
  END IF;

  INSERT INTO public.okey_rooms (
    created_by, is_private, join_code, max_score, turn_seconds,
    game_mode, team_mode, assist_mode, entry_fee, total_hands
  ) VALUES (
    v_uid, p_is_private, v_join_code,
    COALESCE(v_settings.default_max_score, 101),
    COALESCE(v_settings.default_turn_seconds, 20),
    p_game_mode, p_team_mode, p_assist_mode,
    v_entry,
    COALESCE(p_total_hands, 3)
  ) RETURNING * INTO v_room;

  IF v_room_fee > 0 THEN
    PERFORM public.okey_internal_add_points(
      v_uid, -v_room_fee, 'room_fee', v_room.id::text
    );
    INSERT INTO public.okey_house_revenue (source, amount, room_id, user_id, ref)
    VALUES ('room_fee', v_room_fee, v_room.id, v_uid, v_room.id::text)
    ON CONFLICT DO NOTHING;
  END IF;

  FOR v_seat IN 0..3 LOOP
    INSERT INTO public.okey_room_players
      (room_id, seat_no, user_id, joined_at, is_ready)
    VALUES (
      v_room.id, v_seat,
      CASE WHEN v_seat = 0 THEN v_uid ELSE NULL END,
      CASE WHEN v_seat = 0 THEN now() ELSE NULL END,
      false
    );
  END LOOP;

  RETURN v_room;
END;
$$;
REVOKE ALL ON FUNCTION public.create_okey_room(boolean, text, text, text, int, int)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_okey_room(boolean, text, text, text, int, int)
  TO authenticated;

-- -----------------------------------------------------------------------------
-- join_okey_room: ücretli masaya girmek için YETERLİ PUAN şartı geri geldi
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.join_okey_room(
  p_room_id uuid DEFAULT NULL,
  p_join_code text DEFAULT NULL
)
RETURNS TABLE(r_room_id uuid, r_seat_no smallint)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid CONSTANT uuid := (SELECT auth.uid());
  v_room public.okey_rooms%ROWTYPE;
  v_seat smallint;
  v_wallet public.okey_wallets%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'APP:auth_required' USING ERRCODE = '42501';
  END IF;
  IF public.okey_is_banned(v_uid) THEN
    RAISE EXCEPTION 'APP:okey_banned' USING ERRCODE = '42501';
  END IF;
  IF p_room_id IS NULL AND p_join_code IS NULL THEN
    RAISE EXCEPTION 'APP:room_or_code_required' USING ERRCODE = '22023';
  END IF;

  SELECT r.* INTO v_room FROM public.okey_rooms AS r
  WHERE (p_room_id IS NOT NULL AND r.id = p_room_id)
     OR (p_join_code IS NOT NULL AND r.join_code = upper(p_join_code))
  FOR UPDATE;

  IF v_room.id IS NULL THEN
    RAISE EXCEPTION 'APP:not_found' USING ERRCODE = 'P0001';
  END IF;
  IF v_room.status <> 'waiting' THEN
    RAISE EXCEPTION 'APP:room_not_joinable' USING ERRCODE = 'P0001';
  END IF;

  SELECT rp.seat_no INTO v_seat FROM public.okey_room_players AS rp
  WHERE rp.room_id = v_room.id AND rp.user_id = v_uid;
  IF v_seat IS NOT NULL THEN
    RETURN QUERY SELECT v_room.id, v_seat;
    RETURN;
  END IF;

  -- ÜCRETLİ MASA: giriş puanını karşılayabilmeli
  IF v_room.entry_fee > 0 THEN
    v_wallet := public.okey_internal_ensure_wallet(v_uid);
    IF v_wallet.points < v_room.entry_fee THEN
      RAISE EXCEPTION 'APP:insufficient_points | mevcut: %, gerekli: %',
        v_wallet.points, v_room.entry_fee USING ERRCODE = 'P0001';
    END IF;
  END IF;

  SELECT rp.seat_no INTO v_seat FROM public.okey_room_players AS rp
  WHERE rp.room_id = v_room.id AND rp.user_id IS NULL AND NOT rp.is_bot
  ORDER BY rp.seat_no LIMIT 1 FOR UPDATE;

  IF v_seat IS NULL THEN
    RAISE EXCEPTION 'APP:room_full' USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.okey_room_players
  SET user_id = v_uid, joined_at = now(), is_ready = false, left_at = NULL
  WHERE room_id = v_room.id AND seat_no = v_seat;

  RETURN QUERY SELECT v_room.id, v_seat;
END;
$$;
REVOKE ALL ON FUNCTION public.join_okey_room(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.join_okey_room(uuid, text) TO authenticated;

-- -----------------------------------------------------------------------------
-- okey_internal_collect_entry_fees: ÜCRETLİ masada girişleri tahsil eder
-- (bahis kaldırıldığında boşaltılmıştı; geri getirildi)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.okey_internal_collect_entry_fees(p_room_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_room public.okey_rooms%ROWTYPE;
  v_player record;
BEGIN
  SELECT r.* INTO v_room FROM public.okey_rooms AS r
  WHERE r.id = p_room_id FOR UPDATE;

  -- Ücretsiz masa ya da zaten tahsil edilmişse hiçbir şey yapma
  IF v_room.id IS NULL OR v_room.entry_fee <= 0 OR v_room.entry_fee_collected THEN
    RETURN;
  END IF;

  FOR v_player IN
    SELECT rp.user_id FROM public.okey_room_players AS rp
    WHERE rp.room_id = p_room_id AND rp.user_id IS NOT NULL
  LOOP
    PERFORM public.okey_internal_add_points(
      v_player.user_id, -v_room.entry_fee, 'entry_fee',
      p_room_id::text || ':' || v_player.user_id::text
    );
  END LOOP;

  UPDATE public.okey_rooms SET entry_fee_collected = true WHERE id = p_room_id;
END;
$$;
REVOKE ALL ON FUNCTION public.okey_internal_collect_entry_fees(uuid)
  FROM PUBLIC, anon, authenticated;

NOTIFY pgrst, 'reload schema';
