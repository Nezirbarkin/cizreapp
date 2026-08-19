-- ============================================================================
-- !!!! ACİL RUNBOOK SQL'İ — supabase db push çalışmıyorsa burayı kullanın
-- ============================================================================
-- Bu dosya, aşağıdaki dört sorunu BİR ARADA çözen tek bir SQL akışıdır:
--
-- 1) "function public.is_admin() is not unique" (42725)
--    → public.is_admin() birden fazla overload ile tanımlı. Tüm
--    overload'lar pg_proc'tan silinir, kanonik tek implementasyon kurulur.
--
-- 2) "function public.is_courier_role() does not exist" (42883)
--    → 20260802000005 migration'ı yarıda kaldığında bu fonksiyon da
--    oluşmamış olabilir. Burada kanonik tek implementasyon kurulur.
--
-- 3) "relation public.courier_request_rejections does not exist" (42P01)
--    → Tablo hiç oluşmamış. Burada oluşturulur, RLS eklenir.
--
-- 4) "function public.list_available_package_requests" çağrısı
--    → Yukarıdaki bağımlılıklar hazır olduktan sonra RPC yeniden tanımlanır.
--
-- (create_package_request RPC'si 20260807000004_is_admin_overload_fix_and_
--  package_rpc.sql içinde kurulur; burada yeniden tanımlanmaz.)
--
-- KULLANIM:
--   1) ÖNCE 20260807000005_is_admin_overload_fix_and_package_rpc.sql
--      dosyasını SQL Editor'de çalıştırın. Bu dosya
--      - public.is_admin() ambiguity çözümünü yapar
--      - create_package_request RPC'sini kurar
--   2) SONRA bu dosyayı (20260807000005) çalıştırın.
--   3) En alttaki "DOĞRULAMA" bölümündeki sorguları ayrı ayrı çalıştırın.
--   4) Hepsi beklenen sonucu veriyorsa kurye panelini açıp test edin.
--
-- Birden fazla kez çalıştırmak güvenlidir (idempotent).
-- ============================================================================

SET search_path = public, pg_temp;

-- ============================================================================
-- BÖLÜM A: public.is_admin() OVERLOAD AMBIGUITY ÇÖZÜMÜ
-- ============================================================================

-- A.1) Mevcut tüm is_admin() overload'larını pg_proc'tan çekip sil
DO $$
DECLARE
  v_oid  oid;
  v_count int := 0;
BEGIN
  FOR v_oid IN
    SELECT p.oid
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'is_admin'
  LOOP
    EXECUTE format(
      'DROP FUNCTION public.is_admin(%s) CASCADE',
      pg_get_function_identity_arguments(v_oid)
    );
    v_count := v_count + 1;
  END LOOP;

  RAISE NOTICE 'public.is_admin(): % overload silindi', v_count;
END
$$;

-- A.2) Kanonik tek implementasyonu oluştur
-- private.current_user_is_admin() varsa delege et, yoksa inline fallback.
DO $fn$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'private' AND p.proname = 'current_user_is_admin'
  ) THEN
    EXECUTE $sql$
      CREATE FUNCTION public.is_admin()
      RETURNS boolean
      LANGUAGE sql
      STABLE
      SECURITY DEFINER
      SET search_path = ''
      AS $body$
        SELECT private.current_user_is_admin();
      $body$;

      REVOKE ALL ON FUNCTION public.is_admin() FROM PUBLIC, anon;
      GRANT EXECUTE ON FUNCTION public.is_admin()
        TO authenticated, service_role;
    $sql$;
    RAISE NOTICE 'public.is_admin() → private.current_user_is_admin() delegasyonu kuruldu';
  ELSE
    EXECUTE $sql$
      CREATE FUNCTION public.is_admin()
      RETURNS boolean
      LANGUAGE sql
      STABLE
      SECURITY DEFINER
      SET search_path = ''
      AS $body$
        SELECT EXISTS (
          SELECT 1
          FROM public.profiles AS p
          WHERE p.id = (SELECT auth.uid())
            AND p.role::text = 'admin'
        );
      $body$;

      REVOKE ALL ON FUNCTION public.is_admin() FROM PUBLIC, anon;
      GRANT EXECUTE ON FUNCTION public.is_admin()
        TO authenticated, service_role;
    $sql$;
    RAISE NOTICE 'public.is_admin() inline fallback ile kuruldu';
  END IF;
END
$fn$;

