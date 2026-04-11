-- =====================================================
-- DIAGNOZ: Mesajlar Database'de Varsa Ama UI'da Görünmüyorsa
-- =====================================================

-- 1. Tüm mesajları gör
SELECT 
    id,
    conversation_id,
    sender_id,
    LEFT(content, 50) as content_preview,
    created_at
FROM messages
ORDER BY created_at DESC;

-- 2. Tüm conversations'ları gör
SELECT 
    id,
    user_id,
    other_user_id,
    LEFT(last_message, 50) as last_msg_preview,
    last_message_time,
    updated_at
FROM conversations
ORDER BY updated_at DESC;

-- 3. Kullanıcı başına mesaj sayısı
SELECT 
    p.username,
    p.full_name,
    COUNT(m.id) as mesaj_sayisi
FROM profiles p
LEFT JOIN messages m ON m.sender_id = p.id
GROUP BY p.id, p.username, p.full_name
ORDER BY mesaj_sayisi DESC;

-- 4. Kullanıcı başına conversation sayısı
SELECT 
    p.username,
    p.full_name,
    COUNT(c.id) as conversation_sayisi
FROM profiles p
LEFT JOIN conversations c ON c.user_id = p.id OR c.other_user_id = p.id
GROUP BY p.id, p.username, p.full_name
ORDER BY conversation_sayisi DESC;

-- =====================================================
-- SONUÇ:
-- =====================================================
-- Eğer yukarıdaki sorgular mesaj ve conversation gösteriyorsa,
-- sorun Flutter UI'dadır. Şunları kontrol et:
-- 
-- 1. Flutter'da getConversations() fonksiyonu doğru çalışıyor mu?
-- 2. Flutter'da getMessages() fonksiyonu doğru çalışıyor mu?
-- 3. StreamBuilder veya FutureBuilder doğru kullanılıyor mu?
-- 4. UI'da mesaj listesi null/empty mi?
