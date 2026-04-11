-- Storage RLS Debug - Permissions ve Policies Kontrol

-- Test 1: Tüm storage policies'leri listele
SELECT 
  policyname,
  permissive,
  cmd,
  roles,
  qual
FROM pg_policies 
WHERE schemaname = 'storage' 
AND tablename = 'objects'
ORDER BY policyname;

-- Test 2: Auth role'ün izinlerini kontrol et
SELECT * FROM pg_roles WHERE rolname = 'authenticated';

-- Test 3: Bucket'ı kontrol et
SELECT 
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
FROM storage.buckets 
WHERE name = 'shop-images';