-- ============================================================================
-- BÖLÜM A2: public.is_courier_role() EKSİKSE OLUŞTUR
-- ============================================================================
-- 20260802000005 migration'ı yarıda kaldığında bu fonksiyon da oluşmamış
-- olabilir. "function does not exist" (42883) hatasını önlemek için
-- kanonik tek implementasyonu burada kurarız.
-- Önce mevcut overload'ları temizle (ambiguity'yi engelle), sonra
-- kanonik tanımı oluştur.
DO $$
DECLARE
  v_oid  oid;
  v_count int := 0;
BEGIN
  FOR v_oid IN
    SELECT p.oid
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'is_courier_role'
  LOOP
    EXECUTE format(
      'DROP FUNCTION public.is_courier_role(%s) CASCADE',
      pg_get_function_identity_arguments(v_oid)
    );
    v_count := v_count + 1;
  END LOOP;
  RAISE NOTICE 'public.is_courier_role(): % eski overload silindi', v_count;
END
$$;

CREATE OR REPLACE FUNCTION public.is_courier_role()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.profiles AS p
    WHERE p.id = (SELECT auth.uid())
      AND p.role::text = 'courier'
  );
$$;

REVOKE ALL ON FUNCTION public.is_courier_role() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_courier_role()
  TO authenticated, service_role;

-- ============================================================================
-- BÖLÜM B: courier_request_rejections TABLOSU + RPC
-- ============================================================================

-- B.1) Tablo (yoksa oluştur)
CREATE TABLE IF NOT EXISTS public.courier_request_rejections (
  request_id uuid NOT NULL REFERENCES public.courier_requests(id) ON DELETE CASCADE,
  courier_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (request_id, courier_id)
);

-- B.2) İndeks
CREATE INDEX IF NOT EXISTS idx_courier_request_rejections_courier
  ON public.courier_request_rejections (courier_id);

-- B.3) RLS aktif
ALTER TABLE public.courier_request_rejections ENABLE ROW LEVEL SECURITY;

-- B.4) SELECT policy — idempotent
-- A.2 tamamlandıktan sonra artık public.is_admin() tek olduğu için
-- 42725 hatası ALINMAZ.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename  = 'courier_request_rejections'
      AND policyname = 'crr_select_own'
  ) THEN
    CREATE POLICY "crr_select_own"
      ON public.courier_request_rejections FOR SELECT
      TO authenticated
      USING (courier_id = (SELECT auth.uid()) OR public.is_admin());
  END IF;
END
$$;

-- B.5) authenticated'ın INSERT/UPDATE/DELETE yetkisi yok
REVOKE INSERT, UPDATE, DELETE ON public.courier_request_rejections FROM authenticated;

