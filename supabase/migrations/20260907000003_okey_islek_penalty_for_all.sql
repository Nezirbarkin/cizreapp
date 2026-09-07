-- =============================================================================
-- 101 Okey Plus — İŞLEK TAŞ CEZASI ARTIK ELİ KAPALI OYUNCUYA DA YAZILIR
-- -----------------------------------------------------------------------------
-- RULES.md §7 "Hatalı hamle | Anında +101" kuralı, masadaki açık bir pere
-- İŞLENEBİLECEK taşı ıskartaya atmayı cezalandırır ve metinde atan oyuncunun
-- eli açık olmalı diye bir şart YOKTUR. Buna karşın 20260903000001 cezayı
-- `v_is_open` koşuluna bağlamıştı.
--
-- Sonuç: kural kâğıt üzerinde vardı, masada yoktu. Canlı hamle kayıtlarında
-- oyuncuların attığı işlek taşların tamamına yakını el AÇILMADAN önce
-- atılıyor (ör. 2026-09-06 22:00:06'da atılan Mavi 7'yi rakip aynı turda
-- ıskartadan alıp perine işledi) ve hiçbirine ceza yazılmıyordu. Kullanıcı
-- bunu "işlek taş attığımda 101 ceza yazılmıyor" diye bildirdi.
--
-- Bu göç yalnızca o koşulu kaldırır. Diğer iki koruma DURUYOR:
--   * `p_is_auto` — süre dolumu / kopmuş oyuncu adına yapılan otomatik
--     atmalarda ceza yazılmaz (taşı oyuncu seçmedi, RULES.md §7).
--   * okey/sahte okey atışı — daha özel kural (okey atma cezası) kazanır,
--     cezalar üst üste binmez.
--
-- GÖVDE 20260905000001'DEKİ SÜRÜMDEN ALINDI ve canlı şemadaki tanımla
-- (pg_get_functiondef) satır satır karşılaştırıldı: aradaki tek fark
-- aşağıdaki koşuldur.
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '10s';


