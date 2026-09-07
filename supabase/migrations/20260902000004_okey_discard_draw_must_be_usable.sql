-- =============================================================================
-- 101 Okey Plus — YANDAN ÇEKME artık gerçek kuralı UYGULAR
-- -----------------------------------------------------------------------------
-- RULES.md §4 "Yandan (soldaki oyuncudan) taş alma" şunu tarifliyordu:
--   - Elin açık değilse: alınan taş AYNI TURDA açtığın perlerden birinde
--     kullanılmalı.
--   - Elin zaten açıksa: taş yalnızca masadaki açık bir pere işlenebiliyorsa
--     alınabilir; doğrudan ele saklanamaz.
-- Ama bu kural hiçbir zaman KODLANMAMIŞTI — okey_internal_draw_for_seat,
-- 'discard' kaynağından çekerken hiçbir kullanılabilirlik kontrolü yapmadan
-- taşı doğrudan ele ekliyordu. Kullanıcı isteği: "yandan çekilen taş
-- açabiliyorsa geçerli olsun, açamıyorsa taşı geri bırakabilsin" — yani bu
-- boşluk kapatılsın.
--
-- YAKLAŞIM: taş asla "alınıp sonra geri konmuyor" — kullanılamayacaksa
-- BAŞTAN alınmıyor (transaction hiç ilerlemiyor, taş ıskartada kalmaya
-- devam ediyor). Bu hem daha basit hem daha güvenli: yarı tamamlanmış bir
-- "geri koyma" akışına hiç gerek kalmıyor.
--
-- Yeniden kullanılan mevcut motor:
--   - okey_internal_bot_wants_discard: eli henüz açık değilse, taş elin per
--     potansiyelini ARTIRIYOR MU diye zaten botlar için bakıyordu — aynı
--     ölçüt insan oyuncu için de mantıklı ("açmaya yardımcı olmalı").
--   - okey_is_valid_meld: eli zaten açıksa, taş masadaki bir pere (çift/
--     gösterge hariç) eklendiğinde geçerli mi diye okey_add_to_meld'in
--     kullandığı AYNI kontrol.
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '10s';

