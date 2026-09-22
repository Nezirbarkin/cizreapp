-- Ürün Görsel Kütüphanesi Storage Bucket
-- category-images bucket'ının (20260213000001) aynı deseni; tek fark admin
-- kontrolünde inline EXISTS yerine kanonik public.auth_is_admin() kullanılması
-- (bkz. 20260809000001_fix_auth_is_admin_security_definer.sql).

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'product-image-presets',
  'product-image-presets',
  true,
  2097152, -- 2MB limit
  ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/gif']
) ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "Ürün görsel kütüphanesi herkese açık" ON storage.objects;
DROP POLICY IF EXISTS "Sadece adminler kütüphaneye görsel yükleyebilir" ON storage.objects;
DROP POLICY IF EXISTS "Sadece adminler kütüphane görselini güncelleyebilir" ON storage.objects;
DROP POLICY IF EXISTS "Sadece adminler kütüphane görselini silebilir" ON storage.objects;

CREATE POLICY "Ürün görsel kütüphanesi herkese açık"
ON storage.objects FOR SELECT
TO public
USING (bucket_id = 'product-image-presets');

CREATE POLICY "Sadece adminler kütüphaneye görsel yükleyebilir"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'product-image-presets' AND public.auth_is_admin()
);

CREATE POLICY "Sadece adminler kütüphane görselini güncelleyebilir"
ON storage.objects FOR UPDATE
TO authenticated
USING (
  bucket_id = 'product-image-presets' AND public.auth_is_admin()
)
WITH CHECK (
  bucket_id = 'product-image-presets' AND public.auth_is_admin()
);

CREATE POLICY "Sadece adminler kütüphane görselini silebilir"
ON storage.objects FOR DELETE
TO authenticated
USING (
  bucket_id = 'product-image-presets' AND public.auth_is_admin()
);
