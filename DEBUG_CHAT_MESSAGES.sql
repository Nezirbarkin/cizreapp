-- ==============================================================================
-- SOHBET MESAJ GÖRÜNME SORUNU DIAGNOZ
-- ==============================================================================
-- Bu sorgu sohbet sistemindeki mesajların görünmemesini araştırır
-- ==============================================================================

-- 1. Messages tablosu RLS policy durumunu kontrol et
SELECT 
    '=== MESSAGES RLS POLICIES ===' as section;
    
SELECT 
    policyname,
    cmd,
    qual,
    with_check
FROM pg_policies 
WHERE tablename = 'messages'
ORDER BY policyname;

-- 2. Conversations tablosu RLS policy durumunu kontrol et
SELECT 
    '=== CONVERSATIONS RLS POLICIES ===' as section;
    
SELECT 
    policyname,
    cmd,
    qual,
    with_check
FROM pg_policies 
WHERE tablename = 'conversations'
ORDER BY policyname;

-- 3. Messages tablosundaki sütunları kontrol et
SELECT 
    '=== MESSAGES TABLE SCHEMA ===' as section;
    
SELECT 
    column_name,
    data_type,
    is_nullable,
    column_default
FROM information_schema.columns
WHERE table_name = 'messages'
ORDER BY ordinal_position;

-- 4. Conversations tablosundaki sütunları kontrol et
SELECT 
    '=== CONVERSATIONS TABLE SCHEMA ===' as section;
    
SELECT 
    column_name,
    data_type,
    is_nullable,
    column_default
FROM information_schema.columns
WHERE table_name = 'conversations'
ORDER BY ordinal_position;

-- 5. Örnek conversation ve mesaj sayılarını görüntüle
SELECT 
    '=== CONVERSATION EXAMPLES ===' as section;

SELECT 
    c.id as conversation_id,
    c.user_id,
    c.other_user_id,
    (SELECT full_name FROM profiles WHERE id = c.user_id LIMIT 1) as user_name,
    (SELECT full_name FROM profiles WHERE id = c.other_user_id LIMIT 1) as other_user_name,
    (SELECT COUNT(*) FROM messages m WHERE m.conversation_id = c.id) as message_count
FROM conversations c
LIMIT 10;

-- 6. Bir kullanıcının mesajlarını görüntüle (RLS test)
-- Not: Bu sorgu çalıştırıldığında auth.uid() kullanıcısının ID'sine göre sonuç değişir
-- Gerçek test için belirli bir user_id ile test edeceğiz:
SELECT 
    '=== SAMPLE MESSAGES ===' as section;
    
SELECT 
    m.id,
    m.conversation_id,
    m.sender_id,
    (SELECT full_name FROM profiles WHERE id = m.sender_id LIMIT 1) as sender_name,
    m.content,
    m.created_at
FROM messages m
ORDER BY m.created_at DESC
LIMIT 20;

-- 7. İki kullanıcı arasındaki conversation çiftini göster
SELECT 
    '=== CONVERSATION PAIRS ===' as section;

WITH conv_pairs AS (
    SELECT
        LEAST(user_id, other_user_id) as user1,
        GREATEST(user_id, other_user_id) as user2,
        COUNT(*) as conv_count,
        STRING_AGG(id::text, ', ') as conversation_ids
    FROM conversations
    GROUP BY LEAST(user_id, other_user_id), GREATEST(user_id, other_user_id)
    HAVING COUNT(*) > 1
)
SELECT 
    cp.user1,
    (SELECT full_name FROM profiles WHERE id = cp.user1 LIMIT 1) as user1_name,
    cp.user2,
    (SELECT full_name FROM profiles WHERE id = cp.user2 LIMIT 1) as user2_name,
    cp.conv_count,
    cp.conversation_ids
FROM conv_pairs cp
LIMIT 5;

-- 8. Her bir conversation için mesaj dağılımı
SELECT 
    '=== MESSAGE DISTRIBUTION PER CONVERSATION ===' as section;
    
SELECT 
    m.conversation_id,
    c.user_id,
    c.other_user_id,
    COUNT(*) as total_messages,
    COUNT(*) FILTER (WHERE sender_id = c.user_id) as sent_by_user,
    COUNT(*) FILTER (WHERE sender_id = c.other_user_id) as sent_by_other
FROM messages m
JOIN conversations c ON m.conversation_id = c.id
GROUP BY m.conversation_id, c.user_id, c.other_user_id
ORDER BY total_messages DESC
LIMIT 10;

DO $$
BEGIN
    RAISE NOTICE '================================================================';
    RAISE NOTICE 'DIAGNOZ TAMAMLANDI!';
    RAISE NOTICE 'Yukarıdaki sonuçları kontrol edin:';
    RAISE NOTICE '1. RLS policy''ler doğru ayarlanmış mı?';
    RAISE NOTICE '2. Her iki kullanıcı için conversation kaydı var mı?';
    RAISE NOTICE '3. Mesajlar hangi conversation_id''lere kaydedilmiş?';
    RAISE NOTICE '================================================================';
END $$;
