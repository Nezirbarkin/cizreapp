-- =============================================================================
-- 20260719000004_task_images.sql
-- Admin görev oluştururken açıklamaya görsel yükleyebilmesi için:
-- 1) tasks tablosuna image_url alanı
-- 2) task_images storage bucket (RLS: SELECT public, INSERT/UPDATE admin, DELETE admin/sahip)
--
-- Görsel yalnızca admin yüklüyorsa bucket yetkisi auth.uid()=admin klasörü yeterli;
-- basitlik için yükleme yetkisi authenticated + RLS'ye bırakıyoruz.
-- =============================================================================

SET search_path = public, pg_temp;

-- 1) tasks.image_url alanı (nullable — görsel opsiyonel)
ALTER TABLE public.tasks
  ADD COLUMN IF NOT EXISTS image_url TEXT;

COMMENT ON COLUMN public.tasks.image_url IS
  'Admin tarafından yüklenen görev açıklama görseli (public URL). NULL olabilir.';

-- 2) task_images storage bucket
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'task_images',
  'task_images',
  TRUE,
  5242880,  -- 5 MB
  ARRAY['image/jpeg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO UPDATE
  SET name       = EXCLUDED.name,
      public     = EXCLUDED.public,
      file_size_limit = EXCLUDED.file_size_limit,
      allowed_mime_types = EXCLUDED.allowed_mime_types;

-- 3) RLS — storage.objects için task_images bucket
-- SELECT public (herkes görüntüleyebilir — kullanıcılar admin görsellerini görür)
DROP POLICY IF EXISTS "task_images_select" ON storage.objects;
CREATE POLICY "task_images_select" ON storage.objects
  FOR SELECT
  USING (bucket_id = 'task_images');

-- INSERT/UPDATE/DELETE: yalnız admin
-- Admin kontrolü: profiles tablosunda role='admin'
DROP POLICY IF EXISTS "task_images_insert_admin" ON storage.objects;
CREATE POLICY "task_images_insert_admin" ON storage.objects
  FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'task_images'
    AND EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin')
  );

DROP POLICY IF EXISTS "task_images_update_admin" ON storage.objects;
CREATE POLICY "task_images_update_admin" ON storage.objects
  FOR UPDATE
  TO authenticated
  USING (
    bucket_id = 'task_images'
    AND EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin')
  );

DROP POLICY IF EXISTS "task_images_delete_admin" ON storage.objects;
CREATE POLICY "task_images_delete_admin" ON storage.objects
  FOR DELETE
  TO authenticated
  USING (
    bucket_id = 'task_images'
    AND EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin')
  );

-- 4) get_active_tasks ve admin görüntülemede image_url zaten tasks tablosundan gelir
--    (kolon otomatik select'lerle geliyor — RPC RETURNS TABLE'ı genişletmek gerekiyor)
-- → Migration 5'te RPC signature güncellemesi yapacağız.

NOTIFY pgrst, 'reload schema';

DO $$ BEGIN
  RAISE NOTICE '✅ 20260719000004_task_images.sql — tasks.image_url + task_images bucket + RLS';
END $$;