-- -----------------------------------------------------------------------------
-- okey_internal_discard_tile_usable: bu koltuk şu an bu taşı yandan alabilir mi?
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.okey_internal_discard_tile_usable(
  p_match_id uuid,
  p_seat smallint,
  p_candidate jsonb
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SET search_path = ''
AS $$
DECLARE
  v_match public.okey_matches%ROWTYPE;
  v_hand public.okey_player_hands%ROWTYPE;
  v_meld RECORD;
BEGIN
  SELECT m.* INTO v_match FROM public.okey_matches AS m WHERE m.id = p_match_id;
  SELECT h.* INTO v_hand FROM public.okey_player_hands AS h
  WHERE h.match_id = p_match_id AND h.seat_no = p_seat;

  IF v_hand.is_opening_done THEN
    -- Eli açık: taş yalnızca masadaki açık bir pere (çift/gösterge hariç)
    -- işlenebiliyorsa alınabilir.
    FOR v_meld IN
      SELECT tm.tiles FROM public.okey_table_melds AS tm
      WHERE tm.match_id = p_match_id
        AND tm.meld_type NOT IN ('pair', 'gosterge')
    LOOP
      IF public.okey_is_valid_meld(
        v_meld.tiles || jsonb_build_array(p_candidate), v_match.okey_tile
      ) THEN
        RETURN true;
      END IF;
    END LOOP;
    RETURN false;
  ELSE
    -- Eli henüz açık değil: taş elin per potansiyelini artırıyorsa alınabilir.
    RETURN public.okey_internal_bot_wants_discard(
      v_hand.tiles, p_candidate, v_match.okey_tile
    );
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.okey_internal_discard_tile_usable(uuid, smallint, jsonb)
  FROM PUBLIC, anon, authenticated;

-- -----------------------------------------------------------------------------
-- okey_internal_draw_for_seat: 'discard' dalına kullanılabilirlik kontrolü
-- eklendi. 'deck' dalı DEĞİŞMEDİ (deste tükenirse el kazanansız biter —
-- bkz. 20260830000012_okey101_lay_meld_and_modes.sql, buradaki GÜNCEL
-- gövdeden aynen alındı).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.okey_internal_draw_for_seat(
  p_match_id uuid,
  p_seat smallint,
  p_source text -- 'deck' | 'discard'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_match public.okey_matches%ROWTYPE;
  v_drawn jsonb;
  v_deck jsonb;
  v_prev_seat smallint;
  v_prev_pile jsonb;
BEGIN
  SELECT m.* INTO v_match FROM public.okey_matches AS m WHERE m.id = p_match_id;

  IF p_source = 'deck' THEN
    IF v_match.deck_remaining <= 0 THEN
      -- RULES.md kapsamı dışı köşe durum: deste bitti, el kazanansız kapanır
      PERFORM public.okey_internal_finalize_hand(p_match_id, NULL, NULL);
      RETURN NULL;
    END IF;

    SELECT d.remaining_deck INTO v_deck FROM public.okey_match_decks AS d
    WHERE d.match_id = p_match_id FOR UPDATE;

    v_drawn := v_deck -> 0;
    v_deck := v_deck - 0;

    UPDATE public.okey_match_decks SET remaining_deck = v_deck WHERE match_id = p_match_id;
    UPDATE public.okey_matches
    SET deck_remaining = deck_remaining - 1, turn_phase = 'discard'
    WHERE id = p_match_id;

    INSERT INTO public.okey_moves (match_id, hand_no, seat_no, action, tile)
    VALUES (p_match_id, v_match.hand_no, p_seat, 'draw_deck', v_drawn);
  ELSE
    v_prev_seat := (p_seat + 3) % 4;
    v_prev_pile := v_match.discard_piles -> v_prev_seat::text;
    IF v_prev_pile IS NULL OR jsonb_array_length(v_prev_pile) = 0 THEN
      RAISE EXCEPTION 'APP:discard_pile_empty' USING ERRCODE = 'P0001';
    END IF;

    v_drawn := v_prev_pile -> (jsonb_array_length(v_prev_pile) - 1);

    -- KULLANICI İSTEĞİ / RULES.md §4: taş işine yaramıyorsa hiç alınmaz —
    -- ıskartada kalmaya devam eder (fiilen "geri bırakılmış" olur, çünkü
    -- zaten hiç çıkarılmadı).
    IF NOT public.okey_internal_discard_tile_usable(p_match_id, p_seat, v_drawn) THEN
      RAISE EXCEPTION 'APP:discard_tile_not_usable' USING ERRCODE = '22023';
    END IF;

    v_prev_pile := v_prev_pile - (jsonb_array_length(v_prev_pile) - 1);

    UPDATE public.okey_matches
    SET discard_piles = jsonb_set(discard_piles, ARRAY[v_prev_seat::text], v_prev_pile),
        turn_phase = 'discard'
    WHERE id = p_match_id;

    INSERT INTO public.okey_moves (match_id, hand_no, seat_no, action, tile)
    VALUES (p_match_id, v_match.hand_no, p_seat, 'draw_discard', v_drawn);
  END IF;

  UPDATE public.okey_player_hands
  SET tiles = tiles || jsonb_build_array(v_drawn), updated_at = now()
  WHERE match_id = p_match_id AND seat_no = p_seat;

  RETURN v_drawn;
END;
$$;

REVOKE ALL ON FUNCTION public.okey_internal_draw_for_seat(uuid, smallint, text)
  FROM PUBLIC, anon, authenticated;

-- -----------------------------------------------------------------------------
-- okey_bot_take_turn: botun kendi ıskarta kararı, YUKARIDAKİ AYNI ölçütü
-- kullanacak şekilde güncellendi (gövdenin geri kalanı
-- 20260901000009_okey_in_hand_penalty_and_bot_process.sql'deki GÜNCEL
-- AÇ->İŞLE->AT sürümüyle birebir aynı — yalnızca ÇEKME adımındaki ölçüt
-- değişti).
--
-- NEDEN GEREKLİ: bot kendi kararını hep okey_internal_bot_wants_discard ile
-- veriyordu (yalnızca "eldeki per potansiyelini artırır mı" bakan ölçüt).
-- Ama okey_internal_draw_for_seat artık eli AÇIK olan koltuklar için FARKLI
-- bir ölçüt uyguluyor ("masadaki bir pere işlenebiliyor mu"). Eli zaten açık
-- bir bot eski ölçütle "alayım" deyip sonra yeni kapıdan reddedilirse,
-- PERFORM public.okey_internal_draw_for_seat(...) hatayı YAKALAMADAN
-- fırlatır ve botun TÜM turu (açma + işleme + atma dahil) çöker. Botun
-- kararı da aynı fonksiyonu (okey_internal_discard_tile_usable) sorup bu
-- riski tamamen ortadan kaldırır.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.okey_bot_take_turn(uuid);

CREATE FUNCTION public.okey_bot_take_turn(p_match_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid CONSTANT uuid := (SELECT auth.uid());
  v_match public.okey_matches%ROWTYPE;
  v_seat smallint;
  v_prev_seat smallint;
  v_is_bot boolean;
  v_hand_tiles jsonb;
  v_groups jsonb;
  v_tile jsonb;
  v_pile jsonb;
  v_top jsonb;
  v_source text;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'APP:auth_required' USING ERRCODE = '42501';
  END IF;

  SELECT m.* INTO v_match FROM public.okey_matches AS m
  WHERE m.id = p_match_id FOR UPDATE;
  IF v_match.id IS NULL THEN
    RAISE EXCEPTION 'APP:not_found' USING ERRCODE = 'P0001';
  END IF;
  IF v_match.status <> 'in_progress' THEN
    RETURN;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.okey_room_players AS rp
    WHERE rp.room_id = v_match.room_id AND rp.user_id = v_uid
  ) THEN
    RAISE EXCEPTION 'APP:not_seated' USING ERRCODE = '42501';
  END IF;

  v_seat := v_match.turn_seat;

  SELECT rp.is_bot INTO v_is_bot FROM public.okey_room_players AS rp
  WHERE rp.room_id = v_match.room_id AND rp.seat_no = v_seat;
  IF NOT COALESCE(v_is_bot, false) THEN
    RETURN;
  END IF;

  -- 1) ÇEKME — soldakinin ıskartası işe yarıyorsa oradan, yoksa desteden
  IF v_match.turn_phase = 'draw' THEN
    SELECT h.tiles INTO v_hand_tiles FROM public.okey_player_hands AS h
    WHERE h.match_id = p_match_id AND h.seat_no = v_seat;

    v_source := 'deck';
    v_prev_seat := (v_seat + 3) % 4;
    v_pile := v_match.discard_piles -> v_prev_seat::text;

    IF v_pile IS NOT NULL AND jsonb_array_length(v_pile) > 0 THEN
      v_top := v_pile -> (jsonb_array_length(v_pile) - 1);
      IF public.okey_internal_discard_tile_usable(p_match_id, v_seat, v_top) THEN
        v_source := 'discard';
      END IF;
    END IF;

    IF v_source = 'deck' AND v_match.deck_remaining <= 0 THEN
      PERFORM public.okey_internal_finalize_hand(p_match_id, NULL, NULL);
      RETURN;
    END IF;

    PERFORM public.okey_internal_draw_for_seat(p_match_id, v_seat, v_source);
    SELECT m.* INTO v_match FROM public.okey_matches AS m WHERE m.id = p_match_id;
  END IF;

  -- 2) AÇMA
  SELECT h.tiles INTO v_hand_tiles FROM public.okey_player_hands AS h
  WHERE h.match_id = p_match_id AND h.seat_no = v_seat;

  v_groups := public.okey_internal_find_melds(v_hand_tiles, v_match.okey_tile);
  IF jsonb_array_length(COALESCE(v_groups, '[]'::jsonb)) > 0 THEN
    PERFORM public.okey_internal_lay_groups_for_seat(p_match_id, v_seat, v_groups);
  END IF;

  -- 3) İŞLEME — açık perlere taş ekle ("işlek")
  PERFORM public.okey_internal_bot_process_tiles(p_match_id, v_seat);

  -- El bu arada bitmiş olabilir
  SELECT m.* INTO v_match FROM public.okey_matches AS m WHERE m.id = p_match_id;
  IF v_match.status <> 'in_progress' THEN
    RETURN;
  END IF;

  -- 4) ATMA — okey asla atılmaz
  SELECT h.tiles INTO v_hand_tiles FROM public.okey_player_hands AS h
  WHERE h.match_id = p_match_id AND h.seat_no = v_seat;

  IF v_hand_tiles IS NOT NULL AND jsonb_array_length(v_hand_tiles) > 0 THEN
    v_tile := public.okey_internal_bot_pick_discard(v_hand_tiles, v_match.okey_tile);
    IF v_tile IS NOT NULL THEN
      PERFORM public.okey_internal_discard_for_seat(p_match_id, v_seat, v_tile);
    END IF;
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.okey_bot_take_turn(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_bot_take_turn(uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';
