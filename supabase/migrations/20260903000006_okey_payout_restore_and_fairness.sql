-- =============================================================================
-- 101 Okey Plus — POT ÖDEMESİ GERİ BAĞLANDI + ADİL BERABERLİK + SAHİPSİZ POT
-- -----------------------------------------------------------------------------
-- 1) EKONOMİ HATTI KOPMUŞTU (kritik)
--    20260831000007 finalize'a iki ekonomi kancası bağlamıştı:
--        PERFORM public.okey_internal_record_hand_stats(...);   -- el istatistiği
--        PERFORM public.okey_internal_award_match(...);         -- pot dağıtımı
--    20260901000002 finalize'ı "el sayısı" özelliği için baştan yazarken bu
--    İKİ SATIR DÜŞTÜ ve sonraki sürümler (20260901000009) o gövdeyi taşıdı.
--    Sonuç: giriş ücretleri her maçın ilk elinde tahsil ediliyor
--    (okey_internal_collect_entry_fees) ama maç bitince KİMSEYE ödenmiyordu.
--    Masa ücretsiz olamadığı için (min_entry_fee) bu, HER MAÇTA her oyuncunun
--    puanının sessizce yanması demekti. İstatistikler de hiç yazılmıyordu.
--
-- 2) BERABERLİKTE KAYIRMA
--    Eşli modda `v_team_a <= v_team_b` yüzünden eşitlikte hep 0-2 takımı,
--    eşsiz modda ise ilk bulunan (en küçük) koltuk kazanıyordu. Artık
--    beraberlikte pot BERABERE KALANLAR ARASINDA paylaşılır: eşsizde aynı en
--    düşük skoru yapan tüm koltuklar, eşlide takımlar eşitse dört koltuk da
--    kazanan sayılır (fiilen giriş ücreti iadesi).
--
-- 3) SAHİPSİZ POT
--    Kazanan koltuk(lar)ın tamamı BOT ise v_winner_users boş kalıyor, net pot
--    hiç kimseye gitmiyor ve hiçbir deftere de yazılmıyordu — insandan tahsil
--    edilen puan ortadan kayboluyordu. Artık bu tutar okey_house_revenue'ya
--    'unclaimed_pot' olarak yazılır; raporlarda görünür.
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '10s';

-- -----------------------------------------------------------------------------
-- Yeni gelir kalemi: sahipsiz pot
-- -----------------------------------------------------------------------------
ALTER TABLE public.okey_house_revenue
  DROP CONSTRAINT IF EXISTS okey_house_revenue_source_check;
ALTER TABLE public.okey_house_revenue
  ADD CONSTRAINT okey_house_revenue_source_check
  CHECK (source IN ('room_fee', 'commission', 'unclaimed_pot'));

