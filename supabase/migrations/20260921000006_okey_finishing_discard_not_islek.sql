-- =============================================================================
-- 101 Okey — ELİ BİTİREN SON ATIŞ "İŞLEK TAŞ" SAYILMAZ
-- -----------------------------------------------------------------------------
-- Kullanıcı isteği (2026-09-21): "el bittiğinde yani kişi eli bitirse son taş
-- işlekte işlek sayılmasın taş attığında, çünkü mecburdur ve takozda taş yok."
-- ("Takoz" bu projede ıstaka demek.)
--
-- ## Kural
--
-- Elde TEK taş kalmış ve el açıksa, o taşı atmak eli bitirir. Bu atış masadaki
-- bir pere işlenebilir olsa bile "işlek taş atma" cezası (mistake_discard_penalty)
-- YAZILMAZ. Sebep: RULES.md §6'ya göre bitiş yalnızca atmayla olur, açma ve
-- işleme eli boşaltamaz; oyuncunun o taşla yapabileceği başka hamle yoktur.
--
-- Diğer durumlar DEĞİŞMEDİ:
--   * bitmeyen atışta işlek taş hâlâ +101
--   * OKEY atmak (bitiş atışı dahil) hâlâ okey atma cezası
--   * yandan çekilen taşı kullanmamak hâlâ side_draw_penalty
--   * otomatik (süre dolumu / kopmuş oyuncu) atışta işlek cezası zaten yazılmaz
--   * DESTE BİTİŞİNİ kapatan atış (kazanan yok) hâlâ işlek cezasına tabidir:
--     orada oyuncunun elinde başka taşlar var, seçim onundur.
--
-- ## Neden gövde CANLIDAN alındı
--
-- okey_internal_discard_for_seat son haftalarda birden çok göçle değişti.
-- Gövdeyi eski bir dosyadan kopyalamak, sonraki her değişikliği sessizce geri
-- almak demekti. Tanım pg_get_functiondef ile CANLI şemadan alındı; üzerine
-- yalnızca v_finishes eklendi.
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '10s';

CREATE OR REPLACE FUNCTION public.okey_internal_discard_for_seat(p_match_id uuid, p_seat smallint, p_tile jsonb, p_is_auto boolean DEFAULT false)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
  v_finishes boolean;
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

  -- ELİ BİTİREN ATIŞ İŞLEK SAYILMAZ (kullanıcı isteği, 2026-09-21) ------------
  --
  -- "El bittiğinde son taş işlek olsa bile işlek sayılmasın: atmak MECBUR ve
  -- takozda (ıstakada) başka taş yok."
  --
  -- Elde TEK taş kalmış ve el AÇIKSA bu atış eli bitirir (aşağıdaki finalize
  -- koşuluyla aynı). RULES.md §6 bitişi YALNIZCA atmayla tanımlar: açma ve
  -- işleme eli boşaltamaz (APP:must_keep_discard_tile), dolayısıyla o son taşı
  -- pere İŞLEMEK oyuncuya hiçbir zaman açık bir yol değildir. Yani atış bir
  -- SEÇİM değil ZORUNLULUKTUR; taşın masada işlenebilir olması onu "hata"
  -- yapmaz. Eskiden bu atış +101 yazıyor ve ceza kazananın skoruna da
  -- ekleniyordu (-101 + 101): eli bitirmek fiilen bedavaya iniyordu.
  --
  -- YALNIZCA İŞLEK CEZASI muafiyet alır. Okey atma cezası (aşağıda) ve yandan
  -- çekilen taşın kullanılmaması cezası bu atışta da geçerlidir.
  v_finishes := COALESCE(v_is_open, false) AND jsonb_array_length(v_tiles) = 1;

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
     AND NOT v_finishes
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

  -- RULES.md §6: eli boşaldıysa ve el açılmışsa oyuncu BİTİRDİ. (v_finishes ile
  -- AYNI karar: atma öncesi tek taş + açık el = atma sonrası boş el + açık el.)
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
$function$;

NOTIFY pgrst, 'reload schema';