-- B.5b) courier_requests tablosunda create_package_request RPC'sinin
-- ihtiyaç duyduğu kolonların varlığını garanti et (idempotent).
-- 20260802000005 yarıda kaldığında bu kolonlar eksik kalabilir.
DO $$
BEGIN
  ALTER TABLE public.courier_requests
    ADD COLUMN IF NOT EXISTS idempotency_key uuid,
    ADD COLUMN IF NOT EXISTS delivery_card_label text,
    ADD COLUMN IF NOT EXISTS delivery_requested_at timestamptz,
    ADD COLUMN IF NOT EXISTS delivery_confirmed_at timestamptz,
    ADD COLUMN IF NOT EXISTS delivery_confirmed_by uuid
      REFERENCES auth.users(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS accepted_at timestamptz,
    ADD COLUMN IF NOT EXISTS sender_name text,
    ADD COLUMN IF NOT EXISTS sender_phone text,
    ADD COLUMN IF NOT EXISTS pickup_address text,
    ADD COLUMN IF NOT EXISTS pickup_lat double precision,
    ADD COLUMN IF NOT EXISTS pickup_lng double precision,
    ADD COLUMN IF NOT EXISTS delivery_address text,
    ADD COLUMN IF NOT EXISTS delivery_address_detail text,
    ADD COLUMN IF NOT EXISTS delivery_lat double precision,
    ADD COLUMN IF NOT EXISTS delivery_lng double precision,
    ADD COLUMN IF NOT EXISTS distance_km numeric(10, 3),
    ADD COLUMN IF NOT EXISTS total_fee numeric(12, 2),
    ADD COLUMN IF NOT EXISTS courier_fee numeric(12, 2),
    ADD COLUMN IF NOT EXISTS admin_commission numeric(12, 2);
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'courier_requests kolon ekleme atlandı: %', SQLERRM;
END
$$;

CREATE UNIQUE INDEX IF NOT EXISTS uq_courier_requests_sender_idem
  ON public.courier_requests (sender_id, idempotency_key)
  WHERE idempotency_key IS NOT NULL;

-- B.6) RPC'yi yeniden tanımla
CREATE OR REPLACE FUNCTION public.list_available_package_requests()
RETURNS TABLE(
  id uuid,
  distance_km numeric,
  total_fee numeric,
  courier_fee numeric,
  delivery_card_label text,
  created_at timestamptz
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT cr.id, cr.distance_km, cr.total_fee, cr.courier_fee,
         cr.delivery_card_label, cr.created_at
  FROM public.courier_requests AS cr
  WHERE cr.status = 'pending'
    AND cr.courier_id IS NULL
    AND cr.sender_id <> (SELECT auth.uid())
    AND NOT EXISTS (
      SELECT 1 FROM public.courier_request_rejections AS crr
      WHERE crr.request_id = cr.id
        AND crr.courier_id = (SELECT auth.uid())
    )
    AND (SELECT auth.uid()) IS NOT NULL
    AND public.is_courier_role()
  ORDER BY cr.created_at ASC;
$$;

REVOKE ALL ON FUNCTION public.list_available_package_requests() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_available_package_requests() TO authenticated;

-- B.7) create_package_request RPC — "v_existing does not exist" hatasını
-- önlemek için %ROWTYPE yerine tek tek skalaları INTO ile atıyoruz.
-- Fonksiyon zaten RETURNS TABLE ile dönüyor, bu yüzden record tipine
-- gerek yok. 20260807000004'teki versiyon "DECLARE v_existing
-- public.courier_requests%ROWTYPE" kullanıyordu; bu bazı şema
-- durumlarında "relation does not exist" hatası veriyor.
DROP FUNCTION IF EXISTS public.create_package_request(
  double precision, double precision, double precision, double precision,
  text, text, text, text, text, text, text, text, uuid
);

