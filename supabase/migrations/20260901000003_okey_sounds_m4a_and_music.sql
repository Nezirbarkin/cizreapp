-- =============================================================================
-- 101 Okey Plus — .m4a DESTEĞİ + MÜZİK İÇİN BOYUT SINIRI + SİLERKEN TEMİZLİK
-- -----------------------------------------------------------------------------
-- BULUNAN İKİ GERÇEK HATA:
--
-- 1) .m4a YÜKLENEMİYORDU. Dosya seçici .m4a'ya izin veriyordu ama
--    `okey-sounds` bucket'ının allowed_mime_types listesinde m4a'nın MIME
--    türleri (audio/mp4, audio/x-m4a) YOKTU. Yükleme sunucuda reddediliyor,
--    kullanıcıya yalnızca genel bir hata görünüyordu.
--
-- 2) BOYUT SINIRI ÇELİŞİYORDU. Admin arayüzü arka plan şarkısı için 8 MB'a
--    izin veriyordu ama bucket 2 MB'da kesiyordu. Yani "8 MB'a kadar" sözü
--    tutulamıyordu. Şarkılar efektlerden büyük olduğu için sınır 10 MB'a
--    çıkarıldı; arayüz tarafındaki kontrol de buna göre hizalandı.
--
-- AYRICA: admin bir sesi sildiğinde artık DEPODAKİ DOSYA da silinir
-- (`admin_okey_clear_sound` artık silinen kaydın storage_path'ini döner,
--  istemci de dosyayı depodan kaldırır). Önceden yalnızca veritabanı kaydı
--  siliniyor, dosya depoda sonsuza kadar kalıyordu.
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '5s';

-- -----------------------------------------------------------------------------
-- 1) Bucket: m4a MIME türleri + şarkıya yetecek boyut
-- -----------------------------------------------------------------------------
UPDATE storage.buckets
SET
  file_size_limit = 10485760, -- 10 MB (arka plan şarkısı için)
  allowed_mime_types = ARRAY[
    'audio/mpeg',
    'audio/mp3',
    'audio/wav',
    'audio/x-wav',
    'audio/ogg',
    'audio/aac',
    -- .m4a dosyalarının farklı platformlarda aldığı MIME türleri
    'audio/mp4',
    'audio/x-m4a',
    'audio/m4a',
    'audio/aacp',
    'audio/webm'
  ]::text[]
WHERE id = 'okey-sounds';

-- -----------------------------------------------------------------------------
-- 2) admin_okey_clear_sound: silinen kaydın depo yolunu DÖNER
--
-- İstemci bu yolu kullanarak dosyayı depodan da siler. Fonksiyonun dönüş tipi
-- void'den text'e değiştiği için önce düşürülmeli.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.admin_okey_clear_sound(text);

CREATE FUNCTION public.admin_okey_clear_sound(p_sound_key text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_path text;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'APP:forbidden' USING ERRCODE = '42501';
  END IF;

  DELETE FROM public.okey_sound_assets
  WHERE sound_key = p_sound_key
  RETURNING storage_path INTO v_path;

  RETURN v_path; -- kayıt yoksa NULL
END;
$$;
REVOKE ALL ON FUNCTION public.admin_okey_clear_sound(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_okey_clear_sound(text) TO authenticated;

COMMENT ON FUNCTION public.admin_okey_clear_sound(text) IS
  'Ses kaydını siler ve silinen kaydın depo yolunu döner; istemci dosyayı depodan da kaldırır.';

-- -----------------------------------------------------------------------------
-- 3) admin_okey_previous_sound_path: yükleme öncesi ESKİ dosyanın yolu
--
-- Her yükleme zaman damgalı yeni bir yol yazdığı için, eski dosya depoda
-- birikmeye devam ediyordu. İstemci yeni dosyayı yazmadan önce bu fonksiyonla
-- eskisini öğrenip siler.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_okey_previous_sound_path(p_sound_key text)
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_path text;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'APP:forbidden' USING ERRCODE = '42501';
  END IF;

  SELECT storage_path INTO v_path
  FROM public.okey_sound_assets
  WHERE sound_key = p_sound_key;

  RETURN v_path;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_okey_previous_sound_path(text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_okey_previous_sound_path(text)
  TO authenticated;

NOTIFY pgrst, 'reload schema';
