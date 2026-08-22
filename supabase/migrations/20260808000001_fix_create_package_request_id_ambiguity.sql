-- ============================================================================
-- 20260808000001_fix_create_package_request_id_ambiguity.sql
-- ----------------------------------------------------------------------------
-- AMAÇ: create_package_request RPC'sinde "column reference 'id' is ambiguous"
--       (PostgreSQL 42702) hatasını kökünden çözmek.
--
-- ARKA PLAN (tespit edilen kök neden):
--   Fonksiyon şu imzayla tanımlıydı:
--     RETURNS TABLE(
--       id uuid,            <-- PL/pgSQL OUT değişkeni "id"
--       status text, ...
--     )
--   Fonksiyon gövdesinde ise şu ifadeler geçiyordu:
--     1) SELECT cr.id, ... INTO v_ex_id, ... FROM public.courier_requests AS cr
--        -> cr alias'lı olduğu için "id" burada sorun çıkarmaz.
--     2) UPDATE public.balance_transactions AS bt SET reference_id = v_request_id
--        WHERE bt.id = v_tx_id;
--        -> bt alias'lı, "id" nitelenmiş (bt.id). Sorun yok.
--     3) INSERT INTO public.balance_transactions (...) RETURNING id INTO v_tx_id;
--        -> Burada "id" tablo kolonu olmasına rağmen PL/pgSQL parser'ı
--           RETURNS TABLE'daki OUT "id" ile karıştırıyor ve 42702 hatası
--           fırlatıyor. Aynı durum Adım 11'de:
--        INSERT INTO public.courier_requests (...) RETURNING id, created_at
--          INTO v_request_id, v_created_at;
--           -> "id" yine belirsiz; "created_at" ise tablo kolonu olarak net
--              çözümleniyor.
--
--   Sonuç: Flutter "Paket talebini gönderme hatası: PostgrestException
--   (message: column reference 'id' is ambiguous, code: 42702)" hatası alıyor.
--
-- ÇÖZÜM:
--   RETURNS TABLE'daki "id" sütununu benzersiz bir ada (r_id) çeviriyoruz.
--   Böylece PL/pgSQL değişken adı "id" artık mevcut olmadığından
--   RETURNING id her zaman tablo kolonuna yönelir. Fonksiyon içindeki
--   tüm 'id := ...' atamaları 'r_id := ...' olur.
--
--   UYUMLULUK:
--     * Flutter tarafı `params` ile çağırıyor, sonuç satırı olarak
--       Map<String,dynamic> alıyor; RPC'nin döndüğü satırda kolon adı
--       değiştiği için Dart tarafında 'id' bekleyen tek yer:
--         lib/features/user_courier/screens/send_package_screen.dart
--       Bu yüzden migration sonunda COMMENT ile davranış değişikliğini
--       not ediyoruz, ve Flutter tarafında tek satır güncellemesi
--       gerekecek.
--     * (Alternatif olarak) tüm RETURNING'leri
--         RETURNING public.balance_transactions.id INTO v_tx_id
--       şeklinde nitelemek de bir çözüm; fakat RETURNS TABLE ile çakışma
--       genel bir tuzak olduğundan, kalıcı çözüm olarak OUT adını
--       benzersizleştirmek daha sağlam.
--
-- UYGULAMA SIRASI:
--   1) Bu dosyayı Supabase migration olarak yükle (supabase db push veya
--      supabase migration up komutuyla).
--   2) PostgREST schema cache'i otomatik yenilenir (NOTIFY pgrst);
--      yine de Supabase Studio > Settings > API > "Reload schema cache"
--      butonu tetiklenebilir.
--   3) Flutter istemcide `insertedRequest['id']` okuyan satırı
--      `insertedRequest['r_id']` olarak güncelle.
--
-- GERİ ALMA:
--   Bu migration idempotent'tir; fonksiyon zaten DROP IF EXISTS ile
--   yeniden yazılır. Tekrar uygulamak güvenlidir.
-- ============================================================================

SET search_path = '';

-- ----------------------------------------------------------------------------
-- 1) Eski tanımı kaldır (imza 13 parametreli, double precision x4 + text x8 + uuid)
-- ----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.create_package_request(
  double precision, double precision, double precision, double precision,
  text, text, text, text, text, text, text, text, uuid
);

