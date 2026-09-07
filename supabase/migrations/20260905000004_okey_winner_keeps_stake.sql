-- =============================================================================
-- 101 Okey — KAZANANDAN MASA ÜCRETİ ALINMAZ (kullanıcı isteği, 2026-09-05:
-- "okey kazanan kişiden masa ücreti alınmasın, yani puan masa+puan olarak
--  eklensin yeni puana")
-- -----------------------------------------------------------------------------
-- ## Ölçülen sorun
--
-- Masa puanı (giriş puanı × el sayısı) maç BAŞINDA her insan oyuncudan
-- tahsil ediliyor, sonunda pot kazanana veriliyordu. Dört insanın oturduğu
-- masada bu tutar: kazanan −1 masa ödeyip +4 masa alıyor, net +3.
--
-- Ama masaların çoğunda dört insan yok. Üç BOT ile oynanan bir masada
-- pot = masa × 1 (yalnızca insan sayısı kadar toplanır) ve üstünden bir de
-- komisyon kesiliyordu. Yani oyuncu maçı KAZANIYOR ve puanı AZALIYORDU —
-- masa puanı 300, komisyon %10 ise kazanan 270 geri alıp 30 puan kaybediyordu.
-- "Kazandım, puanım düştü" tam olarak buydu.
--
-- ## Yeni kural
--
-- Kazananın kendi masa puanı ONA GERİ DÖNER ve üzerinden komisyon ALINMAZ:
--
--     kazananın yeni puanı = eski puan + MASA PUANI + (kaybedenlerin
--                            potundan düşen pay)
--
-- Komisyon artık yalnızca KAYBEDENLERİN koyduğu tutardan kesilir — kazananın
-- kendi parasından kesilen bir "kazanma vergisi" olmaz.
--
-- ## Defter yine birebir tutar
--
--   toplanan  = masa × insan_sayısı
--   dağıtılan = masa × kazanan_insan_sayısı            (iade)
--             + (masa × kaybeden_insan_sayısı − komisyon)   (pot payı)
--   kasa      = komisyon
--   toplam    = masa × insan_sayısı  ✔
--
-- İade AYRI bir defter sebebiyle ('stake_refund') yazılır; 'match_win' ile
-- birleştirilseydi maç sonu özetinde (okey_match_payouts) "kazandığı pot"
-- olduğundan yüksek görünür, oyuncu masaya girerken ödediği puanı iki kez
-- kazanmış sanırdı.
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '10s';

-- Deftere yeni sebep: kazananın masa puanı iadesi
ALTER TABLE public.okey_point_transactions
  DROP CONSTRAINT IF EXISTS okey_point_transactions_reason_check;
ALTER TABLE public.okey_point_transactions
  ADD CONSTRAINT okey_point_transactions_reason_check
  CHECK (reason IN (
    'signup_bonus', 'hourly_gift', 'ad_reward',
    'entry_fee', 'room_fee', 'match_win', 'stake_refund',
    'admin_grant', 'refund'
  ));

-- -----------------------------------------------------------------------------
-- okey_internal_award_match — gövde 20260905000001'den taşındı. TEK fark:
-- kazananın masa puanı iade edilir ve komisyon yalnızca kaybedenlerin
-- koyduğu tutardan kesilir.
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
  v_winner_human_count int;
  v_loser_pot bigint := 0;
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
  IF v_room.table_stake > 0 AND v_room.entry_fee_collected THEN
    SELECT count(*)::int INTO v_human_count FROM public.okey_room_players AS rp
    WHERE rp.room_id = p_room_id AND rp.user_id IS NOT NULL;

    v_winner_human_count := COALESCE(array_length(v_winner_users, 1), 0);

    -- 1) MASA PUANI İADESİ — kazanandan masa ücreti alınmaz.
    --    Komisyondan ÖNCE ve komisyondan BAĞIMSIZ: bu para hiç dolaşıma
    --    çıkmadı, sadece oyuncunun cebine geri kondu.
    FOR v_i IN 1 .. v_winner_human_count LOOP
      PERFORM public.okey_internal_add_points(
        v_winner_users[v_i],
        v_room.table_stake::bigint,
        'stake_refund',
        p_room_id::text || ':' || v_winner_users[v_i]::text
      );
    END LOOP;

    -- 2) KAYBEDENLERİN POTU — komisyon YALNIZCA buradan kesilir.
    v_loser_pot := v_room.table_stake::bigint
                 * GREATEST(COALESCE(v_human_count, 0) - v_winner_human_count, 0);

    SELECT COALESCE(s.commission_percent, 0) INTO v_percent
    FROM public.okey_settings AS s WHERE s.id = true;

    v_commission := (v_loser_pot * COALESCE(v_percent, 0)) / 100;
    v_pot_net := v_loser_pot - v_commission;

    IF v_commission > 0 THEN
      INSERT INTO public.okey_house_revenue (source, amount, room_id, ref)
      VALUES ('commission', v_commission, p_room_id, p_room_id::text)
      ON CONFLICT DO NOTHING;
    END IF;

    IF v_winner_human_count > 0 AND v_pot_net > 0 THEN
      v_share := v_pot_net / v_winner_human_count;
      v_remainder := v_pot_net - (v_share * v_winner_human_count);

      FOR v_i IN 1 .. v_winner_human_count LOOP
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
                AND COALESCE(v_winner_human_count, 0) > 0
           THEN v_pot_net / v_winner_human_count ELSE 0 END,
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
-- okey_match_payouts — maç sonu özeti İADEYİ de saysın
--
-- Özet artık dört sayı gösteriyor: ödenen masa puanı, İADE, kazanılan pot ve
-- net. İade eklendikten sonra ÖDENEN sütunu kazanan için 0 olur — masa
-- ücreti ondan alınmadı. Aksi halde kart "300 ödedin, 180 kazandın" der ve
-- oyuncu kazandığı maçta zarar ettiğini sanırdı (oysa cüzdanı artmıştır).
--
-- İADE AYRI BİR SÜTUN, çünkü "0 ödedim" ile "hiç ücret yoktu" aynı şey değil:
-- ücretsiz masada da ödenen 0'dır. Kart bu ikisini ancak iadenin kendisini
-- görerek ayırt edebilir ve "masa puanın geri verildi" diyebilir.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.okey_match_payouts(uuid);

