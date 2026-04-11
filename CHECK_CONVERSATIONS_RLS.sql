-- ==============================================================================
-- CHECK: Conversations RLS Policy Kontrolü
-- ==============================================================================
-- Kullanıcı kendi conversation'ını görebiliyor mu?
-- ==============================================================================

-- 1. Mevcut conversations policy'lerini görüntüle
SELECT 
    policyname,
    cmd,
    roles,
    qual,
    with_check
FROM pg_policies 
WHERE tablename = 'conversations'
ORDER BY policyname;

-- 2. Test: Kullanıcının kendi conversation'larını görebiliyor mu?
-- (auth.uid() yerine gerçek bir user_id ile test etmek için)
-- SELECT * FROM conversations WHERE user_id = auth.uid() LIMIT 10;

-- 3. Her kullanıcı için kendi conversation'larını göster
SELECT 
    c.id,
    c.user_id,
    c.other_user_id,
    (SELECT full_name FROM profiles WHERE id = c.other_user_id) as other_user_name,
    c.last_message,
    (SELECT COUNT(*) FROM messages m WHERE m.conversation_id = c.id) as message_count
FROM conversations c
WHERE c.user_id = (SELECT id FROM profiles WHERE id = (SELECT id FROM profiles LIMIT 1))
ORDER BY c.updated_at DESC
LIMIT 20;

DO $$
BEGIN
    RAISE NOTICE '================================================================';
    RAISE NOTICE 'Conversations RLS Policy Kontrolü Tamamlandı';
    RAISE NOTICE 'Yukarıdaki sonuçlara bakın:';
    RAISE NOTICE '1. Policy listesi - user_id kontrolü var mı?';
    RAISE NOTICE '2. Her conversation için mesaj sayısı';
    RAISE NOTICE '================================================================';
END $$;
