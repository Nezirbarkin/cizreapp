-- =====================================================
-- TRIGGER TEŞHİS
-- =====================================================

-- 1. Trigger var mı?
SELECT 
    trigger_name,
    event_manipulation,
    action_timing,
    action_statement
FROM information_schema.triggers
WHERE event_object_schema = 'public' 
  AND event_object_table = 'messages'
ORDER BY trigger_name;

-- 2. Trigger fonksiyonu var mı?
SELECT 
    routine_name,
    routine_type,
    data_type as return_type
FROM information_schema.routines
WHERE routine_schema = 'public' 
  AND routine_name LIKE '%conversation%'
ORDER BY routine_name;

-- 3. Test: Mesaj gönderildiğinde trigger çalışıyor mu?
-- Son mesajları ve conversation durumunu kontrol et
SELECT 
    c.id as conversation_id,
    c.last_message_at,
    c.last_message_content,
    c.last_message_sender_id,
    c.unread_count,
    (SELECT MAX(created_at) FROM messages m WHERE m.conversation_id = c.id) as actual_last_message_at,
    (SELECT content FROM messages m WHERE m.conversation_id = c.id ORDER BY created_at DESC LIMIT 1) as actual_last_content
FROM conversations c
ORDER BY c.last_message_at DESC NULLS LAST
LIMIT 10;

-- 4. RLS durumu
SELECT 
    schemaname,
    tablename,
    relrowse as rls_enabled,
    relforcerowsecurity as rls_forced
FROM pg_class
JOIN pg_namespace ON pg_namespace.oid = pg_class.relnamespace
WHERE pg_class.relname IN ('messages', 'conversations')
  AND pg_namespace.nspname = 'public';
