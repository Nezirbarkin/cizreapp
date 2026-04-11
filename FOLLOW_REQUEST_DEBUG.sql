-- =====================================================
-- TAKİP İSTEĞİ ONAYLAMA SİSTEMİ KONTROLÜ
-- =====================================================

-- 1. follow_requests tablosu yapısı
SELECT 
    column_name,
    data_type,
    is_nullable
FROM information_schema.columns
WHERE table_schema = 'public' 
AND table_name = 'follow_requests'
ORDER BY column_name;

-- 2. follow_requests trigger'ları
SELECT 
    trigger_name,
    event_manipulation,
    action_timing,
    action_statement
FROM information_schema.triggers
WHERE event_object_table = 'follow_requests'
AND trigger_schema = 'public'
ORDER BY trigger_name;

-- 3. Son 10 takip isteği
SELECT 
    id,
    follower_id,
    following_id,
    status,
    created_at,
    updated_at
FROM follow_requests
ORDER BY created_at DESC
LIMIT 10;

-- 4. follows tablosu trigger'ları (onaylandığında buraya da kayıt atılmalı)
SELECT 
    trigger_name,
    event_manipulation,
    action_statement
FROM information_schema.triggers
WHERE event_object_table = 'follows'
AND trigger_schema = 'public'
ORDER BY trigger_name;

-- 5. Onaylanmış istekler
SELECT 
    id,
    follower_id,
    following_id,
    status,
    updated_at
FROM follow_requests
WHERE status = 'accepted'
ORDER BY updated_at DESC
LIMIT 10;
