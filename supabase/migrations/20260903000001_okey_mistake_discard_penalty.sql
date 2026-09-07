-- =============================================================================
-- 101 Okey Plus — İŞLEK TAŞI ATMA CEZASI ("Hatalı hamle" +101, RULES.md §7)
-- -----------------------------------------------------------------------------
-- RULES.md §7 "Hatalı hamle | Anında +101" kuralı yazılıydı ama sunucuda hiç
-- uygulanmıyordu — istemci tarafında yalnızca kozmetik bir kırmızı uyarı
-- vardı (bkz. OkeyGameProvider.discardMistakeTick), gerçek bir puan sonucu
-- yoktu. Artık: eli AÇIK bir oyuncu, masadaki açık bir pere (çift/gösterge
-- hariç, her iki uçtan uzatma dahil) İŞLENEBİLECEK bir taşı ıskartaya atarsa,
-- o elki cezasına sabit bir puan eklenir (varsayılan 101) — TIPKI okey atma
-- cezası (okey_discard_penalty) gibi, el sonunda skora yansır.
--
-- Botlar bundan ETKİLENMEZ: okey_bot_take_turn her zaman ÖNCE
-- okey_internal_bot_process_tiles ile işleyebildiği HER taşı işler, ancak
-- SONRA atar — yani atma anında elinde işlenebilir bir taş kalmaz.
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '10s';

ALTER TABLE public.okey_settings
  ADD COLUMN IF NOT EXISTS mistake_discard_penalty int NOT NULL DEFAULT 101;

COMMENT ON COLUMN public.okey_settings.mistake_discard_penalty IS
  'Masadaki açık bir pere işlenebilecek taşı ıskartaya atan oyuncuya el '
  'sonunda eklenen ceza puanı (RULES.md §7 "Hatalı hamle").';

-- -----------------------------------------------------------------------------
-- okey_internal_discard_for_seat: İŞLEK taş atılırsa da ceza yaz
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.okey_internal_discard_for_seat(
  p_match_id uuid,
  p_seat smallint,
  p_tile jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_match public.okey_matches%ROWTYPE;
  v_room public.okey_rooms%ROWTYPE;
  v_tiles jsonb;
  v_idx int;
  i int;
  v_pile jsonb;
  v_next_seat smallint;
  v_is_open boolean;
  v_penalty int;
  v_meld RECORD;
  v_was_processable boolean := false;
BEGIN
  SELECT m.* INTO v_match FROM public.okey_matches AS m WHERE m.id = p_match_id;
  SELECT r.* INTO v_room FROM public.okey_rooms AS r WHERE r.id = v_match.room_id;

  SELECT h.tiles, h.is_opening_done INTO v_tiles, v_is_open
  FROM public.okey_player_hands AS h
  WHERE h.match_id = p_match_id AND h.seat_no = p_seat FOR UPDATE;

  v_idx := NULL;
  FOR i IN 0 .. jsonb_array_length(v_tiles) - 1 LOOP
    IF v_tiles -> i = p_tile THEN
      v_idx := i;
      EXIT;
    END IF;
  END LOOP;
  IF v_idx IS NULL THEN
    RAISE EXCEPTION 'APP:tile_not_in_hand' USING ERRCODE = '22023';
  END IF;

  -- İŞLEK TAŞI ATMA CEZASI ("Hatalı hamle", RULES.md §7) ---------------------
  -- Taş elden düşürülmeden ÖNCE, MEVCUT masa perlerine göre kontrol edilir
  -- (bkz. okey_internal_discard_tile_usable'daki aynı desen — sadece burada
  -- kontrol edilen taş RAKİBİN ıskartası değil, ATANIN kendi elindeki taş).
  IF v_is_open THEN
    FOR v_meld IN
      SELECT tm.tiles FROM public.okey_table_melds AS tm
      WHERE tm.match_id = p_match_id
        AND tm.meld_type NOT IN ('pair', 'gosterge')
    LOOP
      IF public.okey_internal_extend_meld(
        v_meld.tiles, p_tile, v_match.okey_tile
      ) IS NOT NULL THEN
        v_was_processable := true;
        EXIT;
      END IF;
    END LOOP;
  END IF;

  IF v_was_processable THEN
    SELECT COALESCE(s.mistake_discard_penalty, 101) INTO v_penalty
    FROM public.okey_settings AS s WHERE s.id = true;

    IF COALESCE(v_penalty, 0) > 0 THEN
      UPDATE public.okey_player_hands
      SET penalty_points = penalty_points + v_penalty
      WHERE match_id = p_match_id AND seat_no = p_seat;
    END IF;
  END IF;

  v_tiles := v_tiles - v_idx;

  UPDATE public.okey_player_hands SET tiles = v_tiles, updated_at = now()
  WHERE match_id = p_match_id AND seat_no = p_seat;

  -- OKEY ATMA CEZASI ------------------------------------------------------
  -- Okey (veya onun yerine geçen sahte joker) ıskartaya atılırsa, atan
  -- oyuncunun bu elki cezasına sabit bir ceza eklenir. Ceza el sonunda
  -- skora yansır (bkz. okey_internal_finalize_hand).
  IF public.okey_tile_is_joker(p_tile, v_match.okey_tile) THEN
    SELECT COALESCE(s.okey_discard_penalty, 101) INTO v_penalty
    FROM public.okey_settings AS s WHERE s.id = true;

    IF COALESCE(v_penalty, 0) > 0 THEN
      UPDATE public.okey_player_hands
      SET penalty_points = penalty_points + v_penalty
      WHERE match_id = p_match_id AND seat_no = p_seat;
    END IF;
  END IF;

  v_pile := COALESCE(v_match.discard_piles -> p_seat::text, '[]'::jsonb)
            || jsonb_build_array(p_tile);

  UPDATE public.okey_matches
  SET discard_piles = jsonb_set(discard_piles, ARRAY[p_seat::text], v_pile)
  WHERE id = p_match_id;

  INSERT INTO public.okey_moves (match_id, hand_no, seat_no, action, tile)
  VALUES (p_match_id, v_match.hand_no, p_seat, 'discard', p_tile);

  -- RULES.md §6: eli boşaldıysa ve el açılmışsa oyuncu BİTİRDİ
  IF jsonb_array_length(v_tiles) = 0 AND v_is_open THEN
    PERFORM public.okey_internal_finalize_hand(p_match_id, p_seat, p_tile);
    RETURN;
  END IF;

  UPDATE public.okey_player_hands
  SET opened_this_turn = false
  WHERE match_id = p_match_id AND seat_no = p_seat;

  v_next_seat := (p_seat + 1) % 4;
  UPDATE public.okey_matches
  SET turn_seat = v_next_seat,
      turn_phase = 'draw',
      turn_token = gen_random_uuid(),
      turn_deadline = now() + make_interval(secs => v_room.turn_seconds)
  WHERE id = p_match_id;
END;
$$;
REVOKE ALL ON FUNCTION public.okey_internal_discard_for_seat(uuid, smallint, jsonb)
  FROM PUBLIC, anon, authenticated;

NOTIFY pgrst, 'reload schema';