CREATE FUNCTION public.okey_match_payouts(p_room_id uuid)
RETURNS TABLE(
  seat_no smallint,
  user_id uuid,
  stake bigint,
  won bigint,
  net bigint,
  refund bigint
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid CONSTANT uuid := (SELECT auth.uid());
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'APP:auth_required' USING ERRCODE = '42501';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.okey_room_players AS rp
    WHERE rp.room_id = p_room_id AND rp.user_id = v_uid
  ) THEN
    RAISE EXCEPTION 'APP:not_seated' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT
    rp.seat_no,
    rp.user_id,
    -- ÖDENEN = tahsilat − iade. Kazanan için sıfırlanır.
    COALESCE((
      SELECT -SUM(t.amount) FROM public.okey_point_transactions AS t
      WHERE t.reason IN ('entry_fee', 'stake_refund')
        AND t.ref = p_room_id::text || ':' || rp.user_id::text
    ), 0)::bigint,
    COALESCE((
      SELECT SUM(t.amount) FROM public.okey_point_transactions AS t
      WHERE t.reason = 'match_win'
        AND t.ref = p_room_id::text || ':' || rp.user_id::text
    ), 0)::bigint,
    COALESCE((
      SELECT SUM(t.amount) FROM public.okey_point_transactions AS t
      WHERE t.reason IN ('entry_fee', 'stake_refund', 'match_win')
        AND t.ref = p_room_id::text || ':' || rp.user_id::text
    ), 0)::bigint,
    -- İADE: kazanandan alınmayan masa puanı.
    COALESCE((
      SELECT SUM(t.amount) FROM public.okey_point_transactions AS t
      WHERE t.reason = 'stake_refund'
        AND t.ref = p_room_id::text || ':' || rp.user_id::text
    ), 0)::bigint
  FROM public.okey_room_players AS rp
  WHERE rp.room_id = p_room_id
  ORDER BY rp.seat_no;
END;
$$;
REVOKE ALL ON FUNCTION public.okey_match_payouts(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_match_payouts(uuid) TO authenticated;

COMMENT ON FUNCTION public.okey_match_payouts(uuid) IS
  'Maç sonu ödeme özeti: koltuk başına GERÇEKTEN ödenen masa puanı (kazanana iade edildiyse 0), İADE tutarı, kazanılan pot payı ve net. Yalnızca o odada oturan kullanıcı çağırabilir.';

NOTIFY pgrst, 'reload schema';
