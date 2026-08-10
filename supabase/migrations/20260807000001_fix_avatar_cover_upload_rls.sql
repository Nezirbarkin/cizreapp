-- =============================================================================
-- DOSYA: supabase/migrations/20260807000001_fix_avatar_cover_upload_rls.sql
-- AMAÇ: avatars ve covers bucket'larında authenticated kullanıcıların
--       kendi userId öneki ile dosya yüklemesini garanti altına al.
-- TARİH: 2026-08-07
-- UYGULAMA: Supabase Dashboard > SQL Editor veya supabase db push
--
-- SORUN:
--   20260206000001_create_avatar_cover_buckets.sql'deki INSERT policy yalnız
--   `bucket_id` kontrol ediyor; dosya yolunun kullanıcıya ait olup olmadığına
--   bakmıyor. Flutter istemcisinde `uploadBinary(upsert:true)` ile yapılan
--   çağrılar 403 "new row violates row-level security policy" alabiliyor.
--   Bunun başlıca nedenleri:
--     a) bucket allowed_mime_types / file_size_limit eşleşmiyor olabilir
--     b) auth.uid() NULL ise anon rolü ile INSERT deneniyor olabilir
--     c) önceki nesne varken UPDATE tetikleniyor, UPDATE policy'si USING
--        bucket_id ile filtreliyor ama dosya sahipliği kontrolü yok
--
-- ÇÖZÜM:
--   1) Bucket'ların allowed_mime_types/file_size_limit değerlerini sabitle.
--   2) INSERT policy'yi path öneki (avatar_/cover_ + auth.uid()) ile sıkılaştır.
--   3) UPDATE/DELETE policy'lerini de aynı path öneki ile sınıfla.
--   4) Mevcut policy'leri DROP + CREATE ile idempotent hale getir.
-- =============================================================================

-- 1) BUCKET TANIMLARINI SABİTLE
-- ----------------------------------------------------------------------------
-- ON CONFLICT ile mevcut bucket'ların file_size_limit ve allowed_mime_types
-- alanlarını günceller; yoksa oluşturur. Authenticated kullanıcının yükleme
-- başarısızlığının en sık nedenlerinden biri mime/limit uyumsuzluğudur.

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'avatars',
  'avatars',
  TRUE,
  5242880, -- 5 MB
  ARRAY['image/jpeg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO UPDATE SET
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'covers',
  'covers',
  TRUE,
  10485760, -- 10 MB
  ARRAY['image/jpeg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO UPDATE SET
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

-- 2) AVATARS POLİTİKALARI (sıkılaştırılmış)
-- ----------------------------------------------------------------------------
-- Eski policy'leri temizle (isim çakışmasını önler; idempotent).
DROP POLICY IF EXISTS "avatar_select_policy"  ON storage.objects;
DROP POLICY IF EXISTS "avatar_insert_policy"  ON storage.objects;
DROP POLICY IF EXISTS "avatar_update_policy"  ON storage.objects;
DROP POLICY IF EXISTS "avatar_delete_policy"  ON storage.objects;
DROP POLICY IF EXISTS "Avatars are publicly accessible"            ON storage.objects;
DROP POLICY IF EXISTS "Users can upload their own avatar"          ON storage.objects;
DROP POLICY IF EXISTS "Users can update their own avatar"          ON storage.objects;
DROP POLICY IF EXISTS "Users can delete their own avatar"          ON storage.objects;

-- SELECT: public bucket — herkes okuyabilir (profil avatarları public)
CREATE POLICY "avatar_select_policy"
ON storage.objects FOR SELECT
USING (bucket_id = 'avatars');

-- INSERT: yalnızca authenticated ve dosya yolu 'avatar_' + auth.uid() ile
-- başlamalı. Bu, bir kullanıcının başkasının userId'i adına dosya yazmasını
-- engeller.
CREATE POLICY "avatar_insert_policy"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'avatars'
  AND auth.uid() IS NOT NULL
  AND (storage.foldername(name))[1] = 'avatars'
  AND name LIKE ('avatar_' || auth.uid()::text || '-%')
);

-- UPDATE: yalnızca kendi yolu
CREATE POLICY "avatar_update_policy"
ON storage.objects FOR UPDATE
TO authenticated
USING (
  bucket_id = 'avatars'
  AND name LIKE ('avatar_' || auth.uid()::text || '-%')
)
WITH CHECK (
  bucket_id = 'avatars'
  AND name LIKE ('avatar_' || auth.uid()::text || '-%')
);

-- DELETE: yalnızca kendi yolu
CREATE POLICY "avatar_delete_policy"
ON storage.objects FOR DELETE
TO authenticated
USING (
  bucket_id = 'avatars'
  AND name LIKE ('avatar_' || auth.uid()::text || '-%')
);

