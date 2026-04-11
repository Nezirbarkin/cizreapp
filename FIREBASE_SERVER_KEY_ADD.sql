-- =====================================================
-- FIREBASE SERVER KEY VAULT'A EKLEME (SQL YÖNTEMİ)
-- =====================================================
-- 
-- ADIM 1: Firebase Console'dan Server Key alın
-- ---------------------------------------------------
-- 1. https://console.firebase.google.com/ gidin
-- 2. Proje: cizreapp-3b9a4 seçin
-- 3. ⚙️ Project Settings → Cloud Messaging sekmesi
-- 4. Cloud Messaging API (Legacy) bölümünde Server Key'i kopyalayın
--    (AIzaSyC... ile başlar)
--
-- ADIM 2: Aşağıdaki SQL'i çalıştırın
-- ---------------------------------------------------
-- BURAYA_FIREBASE_SERVER_KEY_YAPIŞTIRIN yerine kendi key'inizi yapıştırın

-- Firebase Server Key'i vault'a ekle
INSERT INTO vault.secrets (name, secret, description)
VALUES (
    'firebase_server_key',
    'BURAYA_FIREBASE_SERVER_KEY_YAPIŞTIRIN',  -- AIzaSyC... ile başlayan key
    'Firebase Legacy Server Key for FCM Push Notifications'
)
ON CONFLICT (name) DO UPDATE SET
    secret = EXCLUDED.secret,
    description = EXCLUDED.description;

-- =====================================================
-- KONTROL: Eklendi mi?
-- =====================================================
SELECT 
    name,
    description,
    created_at,
    updated_at
FROM vault.secrets
WHERE name = 'firebase_server_key';

-- =====================================================
-- TEST: Push notification gönder
-- =====================================================
-- Kendi user ID'nizi kullanın:
-- SELECT send_fcm_push_notification(
--     'SIZIN_USER_ID',
--     'Test Push',
--     'Bu bir test bildirimidir'
-- );
