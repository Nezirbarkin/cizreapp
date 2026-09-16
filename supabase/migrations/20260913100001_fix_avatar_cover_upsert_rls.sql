-- =============================================================================
-- PROFIL AVATARI / KAPAK YUKLEME HATASI (403 "new row violates row-level
-- security policy") DUZELTMESI
-- =============================================================================
-- BELIRTI: Kullanici profilinde hazir avatar sectiginde veya galeriden fotograf
-- yukledginde uygulama "Profil fotografi yuklenemedi. Lutfen tekrar deneyin."
-- diyordu. Ayni sey kapak fotografinda da oluyordu.
--
-- KOK NEDEN: ProfileService tum avatar/kapak yuklemelerini
-- `FileOptions(upsert: true)` ile yapiyor (ayni kullanici ayni dosya adini
-- yeniden yazabilsin diye). storage-api'nin upsert yolu
-- `INSERT ... ON CONFLICT ... RETURNING` kullanir; RETURNING ile geri donen
-- satirin SELECT politikalarindan da gecmesi gerekir. Oysa storage.objects
-- uzerinde `avatars` ve `covers` bucket'lari icin TEK BIR SELECT politikasi
-- bile yoktu (INSERT/UPDATE/DELETE vardi). Dolayisiyla upsert'li her yukleme
-- RLS'e takiliyor, upsert'siz ayni yukleme sorunsuz geciyordu.
--
-- COZUM: Iki bucket icin public SELECT politikasi ekle. Bu yeni bir sizinti
-- acmaz: iki bucket da zaten `public = true` (storage.buckets) ve CDN
-- uzerinden okuma RLS'e hic ugramiyor; ilan-images / stories / news-images
-- gibi diger public bucket'larda ayni sekilde public read politikasi mevcut.
-- =============================================================================

DROP POLICY IF EXISTS avatars_select_public ON storage.objects;
CREATE POLICY avatars_select_public ON storage.objects
  FOR SELECT
  TO public
  USING (bucket_id = 'avatars');

DROP POLICY IF EXISTS covers_select_public ON storage.objects;
CREATE POLICY covers_select_public ON storage.objects
  FOR SELECT
  TO public
  USING (bucket_id = 'covers');

COMMENT ON POLICY avatars_select_public ON storage.objects IS
  'avatars public bucket: upsert:true yuklemelerinin RETURNING satiri icin gerekli SELECT izni.';
COMMENT ON POLICY covers_select_public ON storage.objects IS
  'covers public bucket: upsert:true yuklemelerinin RETURNING satiri icin gerekli SELECT izni.';
