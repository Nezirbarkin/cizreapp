-- =====================================================
-- TEST: Mesaj Ekleme (ADIM 2)
-- =====================================================
-- 
-- ÖNEMLİ: Önce TEST_STEP1_CREATE_CONVERSATION.sql'i çalıştır ve 
-- oradan dönen conversation_id'yi buraya kopyala!
--
-- ADIM 1'den gelen ID'yi aşağıya yapıştır:

INSERT INTO messages (conversation_id, sender_id, content)
VALUES (
    '3628fb2e-6fcf-461c-b65c-913bb5ea5ba7',       -- Conversation ID
    '8d614850-05bf-4b9e-bf67-0c6f3e00deb0',         -- Gönderen
    'Test mesajı - bu çalışırsa mesaj gönderme çalışıyor'
)
RETURNING id, conversation_id, sender_id, content, created_at;
