-- ============================================================================
-- Kullanıcının kendi profiles.fcm_token sütununu yazabilmesi
-- ============================================================================
-- Arka plan (tespit edilen hata):
--   * 20260803000006_secure_profiles_privileges_and_pii migration'ı
--     profiles tablosundaki UPDATE/INSERT grant'lerini REVOKE etti; tüm
--     yazma işlemleri SECURITY DEFINER `set_my_*` RPC'leri üzerinden
--     yapılmak zorunda.
--   * `fcm_token` sütunu için böyle bir RPC yoktu. İstemci
--     `PushNotificationService._saveFCMToken()` doğrudan
--     `profiles.update({fcm_token: ...})` çağırıyordu → 42501
--     (permission denied) alıyordu. Sonuç: push bildirimler hiç
--     gelmiyordu; FCM token DB'ye yazılamadığı için Edge Function
--     `process-notification-outbox` kurye/müşteri tokenını bulamıyordu.
--   * Aynı sorun çıkışta `clearTokenOnLogout()` için de geçerliydi.
--
-- Bu migration:
--   1) `set_my_fcm_token(p_token text)` SECURITY DEFINER RPC'si ekler.
--      - p_token NULL veya '' ise token temizlenir (logout için).
--      - p_token çok uzunsa (>= 4096) reddeder; kötü niyetli uzun
--        string'leri / vector'leri erken keser.
--   2) `clear_my_fcm_token()` RPC'si ekler. İstemci çıkışta bunu
--      çağırır; service_role mantığıyla aynı işi yapar.
--   3) Mevcut müşterilerin fcm_token alanı üzerinde RLS UPDATE
--      politikası YOK (zaten REVOKE). Bu RPC SECURITY DEFINER
--      olduğu için yazma yetkisi service_role üzerinden geçer,
--      RLS bypass olur.
--
-- Güvenlik kapsamı:
--   * Sadece authenticated kullanıcı çağırabilir.
--   * Sadece KENDİ satırı güncellenir (auth.uid() = id).
--   * fcm_token dışındaki alanlara dokunulmaz; UPDATE dar sütunla
--     sınırlıdır.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.set_my_fcm_token(p_token text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'set_my_fcm_token: not authenticated'
      USING ERRCODE = '28000';
  END IF;

  -- Token NULL/empty ise temizle (logout senaryosu). Aksi halde sınır
  -- kontrolü yap; FCM token'ları pratikte 200-300 karakter civarıdır.
  IF p_token IS NOT NULL THEN
    -- Trim ve boş string'i NULL'a çevir
    IF length(p_token) = 0 OR btrim(p_token) = '' THEN
      p_token := NULL;
    ELSIF length(p_token) >= 4096 THEN
      -- Olası kötü niyetli uzun payload'ı reddet. Gerçek FCM token
      -- bundan çok daha kısa olur (en kötü ~500 karakter).
      RAISE EXCEPTION 'set_my_fcm_token: token too long'
        USING ERRCODE = '22023';
    END IF;
  END IF;

  UPDATE public.profiles
    SET fcm_token = p_token
  WHERE id = v_uid;
END;
$$;

REVOKE ALL ON FUNCTION public.set_my_fcm_token(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.set_my_fcm_token(text) TO authenticated, service_role;

COMMENT ON FUNCTION public.set_my_fcm_token IS
  'Kullanıcının kendi profiles.fcm_token alanını güvenli yazması. '
  'NULL/empty geçilirse token temizlenir. SECURITY DEFINER + RLS bypass.';

-- Kısa alias: bazı istemci kodları açıkça "clear" semantiği bekliyor.
CREATE OR REPLACE FUNCTION public.clear_my_fcm_token()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'clear_my_fcm_token: not authenticated'
      USING ERRCODE = '28000';
  END IF;
  UPDATE public.profiles SET fcm_token = NULL WHERE id = v_uid;
END;
$$;

REVOKE ALL ON FUNCTION public.clear_my_fcm_token() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.clear_my_fcm_token() TO authenticated, service_role;

COMMENT ON FUNCTION public.clear_my_fcm_token IS
  'Kullanıcının kendi profiles.fcm_token alanını temizler (logout için).';
