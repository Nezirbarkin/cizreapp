-- =====================================================
-- BİLDİRİM SİSTEMİ DEBUG - SORUN BULMA
-- =====================================================
-- Hangisinde sorun var? Sırasıyla kontrol et
-- =====================================================

-- ADIM 1: Bildirim oluştu mu?
-- ==========================================
-- Beğeni attığınız post ID'sini ve kendi user ID'nizi kullanın

-- En son bildirimleri gör
SELECT 
    id,
    user_id,
    type,
    title,
    created_at
FROM notifications
ORDER BY created_at DESC
LIMIT 20;

-- ADIM 2: Token kaydı var mı?
-- ==========================================
-- Kendi user ID'nizi yazın

-- Senin token'larını gör
SELECT 
    id,
    user_id,
    token,
    device_type,
    created_at
FROM notification_tokens
WHERE user_id = 'BURAYA_KENDI_USER_ID_NI_YAZ'
ORDER BY created_at DESC;

-- ADIM 3: Tüm token'lar
-- ==========================================
-- Sistemde hiç token var mı?

SELECT 
    COUNT(*) as toplam_token,
    COUNT(DISTINCT user_id) as token_sahibi_kisi_sayisi
FROM notification_tokens;

-- ADIM 4: Notification preferences var mı?
-- ==========================================
-- Kendi user ID'nini yazın

SELECT *
FROM notification_preferences
WHERE user_id = 'BURAYA_KENDI_USER_ID_NI_YAZ';

-- ADIM 5: Push_enabled ayarı
-- ==========================================
-- Bildirim tercihlerinde push açık mı?

SELECT 
    user_id,
    push_enabled,
    likes_enabled,
    comments_enabled,
    followers_enabled
FROM notification_preferences
WHERE push_enabled = true
LIMIT 10;

-- ADIM 6: Trigger'lar çalışıyor mu?
-- ==========================================
-- Trigger'lar var mı?

SELECT 
    trigger_name,
    event_object_table,
    action_statement
FROM information_schema.triggers
WHERE event_object_table IN ('post_likes', 'notifications')
AND trigger_schema = 'public'
ORDER BY event_object_table;

-- =====================================================
-- ÖZET KONTROL
-- =====================================================

-- Tüm tablolardaki toplam sayıları gör
SELECT 
    'notifications' as tablo,
    COUNT(*) as toplam
FROM notifications
UNION ALL
SELECT 
    'notification_tokens' as tablo,
    COUNT(*) as toplam
FROM notification_tokens
UNION ALL
SELECT 
    'notification_preferences' as tablo,
    COUNT(*) as toplam
FROM notification_preferences
UNION ALL
SELECT 
    'post_likes' as tablo,
    COUNT(*) as toplam
FROM post_likes
ORDER BY tablo;
