-- =============================================================================
-- DOSYA: supabase/migrations/20260815000001_fix_stories_storage_rls.sql
-- AMAÇ: stories bucket'ında authenticated kullanıcıların story yüklerken aldığı
--       403 "new row violates row-level security policy" hatasını düzeltmek ve
--       storage RLS politikalarını tutarlı hale getirmek.
-- TARİH: 2026-08-13
--
-- TEŞHİS:
--   * stories bucket mevcut, public=true, file_size_limit/allowed_mime_types
--     boş → 403 MIME/boyut kaynaklı değil, saf RLS reddi.
--   * Anon anahtarla stories bucket'a upload BAŞARILI oluyor; buna karşın
--     authenticated kullanıcı 403 alıyor. Bu, production'da stories bucket'ına
--     atıf yapan çakışan/eski politikalara işaret ediyor (anon'a açık bir
--     INSERT politikası + authenticated'ı reddeden kısıtlayıcı bir politika
--     bir arada yaşayabilir; RESTRICTIVE politikalar PERMISSIVE'lerle AND'lenir
--     ve authenticated yükleme path'ini bloke eder).
--
-- ÇÖZÜM:
--   1) storage.objects üzerinde stories bucket'ına atıfta bulunan TÜM
--      politikaları kaldır (bilinen eski isimler + koşullarında 'stories'
--      geçen bilinmeyen politikalar dahil).
--   2) Temiz ve minimal 4 politika oluştur:
--      - SELECT → public            (story'ler herkese görünür, bucket public)
--      - INSERT → authenticated     (giriş yapmış kullanıcı yükler)
--      - UPDATE → authenticated     (upsert:true yüklemeleri için)
--      - DELETE → authenticated
--   İstemci (StoryService/SocialScreen) path'lerinde auth.uid() öneki
--   kullanmadığı için klasör-bazlı sahiplik kısıtı eklenmedi; dosya adları
--   story_{userId}_{timestamp}.{ext} formatında zaten tekil.
-- =============================================================================

-- 1) Bucket'ın varlığını ve public bayrağını garanti et
INSERT INTO storage.buckets (id, name, public)
VALUES ('stories', 'stories', true)
ON CONFLICT (id) DO UPDATE SET public = true;

-- 2) Bilinen eski politika isimlerini düşür (idempotent)
DROP POLICY IF EXISTS "Story bucket upload policy"       ON storage.objects;
DROP POLICY IF EXISTS "Story bucket public read policy"  ON storage.objects;
DROP POLICY IF EXISTS "Story bucket delete policy"       ON storage.objects;
DROP POLICY IF EXISTS "Users can upload stories"         ON storage.objects;
DROP POLICY IF EXISTS "Users can view stories"           ON storage.objects;
DROP POLICY IF EXISTS "Users can delete own stories"     ON storage.objects;
DROP POLICY IF EXISTS "stories_upload_policy"            ON storage.objects;
DROP POLICY IF EXISTS "stories_select_policy"            ON storage.objects;
DROP POLICY IF EXISTS "stories_delete_policy"            ON storage.objects;
DROP POLICY IF EXISTS "stories_upload_new"               ON storage.objects;
DROP POLICY IF EXISTS "stories_select_new"               ON storage.objects;
DROP POLICY IF EXISTS "stories_update_new"               ON storage.objects;
DROP POLICY IF EXISTS "stories_delete_new"               ON storage.objects;
DROP POLICY IF EXISTS "stories_select_v2"                ON storage.objects;
DROP POLICY IF EXISTS "stories_insert_v2"                ON storage.objects;
DROP POLICY IF EXISTS "stories_update_v2"                ON storage.objects;
DROP POLICY IF EXISTS "stories_delete_v2"                ON storage.objects;

-- 3) Koşullarında 'stories' geçen kalan tüm storage.objects politikalarını
--    programatik olarak düşür (Dashboard'dan ya da unutulmuş migration'lardan
--    kalmış bilinmeyen/kısıtlayıcı politikalar dahil). Sadece storage.objects
--    üzerindeki ve 'stories' kelimesi içeren politikalar hedeflenir; diğer
--    bucket'ların (avatars, covers, news-images, ...) politikalarına
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
        position('stories' in coalesce(qual, '')) > 0
        OR position('stories' in coalesce(with_check, '')) > 0
      )
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON storage.objects', r.policyname);
    RAISE NOTICE 'Dropped storage policy: %', r.policyname;
  END LOOP;
END $$;

-- 4) Temiz politika seti
-- SELECT: bucket public olduğu için okuma herkese açık
CREATE POLICY "stories_select_v2"
ON storage.objects FOR SELECT
TO public
USING (bucket_id = 'stories');

-- INSERT: yalnızca giriş yapmış kullanıcılar yükleyebilir
-- (anon yüklemesini de kapatır → mevcut açık kapanır)
CREATE POLICY "stories_insert_v2"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (bucket_id = 'stories');

-- UPDATE: yalnızca giriş yapmış kullanıcılar (upsert:true yüklemeleri için)
CREATE POLICY "stories_update_v2"
ON storage.objects FOR UPDATE
TO authenticated
USING (bucket_id = 'stories')
WITH CHECK (bucket_id = 'stories');

-- DELETE: yalnızca giriş yapmış kullanıcılar
CREATE POLICY "stories_delete_v2"
ON storage.objects FOR DELETE
TO authenticated
USING (bucket_id = 'stories');

-- 5) Doğrulama (rapor amaçlı): stories politikaları listelenmeli
DO $$
DECLARE
  v_count INT;
BEGIN
  SELECT COUNT(*) INTO v_count
  FROM pg_policies
  WHERE schemaname = 'storage'
    AND tablename = 'objects'
    AND (qual LIKE '%stories%' OR with_check LIKE '%stories%');

  RAISE NOTICE 'stories bucket politika sayısı: % (4 olmalı: select/insert/update/delete)', v_count;

  IF v_count <> 4 THEN
    RAISE EXCEPTION 'Beklenmedik stories politika sayısı: % (4 bekleniyordu). Kontrol edin.', v_count;
  END IF;
END $$;