CREATE FUNCTION public.create_package_request(
  p_pickup_lat double precision,
  p_pickup_lng double precision,
  p_delivery_lat double precision,
  p_delivery_lng double precision,
  p_sender_name text,
  p_sender_phone text,
  p_recipient_name text,
  p_recipient_phone text,
  p_pickup_address text,
  p_delivery_address text,
  p_delivery_address_detail text,
  p_description text,
  p_idempotency_key uuid
)
RETURNS TABLE(
  id uuid,
  status text,
  total_fee numeric,
  courier_fee numeric,
  admin_commission numeric,
  distance_km numeric,
  created_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id     CONSTANT uuid := (SELECT auth.uid());
  v_settings    public.courier_service_settings%ROWTYPE;
  v_distance_km numeric(10, 3);
  v_total_fee   numeric(12, 2);
  v_courier_fee numeric(12, 2);
  v_admin_fee   numeric(12, 2);
  v_commission  numeric(5, 2);
  v_balance_id  uuid;
  v_balance     numeric(12, 2);
  v_tx_id       uuid;
  v_request_id  uuid;
  v_created_at  timestamptz;
  -- Idempotency: %ROWTYPE yerine tek tek skalalar (v_existing record
  -- sorununu kökünden çözer)
  v_ex_id           uuid;
  v_ex_status       text;
  v_ex_total_fee    numeric;
  v_ex_courier_fee  numeric;
  v_ex_admin_fee    numeric;
  v_ex_distance_km  numeric;
  v_ex_created_at   timestamptz;
BEGIN
  -- 1) Oturum kontrolü
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'APP:auth_required | oturum açmanız gerekiyor'
      USING ERRCODE = '42501';
  END IF;

  -- 2) Idempotency: aynı (sender_id, key) daha önce kullanıldıysa mevcut kaydı döner
  IF p_idempotency_key IS NOT NULL THEN
    SELECT cr.id, cr.status::text, cr.total_fee, cr.courier_fee,
           cr.admin_commission, cr.distance_km, cr.created_at
      INTO v_ex_id, v_ex_status, v_ex_total_fee, v_ex_courier_fee,
           v_ex_admin_fee, v_ex_distance_km, v_ex_created_at
    FROM public.courier_requests AS cr
    WHERE cr.sender_id = v_user_id
      AND cr.idempotency_key = p_idempotency_key
    LIMIT 1;

    IF v_ex_id IS NOT NULL THEN
      id            := v_ex_id;
      status        := v_ex_status;
      total_fee     := v_ex_total_fee;
      courier_fee   := v_ex_courier_fee;
      admin_commission := v_ex_admin_fee;
      distance_km   := v_ex_distance_km;
      created_at    := v_ex_created_at;
      RETURN NEXT;
      RETURN;
    END IF;
  END IF;

  -- 3) Koordinat doğrulama
  IF p_pickup_lat IS NULL OR p_pickup_lat < -90 OR p_pickup_lat > 90
     OR p_delivery_lat IS NULL OR p_delivery_lat < -90 OR p_delivery_lat > 90
     OR p_pickup_lng IS NULL OR p_pickup_lng < -180 OR p_pickup_lng > 180
     OR p_delivery_lng IS NULL OR p_delivery_lng < -180 OR p_delivery_lng > 180 THEN
    RAISE EXCEPTION 'APP:invalid_coordinates | koordinat aralık dışı'
      USING ERRCODE = '22023';
  END IF;

  -- 4) Zorunlu alanlar
  IF NULLIF(trim(p_sender_name), '') IS NULL THEN
    RAISE EXCEPTION 'APP:sender_name_required' USING ERRCODE = '22023';
  END IF;
  IF NULLIF(trim(p_recipient_name), '') IS NULL THEN
    RAISE EXCEPTION 'APP:recipient_name_required' USING ERRCODE = '22023';
  END IF;
  IF NULLIF(trim(p_pickup_address), '') IS NULL THEN
    RAISE EXCEPTION 'APP:pickup_address_required' USING ERRCODE = '22023';
  END IF;
  IF NULLIF(trim(p_delivery_address), '') IS NULL THEN
    RAISE EXCEPTION 'APP:delivery_address_required' USING ERRCODE = '22023';
  END IF;

  -- 5) Aktif servis ayarları
  SELECT css.* INTO v_settings
  FROM public.courier_service_settings AS css
  WHERE css.enabled = true
  ORDER BY css.updated_at DESC NULLS LAST
  LIMIT 1;

  IF v_settings.id IS NULL THEN
    RAISE EXCEPTION 'APP:service_disabled | kurye servisi aktif değil'
      USING ERRCODE = 'P0001';
  END IF;

  IF COALESCE(v_settings.allows_user_requests, false) = false THEN
    RAISE EXCEPTION 'APP:user_requests_disabled | kullanıcı talepleri kapalı'
      USING ERRCODE = 'P0001';
  END IF;

  v_commission := COALESCE(v_settings.commission_percent, 20);

  -- 6) Haversine mesafe (km)
  v_distance_km := round(
    6371 * 2 * asin(sqrt(
      power(sin(radians((p_delivery_lat - p_pickup_lat) / 2.0)), 2)
      + cos(radians(p_pickup_lat)) * cos(radians(p_delivery_lat))
        * power(sin(radians((p_delivery_lng - p_pickup_lng) / 2.0)), 2)
    ))::numeric,
    3
  );

  -- 7) Ücret hesabı
  v_total_fee := round(
    v_settings.base_fee + v_distance_km * v_settings.per_km_fee,
    2
  );
  v_courier_fee := round(v_total_fee * (1 - v_commission / 100.0), 2);
  v_admin_fee   := v_total_fee - v_courier_fee;

  IF v_total_fee <= 0 THEN
    RAISE EXCEPTION 'APP:invalid_total_fee | hesaplanan ücret sıfır'
      USING ERRCODE = 'P0001';
  END IF;

  -- 8) Bakiye kilidi
  SELECT ub.id, ub.balance
    INTO v_balance_id, v_balance
  FROM public.user_balances AS ub
  WHERE ub.user_id = v_user_id
  FOR UPDATE;

  IF v_balance_id IS NULL THEN
    RAISE EXCEPTION 'APP:balance_not_found' USING ERRCODE = 'P0001';
  END IF;

  IF v_balance < v_total_fee THEN
    RAISE EXCEPTION 'APP:insufficient_balance | mevcut: %, gerekli: %',
      v_balance, v_total_fee USING ERRCODE = 'P0001';
  END IF;

  -- 9) Bakiye düşümü
  UPDATE public.user_balances AS ub
     SET balance = ub.balance - v_total_fee,
         total_spent = ub.total_spent + v_total_fee,
         updated_at = now()
   WHERE ub.id = v_balance_id;

  -- 10) Ledger kaydı
  INSERT INTO public.balance_transactions (
    user_id, type, amount, net_amount,
    balance_before, balance_after,
    reference_type, reference_id,
    status, description, metadata
  ) VALUES (
    v_user_id, 'courier_payment'::public.balance_transaction_type,
    v_total_fee, v_total_fee,
    v_balance, v_balance - v_total_fee,
    'courier_request', gen_random_uuid(),
    'completed', 'Paket gönderim ücreti',
    jsonb_build_object('flow', 'create_package_request')
  )
  RETURNING id INTO v_tx_id;

  -- 11) Talep oluştur
  INSERT INTO public.courier_requests (
    sender_id, sender_name, sender_phone,
    recipient_name, recipient_phone,
    pickup_address, pickup_lat, pickup_lng,
    delivery_address, delivery_address_detail,
    delivery_lat, delivery_lng,
    description, distance_km, total_fee, courier_fee, admin_commission,
    status, courier_id, idempotency_key
  ) VALUES (
    v_user_id, p_sender_name, p_sender_phone,
    p_recipient_name, p_recipient_phone,
    p_pickup_address, p_pickup_lat, p_pickup_lng,
    p_delivery_address, p_delivery_address_detail,
    p_delivery_lat, p_delivery_lng,
    p_description, v_distance_km, v_total_fee, v_courier_fee, v_admin_fee,
    'pending', NULL, p_idempotency_key
  )
  RETURNING id, created_at INTO v_request_id, v_created_at;

  -- 12) Ledger referansını talep ile güncelle
  UPDATE public.balance_transactions AS bt
     SET reference_id = v_request_id
   WHERE bt.id = v_tx_id;

  -- 13) Sonuç
  id              := v_request_id;
  status          := 'pending';
  total_fee       := v_total_fee;
  courier_fee     := v_courier_fee;
  admin_commission := v_admin_fee;
  distance_km     := v_distance_km;
  created_at      := v_created_at;
  RETURN NEXT;
