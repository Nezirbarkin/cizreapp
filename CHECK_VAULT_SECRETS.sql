-- =====================================================
-- VAULT SECRETS KONTROL - Firebase Key Mevcut Mu?
-- =====================================================

-- 1. Vault'ta tüm secretları listele (isim ve açıklama)
SELECT 
    name,
    description,
    created_at
FROM vault.secrets
ORDER BY name;

-- 2. Firebase ile ilgili secretlar var mı?
SELECT 
    name,
    description,
    created_at
FROM vault.secrets
WHERE name ILIKE '%firebase%'
   OR description ILIKE '%firebase%'
   OR name ILIKE '%fcm%'
ORDER BY name;

-- =====================================================
-- SONUÇ
-- =====================================================
-- Eğer 'firebase_service_account' veya 'firebase_server_key' varsa,
-- send_fcm_push_notification fonksiyonu bunu kullanabilir.
-- =====================================================
