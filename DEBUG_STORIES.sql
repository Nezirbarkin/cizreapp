-- Story'lerin durumunu kontrol etmek için debug sorguları

-- 1. Tüm aktif story'leri göster (son 24 saat)
SELECT 
    s.id,
    s.user_id,
    p.username,
    p.full_name,
    s.media_type,
    s.views_count,
    s.created_at,
    s.expires_at,
    CASE 
        WHEN s.expires_at > NOW() THEN 'AKTİF'
        ELSE 'SÜRESİ DOLMUŞ'
    END as durum,
    EXTRACT(EPOCH FROM (s.expires_at - NOW()))/3600 as kalan_saat
FROM stories s
LEFT JOIN profiles p ON s.user_id = p.id
ORDER BY s.created_at DESC;

-- 2. Kullanıcıya göre story sayısı
SELECT 
    p.username,
    p.full_name,
    COUNT(s.id) as toplam_story,
    COUNT(CASE WHEN s.expires_at > NOW() THEN 1 END) as aktif_story
FROM profiles p
LEFT JOIN stories s ON p.id = s.user_id
GROUP BY p.id, p.username, p.full_name
HAVING COUNT(s.id) > 0
ORDER BY aktif_story DESC;

-- 3. Son eklenen 10 story
SELECT 
    s.id,
    p.username,
    s.media_type,
    s.created_at,
    s.expires_at,
    CASE 
        WHEN s.expires_at > NOW() THEN '✓ AKTİF'
        ELSE '✗ SÜRESİ DOLMUŞ'
    END as durum
FROM stories s
LEFT JOIN profiles p ON s.user_id = p.id
ORDER BY s.created_at DESC
LIMIT 10;

-- 4. Story görüntülenme istatistikleri
SELECT 
    s.id,
    p.username as hikaye_sahibi,
    s.media_type,
    COUNT(sv.id) as goruntuleme_sayisi,
    s.created_at
FROM stories s
LEFT JOIN profiles p ON s.user_id = p.id
LEFT JOIN story_views sv ON s.id = sv.story_id
WHERE s.expires_at > NOW()
GROUP BY s.id, p.username, s.media_type, s.created_at
ORDER BY goruntuleme_sayisi DESC;

-- 5. Belirli bir kullanıcının story'lerini göster (user_id'yi değiştirin)
-- SELECT 
--     s.id,
--     s.media_type,
--     s.created_at,
--     s.expires_at,
--     CASE 
--         WHEN s.expires_at > NOW() THEN 'AKTİF'
--         ELSE 'SÜRESİ DOLMUŞ'
--     END as durum
-- FROM stories s
-- WHERE s.user_id = 'KULLANICI_ID_BURAYA'
-- ORDER BY s.created_at DESC;

-- 6. RLS Policy kontrolü
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
WHERE tablename = 'stories';

-- 7. Süresi dolmuş story'leri temizle (opsiyonel - dikkatli kullanın!)
-- DELETE FROM stories WHERE expires_at < NOW();

-- 8. Story tablosu yapısını kontrol et
SELECT 
    column_name,
    data_type,
    is_nullable,
    column_default
FROM information_schema.columns
WHERE table_name = 'stories'
ORDER BY ordinal_position;