END;
$$;

REVOKE ALL ON FUNCTION public.create_package_request(
  double precision, double precision, double precision, double precision,
  text, text, text, text, text, text, text, text, uuid
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_package_request(
  double precision, double precision, double precision, double precision,
  text, text, text, text, text, text, text, text, uuid
) TO authenticated;

-- ============================================================================
-- BÖLÜM C: PostgREST schema cache'ini yenile
-- ============================================================================
DO $$
BEGIN
  PERFORM pg_notify('pgrst', 'reload schema');
  RAISE NOTICE 'PostgREST schema cache reload tetiklendi';
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'PostgREST reload tetiklenemedi: %. Dashboard > API > '
                'Reload schema cache butonunu kullanın.', SQLERRM;
END
$$;

-- ============================================================================
-- DOĞRULAMA — bu sorguları ayrı ayrı çalıştırın ve sonuçları kontrol edin
-- ============================================================================
-- 1) is_admin() tek overload mı?
--    SELECT count(*) FROM pg_proc p
--    JOIN pg_namespace n ON n.oid = p.pronamespace
--    WHERE n.nspname = 'public' AND p.proname = 'is_admin';
--    Beklenen: 1
--
-- 2) is_admin() çağrısı hata veriyor mu?
--    SELECT public.is_admin();
--    Beklenen: 42725 YOK, t/f döner
--
-- 3) Tablo mevcut mu?
--    SELECT to_regclass('public.courier_request_rejections');
--    Beklenen: courier_request_rejections (null değil)
--
-- 4) list_available_package_requests var mı?
--    SELECT pronargs FROM pg_proc
--    WHERE proname = 'list_available_package_requests';
--    Beklenen: 0 (parametresiz)
--
-- 5) create_package_request var mı?
--    SELECT pronargs FROM pg_proc
--    WHERE proname = 'create_package_request';
--    Beklenen: 13
--
-- 6) is_courier_role var mı?
--    SELECT count(*) FROM pg_proc p
--    JOIN pg_namespace n ON n.oid = p.pronamespace
--    WHERE n.nspname = 'public' AND p.proname = 'is_courier_role';
--    Beklenen: 1
--
-- 7) Hâlâ hata varsa: Supabase Dashboard > API > "Reload schema cache"
--    butonuna tıklayıp 30 saniye bekleyin, kurye panelini tekrar açın.
--
-- !!! DOĞRULAMA SORGULARINI TEK SEFERDE YAPIŞTIRMAYIN !!!
-- Her birini ayrı New query'de çalıştırın. SQL Editor birden fazla
-- SELECT'i ; ile ayırarak kabul eder, ama yorum satırlarındaki tire
-- işareti "-" syntax hatasına yol açabilir. Tek sorgu = tek başarı.
-- ============================================================================
