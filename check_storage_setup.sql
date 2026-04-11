-- =====================================================
-- STORAGE BUCKETS VE POLICIES KONTROL SQL
-- =====================================================

-- 1. Mevcut storage buckets
SELECT 
    id, 
    name, 
    public,
    created_at,
    updated_at,
    file_size_limit,
    allowed_mime_types
FROM storage.buckets
ORDER BY name;

-- 2. Storage policies (tüm bucketlar için)
SELECT 
    policys.id,
    buckets.name as bucket_name,
    policys.name,
    policys.definition,
    policys.action,
    policys.created_at
FROM storage.policys
JOIN storage.buckets ON storage.policys.bucket_id = storage.buckets.id
ORDER BY buckets.name, policys.name;

-- 3. RLS policies kontrolü (storage.objects tablosu)
SELECT 
    schemaname,
    tablename,
    policyname,
    permissive,
    roles,
    cmd,
    qual,
    with_check
FROM pg_policies
WHERE tablename = 'objects'
ORDER BY policyname;

-- 4. Storage folder yapısı kontrolü
SELECT 
    substring(name from '^(?:[^/]+/){1}[^/]*') as folder,
    COUNT(*) as file_count,
    SUM(COALESCE(metadata->>'size', '0')::bigint) as total_size
FROM storage.objects
GROUP BY folder
ORDER BY folder;

-- 5. MIME type kontrolü
SELECT 
    COALESCE(metadata->>'mimetype', 'unknown') as mime_type,
    COUNT(*) as count
FROM storage.objects
GROUP BY mime_type
ORDER BY count DESC;
