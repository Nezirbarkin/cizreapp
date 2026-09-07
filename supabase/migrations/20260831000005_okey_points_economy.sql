-- =============================================================================
-- 101 Okey Plus — Puan ekonomisi (SADECE OKEY'E ÖZEL)
-- -----------------------------------------------------------------------------
-- Bu puanlar uygulamanın mevcut ödül/bakiye sistemlerinden TAMAMEN AYRIDIR;
-- yalnızca Okey masalarında kullanılır ve başka hiçbir yere aktarılmaz.
--
-- İçerik:
--   okey_wallets              : oyuncunun Okey puanı
--   okey_point_transactions   : her hareketin defteri (idempotent)
--   okey_stats                : maç/el istatistikleri ve skor (sıralama için)
--   Saatlik hediye            : saatte bir 100 puan ("Hediye Al")
--   Reklam ödülü              : mevcut SSV-doğrulamalı reklam oturumuna bağlı
--   Admin puan ekleme
--   Masa giriş ücreti + kazanana pot
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '5s';

-- -----------------------------------------------------------------------------
-- Ayarlar
-- -----------------------------------------------------------------------------
ALTER TABLE public.okey_settings
  ADD COLUMN IF NOT EXISTS starting_points int NOT NULL DEFAULT 1000,
  ADD COLUMN IF NOT EXISTS hourly_gift_points int NOT NULL DEFAULT 100,
  ADD COLUMN IF NOT EXISTS ad_reward_points int NOT NULL DEFAULT 250;

COMMENT ON COLUMN public.okey_settings.hourly_gift_points IS
  'Saatlik "Hediye Al" ile verilen Okey puanı (varsayılan 100).';

-- Masa giriş ücreti (bahis)
ALTER TABLE public.okey_rooms
  ADD COLUMN IF NOT EXISTS entry_fee int NOT NULL DEFAULT 0
  CHECK (entry_fee >= 0);

COMMENT ON COLUMN public.okey_rooms.entry_fee IS
  'Masaya girerken oyuncu başına düşülen Okey puanı. Maç sonunda toplam pot kazanana verilir.';

-- -----------------------------------------------------------------------------
-- Cüzdan
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.okey_wallets (
  user_id uuid PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  points bigint NOT NULL DEFAULT 0 CHECK (points >= 0),
  last_hourly_claim_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.okey_wallets IS
  'Yalnız Okey oyununda kullanılan puan cüzdanı. Uygulamanın diğer puan/bakiye sistemlerinden bağımsızdır.';

ALTER TABLE public.okey_wallets ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS okey_wallets_select_own ON public.okey_wallets;
CREATE POLICY okey_wallets_select_own ON public.okey_wallets
  FOR SELECT TO authenticated
  USING (user_id = (SELECT auth.uid()) OR public.is_admin());

REVOKE INSERT, UPDATE, DELETE ON public.okey_wallets FROM authenticated;

-- -----------------------------------------------------------------------------
-- Defter (ledger)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.okey_point_transactions (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  amount bigint NOT NULL,
  reason text NOT NULL CHECK (reason IN (
    'signup_bonus', 'hourly_gift', 'ad_reward',
    'entry_fee', 'match_win', 'admin_grant', 'refund'
  )),
  ref text,
  balance_after bigint NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.okey_point_transactions IS
  'Okey puan hareketlerinin defteri. (reason, ref) benzersizdir — aynı reklam oturumu veya aynı maç için iki kez puan verilemez.';

-- İdempotans: aynı sebep+referans ikinci kez işlenemez
CREATE UNIQUE INDEX IF NOT EXISTS uq_okey_point_tx_reason_ref
  ON public.okey_point_transactions (reason, ref)
  WHERE ref IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_okey_point_tx_user
  ON public.okey_point_transactions (user_id, created_at DESC);

ALTER TABLE public.okey_point_transactions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS okey_point_tx_select_own ON public.okey_point_transactions;
CREATE POLICY okey_point_tx_select_own ON public.okey_point_transactions
  FOR SELECT TO authenticated
  USING (user_id = (SELECT auth.uid()) OR public.is_admin());

REVOKE INSERT, UPDATE, DELETE ON public.okey_point_transactions FROM authenticated;

-- -----------------------------------------------------------------------------
-- İstatistik / skor
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.okey_stats (
  user_id uuid PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  matches_played int NOT NULL DEFAULT 0,
  matches_won int NOT NULL DEFAULT 0,
  hands_played int NOT NULL DEFAULT 0,
  hands_won int NOT NULL DEFAULT 0,
  total_points_won bigint NOT NULL DEFAULT 0,
  best_match_score int,
  updated_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON COLUMN public.okey_stats.best_match_score IS
  'En iyi (EN DÜŞÜK) maç sonu ceza puanı — 101 Okey''de düşük skor iyidir.';

ALTER TABLE public.okey_stats ENABLE ROW LEVEL SECURITY;

-- Skor tablosu herkese açık (sıralama için)
DROP POLICY IF EXISTS okey_stats_select ON public.okey_stats;
CREATE POLICY okey_stats_select ON public.okey_stats
  FOR SELECT TO authenticated USING (true);

REVOKE INSERT, UPDATE, DELETE ON public.okey_stats FROM authenticated;

-- =============================================================================
-- İÇ YARDIMCILAR
-- =============================================================================

-- Cüzdanı yoksa oluşturur (başlangıç bonusuyla) ve satırı kilitleyip döner.
CREATE OR REPLACE FUNCTION public.okey_internal_ensure_wallet(p_user_id uuid)
RETURNS public.okey_wallets
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_wallet public.okey_wallets%ROWTYPE;
  v_start int;
BEGIN
  SELECT w.* INTO v_wallet FROM public.okey_wallets AS w
  WHERE w.user_id = p_user_id FOR UPDATE;

  IF v_wallet.user_id IS NOT NULL THEN
    RETURN v_wallet;
  END IF;

  SELECT COALESCE(s.starting_points, 1000) INTO v_start
  FROM public.okey_settings AS s WHERE s.id = true;

  INSERT INTO public.okey_wallets (user_id, points)
  VALUES (p_user_id, COALESCE(v_start, 1000))
  ON CONFLICT (user_id) DO NOTHING;

  SELECT w.* INTO v_wallet FROM public.okey_wallets AS w
  WHERE w.user_id = p_user_id FOR UPDATE;

  IF COALESCE(v_start, 1000) > 0 THEN
    INSERT INTO public.okey_point_transactions
      (user_id, amount, reason, ref, balance_after)
    VALUES (p_user_id, COALESCE(v_start, 1000), 'signup_bonus',
            p_user_id::text, v_wallet.points)
    ON CONFLICT DO NOTHING;
  END IF;

  RETURN v_wallet;
END;
$$;
REVOKE ALL ON FUNCTION public.okey_internal_ensure_wallet(uuid)
  FROM PUBLIC, anon, authenticated;

-- Puan ekler/çıkarır ve deftere yazar. [p_ref] verilirse idempotenttir:
-- aynı (reason, ref) ikinci kez işlenirse hiçbir şey yapmaz.
-- Bakiye yetersizse APP:insufficient_points fırlatır.
CREATE OR REPLACE FUNCTION public.okey_internal_add_points(
  p_user_id uuid,
  p_amount bigint,
  p_reason text,
  p_ref text DEFAULT NULL
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_wallet public.okey_wallets%ROWTYPE;
  v_new bigint;
BEGIN
  IF p_user_id IS NULL THEN RETURN NULL; END IF;

  -- İdempotans kontrolü
  IF p_ref IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.okey_point_transactions AS t
    WHERE t.reason = p_reason AND t.ref = p_ref
  ) THEN
    SELECT w.points INTO v_new FROM public.okey_wallets AS w
    WHERE w.user_id = p_user_id;
    RETURN v_new;
  END IF;

  v_wallet := public.okey_internal_ensure_wallet(p_user_id);
  v_new := v_wallet.points + p_amount;

  IF v_new < 0 THEN
    RAISE EXCEPTION 'APP:insufficient_points | mevcut: %, gerekli: %',
      v_wallet.points, -p_amount USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.okey_wallets
  SET points = v_new, updated_at = now()
  WHERE user_id = p_user_id;

  INSERT INTO public.okey_point_transactions
    (user_id, amount, reason, ref, balance_after)
  VALUES (p_user_id, p_amount, p_reason, p_ref, v_new);

  RETURN v_new;
END;
$$;
REVOKE ALL ON FUNCTION public.okey_internal_add_points(uuid, bigint, text, text)
  FROM PUBLIC, anon, authenticated;

-- =============================================================================
-- İSTEMCİ RPC'LERİ
-- =============================================================================

-- -----------------------------------------------------------------------------
-- okey_get_wallet: puan + saatlik hediye durumu
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.okey_get_wallet();

CREATE FUNCTION public.okey_get_wallet()
RETURNS TABLE(
  points bigint,
  last_hourly_claim_at timestamptz,
  can_claim_hourly boolean,
  seconds_until_next_gift int,
  hourly_gift_points int,
  ad_reward_points int
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid CONSTANT uuid := (SELECT auth.uid());
  v_wallet public.okey_wallets%ROWTYPE;
  v_settings public.okey_settings%ROWTYPE;
  v_next timestamptz;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'APP:auth_required' USING ERRCODE = '42501';
  END IF;

  v_wallet := public.okey_internal_ensure_wallet(v_uid);
  SELECT s.* INTO v_settings FROM public.okey_settings AS s WHERE s.id = true;

  v_next := COALESCE(v_wallet.last_hourly_claim_at, 'epoch'::timestamptz)
            + interval '1 hour';

  RETURN QUERY SELECT
    v_wallet.points,
    v_wallet.last_hourly_claim_at,
    now() >= v_next,
    GREATEST(0, EXTRACT(EPOCH FROM (v_next - now()))::int),
    COALESCE(v_settings.hourly_gift_points, 100),
    COALESCE(v_settings.ad_reward_points, 250);
END;
$$;
REVOKE ALL ON FUNCTION public.okey_get_wallet() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_get_wallet() TO authenticated;

-- -----------------------------------------------------------------------------
-- okey_claim_hourly_gift: saatte bir hediye
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.okey_claim_hourly_gift();

CREATE FUNCTION public.okey_claim_hourly_gift()
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid CONSTANT uuid := (SELECT auth.uid());
  v_wallet public.okey_wallets%ROWTYPE;
  v_gift int;
  v_new bigint;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'APP:auth_required' USING ERRCODE = '42501';
  END IF;

  v_wallet := public.okey_internal_ensure_wallet(v_uid);

  -- Süre kontrolü SUNUCUDA yapılır; istemcinin beyanına güvenilmez.
  IF v_wallet.last_hourly_claim_at IS NOT NULL
     AND v_wallet.last_hourly_claim_at > now() - interval '1 hour' THEN
    RAISE EXCEPTION 'APP:gift_not_ready' USING ERRCODE = 'P0001';
  END IF;

  SELECT COALESCE(s.hourly_gift_points, 100) INTO v_gift
  FROM public.okey_settings AS s WHERE s.id = true;

  -- Saat damgası önce yazılır ki eşzamanlı iki çağrı ikinci kez veremesin
  UPDATE public.okey_wallets
  SET last_hourly_claim_at = now()
  WHERE user_id = v_uid;

  v_new := public.okey_internal_add_points(
    v_uid, v_gift, 'hourly_gift',
    v_uid::text || ':' || to_char(now(), 'YYYYMMDDHH24')
  );

  RETURN v_new;
END;
$$;
REVOKE ALL ON FUNCTION public.okey_claim_hourly_gift() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_claim_hourly_gift() TO authenticated;

-- -----------------------------------------------------------------------------
-- okey_claim_ad_reward: reklam izleyerek puan
-- Mevcut SSV-doğrulamalı reklam altyapısına bağlanır: oturum çağırana ait ve
-- SUNUCU TARAFINDA doğrulanmış (credited) olmalıdır. Aynı oturum iki kez
-- kullanılamaz (defterdeki (reason, ref) benzersizliği).
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.okey_claim_ad_reward(uuid);

CREATE FUNCTION public.okey_claim_ad_reward(p_session_id uuid)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid CONSTANT uuid := (SELECT auth.uid());
  v_ok boolean;
  v_points int;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'APP:auth_required' USING ERRCODE = '42501';
  END IF;
  IF p_session_id IS NULL THEN
    RAISE EXCEPTION 'APP:session_required' USING ERRCODE = '22023';
  END IF;

  -- Oturum bana ait ve gerçekten doğrulanmış mı? (SSV tamamlanmış olmalı)
  SELECT EXISTS (
    SELECT 1 FROM public.ad_reward_sessions AS s
    WHERE s.id = p_session_id
      AND s.user_id = v_uid
      AND s.credited_at IS NOT NULL
  ) INTO v_ok;

  IF NOT v_ok THEN
    RAISE EXCEPTION 'APP:ad_not_verified' USING ERRCODE = '42501';
  END IF;

  SELECT COALESCE(s.ad_reward_points, 250) INTO v_points
  FROM public.okey_settings AS s WHERE s.id = true;

  RETURN public.okey_internal_add_points(
    v_uid, v_points, 'ad_reward', p_session_id::text
  );
END;
$$;
REVOKE ALL ON FUNCTION public.okey_claim_ad_reward(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_claim_ad_reward(uuid) TO authenticated;

-- -----------------------------------------------------------------------------
-- admin_okey_grant_points: admin puan ekler/çıkarır
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.admin_okey_grant_points(uuid, bigint, text);

CREATE FUNCTION public.admin_okey_grant_points(
  p_user_id uuid,
  p_amount bigint,
  p_note text DEFAULT NULL
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'APP:forbidden' USING ERRCODE = '42501';
  END IF;
  IF p_amount = 0 THEN
    RAISE EXCEPTION 'APP:invalid_value' USING ERRCODE = '22023';
  END IF;

  RETURN public.okey_internal_add_points(
    p_user_id, p_amount, 'admin_grant',
    -- Her admin işlemi ayrı kayıt olsun diye benzersiz referans
    p_user_id::text || ':' || gen_random_uuid()::text
      || COALESCE(' | ' || p_note, '')
  );
END;
$$;
REVOKE ALL ON FUNCTION public.admin_okey_grant_points(uuid, bigint, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_okey_grant_points(uuid, bigint, text)
  TO authenticated;

-- -----------------------------------------------------------------------------
-- okey_leaderboard: skor tablosu
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.okey_leaderboard(int);

CREATE FUNCTION public.okey_leaderboard(p_limit int DEFAULT 50)
RETURNS TABLE(
  user_id uuid,
  display_name text,
  avatar_url text,
  points bigint,
  matches_played int,
  matches_won int,
  hands_won int,
  best_match_score int
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT
    st.user_id,
    COALESCE(p.full_name, p.username, 'Oyuncu'),
    p.avatar_url,
    COALESCE(w.points, 0),
    st.matches_played,
    st.matches_won,
    st.hands_won,
    st.best_match_score
  FROM public.okey_stats AS st
  JOIN public.profiles AS p ON p.id = st.user_id
  LEFT JOIN public.okey_wallets AS w ON w.user_id = st.user_id
  WHERE (SELECT auth.uid()) IS NOT NULL
  ORDER BY st.matches_won DESC, st.hands_won DESC, COALESCE(w.points, 0) DESC
  LIMIT LEAST(GREATEST(COALESCE(p_limit, 50), 1), 200);
$$;
REVOKE ALL ON FUNCTION public.okey_leaderboard(int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_leaderboard(int) TO authenticated;

NOTIFY pgrst, 'reload schema';