-- ----------------------------------------------------------------------------
-- 2) Yeniden tanımla — RETURNS TABLE'daki "id" artık "r_id"
-- ----------------------------------------------------------------------------
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
-- TÜM RETURNS TABLE kolonları "r_" önekiyle: PL/pgSQL değişkenleri ile
-- tablo kolonları arasındaki ambiguity'yi (42702) kökünden çözer.
RETURNS TABLE(
  r_id              uuid,
  r_status          text,
  r_total_fee       numeric,
  r_courier_fee     numeric,
  r_admin_commission numeric,
  r_distance_km     numeric,
  r_created_at      timestamptz
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
      r_id               := v_ex_id;
      r_status           := v_ex_status;
      r_total_fee        := v_ex_total_fee;
      r_courier_fee      := v_ex_courier_fee;
      r_admin_commission := v_ex_admin_fee;
      r_distance_km      := v_ex_distance_km;
      r_created_at       := v_ex_created_at;
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
  --     RETURNING id INTO v_tx_id artık belirsiz değil: PL/pgSQL kapsamında
  --     "id" adında bir değişken yok (RETURNS TABLE'daki isim "r_id" oldu),
  --     dolayısıyla parser balance_transactions.id'a yönelir.
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

  -- 11) Talep oluştur — RETURNING id, created_at:
  --     "id" artık courier_requests.id olarak net çözümlenir.
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

  -- 13) Sonuç — TÜM OUT kolonları "r_" önekli (42702 çakışma çözümü)
  r_id               := v_request_id;
  r_status           := 'pending';
  r_total_fee        := v_total_fee;
  r_courier_fee      := v_courier_fee;
  r_admin_commission := v_admin_fee;
  r_distance_km      := v_distance_km;
  r_created_at       := v_created_at;
  RETURN NEXT;
END;
$$;

-- ----------------------------------------------------------------------------
-- 3) Yetkiler
-- ----------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.create_package_request(
  double precision, double precision, double precision, double precision,
  text, text, text, text, text, text, text, text, uuid
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_package_request(
  double precision, double precision, double precision, double precision,
  text, text, text, text, text, text, text, text, uuid
) TO authenticated;

COMMENT ON FUNCTION public.create_package_request(
  double precision, double precision, double precision, double precision,
  text, text, text, text, text, text, text, text, uuid
) IS
  'Sunucu-otoriteli atomik paket talebi: mesafe + ücret + bakiye düşümü + ledger. Idempotent. '
  '(2026-08-08 HOTFIX v2: RETURNS TABLE''daki TÜM kolon adları "r_" önekli '
  '(r_id, r_status, r_total_fee, r_courier_fee, r_admin_commission, '
  'r_distance_km, r_created_at). "column reference ... is ambiguous" 42702 '
  'hatası tüm kolonlar için kökünden çözüldü. Flutter tarafı '
  'insertedRequest["r_id"], insertedRequest["r_total_fee"] vb. okumalı.)';

-- ----------------------------------------------------------------------------
-- 4) PostgREST schema cache'ini yenile
-- ----------------------------------------------------------------------------
DO $$
BEGIN
  PERFORM pg_notify('pgrst', 'reload schema');
EXCEPTION WHEN OTHERS THEN
  -- pg_notify tüm bağlamlarda çalışır; yine de hata olursa yut.
  NULL;
END;
$$;

-- ============================================================================
-- DOĞRULAMA (uygulama sonrası psql'de çalıştır):
--
--   \df+ public.create_package_request
--     -> RETURNS table içinde "r_id, r_status, r_total_fee, r_courier_fee,
--        r_admin_commission, r_distance_km, r_created_at" görünmeli.
--        "id", "status", "total_fee", "created_at" gibi düz adlar görünMEMELİ.
--
--   SELECT * FROM public.create_package_request(
--     37.3255, 42.1876, 37.3310, 42.1950,
--     'Ali','5551112233','Veli','5552223344',
--     'Cizre Merkez','Cizre Stadyum',NULL,'Test paketi',
--     gen_random_uuid()
--   );
--     -> Tek satır dönmeli; sütun adları: r_id, r_status, r_total_fee,
--        r_courier_fee, r_admin_commission, r_distance_km, r_created_at.
-- ============================================================================
