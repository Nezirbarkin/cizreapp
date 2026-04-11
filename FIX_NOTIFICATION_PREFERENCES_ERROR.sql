-- =====================================================
-- HATA DÜZELTMESİ: notification_preferences Yapısı
-- =====================================================

-- notification_preferences tablosunun yapısını kontrol et
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'public' 
AND table_name = 'notification_preferences'
ORDER BY ordinal_position;

-- Eğer push_enabled alanı yoksa, aşağıdaki SQL'i çalıştır:
-- =====================================================

-- push_enabled alanını ekle (varsa sorun gelmeyecek)
ALTER TABLE notification_preferences
ADD COLUMN IF NOT EXISTS push_enabled boolean DEFAULT true;

ALTER TABLE notification_preferences
ADD COLUMN IF NOT EXISTS email_enabled boolean DEFAULT true;

-- Mevcut kayıtlar için default değerleri set et
UPDATE notification_preferences
SET push_enabled = true,
    email_enabled = true
WHERE push_enabled IS NULL OR email_enabled IS NULL;

-- =====================================================
-- Düzeltilmiş send_push_on_notification Fonksiyonu
-- =====================================================

CREATE OR REPLACE FUNCTION send_push_on_notification()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_prefs record;
    v_push_enabled boolean := true; -- Default: push gönder
BEGIN
    -- Kullanıcının bildirim tercihlerini kontrol et
    SELECT * INTO v_prefs
    FROM notification_preferences
    WHERE user_id = NEW.user_id;
    
    -- Tercih varsa ve push_enabled varsa kontrol et, yoksa default true
    IF v_prefs IS NOT NULL THEN
        v_push_enabled := COALESCE(v_prefs.push_enabled, true);
    END IF;
    
    -- Eğer tercih yoksa veya push bildirimleri açıksa gönder
    IF v_push_enabled = true THEN
        -- Async olarak push gönder
        PERFORM send_fcm_push_notification(
            NEW.user_id,
            COALESCE(NEW.title, 'Yeni Bildirim'),
            COALESCE(NEW.body, ''),
            jsonb_build_object(
                'notification_id', NEW.id,
                'type', NEW.type,
                'data', COALESCE(NEW.data, '{}'::jsonb)
            )
        );
    END IF;
    
    RETURN NEW;
END;
$$;

-- =====================================================
-- Beğeni İşlemi İçin Düzeltilmiş Fonksiyon
-- =====================================================

-- Eğer post_likes tablosunda bildirim gönderilen bir trigger var ise:

CREATE OR REPLACE FUNCTION notify_post_liked()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_post record;
    v_user_prefs record;
    v_push_enabled boolean := true;
BEGIN
    -- Postun bilgilerini al
    SELECT id, user_id INTO v_post
    FROM posts
    WHERE id = NEW.post_id;
    
    IF v_post IS NULL THEN
        RETURN NEW;
    END IF;
    
    -- Kullanıcının tercihlerini kontrol et
    SELECT * INTO v_user_prefs
    FROM notification_preferences
    WHERE user_id = v_post.user_id;
    
    -- Tercih varsa push_enabled'ı al
    IF v_user_prefs IS NOT NULL THEN
        v_push_enabled := COALESCE(v_user_prefs.push_enabled, true);
    END IF;
    
    -- Push gönder (tercih açıksa)
    IF v_push_enabled = true THEN
        PERFORM send_fcm_push_notification(
            v_post.user_id,
            '❤️ Beğeni',
            'Birisi postunuzu beğendi',
            jsonb_build_object(
                'post_id', NEW.post_id,
                'type', 'post_liked'
            )
        );
    END IF;
    
    RETURN NEW;
END;
$$;

-- =====================================================
-- ÖNEMLİ: notification_preferences Yapısını Kontrol Et
-- =====================================================

-- Mevcut alanları kontrol et
SELECT 
    column_name,
    data_type,
    is_nullable
FROM information_schema.columns
WHERE table_schema = 'public' 
AND table_name = 'notification_preferences'
ORDER BY ordinal_position;