-- 3) COVERS POLİTİKALARI (sıkılaştırılmış)
-- ----------------------------------------------------------------------------
DROP POLICY IF EXISTS "cover_select_policy"   ON storage.objects;
DROP POLICY IF EXISTS "cover_insert_policy"   ON storage.objects;
DROP POLICY IF EXISTS "cover_update_policy"   ON storage.objects;
DROP POLICY IF EXISTS "cover_delete_policy"   ON storage.objects;
DROP POLICY IF EXISTS "Covers are publicly accessible"              ON storage.objects;
DROP POLICY IF EXISTS "Users can upload their own cover"            ON storage.objects;
DROP POLICY IF EXISTS "Users can update their own cover"            ON storage.objects;
DROP POLICY IF EXISTS "Users can delete their own cover"            ON storage.objects;

CREATE POLICY "cover_select_policy"
ON storage.objects FOR SELECT
USING (bucket_id = 'covers');

CREATE POLICY "cover_insert_policy"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'covers'
  AND auth.uid() IS NOT NULL
  AND (storage.foldername(name))[1] = 'covers'
  AND name LIKE ('cover_' || auth.uid()::text || '-%')
);

CREATE POLICY "cover_update_policy"
ON storage.objects FOR UPDATE
TO authenticated
USING (
  bucket_id = 'covers'
  AND name LIKE ('cover_' || auth.uid()::text || '-%')
)
WITH CHECK (
  bucket_id = 'covers'
  AND name LIKE ('cover_' || auth.uid()::text || '-%')
);

CREATE POLICY "cover_delete_policy"
ON storage.objects FOR DELETE
TO authenticated
USING (
  bucket_id = 'covers'
  AND name LIKE ('cover_' || auth.uid()::text || '-%')
);

-- 4) ADMİN BYPASS: tüm storage.objects üzerinde admin rolü tam erişim
-- ----------------------------------------------------------------------------
-- Profil/avatar/cover silme veya temizlik operasyonları için admin rolündeki
-- kullanıcıların tüm bucket'larda işlem yapabilmesini sağlar. Mevcut
-- admin_all politikası yoksa ekle, varsa dokunma.
DROP POLICY IF EXISTS "storage_admin_all_avatars_covers" ON storage.objects;
CREATE POLICY "storage_admin_all_avatars_covers"
ON storage.objects FOR ALL
TO authenticated
USING (
  bucket_id IN ('avatars', 'covers')
  AND EXISTS (
    SELECT 1 FROM profiles
    WHERE id = auth.uid() AND role = 'admin'
  )
)
WITH CHECK (
  bucket_id IN ('avatars', 'covers')
  AND EXISTS (
    SELECT 1 FROM profiles
    WHERE id = auth.uid() AND role = 'admin'
  )
);

-- 5) DOĞRULAMA SORGUSU (rapor amaçlı)
-- ----------------------------------------------------------------------------
-- Bu sorgular elle çalıştırıldığında:
--   - bucket id'ler: avatars, covers
--   - policy isimleri: avatar_*/cover_*_policy
--   - file_size_limit ve allowed_mime_types dolu olmalı
DO $$
DECLARE
  v_avatars RECORD;
  v_covers  RECORD;
  v_av_count INT;
  v_cv_count INT;
BEGIN
  SELECT * INTO v_avatars FROM storage.buckets WHERE id = 'avatars';
  SELECT * INTO v_covers  FROM storage.buckets WHERE id = 'covers';

  IF v_avatars.id IS NULL THEN
    RAISE EXCEPTION 'avatars bucket bulunamadı!';
  END IF;
  IF v_covers.id IS NULL THEN
    RAISE EXCEPTION 'covers bucket bulunamadı!';
  END IF;

  SELECT COUNT(*) INTO v_av_count FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects'
      AND policyname LIKE 'avatar_%_policy';
  SELECT COUNT(*) INTO v_cv_count FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects'
      AND policyname LIKE 'cover_%_policy';

  RAISE NOTICE 'avatars bucket: file_size_limit=%, mimes=%',
    v_avatars.file_size_limit, v_avatars.allowed_mime_types;
  RAISE NOTICE 'covers bucket:  file_size_limit=%, mimes=%',
    v_covers.file_size_limit, v_covers.allowed_mime_types;
  RAISE NOTICE 'avatar policy sayısı: % (4 olmalı: select/insert/update/delete)', v_av_count;
  RAISE NOTICE 'cover policy sayısı:  % (4 olmalı: select/insert/update/delete)', v_cv_count;
END $$;

SELECT 'avatar/cover storage RLS sıkılaştırma tamamlandı.' AS status;
