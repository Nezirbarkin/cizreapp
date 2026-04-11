-- shop-images bucket için tüm RLS policy'leri sıfırla
-- Tüm storage.objects policy'lerini temizle

-- shop-images bucket'ına ait tüm policy'leri kaldır (isim farketmeksizin)
DO $$
DECLARE
    policy_record RECORD;
BEGIN
    -- shop-images bucket'ına ait policy'leri bul ve sil
    FOR policy_record IN 
        SELECT policyname 
        FROM pg_policies 
        WHERE schemaname = 'storage' 
        AND tablename = 'objects'
        AND policyname LIKE '%shop%' OR policyname LIKE '%image%' OR policyname LIKE '%upload%'
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON storage.objects', policy_record.policyname);
    END LOOP;
END $$;

-- Yeni policy'leri oluştur

-- 1. INSERT policy - Kullanıcılar kendi klasörüne yükleyebilir
CREATE POLICY "Users can upload to own folder"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'shop-images' AND 
  (auth.uid())::text = split_part(name, '/', 1)
);

-- 2. SELECT policy - Herkes görebilir
CREATE POLICY "Public view shop images"
ON storage.objects FOR SELECT
TO public
USING (bucket_id = 'shop-images');

-- 3. UPDATE policy - Kullanıcı kendi dosyalarını güncelleyebilir
CREATE POLICY "Users update own shop images"
ON storage.objects FOR UPDATE
TO authenticated
USING (
  bucket_id = 'shop-images' AND 
  (auth.uid())::text = split_part(name, '/', 1)
)
WITH CHECK (
  bucket_id = 'shop-images' AND 
  (auth.uid())::text = split_part(name, '/', 1)
);

-- 4. DELETE policy - Kullanıcı kendi dosyalarını silebilir
CREATE POLICY "Users delete own shop images"
ON storage.objects FOR DELETE
TO authenticated
USING (
  bucket_id = 'shop-images' AND 
  (auth.uid())::text = split_part(name, '/', 1)
);

-- Bilgi
SELECT 'Shop images RLS policies reset complete!' as status;
