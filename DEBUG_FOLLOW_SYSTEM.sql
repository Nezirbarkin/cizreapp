-- =====================================================
-- GİZLİ HESAP TAKİP SİSTEMİ DİAGNOSTİK SQL
-- =====================================================
-- Bu SQL dosyası şu sorunları araştırır:
-- 1. Gizli hesap takip isteği kabul edildiğinde follows tablosuna ekleniyor mu?
-- 2. Follow_requests tablosunda 'accepted' durumundaki kayıtlar follows'ta var mı?
-- 3. Arkadaş sayısı hesaplaması doğru çalışıyor mu?
-- =====================================================

-- =====================================================
-- 1. TABLO YAPILARINI KONTROL ET
-- =====================================================

-- 1.1 follow_requests tablosu yapısı
SELECT 
    column_name,
    data_type,
    is_nullable,
    column_default
FROM information_schema.columns
WHERE table_schema = 'public'
AND table_name = 'follow_requests'
ORDER BY ordinal_position;

-- 1.2 follows tablosu yapısı
SELECT 
    column_name,
    data_type,
    is_nullable,
    column_default
FROM information_schema.columns
WHERE table_schema = 'public'
AND table_name = 'follows'
ORDER BY ordinal_position;

-- 1.3 profiles tablosunda profile_is_public kolonu var mı?
SELECT 
    column_name,
    data_type,
    column_default
FROM information_schema.columns
WHERE table_schema = 'public'
AND table_name = 'profiles'
AND column_name = 'profile_is_public';

-- =====================================================
-- 2. TRIGGER VE FONKSİYONLARI KONTROL ET
-- =====================================================

-- 2.1 follow_requests trigger'ları
SELECT 
    trigger_name,
    event_manipulation,
    action_statement,
    action_timing
FROM information_schema.triggers
WHERE event_object_table = 'follow_requests'
AND trigger_schema = 'public'
ORDER BY trigger_name;

-- 2.2 follows trigger'ları
SELECT 
    trigger_name,
    event_manipulation,
    action_statement,
    action_timing
FROM information_schema.triggers
WHERE event_object_table = 'follows'
AND trigger_schema = 'public'
ORDER BY trigger_name;

-- 2.3 upsert_follow_request fonksiyonu var mı?
SELECT 
    routine_name,
    routine_type
FROM information_schema.routines
WHERE routine_schema = 'public'
AND routine_name LIKE '%follow%';

-- =====================================================
-- 3. VERİ TUTARLILIK KONTROLLERİ
-- =====================================================

-- 3.1 Toplam kayıt sayıları
SELECT 
    'follow_requests' as table_name,
    COUNT(*) as total_records,
    COUNT(*) FILTER (WHERE status = 'pending') as pending,
    COUNT(*) FILTER (WHERE status = 'accepted') as accepted,
    COUNT(*) FILTER (WHERE status = 'rejected') as rejected
FROM follow_requests

UNION ALL

SELECT 
    'follows' as table_name,
    COUNT(*) as total_records,
    0 as pending,
    0 as accepted,
    0 as rejected
FROM follows;

-- 3.2 KRİTİK SORUN: accepted istekler follows tablosunda yok mu?
SELECT 
    fr.id as request_id,
    fr.follower_id,
    fr.following_id,
    fr.status,
    fr.created_at,
    CASE 
        WHEN f.id IS NULL THEN 'EXIK!'
        ELSE 'Var'
    END as follows_status
FROM follow_requests fr
LEFT JOIN follows f ON 
    f.follower_id = fr.follower_id AND 
    f.following_id = fr.following_id
WHERE fr.status = 'accepted'
ORDER BY fr.created_at DESC
LIMIT 50;

-- 3.3 follow_requests'te var ama follows'ta OLMAYAN accepted kayıtlar
SELECT 
    fr.id as request_id,
    fr.follower_id,
    fr.following_id,
    p1.username as follower_username,
    p2.username as following_username,
    fr.status,
    fr.created_at
