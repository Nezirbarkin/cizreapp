-- =============================================================================
-- admin_scan_fraud_signals: digest() bulunamama hatasını düzelt
-- =============================================================================
-- `supabase db lint` bulgusu (canlı, 2026-09-07):
--     public.admin_scan_fraud_signals
--     ERROR: function digest(text, unknown) does not exist
--
-- NEDEN: pgcrypto `extensions` şemasında kurulu (digest fonksiyonları orada),
-- fonksiyonun search_path'i ise yalnız `public`. Bu yüzden admin panelindeki
-- "Dolandırıcılık Sinyalleri" taraması (lib/features/admin/services/
-- fraud_detection_service.dart:43) canlıda her çağrıda patlıyordu.
--
-- ÇÖZÜM: search_path'e `extensions` eklenir. Supabase'in standart deseni
-- budur; `extensions` şemasına yalnız superuser yazabildiği için
-- SECURITY DEFINER bağlamında güvenlidir.
--
-- Bu düzeltme 20260907120001 ile birlikte anlam kazanıyor: fiyat
-- manipülasyonu denemeleri artık fraud_signals'a 'price_tampering' olarak
-- düşüyor ve admin taraması nihayet çalışacak.
-- =============================================================================

DO $$
DECLARE
  v_sig text;
BEGIN
  SELECT string_agg(format('%s', pg_get_function_identity_arguments(p.oid)), '')
    INTO v_sig
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'admin_scan_fraud_signals';

  IF v_sig IS NULL THEN
    RAISE NOTICE 'admin_scan_fraud_signals bulunamadi, atlaniyor';
    RETURN;
  END IF;

  EXECUTE format(
    'ALTER FUNCTION public.admin_scan_fraud_signals(%s) SET search_path = public, extensions',
    v_sig
  );
END $$;

NOTIFY pgrst, 'reload schema';
