-- =============================================================================
-- 101 Okey Plus — Sistem kazancı: oda kurma ücreti + pot komisyonu
-- -----------------------------------------------------------------------------
--   1) okey_settings.room_creation_fee  : masa açmanın sabit ücreti
--   2) okey_settings.commission_percent : pottan kesilen yüzde
--   Her ikisi de ADMIN PANELİNDEN ayarlanabilir.
--
--   Kesilen puanlar oyunculardan ÇIKAR ve dolaşımdan kalkar (enflasyon freni);
--   raporlanabilmesi için okey_house_revenue tablosuna işlenir.
--
--   ÖRNEK (4 gerçek oyuncu, 100 giriş ücreti, %10 komisyon):
--     Brüt pot   = 100 x 4 = 400
--     Komisyon   = 40   -> sistem kazancı
--     Net pot    = 360  -> kazanan(lar)a
--     Kazananın net kârı = 360 - 100 (kendi ücreti) = +260
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '5s';

-- -----------------------------------------------------------------------------
-- Ayarlar
-- -----------------------------------------------------------------------------
ALTER TABLE public.okey_settings
  ADD COLUMN IF NOT EXISTS room_creation_fee int NOT NULL DEFAULT 50,
  ADD COLUMN IF NOT EXISTS commission_percent int NOT NULL DEFAULT 10;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'okey_settings_commission_check'
  ) THEN
    ALTER TABLE public.okey_settings
      ADD CONSTRAINT okey_settings_commission_check
      CHECK (commission_percent >= 0 AND commission_percent <= 50);
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'okey_settings_room_fee_check'
  ) THEN
    ALTER TABLE public.okey_settings
      ADD CONSTRAINT okey_settings_room_fee_check
      CHECK (room_creation_fee >= 0);
  END IF;
END;
$$;

COMMENT ON COLUMN public.okey_settings.room_creation_fee IS
  'Masa açan oyuncudan alınan sabit ücret (sistem kazancı).';
COMMENT ON COLUMN public.okey_settings.commission_percent IS
  'Maç sonunda pottan kesilen yüzde (sistem kazancı). En fazla %50.';

-- Ledger'a yeni sebep: oda kurma ücreti
ALTER TABLE public.okey_point_transactions
  DROP CONSTRAINT IF EXISTS okey_point_transactions_reason_check;
ALTER TABLE public.okey_point_transactions
  ADD CONSTRAINT okey_point_transactions_reason_check
  CHECK (reason IN (
    'signup_bonus', 'hourly_gift', 'ad_reward',
    'entry_fee', 'room_fee', 'match_win', 'admin_grant', 'refund'
  ));

-- -----------------------------------------------------------------------------
-- Sistem kazancı defteri
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.okey_house_revenue (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  source text NOT NULL CHECK (source IN ('room_fee', 'commission')),
  amount bigint NOT NULL CHECK (amount > 0),
  room_id uuid,
  user_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  ref text,
  created_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.okey_house_revenue IS
  'Okey sistem kazancı: oda kurma ücretleri ve pot komisyonları. Raporlama içindir; bu puanlar dolaşımdan çıkmıştır.';

CREATE UNIQUE INDEX IF NOT EXISTS uq_okey_house_revenue_ref
  ON public.okey_house_revenue (source, ref) WHERE ref IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_okey_house_revenue_created
  ON public.okey_house_revenue (created_at DESC);

ALTER TABLE public.okey_house_revenue ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS okey_house_revenue_admin ON public.okey_house_revenue;
CREATE POLICY okey_house_revenue_admin ON public.okey_house_revenue
  FOR SELECT TO authenticated USING (public.is_admin());

REVOKE INSERT, UPDATE, DELETE ON public.okey_house_revenue FROM authenticated;

-- -----------------------------------------------------------------------------
-- create_okey_room: ODA KURMA ÜCRETİ alınır
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.create_okey_room(boolean, text, text, text, int);

CREATE FUNCTION public.create_okey_room(
  p_is_private boolean DEFAULT false,
  p_game_mode text DEFAULT 'katlamasiz',
  p_team_mode text DEFAULT 'essiz',
  p_assist_mode text DEFAULT 'yardimli',
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
  IF COALESCE(p_entry_fee, 0) < 0 THEN
    RAISE EXCEPTION 'APP:invalid_entry_fee' USING ERRCODE = '22023';
  END IF;

  SELECT s.* INTO v_settings FROM public.okey_settings AS s WHERE s.id = true;
  v_room_fee := COALESCE(v_settings.room_creation_fee, 0);

  -- Kurucu hem oda ücretini hem kendi giriş ücretini karşılayabilmeli
  v_needed := v_room_fee::bigint + COALESCE(p_entry_fee, 0)::bigint;
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
    game_mode, team_mode, assist_mode, entry_fee
  ) VALUES (
    v_uid, p_is_private, v_join_code,
    COALESCE(v_settings.default_max_score, 101),
    COALESCE(v_settings.default_turn_seconds, 20),
    p_game_mode, p_team_mode, p_assist_mode, COALESCE(p_entry_fee, 0)
  ) RETURNING * INTO v_room;

  -- SİSTEM KAZANCI: oda kurma ücreti
  IF v_room_fee > 0 THEN
    PERFORM public.okey_internal_add_points(
      v_uid, -v_room_fee, 'room_fee', v_room.id::text
    );
    INSERT INTO public.okey_house_revenue (source, amount, room_id, user_id, ref)
    VALUES ('room_fee', v_room_fee, v_room.id, v_uid, v_room.id::text)
    ON CONFLICT DO NOTHING;
  END IF;

  FOR v_seat IN 0..3 LOOP
    INSERT INTO public.okey_room_players (room_id, seat_no, user_id, joined_at, is_ready)
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
REVOKE ALL ON FUNCTION public.create_okey_room(boolean, text, text, text, int)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_okey_room(boolean, text, text, text, int)
  TO authenticated;

-- -----------------------------------------------------------------------------
-- okey_internal_award_match: POTTAN KOMİSYON kesilir, kalanı kazanan(lar)a
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
  v_winner_seat int;
  v_human_count int;
  v_pot_gross bigint;
  v_commission bigint;
  v_pot_net bigint;
  v_percent int;
  v_player record;
  v_winner_seats int[] := ARRAY[]::int[];
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
      v_winner_scores := v_winner_scores
        || COALESCE((p_final_scores ->> v_seat::text)::int, 0);
    END IF;
  END LOOP;

  -- POT + KOMİSYON
  SELECT count(*)::int INTO v_human_count FROM public.okey_room_players AS rp
  WHERE rp.room_id = p_room_id AND rp.user_id IS NOT NULL;

  v_pot_gross := v_room.entry_fee::bigint * v_human_count;

  SELECT COALESCE(s.commission_percent, 0) INTO v_percent
  FROM public.okey_settings AS s WHERE s.id = true;

  v_commission := (v_pot_gross * COALESCE(v_percent, 0)) / 100;
  v_pot_net := v_pot_gross - v_commission;

  IF v_pot_gross > 0 AND v_room.entry_fee_collected THEN
    -- SİSTEM KAZANCI: komisyon kaydedilir (puanlar dolaşımdan çıkar)
    IF v_commission > 0 THEN
      INSERT INTO public.okey_house_revenue (source, amount, room_id, ref)
      VALUES ('commission', v_commission, p_room_id, p_room_id::text)
      ON CONFLICT DO NOTHING;
    END IF;

    IF array_length(v_winner_users, 1) IS NOT NULL AND v_pot_net > 0 THEN
      v_share := v_pot_net / array_length(v_winner_users, 1);
      v_remainder := v_pot_net - (v_share * array_length(v_winner_users, 1));

      FOR v_i IN 1 .. array_length(v_winner_users, 1) LOOP
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
            p_room_id::text || ':' || v_winner_users[v_i]::text
          );
        END;
      END LOOP;
    END IF;
  END IF;

  -- İSTATİSTİKLER
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
-- Admin: ayarlar (oda ücreti + komisyon dahil) ve kazanç özeti
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.admin_okey_update_settings(int, int);
DROP FUNCTION IF EXISTS public.admin_okey_update_settings(int, int, int, int, int, int, int);