CREATE OR REPLACE FUNCTION public.okey_internal_discard_for_seat(
  p_match_id uuid,
  p_seat smallint,
  p_tile jsonb,
  p_is_auto boolean DEFAULT false
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
  v_side_tile jsonb;
  v_side_count int;
  v_cur_count int;
BEGIN
  SELECT m.* INTO v_match FROM public.okey_matches AS m WHERE m.id = p_match_id;
  SELECT r.* INTO v_room FROM public.okey_rooms AS r WHERE r.id = v_match.room_id;

  SELECT h.tiles, h.is_opening_done, h.side_draw_tile, h.side_draw_count
    INTO v_tiles, v_is_open, v_side_tile, v_side_count
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
  -- Otomatik hamlede yazılmaz: atılan taşı oyuncu seçmedi.
  --
  -- ELİ AÇIK OLMA ŞARTI KALKTI (kullanıcı isteği, 2026-09-07): ceza artık
  -- masadaki bir pere işlenebilen HER ıskarta için yazılır, atan oyuncunun
  -- eli açık olmasa bile. Kural zaten RULES.md §7'de şartsız yazılıydı;
  -- v_is_open koşulu 20260903000001'de kodda eklenmişti ve pratikte kuralı
  -- öldürüyordu — oyuncuların attığı işlek taşların neredeyse tamamı el
  -- açılmadan ÖNCE atılıyor, dolayısıyla hiç ceza yazılmıyordu.
  --
  -- OKEY ATILDIĞINDA DA YAZILMAZ: okey neredeyse her zaman bir pere
  -- işlenebilir, dolayısıyla okey atan oyuncu hem okey_discard_penalty hem
  -- mistake_discard_penalty yiyip TEK hamle için 202 ödüyordu. Aynı hatanın
  -- iki kez cezalandırılması yerine DAHA ÖZEL kural (okey cezası, RULES.md §8)
  -- geçerlidir.
  IF NOT p_is_auto
     AND NOT public.okey_tile_is_joker(p_tile, v_match.okey_tile) THEN
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

  -- YANDAN ÇEKİLEN TAŞ KULLANILMADIYSA CEZA (RULES.md §4/§7) ----------------
  -- v_tiles = ATMA ÖNCESİ el. Taşın kopya sayısı çekme anındakinden AZALMADIYSA
  -- taş perlere girmemiş / işlenmemiş demektir. Taşı ıskartaya atmak da
  -- "kullanmak" sayılmaz (o durumda sayı bu noktada hâlâ eski değerdedir).
  IF v_side_tile IS NOT NULL AND v_side_count IS NOT NULL THEN
    v_cur_count := 0;
    FOR i IN 0 .. jsonb_array_length(v_tiles) - 1 LOOP
      IF v_tiles -> i = v_side_tile THEN
        v_cur_count := v_cur_count + 1;
      END IF;
    END LOOP;

    IF v_cur_count >= v_side_count THEN
      SELECT COALESCE(s.side_draw_penalty, 101) INTO v_penalty
      FROM public.okey_settings AS s WHERE s.id = true;

      IF COALESCE(v_penalty, 0) > 0 THEN
        UPDATE public.okey_player_hands
        SET penalty_points = penalty_points + v_penalty
        WHERE match_id = p_match_id AND seat_no = p_seat;
      END IF;
    END IF;
  END IF;

  v_tiles := v_tiles - v_idx;

  UPDATE public.okey_player_hands SET tiles = v_tiles, updated_at = now()
  WHERE match_id = p_match_id AND seat_no = p_seat;

  -- OKEY ATMA CEZASI --------------------------------------------------------
  -- Otomatik hamlede yazılmaz (bkz. yukarıdaki gerekçe).
  IF NOT p_is_auto
     AND public.okey_tile_is_joker(p_tile, v_match.okey_tile) THEN
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
  VALUES (
    p_match_id, v_match.hand_no, p_seat,
    CASE WHEN p_is_auto THEN 'timeout_auto_discard' ELSE 'discard' END,
    p_tile
  );

  -- RULES.md §6: eli boşaldıysa ve el açılmışsa oyuncu BİTİRDİ
  IF jsonb_array_length(v_tiles) = 0 AND v_is_open THEN
    PERFORM public.okey_internal_finalize_hand(p_match_id, p_seat, p_tile);
    RETURN;
  END IF;

  UPDATE public.okey_player_hands
  SET opened_this_turn = false,
      side_draw_tile = NULL,
      side_draw_count = NULL
  WHERE match_id = p_match_id AND seat_no = p_seat;

  -- DESTE BİTTİYSE EL BURADA KAPANIR (kullanıcı isteği 2026-09-05:
  -- "taşları bittiğinde son kişi taş attığı gibi oyun bitsin").
  --
  -- Eskiden el ancak SIRADAKİ oyuncu boş desteden çekmeye çalışınca
  -- kapanıyordu (bkz. okey_internal_draw_for_seat). Yani son taş atıldıktan
  -- sonra masa bir tur daha dönüyor, oyuncular elin neden ve ne zaman
  -- bittiğini göremiyordu. Sıra devretmeden kapatmak hem kuralı hem de
  -- masadaki algıyı düzeltir.
  IF v_match.deck_remaining <= 0 THEN
    PERFORM public.okey_internal_finalize_hand(p_match_id, NULL, NULL);
    RETURN;
  END IF;

  v_next_seat := (p_seat + 1) % 4;
  UPDATE public.okey_matches
  SET turn_seat = v_next_seat,
      turn_phase = 'draw',
      turn_token = gen_random_uuid(),
      turn_deadline = now() + make_interval(secs => v_room.turn_seconds)
  WHERE id = p_match_id;
END;
$$;

REVOKE ALL ON FUNCTION public.okey_internal_discard_for_seat(uuid, smallint, jsonb, boolean)
  FROM PUBLIC, anon, authenticated;

NOTIFY pgrst, 'reload schema';
