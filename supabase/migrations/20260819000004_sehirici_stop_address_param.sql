-- =============================================================================
-- Şehiriçi: durak upsert RPC'sine adres parametresi
-- Tarih: 2026-08-19
-- =============================================================================
-- KÖK NEDEN
--   `sehirici_stops` tablosunda `address` sütunu VAR ve admin panelindeki durak
--   formunda "Adres" alanı VAR; Dart tarafında SehiriciLineService.upsertStop
--   `address` parametresini kabul ediyor — ama RPC'ye hiç göndermiyor, çünkü
--   admin_upsert_sehirici_stop imzasında böyle bir parametre yoktu:
--
--     admin_upsert_sehirici_stop(p_id, p_city_id, p_name, p_code, p_lat,
--                                p_lng, p_is_active)
--
--   Sonuç: yönetici adres yazıyor, "Kaydet" başarılı görünüyor, adres sessizce
--   kayboluyor. Düzenlemek için tekrar açıldığında alan yine boş.
--
-- ÇÖZÜM
--   p_address parametresini SONA, DEFAULT NULL ile ekle. Böylece:
--     • Yeni Dart kodu adresi gönderir.
--     • Parametreyi geçmeyen eski çağrılar aynen çalışmaya devam eder.
--   NULL adres, INSERT'te NULL yazar; UPDATE'te ise mevcut adresi EZMEZ
--   (COALESCE ile korunur) — parametreyi göndermeyen eski bir istemci
--   kayıtlı adresi silmesin diye.
--
-- NOT: DEFAULT'lu yeni parametre eklemek PostgreSQL'de aynı ada sahip ikinci
--   bir fonksiyon YARATIR (overload). Belirsiz çağrıları önlemek için eski
--   7 parametreli sürüm açıkça düşürülür.
-- =============================================================================

BEGIN;

DROP FUNCTION IF EXISTS public.admin_upsert_sehirici_stop(
  UUID, UUID, TEXT, TEXT, DOUBLE PRECISION, DOUBLE PRECISION, BOOLEAN
);

CREATE OR REPLACE FUNCTION public.admin_upsert_sehirici_stop(
  p_id UUID,
  p_city_id UUID,
  p_name TEXT,
  p_code TEXT,
  p_lat DOUBLE PRECISION,
  p_lng DOUBLE PRECISION,
  p_is_active BOOLEAN,
  p_address TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id UUID;
BEGIN
  IF NOT public.auth_sehirici_is_admin() THEN
    RAISE EXCEPTION 'Bu işlem için admin yetkisi gerekir';
  END IF;

  INSERT INTO public.sehirici_stops (id, city_id, name, code, lat, lng, is_active, address)
  VALUES (
    COALESCE(p_id, gen_random_uuid()),
    p_city_id,
    p_name,
    NULLIF(TRIM(p_code), ''),
    p_lat,
    p_lng,
    COALESCE(p_is_active, TRUE),
    NULLIF(TRIM(p_address), '')
  )
  ON CONFLICT (id) DO UPDATE SET
    city_id = EXCLUDED.city_id,
    name = EXCLUDED.name,
    code = EXCLUDED.code,
    lat = EXCLUDED.lat,
    lng = EXCLUDED.lng,
    is_active = EXCLUDED.is_active,
    -- Parametre geçilmediyse (NULL) mevcut adres korunur.
    address = COALESCE(EXCLUDED.address, public.sehirici_stops.address),
    updated_at = now()
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_upsert_sehirici_stop(
  UUID, UUID, TEXT, TEXT, DOUBLE PRECISION, DOUBLE PRECISION, BOOLEAN, TEXT
) TO authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;
