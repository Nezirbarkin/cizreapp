-- Category Images Storage Bucket
-- Kategori resimleri için Supabase Storage bucket'ı

-- Bucket oluştur
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'category-images',
  'category-images',
  true,
  2097152, -- 2MB limit
  ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/gif']
) ON CONFLICT (id) DO NOTHING;

-- Mevcut policy'leri sil (varsa)
DROP POLICY IF EXISTS "Kategori resimleri herkese açık" ON storage.objects;
DROP POLICY IF EXISTS "Sadece adminler kategori resmi yükleyebilir" ON storage.objects;
DROP POLICY IF EXISTS "Sadece adminler kategori resmi güncelleyebilir" ON storage.objects;
DROP POLICY IF EXISTS "Sadece adminler kategori resmi silebilir" ON storage.objects;

-- Kullanıcılar herkes resimleri görebilir
CREATE POLICY "Kategori resimleri herkese açık"
ON storage.objects FOR SELECT
TO public
USING (bucket_id = 'category-images');

-- Sadece adminler resim yükleyebilir
CREATE POLICY "Sadece adminler kategori resmi yükleyebilir"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'category-images' AND
  EXISTS (
    SELECT 1 FROM profiles
    WHERE id = auth.uid() AND role = 'admin'
  )
);

-- Sadece adminler resimleri güncelleyebilir
CREATE POLICY "Sadece adminler kategori resmi güncelleyebilir"
ON storage.objects FOR UPDATE
TO authenticated
USING (
  bucket_id = 'category-images' AND
  EXISTS (
    SELECT 1 FROM profiles
    WHERE id = auth.uid() AND role = 'admin'
  )
)
WITH CHECK (
  bucket_id = 'category-images' AND
  EXISTS (
    SELECT 1 FROM profiles
    WHERE id = auth.uid() AND role = 'admin'
  )
);

-- Sadece adminler resimleri silebilir
CREATE POLICY "Sadece adminler kategori resmi silebilir"
ON storage.objects FOR DELETE
TO authenticated
USING (
  bucket_id = 'category-images' AND
  EXISTS (
    SELECT 1 FROM profiles
    WHERE id = auth.uid() AND role = 'admin'
  )
);
