-- =====================================================
-- TEST: Conversation + Message Oluşturma
-- =====================================================

-- ADIM 1: Conversation oluştur
INSERT INTO conversations (user_id, other_user_id, last_message, last_message_time)
VALUES (
    '8d614850-05bf-4b9e-bf67-0c6f3e00deb0',
    '78665f8b-6a07-40f3-b13d-d4b5a29296c6',
    'Test mesajı',
    NOW()
)
RETURNING id, user_id, other_user_id, last_message, last_message_time, created_at;
