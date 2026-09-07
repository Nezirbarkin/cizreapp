-- =============================================================================
-- 101 Okey Plus — POT ÖDEMESİ GERİ GELDİ (ücretli masalar için)
-- -----------------------------------------------------------------------------
-- Bahis kaldırıldığında pot dağıtımı da çıkarılmıştı. Masa puanı isteğe bağlı
-- olarak geri geldiği için pot ödemesi de geri geliyor:
--
--   Brüt pot   = giriş ücreti x masadaki İNSAN sayısı
--   Komisyon   = brüt pot x okey_settings.commission_percent / 100  (sistem)
--   Net pot    = kazanan(lar)a
--
-- EŞLİ modda pot kazanan TAKIMIN İKİ ÜYESİ arasında EŞİT paylaşılır.
-- (Bu, geçmişte gerçek bir hataydı: pot tek oyuncuya gidiyor, eş hiçbir şey
--  almıyordu. Bu yüzden takım hesabı burada açıkça yazılıdır.)
--
-- ÜCRETSİZ masada (entry_fee = 0) hiçbir puan hareketi olmaz; yalnızca
-- istatistikler yazılır.
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '10s';

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

  -- KAZANAN(LAR)
  IF v_room.team_mode = 'esli' THEN
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
      -- EŞLİ modda iki kazanan arasında EŞİT paylaşım
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
    END IF;
  END IF;

  -- İSTATİSTİKLER / SKOR TABLOSU (ücretsiz masada da yazılır)
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

NOTIFY pgrst, 'reload schema';
