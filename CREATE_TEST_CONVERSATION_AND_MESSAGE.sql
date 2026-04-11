-- =====================================================
-- GERÇEÇİKLİ TEST: Conversation + Message Oluşturma
-- =====================================================

-- 1. Önce mevcut kullanıcıları gör
SELECT id, username, full_name 
FROM profiles 
ORDER BY created_at DESC
LIMIT 5;

-- =====================================================
-- ADIM 1: İlk olarak conversation oluştur
-- =====================================================

-- Aşağıdaki sorguyu çalıştırmadan önce, yukarıdan iki gerçek user_id al
-- ve buraya yapıştır:

-- Örnek (kendi ID'lerinle değiştir):
INSERT INTO conversations (user_id, other_user_id, last_message, last_message_time)
VALUES (
    'BURAYA_ILK_KULLANICI_ID_YAZ',      -- user_id (sohbeti başlatan)
    'BURAYA_IKINCI_KULLANICI_ID_YAZ',    -- other_user_id (diğer taraf)
    'Test mesajı',
    NOW()
)
RETURNING id, user_id, other_user_id, last_message, last_message_time, created_at;

-- =====================================================
-- ADIM 2: Sonra bu conversation için mesaj ekle
-- =====================================================

-- Yukarıdaki INSERT işleminin döndürdüğü conversation_id'yi kullan
INSERT INTO messages (conversation_id, sender_id, content)
VALUES (
    'BURAYA_YUKARIDAKI_CONVERSATION_ID_YAZ',  -- Az önce oluşturulan conversation'ın ID'si
    'BURAYA_GONDEREN_KULLANICI_ID_YAZ',       -- Mesajı gönderen kişinin ID'si
    'Bu bir test mesajıdır'
)
RETURNING id, conversation_id, sender_id, content, created_at;

-- =====================================================
-- ADIM 3: Sonuçları kontrol et
-- =====================================================

-- Conversations'ı gör
SELECT 
    id,
    user_id,
    other_user_id,
    last_message,
    last_message_time,
    created_at
FROM conversations
ORDER BY created_at DESC;

-- Messages'ı gör
SELECT 
    id,
    conversation_id,
    sender_id,
    content,
    created_at
FROM messages
ORDER BY created_at DESC;

-- =====================================================
-- ADIM 4: Trigger testi (Otomatik güncelleme kontrolü)
-- =====================================================

-- Şimdi ikinci bir mesaj ekleyelim, trigger'ın çalışıp çalışmadığını görelim
-- Aynı conversation_id'yi kullan:

INSERT INTO messages (conversation_id, sender_id, content)
VALUES (
    'BURAYA_CONVERSATION_ID_YAZ',  -- Aynı conversation ID
    'BURAYA_GONDEREN_KULLANICI_ID_YAZ',
    'İkinci test mesajı - trigger kontrolü'
)
RETURNING id, conversation_id, sender_id, content, created_at;

-- Trigger çalıştıysa, conversations.last_message ve .last_message_time güncellenmiş olmalı
SELECT 
    id,
    user_id,
    other_user_id,
    last_message,
    last_message_time,
    updated_at
FROM conversations
WHERE id = 'BURAYA_CONVERSATION_ID_YAZ';

-- =====================================================
-- NOTLAR:
-- =====================================================
-- 1. Her 'BURAYA...' yazan yeri gerçek ID'lerle değiştirmelisin
-- 2. İlk adımdan dönen conversation_id'yi kopyala ve ikinci adımda kullan
-- 3. Trigger çalışıyorsa, her mesajda last_message ve last_message_time güncellenir
-- 4. Eğer trigger çalışmazsa, final_complete_fix.sql'i tekrar çalıştır
