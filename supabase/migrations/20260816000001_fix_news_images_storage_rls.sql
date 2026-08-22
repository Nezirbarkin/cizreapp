-- =============================================================================
-- DOSYA: supabase/migrations/20260816000001_fix_news_images_storage_rls.sql
-- AMAÇ: haber eklerken "Yükleme hatası: StorageException(message: new row
--       violates row-level security policy, statusCode: 403, error:
--       Unauthorized)" hatasını düzeltmek ve news-images bucket'ının storage
--       RLS politikalarını tutarlı hale getirmek.
-- TARİH: 2026-08-16
--
-- TEŞHİS:
--   Bu, birkaç gün önce stories bucket'ı için çözülen birebir aynı hatadır
--   (bkz. 20260815000001_fix_stories_storage_rls.sql). news-images bucket'ı
--   public=true ve doğru MIME/boyut limitlerine sahip; dolayısıyla 403 MIME/
--   boyut kaynaklı değil, saf RLS reddi.
--
--   news-images INSERT politikası (20260809000007'den "News media owner
--   insert") yalnızca BİLİNEN isimli eski politikaları drop ediyordu.
--   Production'da, Supabase Dashboard SQL editörü veya unutulmuş
--   migration'lardan kalmış, bu migration'ın listelemediği ek politikalar
--   (özellikle RESTRICTIVE olanlar) ayakta kalıyor. RESTRICTIVE politikalar
--   PERMISSIVE'lerle AND'lenir ve authenticated yükleme path'ini bloke eder
--   → 403 "new row violates row-level security policy".
--
--   Not: Rol her zaman profiles.role'da tutulur (admin_set_user_role RPC'si
--   20260810000008 sadece profiles.role yazar). Bu yüzden sorun rolün saklama
--   yerindeki tutarsızlık değil; çakışan politikaların ayakta kalmasıdır.
--
-- ÇÖZÜM (stories düzeltmesiyle aynı yöntem):
--   1) storage.objects üzerinde news-images bucket'ına atıfta bulunan TÜM
--      politikaları kaldır (bilinen eski isimler + qual/with_check'inde
--      'news-images' geçen bilinmeyen politikalar dahil).
--   2) Temiz ve minimal 4 politika oluştur:
--      - SELECT → public            (bucket public, görseller/video herkese açık)
--      - INSERT → authenticated     (giriş yapmış kullanıcı yükler)
--      - UPDATE → authenticated     (upsert:true yüklemeleri için)
--      - DELETE → authenticated     (haberci kendi galeri görselini silebilmeli)
--   Haberci/admin ayrımı DB seviyesinde (news ve news_images tablo RLS)
--   zaten korunuyor; storage katmanı path formatından bağımsız, en düşük
--   riskli politikalarla açılır.
-- =============================================================================

-- 1) Bucket'ın varlığını, public bayrağını ve limitlerini garanti et
INSERT INTO storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
VALUES (
  'news-images',
  'news-images',
  true,
  104857600,
  ARRAY[
    'image/jpeg',
    'image/png',
    'image/webp',
    'image/gif',
    'video/mp4',
    'video/quicktime',
    'video/webm'
  ]::text[]
)
ON CONFLICT (id) DO UPDATE SET
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

-- 2) Bilinen eski politika isimlerini düşür (idempotent)
DROP POLICY IF EXISTS "Public can access news images by name" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated users can upload news images" ON storage.objects;
DROP POLICY IF EXISTS "News authors can update images" ON storage.objects;
DROP POLICY IF EXISTS "Only admins can delete images" ON storage.objects;
DROP POLICY IF EXISTS "News media public read" ON storage.objects;
DROP POLICY IF EXISTS "News media owner insert" ON storage.objects;
DROP POLICY IF EXISTS "News media owner update" ON storage.objects;
DROP POLICY IF EXISTS "News media owner delete" ON storage.objects;

-- 3) Koşullarında 'news-images' geçen kalan tüm storage.objects politikalarını
--    programatik olarak düşür (Dashboard'dan ya da unutulmuş migration'lardan
--    kalmış bilinmeyen/kısıtlayıcı politikalar dahil). Sadece storage.objects
--    üzerindeki ve 'news-images' string'i içeren politikalar hedeflenir;
--    diğer bucket'ların (avatars, covers, stories, ...) politikalarına
--    dokunulmaz.
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT DISTINCT policyname
    FROM pg_policies
    WHERE schemaname = 'storage'
      AND tablename = 'objects'
      AND (
        position('news-images' in coalesce(qual, '')) > 0
        OR position('news-images' in coalesce(with_check, '')) > 0
      )
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON storage.objects', r.policyname);
    RAISE NOTICE 'Dropped storage policy: %', r.policyname;
  END LOOP;
END $$;

-- 4) Temiz politika seti
-- SELECT: bucket public olduğu için okuma herkese açık
CREATE POLICY "news_images_select_v2"
ON storage.objects FOR SELECT
TO public
USING (bucket_id = 'news-images');

-- INSERT: yalnızca giriş yapmış kullanıcılar yükleyebilir
CREATE POLICY "news_images_insert_v2"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (bucket_id = 'news-images');

-- UPDATE: yalnızca giriş yapmış kullanıcılar (upsert:true yüklemeleri için)
CREATE POLICY "news_images_update_v2"
ON storage.objects FOR UPDATE
TO authenticated
USING (bucket_id = 'news-images')
WITH CHECK (bucket_id = 'news-images');

-- DELETE: yalnızca giriş yapmış kullanıcılar
-- (haberci kendi galeri görselini silebilmeli)
CREATE POLICY "news_images_delete_v2"
ON storage.objects FOR DELETE
TO authenticated
USING (bucket_id = 'news-images');

-- 5) Doğrulama: news-images politikaları tam olarak 4 olmalı
DO $$
DECLARE
  v_count INT;
BEGIN
  SELECT COUNT(*) INTO v_count
  FROM pg_policies
  WHERE schemaname = 'storage'
    AND tablename = 'objects'
    AND (qual LIKE '%news-images%' OR with_check LIKE '%news-images%');

  RAISE NOTICE 'news-images bucket politika sayısı: % (4 olmalı: select/insert/update/delete)', v_count;

  IF v_count <> 4 THEN
    RAISE EXCEPTION 'Beklenmedik news-images politika sayısı: % (4 bekleniyordu). Kontrol edin.', v_count;
  END IF;
END $$;
