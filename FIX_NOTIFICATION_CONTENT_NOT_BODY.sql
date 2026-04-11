-- =====================================================
-- NOTIFICATIONS TABLOSU BODY → CONTENT DÜZELTMESI
-- =====================================================
-- Sorun: SQL fonksiyonları "body" kullanıyor
-- Gerçek: Tablo "content" kullanıyor
-- =====================================================

-- =====================================================
-- ÇÖZÜM: Trigger fonksiyonlarını "content" olarak güncelle
-- =====================================================

-- 1. notify_post_like - BEĞENİ BİLDİRİMİ
CREATE OR REPLACE FUNCTION notify_post_like()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_post_owner_id uuid;
    v_likes_enabled boolean;
BEGIN
    SELECT user_id INTO v_post_owner_id
    FROM posts WHERE id = NEW.post_id;
    
    IF v_post_owner_id IS NULL OR v_post_owner_id = NEW.user_id THEN
        RETURN NEW;
    END IF;
    
    SELECT COALESCE(likes_enabled, true) INTO v_likes_enabled
    FROM notification_preferences
    WHERE user_id = v_post_owner_id;
    
    v_likes_enabled := COALESCE(v_likes_enabled, true);
    
    IF v_likes_enabled = true THEN
        INSERT INTO notifications (user_id, type, title, content, is_read)
        VALUES (
            v_post_owner_id,
            'like',
            '❤️ Beğeni',
            'Birisi postunuzu beğendi',
            false
        );
    END IF;
    
    RETURN NEW;
EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'notify_post_like error: %', SQLERRM;
    RETURN NEW;
END;
$$;

-- 2. notify_user_followed - TAKİP BİLDİRİMİ
CREATE OR REPLACE FUNCTION notify_user_followed()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_followers_enabled boolean;
BEGIN
    SELECT COALESCE(followers_enabled, true) INTO v_followers_enabled
    FROM notification_preferences
    WHERE user_id = NEW.following_id;
    
    v_followers_enabled := COALESCE(v_followers_enabled, true);
    
    IF v_followers_enabled = true THEN
        INSERT INTO notifications (user_id, type, title, content, is_read)
        VALUES (
            NEW.following_id,
            'follow',
            '👤 Yeni Takipçi',
            'Sizi takip etmeye başladı',
            false
        );
    END IF;
    
    RETURN NEW;
EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'notify_user_followed error: %', SQLERRM;
    RETURN NEW;
END;
$$;

-- 3. notify_post_comment - YORUM BİLDİRİMİ
CREATE OR REPLACE FUNCTION notify_post_comment()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_post_owner_id uuid;
    v_comments_enabled boolean;
    v_commenter_name text;
BEGIN
    SELECT user_id INTO v_post_owner_id
    FROM posts WHERE id = NEW.post_id;
    
    IF v_post_owner_id IS NULL OR v_post_owner_id = NEW.user_id THEN
        RETURN NEW;
    END IF;
    
    SELECT full_name INTO v_commenter_name
    FROM profiles WHERE id = NEW.user_id;
    
    SELECT COALESCE(comments_enabled, true) INTO v_comments_enabled
    FROM notification_preferences
    WHERE user_id = v_post_owner_id;
    
    v_comments_enabled := COALESCE(v_comments_enabled, true);
    
    IF v_comments_enabled = true THEN
        INSERT INTO notifications (user_id, type, title, content, is_read)
        VALUES (
            v_post_owner_id,
            'comment',
            '💬 Yeni Yorum',
            COALESCE(v_commenter_name, 'Birisi') || ' postunuzu yorumladı',
            false
        );
    END IF;
    
    RETURN NEW;
EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'notify_post_comment error: %', SQLERRM;
    RETURN NEW;
END;
$$;

-- 4. send_push_on_notification - PUSH GÖNDERME
CREATE OR REPLACE FUNCTION send_push_on_notification()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_push_enabled boolean := true;
BEGIN
    SELECT COALESCE(push_enabled, true) INTO v_push_enabled
    FROM notification_preferences
    WHERE user_id = NEW.user_id;
    
    v_push_enabled := COALESCE(v_push_enabled, true);
    
    IF v_push_enabled = true THEN
        PERFORM send_fcm_push_notification(
            NEW.user_id,
            COALESCE(NEW.title, 'Yeni Bildirim'),
            COALESCE(NEW.content, ''),  -- body değil content!
            '{}'::jsonb
        );
    END IF;
    
    RETURN NEW;
END;
$$;

-- =====================================================
-- KONTROL: Şimdi bildirim oluşturabilir miyiz?
-- =====================================================

-- Test bildirimi oluştur (kendi user_id'nizi yazın)
-- INSERT INTO notifications (user_id, type, title, content, is_read)
-- VALUES (
--     'BURAYA_USER_ID',
--     'test',
--     'Test Bildirimi',
--     'Bu bir test bildirimidir',
--     false
-- );

-- Son 10 bildirim
SELECT 
    id,
    user_id,
    type,
    title,
    content,
    created_at
FROM notifications
ORDER BY created_at DESC
LIMIT 10;

-- =====================================================
-- TAMAMLANDI!
-- =====================================================
-- Şimdi beğeni/takip/yorum bildirimleri çalışacak!
