-- =============================================================================
-- 101 Okey Plus — EŞLİ modda pot dağıtımı düzeltmesi
-- -----------------------------------------------------------------------------
-- HATA: okey_internal_award_match kazananı her zaman TEK KOLTUK olarak
-- belirliyordu. Eşli (2v2) modda bu yanlış: kazanan TAKIMDIR ve pot iki eş
-- arasında paylaşılmalıdır. Eski hâlinde kazanan takımın bir üyesi potun
-- tamamını alıyor, eşi hiçbir şey almıyordu.
--
-- DÜZELTİLMİŞ DAVRANIŞ
--   Eşsiz (tekli): kazanan = kümülatif cezası EN DÜŞÜK oyuncu, potun tamamını alır.
--   Eşli (2v2)   : takımlar karşılıklı oturanlardır (0+2 ve 1+3).
--                  Kazanan takım = iki üyesinin TOPLAM cezası daha düşük olan.
--                  Pot iki eş arasında EŞİT paylaşılır; tek sayı artarsa
--                  kalan, bireysel cezası daha düşük olan eşe verilir.
--                  Takımdaki koltuk botsa (cüzdanı yok), payı insan eşe geçer.
--   Her iki modda da kazananlar `matches_won` alır.
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '5s';

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
  v_winner_seat int;
  v_human_count int;
  v_pot bigint;
  v_player record;

  -- Kazanan koltuklar (eşsizde 1, eşlide 2 koltuk)
  v_winner_seats int[] := ARRAY[]::int[];
  -- Bu koltuklardaki gerçek kullanıcılar (bot koltukları buraya girmez)
  v_winner_users uuid[] := ARRAY[]::uuid[];
  v_winner_scores int[] := ARRAY[]::int[];

  v_team_a int;
  v_team_b int;
  v_share bigint;
  v_remainder bigint;
  v_i int;
  v_uid uuid;
BEGIN
  SELECT r.* INTO v_room FROM public.okey_rooms AS r WHERE r.id = p_room_id;
  IF v_room.id IS NULL THEN RETURN; END IF;

  -- ---------------------------------------------------------------------
  -- KAZANAN(LAR)IN BELİRLENMESİ
  -- ---------------------------------------------------------------------
  IF v_room.team_mode = 'esli' THEN
    -- Takım A: 0 + 2, Takım B: 1 + 3
    v_team_a := COALESCE((p_final_scores ->> '0')::int, 0)
              + COALESCE((p_final_scores ->> '2')::int, 0);
    v_team_b := COALESCE((p_final_scores ->> '1')::int, 0)
              + COALESCE((p_final_scores ->> '3')::int, 0);

    IF v_team_a <= v_team_b THEN
      v_winner_seats := ARRAY[0, 2];
    ELSE
      v_winner_seats := ARRAY[1, 3];
    END IF;
  ELSE
    -- Eşsiz: cezası en düşük tek oyuncu
    v_best := NULL;
    FOR v_seat IN 0..3 LOOP
      v_score := COALESCE((p_final_scores ->> v_seat::text)::int, 0);
      IF v_best IS NULL OR v_score < v_best THEN
        v_best := v_score;
        v_winner_seat := v_seat;
      END IF;
    END LOOP;
    v_winner_seats := ARRAY[v_winner_seat];
  END IF;

  -- Kazanan koltuklardaki GERÇEK kullanıcılar (botlar cüzdansızdır)
  FOREACH v_seat IN ARRAY v_winner_seats LOOP
    SELECT rp.user_id INTO v_uid FROM public.okey_room_players AS rp
    WHERE rp.room_id = p_room_id AND rp.seat_no = v_seat;
    IF v_uid IS NOT NULL THEN
      v_winner_users := v_winner_users || v_uid;
      v_winner_scores := v_winner_scores
        || COALESCE((p_final_scores ->> v_seat::text)::int, 0);
    END IF;
  END LOOP;

  -- ---------------------------------------------------------------------
  -- POT DAĞITIMI
  -- ---------------------------------------------------------------------
  SELECT count(*)::int INTO v_human_count FROM public.okey_room_players AS rp
  WHERE rp.room_id = p_room_id AND rp.user_id IS NOT NULL;

  v_pot := v_room.entry_fee::bigint * v_human_count;

  IF v_pot > 0
     AND v_room.entry_fee_collected
     AND array_length(v_winner_users, 1) IS NOT NULL THEN

    v_share := v_pot / array_length(v_winner_users, 1);
    v_remainder := v_pot - (v_share * array_length(v_winner_users, 1));

    FOR v_i IN 1 .. array_length(v_winner_users, 1) LOOP
      -- Kalan (tek sayı artığı) bireysel cezası daha düşük olan eşe gider
      DECLARE
        v_extra bigint := 0;
        v_is_best boolean := true;
        v_j int;
      BEGIN
        IF v_remainder > 0 THEN
          FOR v_j IN 1 .. array_length(v_winner_scores, 1) LOOP
            IF v_winner_scores[v_j] < v_winner_scores[v_i] THEN
              v_is_best := false;
              EXIT;
            END IF;
          END LOOP;
          IF v_is_best THEN
            v_extra := v_remainder;
            v_remainder := 0;
          END IF;
        END IF;

        PERFORM public.okey_internal_add_points(
          v_winner_users[v_i],
          v_share + v_extra,
          'match_win',
          -- Her kazanan için AYRI referans: aynı maçta iki eşe ödeme
          -- yapılabilmeli ama her biri yalnızca BİR KEZ ödenmeli.
          p_room_id::text || ':' || v_winner_users[v_i]::text
        );
      END;
    END LOOP;
  END IF;

  -- ---------------------------------------------------------------------
  -- İSTATİSTİKLER
  -- ---------------------------------------------------------------------
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
           THEN v_pot / array_length(v_winner_users, 1) ELSE 0 END,
      v_score
    )
    ON CONFLICT (user_id) DO UPDATE SET
      matches_played = st.matches_played + 1,
      matches_won = st.matches_won + EXCLUDED.matches_won,
      total_points_won = st.total_points_won + EXCLUDED.total_points_won,
      best_match_score = LEAST(COALESCE(st.best_match_score, EXCLUDED.best_match_score),
                               EXCLUDED.best_match_score),
      updated_at = now();
  END LOOP;
END;
$$;
REVOKE ALL ON FUNCTION public.okey_internal_award_match(uuid, jsonb)
  FROM PUBLIC, anon, authenticated;

NOTIFY pgrst, 'reload schema';