FROM follow_requests fr
INNER JOIN profiles p1 ON p1.id = fr.follower_id
INNER JOIN profiles p2 ON p2.id = fr.following_id
LEFT JOIN follows f ON 
    f.follower_id = fr.follower_id AND 
    f.following_id = fr.following_id
WHERE fr.status = 'accepted'
AND f.id IS NULL
ORDER BY fr.created_at DESC;

-- 3.4 Gizli hesap kullanıcıları ve profile_is_public durumu
SELECT 
    id,
    username,
    profile_is_public,
    (SELECT COUNT(*) FROM follows WHERE following_id = profiles.id) as followers_count,
    (SELECT COUNT(*) FROM follows WHERE follower_id = profiles.id) as following_count
FROM profiles
WHERE profile_is_public = false
ORDER BY username
LIMIT 20;

-- =====================================================
-- 4. ARKADAŞ SAYISI HESAPLAMA TESTLERİ
-- =====================================================

-- 4.1 Mevcut friends hesaplama mantığı (Flutter'daki gibi)
WITH user_followers AS (
    SELECT follower_id
    FROM follows
    WHERE following_id = 'TEST_USER_ID' -- Buraya test user ID girin
),
user_following AS (
    SELECT following_id
    FROM follows
    WHERE follower_id = 'TEST_USER_ID' -- Buraya test user ID girin
)
SELECT 
    COUNT(*) as friends_count
FROM user_followers
INTERSECT
SELECT following_id
FROM user_following;

-- 4.2 Eğer follow_requests accepted ise follows'ta olmalı kontrolü
-- (Sorunu gösteren sorgu)
SELECT 
    p.id,
    p.username,
    COUNT(DISTINCT CASE 
        WHEN f1.id IS NOT NULL THEN f1.follower_id 
    END) as actual_followers,
    COUNT(DISTINCT CASE 
        WHEN fr.status = 'accepted' AND f1.id IS NULL THEN fr.follower_id
    END) as missing_followers_in_follows_table,
    COUNT(DISTINCT CASE 
        WHEN fr.status = 'accepted' THEN fr.follower_id
    END) as total_accepted_requests
FROM profiles p
LEFT JOIN follow_requests fr ON 
    fr.following_id = p.id AND 
    fr.status = 'accepted'
LEFT JOIN follows f1 ON 
    f1.follower_id = fr.follower_id AND 
    f1.following_id = p.id
WHERE p.profile_is_public = false
GROUP BY p.id, p.username
HAVING COUNT(DISTINCT CASE 
    WHEN fr.status = 'accepted' AND f1.id IS NULL THEN fr.follower_id
END) > 0
LIMIT 20;

-- =====================================================
-- 5. ÖRNEK KULLANICI İÇİN DETAYLI ANALİZ
-- =====================================================

-- 5.1 Belirli bir kullanıcının takip/takipçi/arkadaş durumunu görüntüle
-- Buraya test etmek istediğiniz user ID'yi yazın:
DO $$
DECLARE
    v_user_id UUID := 'TEST_USER_ID'::UUID; -- Buraya test user ID girin
BEGIN
    RAISE NOTICE '=== KULLANICI ANALİZİ: % ===', v_user_id;
    
    -- Takipçiler
    RAISE NOTICE 'Takipçi Sayısı (follows tablosundan): %',
        (SELECT COUNT(*) FROM follows WHERE following_id = v_user_id);
    
    -- Takip edilenler
    RAISE NOTICE 'Takip Edilen Sayısı (follows tablosundan): %',
        (SELECT COUNT(*) FROM follows WHERE follower_id = v_user_id);
    
    -- Bekleyen istekler
    RAISE NOTICE 'Bekleyen İstek Sayısı: %',
        (SELECT COUNT(*) FROM follow_requests 
         WHERE following_id = v_user_id AND status = 'pending');
    
    -- Kabul edilmiş istekler
    RAISE NOTICE 'Kabul Edilmiş İstek Sayısı: %',
        (SELECT COUNT(*) FROM follow_requests 
         WHERE following_id = v_user_id AND status = 'accepted');
    
    -- Accepted ama follows'ta olmayanlar (SORUN!)
    RAISE NOTICE 'KABUL EDİLMİŞ AMA FOLLOWS TABLOSUNDA OLMAYAN: %',
        (SELECT COUNT(*)
         FROM follow_requests fr
         LEFT JOIN follows f ON f.follower_id = fr.follower_id AND f.following_id = v_user_id
         WHERE fr.following_id = v_user_id 
         AND fr.status = 'accepted' 
         AND f.id IS NULL);
END $$;

-- 5.2 Belirli bir kullanıcının tüm ilişkilerini detaylı görüntüle
SELECT 
    'followers_from_follows' as relationship_type,
    f.follower_id,
    p.username,
    f.created_at
FROM follows f
INNER JOIN profiles p ON p.id = f.follower_id
WHERE f.following_id = 'TEST_USER_ID' -- Buraya test user ID girin

UNION ALL

SELECT 
    'followers_from_accepted_requests' as relationship_type,
    fr.follower_id,
    p.username,
    fr.created_at
FROM follow_requests fr
INNER JOIN profiles p ON p.id = fr.follower_id
LEFT JOIN follows f ON f.follower_id = fr.follower_id AND f.following_id = fr.following_id
WHERE fr.following_id = 'TEST_USER_ID' -- Buraya test user ID girin
AND fr.status = 'accepted'
AND f.id IS NULL -- Sadece follows'ta OLMAYANları göster

ORDER BY created_at DESC;

-- =====================================================
-- 6. DUPLICATE KAYIT KONTROLLERİ
-- =====================================================

-- 6.1 follow_requests duplicate kontrolü
SELECT 
    follower_id,
    following_id,
    COUNT(*) as duplicate_count,
    STRING_AGG(status || ' (' || id::text || ')', ', ') as details
FROM follow_requests
GROUP BY follower_id, following_id
HAVING COUNT(*) > 1
ORDER BY duplicate_count DESC
LIMIT 20;

-- 6.2 follows duplicate kontrolü
SELECT 
    follower_id,
    following_id,
    COUNT(*) as duplicate_count
FROM follows
GROUP BY follower_id, following_id
HAVING COUNT(*) > 1
ORDER BY duplicate_count DESC
LIMIT 20;

-- =====================================================
-- 7. UNIQUE CONSTRAINT KONTROLLERİ
-- =====================================================

-- 7.1 follow_requests unique constraints
SELECT 
    conname as constraint_name,
    pg_get_constraintdef(c.oid) as constraint_definition
FROM pg_constraint c
JOIN pg_namespace n ON n.oid = c.connamespace
WHERE conrelid = 'public.follow_requests'::regclass
AND contype = 'u';

-- 7.2 follows unique constraints
SELECT 
    conname as constraint_name,
    pg_get_constraintdef(c.oid) as constraint_definition
FROM pg_constraint c
JOIN pg_namespace n ON n.oid = c.connamespace
WHERE conrelid = 'public.follows'::regclass
AND contype = 'u';

-- =====================================================
-- KULLANIM TALİMATLARI:
-- =====================================================
-- 
-- 1. Önce tüm sorguları çalıştırın ve sonuçları inceleyin
-- 
-- 2. 3.2 ve 3.3 sorguları en kritik olanlarıdır:
--    - Eğer 'EXIK!' sonuçları görüyorsanız, accepted istekler follows'ta yok demektir
-- 
-- 3. 5.1 ve 5.2 sorgularında TEST_USER_ID yerine gerçek bir kullanıcı ID'si yazın
--    ve detaylı analiz görün
-- 
-- 4. Sonuçları analiz ettikten sonra FIX_FOLLOW_SYSTEM.sql dosyasını çalıştırın
-- =====================================================
