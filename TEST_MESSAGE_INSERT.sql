-- =====================================================
-- TEST: MESAJ EKLEME VE SORGULAMA
-- =====================================================

-- 1. Test için kullanıcı ID'lerini al (mevcut kullanıcılar)
SELECT id, username, full_name 
FROM profiles 
LIMIT 5;

-- 2. Manuel test mesajı ekle
-- BURAYA KENDİ USER_ID'LERİNİ YAZMALISIN!
-- Bu sorguyu çalıştırmadan önce yukarıdaki sonuçlardan iki kullanıcı ID'sini al
-- ve aşağıdaki 'USER_ID_1' ve 'USER_ID_2' kısımlarını değiştir

-- Örnek (kendi ID'lerinle değiştir):
INSERT INTO messages (conversation_id, sender_id, content)
VALUES (
    '550e8400-e29b-41d4-a716-446655440000',  -- Test conversation ID
    '550e8400-e29b-41d4-a716-446655440001',  -- Test sender ID
    'Test mesajı - bu manuel eklenen bir mesajdır'
);

-- 3. Mesajların geldiğini kontrol et
SELECT 
    id,
    conversation_id,
    sender_id,
    content,
    created_at
FROM messages
ORDER BY created_at DESC
LIMIT 5;

-- 4. Conversations'ı kontrol et
SELECT 
    id,
    user_id,
    other_user_id,
    last_message,
    last_message_time,
    updated_at
FROM conversations
ORDER BY updated_at DESC
LIMIT 5;

-- =====================================================
-- EĞER YUKARIDAKİ SORGU ÇALIŞMAZSA, TEST İÇİN:
-- =====================================================

-- 5. Test conversation oluştur (gerçek bir user ID ile)
-- INSERT INTO conversations (user_id, other_user_id, last_message, last_message_time)
-- VALUES ('GERCEK_USER_ID', 'DIGER_USER_ID', 'Test mesajı', NOW());

-- 6. Sonra bu conversation için mesaj ekle
-- INSERT INTO messages (conversation_id, sender_id, content)
-- VALUES ('CONVERSATION_ID', 'SENDER_ID', 'Test mesajı');