-- -----------------------------------------------------------------------------
-- okey_internal_award_match — gövde 20260901000011'den taşındı.
-- Farklar: beraberlikte paylaşım + sahipsiz potun deftere yazılması.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.okey_internal_award_match(
  p_room_id uuid,
  p_final_scores jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_room public.okey_rooms%ROWTYPE;
  v_seat int;
  v_score int;
  v_best int;
  v_player record;
  v_winner_seats int[] := ARRAY[]::int[];
  v_winner_users uuid[] := ARRAY[]::uuid[];
  v_team_a int;
  v_team_b int;
  v_human_count int;
  v_pot_gross bigint := 0;
  v_commission bigint := 0;
  v_pot_net bigint := 0;
  v_percent int;
  v_share bigint;
  v_remainder bigint;
  v_uid uuid;
  v_i int;
BEGIN
  SELECT r.* INTO v_room FROM public.okey_rooms AS r WHERE r.id = p_room_id;
  IF v_room.id IS NULL THEN RETURN; END IF;

  -- KAZANAN(LAR) — beraberlikte HEPSİ kazanır, pot aralarında paylaşılır.
  IF v_room.team_mode = 'esli' THEN
    v_team_a := COALESCE((p_final_scores ->> '0')::int, 0)
              + COALESCE((p_final_scores ->> '2')::int, 0);
    v_team_b := COALESCE((p_final_scores ->> '1')::int, 0)
              + COALESCE((p_final_scores ->> '3')::int, 0);
    IF v_team_a = v_team_b THEN
      v_winner_seats := ARRAY[0, 1, 2, 3]; -- berabere: giriş ücreti iadesi
    ELSIF v_team_a < v_team_b THEN
      v_winner_seats := ARRAY[0, 2];
    ELSE
      v_winner_seats := ARRAY[1, 3];
    END IF;
  ELSE
    v_best := NULL;
    FOR v_seat IN 0..3 LOOP
      v_score := COALESCE((p_final_scores ->> v_seat::text)::int, 0);
      IF v_best IS NULL OR v_score < v_best THEN
        v_best := v_score;
      END IF;
    END LOOP;
    FOR v_seat IN 0..3 LOOP
      IF COALESCE((p_final_scores ->> v_seat::text)::int, 0) = v_best THEN
        v_winner_seats := v_winner_seats || v_seat;
      END IF;
    END LOOP;
  END IF;

  FOREACH v_seat IN ARRAY v_winner_seats LOOP
    SELECT rp.user_id INTO v_uid FROM public.okey_room_players AS rp
    WHERE rp.room_id = p_room_id AND rp.seat_no = v_seat;
    IF v_uid IS NOT NULL THEN
      v_winner_users := v_winner_users || v_uid;
    END IF;
  END LOOP;

  -- POT (yalnızca ÜCRETLİ masada ve giriş tahsil edilmişse)
  IF v_room.entry_fee > 0 AND v_room.entry_fee_collected THEN
    SELECT count(*)::int INTO v_human_count FROM public.okey_room_players AS rp
    WHERE rp.room_id = p_room_id AND rp.user_id IS NOT NULL;

    v_pot_gross := v_room.entry_fee::bigint * COALESCE(v_human_count, 0);

    SELECT COALESCE(s.commission_percent, 0) INTO v_percent
    FROM public.okey_settings AS s WHERE s.id = true;

    v_commission := (v_pot_gross * COALESCE(v_percent, 0)) / 100;
    v_pot_net := v_pot_gross - v_commission;

    IF v_commission > 0 THEN
      INSERT INTO public.okey_house_revenue (source, amount, room_id, ref)
      VALUES ('commission', v_commission, p_room_id, p_room_id::text)
      ON CONFLICT DO NOTHING;
    END IF;

    IF array_length(v_winner_users, 1) IS NOT NULL AND v_pot_net > 0 THEN
      v_share := v_pot_net / array_length(v_winner_users, 1);
      v_remainder := v_pot_net - (v_share * array_length(v_winner_users, 1));

      FOR v_i IN 1 .. array_length(v_winner_users, 1) LOOP
        PERFORM public.okey_internal_add_points(
          v_winner_users[v_i],
          v_share + CASE WHEN v_i = 1 THEN v_remainder ELSE 0 END,
          'match_win',
          p_room_id::text || ':' || v_winner_users[v_i]::text
        );
      END LOOP;
    ELSIF v_pot_net > 0 THEN
      -- Kazananların tamamı BOT: pot kimseye gitmiyor. Yok saymak yerine
      -- deftere yazılır ki dolaşımdan çıkan puan raporlarda görünsün.
      INSERT INTO public.okey_house_revenue (source, amount, room_id, ref)
      VALUES ('unclaimed_pot', v_pot_net, p_room_id, p_room_id::text)
      ON CONFLICT DO NOTHING;
    END IF;
  END IF;

  -- İSTATİSTİKLER / SKOR TABLOSU
  FOR v_player IN
    SELECT rp.user_id, rp.seat_no FROM public.okey_room_players AS rp
    WHERE rp.room_id = p_room_id AND rp.user_id IS NOT NULL
  LOOP
    v_score := COALESCE((p_final_scores ->> v_player.seat_no::text)::int, 0);

    INSERT INTO public.okey_stats AS st (
      user_id, matches_played, matches_won, total_points_won, best_match_score
    ) VALUES (
      v_player.user_id, 1,
      CASE WHEN v_player.seat_no = ANY(v_winner_seats) THEN 1 ELSE 0 END,
      CASE WHEN v_player.seat_no = ANY(v_winner_seats)
                AND array_length(v_winner_users, 1) IS NOT NULL
           THEN v_pot_net / array_length(v_winner_users, 1) ELSE 0 END,
      v_score
    )
    ON CONFLICT (user_id) DO UPDATE SET
      matches_played = st.matches_played + 1,
      matches_won = st.matches_won + EXCLUDED.matches_won,
      total_points_won = st.total_points_won + EXCLUDED.total_points_won,
      best_match_score = LEAST(
        COALESCE(st.best_match_score, EXCLUDED.best_match_score),
        EXCLUDED.best_match_score
      ),
      updated_at = now();
  END LOOP;
END;
$$;
REVOKE ALL ON FUNCTION public.okey_internal_award_match(uuid, jsonb)
  FROM PUBLIC, anon, authenticated;

-- -----------------------------------------------------------------------------
-- okey_internal_finalize_hand — gövde 20260901000009'dan taşındı; fark:
-- DÜŞMÜŞ OLAN iki ekonomi kancası geri bağlandı.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.okey_internal_finalize_hand(
  p_match_id uuid,
  p_winner_seat smallint,
  p_last_tile jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
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
$$;
REVOKE ALL ON FUNCTION public.okey_internal_finalize_hand(uuid, smallint, jsonb)
  FROM PUBLIC, anon, authenticated;

NOTIFY pgrst, 'reload schema';
