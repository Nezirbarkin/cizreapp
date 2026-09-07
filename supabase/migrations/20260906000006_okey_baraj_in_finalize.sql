-- =============================================================================
-- 101 Okey — BARAJ ÖDÜLÜNÜN EL SONU HESABINA BAĞLANMASI
-- -----------------------------------------------------------------------------
-- Kuralın kendisi 20260906000005'te (eşikler, ödüller, okey_baraj_kind ve
-- okey_internal_baraj_adjustments). Burada yalnızca el sonu hesabına bağlanır.
--
-- ## Neden gövde CANLIDAN alındı
--
-- okey_internal_finalize_hand uzun bir fonksiyon ve son haftalarda birden çok
-- yerden güncellendi. Gövdeyi eski bir göç dosyasından kopyalamak, o
-- dosyadan SONRA yapılmış her değişikliği sessizce geri almak demekti.
-- Bu yüzden tanım `pg_get_functiondef` ile CANLI şemadan alındı ve üzerine
-- yalnızca baraj bloğu eklendi — geri kalan her satır olduğu gibi duruyor.
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '10s';

CREATE OR REPLACE FUNCTION public.okey_internal_finalize_hand(p_match_id uuid, p_winner_seat smallint, p_last_tile jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_match public.okey_matches%ROWTYPE;
  v_room public.okey_rooms%ROWTYPE;
  v_winner public.okey_player_hands%ROWTYPE;
  v_h public.okey_player_hands%ROWTYPE;
  v_multiplier int := 1;
  v_with_okey boolean := false;
  v_elden boolean := false;
  v_with_pairs boolean := false;
  v_win_label text := NULL;
  v_base int;
  v_hand_scores jsonb := '{}'::jsonb;
  v_new_scores jsonb;
  v_seat int;
  v_max_cum int := 0;
  v_hands_played int;
  v_in_hand_penalty int;
  v_extra int;
  v_has_okey boolean;
  v_baraj record;
  i int;
BEGIN
  SELECT m.* INTO v_match FROM public.okey_matches AS m WHERE m.id = p_match_id;
  SELECT r.* INTO v_room FROM public.okey_rooms AS r
  WHERE r.id = v_match.room_id FOR UPDATE;

  SELECT COALESCE(s.okey_in_hand_penalty, 101) INTO v_in_hand_penalty
  FROM public.okey_settings AS s WHERE s.id = true;

  IF p_winner_seat IS NOT NULL THEN
    SELECT h.* INTO v_winner FROM public.okey_player_hands AS h
    WHERE h.match_id = p_match_id AND h.seat_no = p_winner_seat;

    v_with_okey := p_last_tile IS NOT NULL
                   AND public.okey_tile_is_joker(p_last_tile, v_match.okey_tile);
    v_elden := COALESCE(v_winner.opened_this_turn, false);
    v_with_pairs := COALESCE(v_winner.opened_with_pairs, false);

    v_multiplier := 1;
    IF v_with_okey THEN v_multiplier := v_multiplier * 2; END IF;
    IF v_elden THEN v_multiplier := v_multiplier * 2; END IF;
    IF v_with_pairs THEN v_multiplier := v_multiplier * 2; END IF;

    v_win_label := CASE
      WHEN v_elden AND v_with_okey THEN 'elden_okey'
      WHEN v_elden THEN 'elden'
      WHEN v_with_okey THEN 'okey'
      WHEN v_with_pairs THEN 'cift'
      ELSE 'normal'
    END;
  END IF;

  FOR v_h IN
    SELECT h.* FROM public.okey_player_hands AS h WHERE h.match_id = p_match_id
  LOOP
    v_has_okey := false;
    IF v_h.tiles IS NOT NULL THEN
      FOR i IN 0 .. GREATEST(jsonb_array_length(v_h.tiles) - 1, -1) LOOP
        IF public.okey_tile_is_joker(v_h.tiles -> i, v_match.okey_tile) THEN
          v_has_okey := true;
          EXIT;
        END IF;
      END LOOP;
    END IF;

    v_extra := COALESCE(v_h.penalty_points, 0)
             + CASE WHEN v_has_okey THEN COALESCE(v_in_hand_penalty, 0)
                    ELSE 0 END;

    IF p_winner_seat IS NOT NULL AND v_h.seat_no = p_winner_seat THEN
      v_hand_scores := jsonb_set(
        v_hand_scores, ARRAY[v_h.seat_no::text], to_jsonb(-101 + v_extra));
      CONTINUE;
    END IF;

    IF NOT v_h.is_opening_done THEN
      v_base := CASE WHEN v_h.went_for_pairs THEN 404 ELSE 202 END;
    ELSIF v_h.opened_with_pairs THEN
      v_base := public.okey_hand_penalty_value(v_h.tiles, v_match.okey_tile) * 2;
    ELSE
      v_base := public.okey_hand_penalty_value(v_h.tiles, v_match.okey_tile);
    END IF;

    v_hand_scores := jsonb_set(
      v_hand_scores, ARRAY[v_h.seat_no::text],
      to_jsonb(v_base * v_multiplier + v_extra));
  END LOOP;

  -- BARAJ ÖDÜLÜ (kullanıcı isteği, 2026-09-06) --------------------------------
  --
  -- Açılışta 6+ çift ya da 151+ puan koyan oyuncunun EL CEZASINDAN düşülür.
  -- Skorlar ceza olduğu için bu bir ödüldür; eli bitiren iki katını alır ve
  -- eşli modda çift+per barajı yapan takıma ek ödül verilir
  -- (bkz. okey_internal_baraj_adjustments).
  --
  -- ÇARPANLARDAN SONRA uygulanır: baraj ödülü elin kendi cezasına bağlı
  -- değil, sabit bir indirimdir. Çarpanın içine girseydi okeyle biten bir
  -- elde ödül kendiliğinden dört katına çıkardı.
  FOR v_baraj IN
    SELECT * FROM public.okey_internal_baraj_adjustments(
      p_match_id, p_winner_seat)
  LOOP
    v_hand_scores := jsonb_set(
      v_hand_scores,
      ARRAY[v_baraj.seat_no::text],
      to_jsonb(
        COALESCE((v_hand_scores ->> v_baraj.seat_no::text)::int, 0)
        - v_baraj.bonus
      )
    );
  END LOOP;

  v_new_scores := v_match.scores;
  FOR v_seat IN 0..3 LOOP
    v_new_scores := jsonb_set(
      v_new_scores,
      ARRAY[v_seat::text],
      to_jsonb(
        COALESCE((v_match.scores ->> v_seat::text)::int, 0)
        + COALESCE((v_hand_scores ->> v_seat::text)::int, 0)
      )
    );
    v_max_cum := GREATEST(v_max_cum,
                          COALESCE((v_new_scores ->> v_seat::text)::int, 0));
  END LOOP;

  INSERT INTO public.okey_scores_history
    (match_id, hand_no, seat_no, user_id, points, reason)
  SELECT p_match_id, v_match.hand_no, rp.seat_no, rp.user_id,
         COALESCE((v_hand_scores ->> rp.seat_no::text)::int, 0),
         COALESCE(v_win_label, 'deste_bitti')
  FROM public.okey_room_players AS rp
  WHERE rp.room_id = v_match.room_id AND rp.user_id IS NOT NULL;

  UPDATE public.okey_matches
  SET status = 'finished',
      winner_seat = p_winner_seat,
      win_type = v_win_label,
      scores = v_new_scores,
      finished_at = now()
  WHERE id = p_match_id;

  IF p_winner_seat IS NOT NULL THEN
    INSERT INTO public.okey_moves (match_id, hand_no, seat_no, action)
    VALUES (p_match_id, v_match.hand_no, p_winner_seat, 'declare_win');
  END IF;

  -- EKONOMİ: bu elin istatistikleri (20260901000002'de sehven düşmüştü)
  PERFORM public.okey_internal_record_hand_stats(v_match.room_id, p_winner_seat);

  v_hands_played := v_match.hand_no;

  IF v_max_cum >= v_room.max_score
     OR v_hands_played >= COALESCE(v_room.total_hands, 3) THEN
    UPDATE public.okey_rooms SET status = 'finished', updated_at = now()
    WHERE id = v_room.id;
    -- EKONOMİ: maç bitti — pot kazanan(lar)a dağıtılır
    -- (20260901000002'de sehven düşmüştü; giriş ücretleri tahsil edilip
    --  hiç ödenmiyordu)
    PERFORM public.okey_internal_award_match(v_room.id, v_new_scores);
  ELSE
    PERFORM public.start_okey_hand(v_room.id);
  END IF;
END;
$function$;

NOTIFY pgrst, 'reload schema';
