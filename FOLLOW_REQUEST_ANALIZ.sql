-- =====================================================
-- TAKİP İSTEĞİ SİSTEMİ - TAM ANALIZ
-- =====================================================

-- 1. follow_requests tablosu var mı?
SELECT 
    table_name,
    column_name,
    data_type,
    is_nullable
FROM information_schema.columns
WHERE table_schema = 'public' 
AND table_name IN ('follow_requests', 'follows')
ORDER BY table_name, column_name;

-- 2. Takip sistemi ile ilgili tüm trigger'lar
SELECT 
    trigger_name,
    event_object_table,
    event_manipulation,
    action_timing
FROM information_schema.triggers
WHERE trigger_schema = 'public'
AND event_object_table IN ('follow_requests', 'follows', 'notifications')
ORDER BY event_object_table, trigger_name;

-- 3. Son takip istekleri (eğer tablo varsa)
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

-- 4. follows tablosu son kayıtlar
SELECT 
    follower_id,
    following_id,
    created_at
FROM follows
ORDER BY created_at DESC
LIMIT 10;

-- 5. Bildirim türleri
SELECT 
    enumlabel as notification_type
FROM pg_enum
WHERE enumtypid = 'public.notification_type'::regtype
ORDER BY enumlabel;
