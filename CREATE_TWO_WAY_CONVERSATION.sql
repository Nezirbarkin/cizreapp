-- =====================================================
-- İKİ YÖNLÜ CONVERSATION SİSTEMİ
-- =====================================================
-- Her iki kullanıcı için ayrı conversation oluşturur
-- Böylece herkes kendi bakış açısından sohbeti görebilir
-- =====================================================

-- İlk conversation'ı oluştur (test → fatmabrk)
-- Bu zaten var, kontrol edelim
SELECT 
    id, 
    user_id, 
    other_user_id, 
    last_message, 
    last_message_time 
FROM conversations 
WHERE user_id = '8d614850-05bf-4b9e-bf67-0c6f3e00deb0' 
  AND other_user_id = '78665f8b-6a07-40f3-b13d-d4b5a29296c6';

-- İkinci conversation'ı oluştur (fatmabrk → test)
INSERT INTO conversations (user_id, other_user_id, last_message, last_message_time)
VALUES (
    '78665f8b-6a07-40f3-b13d-d4b5a29296c6',
    '8d614850-05bf-4b9e-bf67-0c6f3e00deb0',
    'Test mesajı',
    NOW()
)
ON CONFLICT DO NOTHING
RETURNING id, user_id, other_user_id, last_message, last_message_time;

-- =====================================================
-- KONTROL
-- =====================================================

-- Her iki conversation'ı gör
SELECT 
    id, 
    user_id, 
    other_user_id, 
    last_message, 
    last_message_time 
FROM conversations 
WHERE (user_id = '8d614850-05bf-4b9e-bf67-0c6f3e00deb0' 
  AND other_user_id = '78665f8b-6a07-40f3-b13d-d4b5a29296c6')
   OR (user_id = '78665f8b-6a07-40f3-b13d-d4b5a29296c6' 
  AND other_user_id = '8d614850-05bf-4b9e-bf67-0c6f3e00deb0')
ORDER BY user_id;

-- =====================================================
-- ŞİMDİ İKİ YÖNLÜ MESAJ EKLEME TESTİ
-- =====================================================

-- Test'ten fatmabrk'a mesaj
INSERT INTO messages (conversation_id, sender_id, content)
VALUES (
    (SELECT id FROM conversations WHERE user_id = '8d614850-05bf-4b9e-bf67-0c6f3e00deb0' AND other_user_id = '78665f8b-6a07-40f3-b13d-d4b5a29296c6'),
    '8d614850-05bf-4b9e-bf67-0c6f3e00deb0',
    'Merhaba fatmabrk! Bu test mesajıdır.'
)
RETURNING id, conversation_id, sender_id, content, created_at;

-- =====================================================
-- SONUÇ
-- =====================================================
-- Artık her iki kullanıcı da kendi conversation'ını görecek
-- fatmabrk, kendi conversation'ında test'ten gelen mesajı görebilecek
