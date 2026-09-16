-- =============================================================================
-- 101 OKEY — MASA PUANI SERBEST GİRİLİR (kullanıcı isteği, 2026-09-13:
-- "masa açta istediği puanla açabilsin ama en düşük 100 olsun",
--  "oyuncu istenirse TÜM puanını masaya koyabilsin")
-- -----------------------------------------------------------------------------
-- Masa kurma ekranı bugüne kadar beş hazır çip (100/250/500/1000/5000)
-- sunuyordu. Artık istenen tutar yazılabilecek; alt sınır 100, üst sınır
-- oyuncunun CÜZDANI.
--
-- Arayüzün üst sınırı doğru göstermesi için üç sayıya ihtiyacı var ve hiçbiri
-- istemcide yok:
--
--   * okey_settings.min_entry_fee      — alt sınır (RLS: tablo istemciye kapalı)
--   * okey_settings.room_creation_fee  — masayı AÇMANIN ayrı bedeli
--   * okey_wallets.points              — cüzdan
--
-- Gerçek kısıt `create_okey_room` içindeki hesaptır:
--     room_creation_fee + entry_fee × total_hands  ≤  cüzdan
-- yani el başına tavan = (cüzdan - room_creation_fee) / el sayısı. Bölmeyi
-- istemci yapar (el sayısı ekranda değişiyor); bu RPC yalnızca üç girdiyi
-- verir.
--
-- SUNUCU SON SÖZÜ SÖYLEMEYE DEVAM EDER: bu fonksiyon bir KOLAYLIK, bir izin
-- kapısı değil. Arayüz atlansa bile create_okey_room hem alt sınırı
-- (APP:entry_fee_too_low) hem bakiyeyi (APP:insufficient_points) doğruluyor.
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '10s';

DROP FUNCTION IF EXISTS public.okey_room_limits();

CREATE FUNCTION public.okey_room_limits()
RETURNS TABLE(
  min_entry_fee int,
  room_creation_fee int,
  wallet_points bigint
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid CONSTANT uuid := (SELECT auth.uid());
  v_settings public.okey_settings%ROWTYPE;
  v_points bigint := 0;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'APP:auth_required' USING ERRCODE = '42501';
  END IF;

  SELECT s.* INTO v_settings FROM public.okey_settings AS s WHERE s.id = true;

  -- Cüzdanı OLUŞTURMAZ: bu salt okunur bir sorgu (STABLE). Cüzdanı olmayan
  -- oyuncu için 0 döner; masayı kurmaya çalıştığında create_okey_room zaten
  -- cüzdanı açar ve bakiyeyi doğrular.
  SELECT w.points INTO v_points
  FROM public.okey_wallets AS w WHERE w.user_id = v_uid;

  RETURN QUERY SELECT
    GREATEST(COALESCE(v_settings.min_entry_fee, 100), 1),
    GREATEST(COALESCE(v_settings.room_creation_fee, 0), 0),
    COALESCE(v_points, 0);
END;
$$;

REVOKE ALL ON FUNCTION public.okey_room_limits() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_room_limits() TO authenticated;

COMMENT ON FUNCTION public.okey_room_limits() IS
  'Masa kurma ekranının sınırları: en düşük giriş puanı, oda açma ücreti ve çağıranın cüzdanı. El başına tavanı istemci hesaplar: (cüzdan - oda ücreti) / el sayısı.';

NOTIFY pgrst, 'reload schema';