CREATE FUNCTION public.admin_okey_update_settings(
  p_max_score int,
  p_turn_seconds int,
  p_room_creation_fee int DEFAULT NULL,
  p_commission_percent int DEFAULT NULL,
  p_hourly_gift_points int DEFAULT NULL,
  p_ad_reward_points int DEFAULT NULL,
  p_starting_points int DEFAULT NULL
)
RETURNS public.okey_settings
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_row public.okey_settings%ROWTYPE;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'APP:forbidden' USING ERRCODE = '42501';
  END IF;
  IF p_max_score <= 0 OR p_turn_seconds <= 0 THEN
    RAISE EXCEPTION 'APP:invalid_value' USING ERRCODE = '22023';
  END IF;
  IF p_commission_percent IS NOT NULL
     AND (p_commission_percent < 0 OR p_commission_percent > 50) THEN
    RAISE EXCEPTION 'APP:invalid_commission | 0-50 arasi olmali'
      USING ERRCODE = '22023';
  END IF;
  IF p_room_creation_fee IS NOT NULL AND p_room_creation_fee < 0 THEN
    RAISE EXCEPTION 'APP:invalid_value' USING ERRCODE = '22023';
  END IF;

  UPDATE public.okey_settings
  SET default_max_score = p_max_score,
      default_turn_seconds = p_turn_seconds,
      room_creation_fee = COALESCE(p_room_creation_fee, room_creation_fee),
      commission_percent = COALESCE(p_commission_percent, commission_percent),
      hourly_gift_points = COALESCE(p_hourly_gift_points, hourly_gift_points),
      ad_reward_points = COALESCE(p_ad_reward_points, ad_reward_points),
      starting_points = COALESCE(p_starting_points, starting_points),
      updated_by = (SELECT auth.uid())
  WHERE id = true
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_okey_update_settings(int, int, int, int, int, int, int)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_okey_update_settings(int, int, int, int, int, int, int)
  TO authenticated;

-- Sistem kazancı özeti
DROP FUNCTION IF EXISTS public.admin_okey_revenue_summary();

CREATE FUNCTION public.admin_okey_revenue_summary()
RETURNS TABLE(
  total_revenue bigint,
  room_fee_total bigint,
  commission_total bigint,
  today_revenue bigint,
  total_points_in_circulation bigint
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT
    COALESCE((SELECT sum(amount) FROM public.okey_house_revenue), 0),
    COALESCE((SELECT sum(amount) FROM public.okey_house_revenue WHERE source = 'room_fee'), 0),
    COALESCE((SELECT sum(amount) FROM public.okey_house_revenue WHERE source = 'commission'), 0),
    COALESCE((SELECT sum(amount) FROM public.okey_house_revenue
              WHERE created_at >= date_trunc('day', now())), 0),
    COALESCE((SELECT sum(points) FROM public.okey_wallets), 0)
  WHERE public.is_admin();
$$;
REVOKE ALL ON FUNCTION public.admin_okey_revenue_summary() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_okey_revenue_summary() TO authenticated;

NOTIFY pgrst, 'reload schema';
