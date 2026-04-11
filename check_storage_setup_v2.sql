-- =====================================================
-- STORAGE BUCKETS VE POLICIES KONTROL SQL v2
-- =====================================================

-- 1. Mevcut storage buckets
SELECT 
    id, 
    name, 
    public,
    created_at,
    file_size_limit,
    allowed_mime_types
FROM storage.buckets
ORDER BY name;

-- 2. Storage objects sayısı (bucketlara göre)
SELECT 
    bucket_id,
    COUNT(*) as file_count
FROM storage.objects
GROUP BY bucket_id
ORDER BY bucket_id;

-- 3. Storage folder yapısı kontrolü
SELECT 
    bucket_id,
    substring(name from '^(?:[^/]+/){0,2}[^/]*') as folder,
    COUNT(*) as file_count
FROM storage.objects
GROUP BY bucket_id, folder
ORDER BY bucket_id, folder;

-- 4. MIME type kontrolü
SELECT 
    COALESCE(metadata->>'mimetype', 'unknown') as mime_type,
    COUNT(*) as count
FROM storage.objects
GROUP BY mime_type
ORDER BY count DESC;

-- 5. RLS policies kontrolü (storage.objects tablosu için)
SELECT 
    policyname,
    permissive,
    roles,
    cmd,
    qual,
    with_check
FROM pg_policies
WHERE schemaname = 'storage' AND tablename = 'objects'
ORDER BY policyname;
