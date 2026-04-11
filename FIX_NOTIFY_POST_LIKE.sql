-- =====================================================
-- HATA KAYNAĞINI BULUP DÜZELTMESİ
-- =====================================================
-- Hatalı trigger: notify_post_like_trigger
-- Hatalı fonksiyon: notify_post_like()
-- Hata: SELECT * yapıp v_prefs.push_enabled erişimi
-- =====================================================

-- =====================================================
-- 1. HATA VEREN notify_post_like() FONKSİYONUNU DÜZELT
-- =====================================================

CREATE OR REPLACE FUNCTION notify_post_like()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_post_owner_id uuid;
    v_likes_enabled boolean;
    v_push_enabled boolean;
    v_notification_id uuid;
BEGIN
    -- Post sahibini bul
    SELECT user_id INTO v_post_owner_id
    FROM posts
    WHERE id = NEW.post_id;
    
    -- Post sahibi yoksa veya kendi postuna beğeni ise çık
    IF v_post_owner_id IS NULL OR v_post_owner_id = NEW.user_id THEN
        RETURN NEW;
    END IF;
    
    -- Kullanıcının tercihlerini kontrol et (SELECT * KULLANMA!)
    SELECT 
        COALESCE(likes_enabled, true) as likes_en,
        COALESCE(push_enabled, true) as push_en
    INTO v_likes_enabled, v_push_enabled
    FROM notification_preferences
    WHERE user_id = v_post_owner_id;
    
    -- Varsayılan değerler (tercih yoksa true)
    v_likes_enabled := COALESCE(v_likes_enabled, true);
    v_push_enabled := COALESCE(v_push_enabled, true);
    
    -- Her iki tercih de açıksa bildirim oluştur
    IF v_likes_enabled = true THEN
        -- Bildirim oluştur
        INSERT INTO notifications (
            user_id,
            type,
            title,
            body,
            data,
            is_read
        ) VALUES (
            v_post_owner_id,
            'like',
            '❤️ Beğeni',
            'Birisi postunuzu beğendi',
            jsonb_build_object(
                'post_id', NEW.post_id,
                'user_id', NEW.user_id
            ),
            false
        ) RETURNING id INTO v_notification_id;
        
        -- Push bildirimini gönder (tercih açıksa)
        IF v_push_enabled = true THEN
            PERFORM send_fcm_push_notification(
                v_post_owner_id,
                '❤️ Beğeni',
                'Birisi postunuzu beğendi',
                jsonb_build_object(
                    'post_id', NEW.post_id,
                    'notification_id', v_notification_id,
                    'type', 'post_liked'
                )
            );
        END IF;
    END IF;
    
    RETURN NEW;
EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'notify_post_like error: %', SQLERRM;
    RETURN NEW;
END;
$$;

-- =====================================================
-- 2. KONTROL: notify_post_like() DÜZGÜN ÇALIŞIYOR MU?
-- =====================================================

-- Düzeltilmiş fonksiyonu kontrol et:
SELECT 
    routine_name,
    routine_type,
    data_type
FROM information_schema.routines
WHERE routine_schema = 'public'
AND routine_name = 'notify_post_like';

-- =====================================================
-- 3. TEST: Beğeni Eklemeyi Test Et
-- =====================================================

-- Eğer hata vermeye devam ederse, bu test sorgularını çalıştır:

-- Test 1: Kullanıcının tercihleri var mı?
-- SELECT * FROM notification_preferences WHERE user_id = 'USER_ID';

-- Test 2: Post var mı?
-- SELECT id, user_id FROM posts WHERE id = 'POST_ID';

-- Test 3: Beğeni ekle (test)
-- INSERT INTO post_likes (post_id, user_id) VALUES ('POST_ID', 'USER_ID');

-- =====================================================
-- 4. BAŞARILI OLURSA SONUÇ
-- =====================================================

-- Beğeni eklendiğinde:
-- ✅ Notification oluşturulur
-- ✅ Push bildirimi gönderilir (tercih açıksa)
-- ✅ Beğeni sayısı artırılır

-- =====================================================
-- 5. HALA SORUN VARSA
-- =====================================================

-- Eğer hata hala veriyorsa, hangi fonksiyon hata veriyor?
-- Trigger'lar sırasıyla çalışıyor:
-- 1. notify_post_like_trigger → notify_post_like()
-- 2. post_likes_count_trigger → update_post_likes_count()
-- 3. post_likes_insert_trigger → increment_post_likes_count()

-- Eğer 1. trigger başarılı olursa, diğerleri de çalışacak

-- Hata vermeye devam ederse:
-- A) Hata mesajında fonksiyon adı belirtiliyorsa, o fonksiyonu düzelt
-- B) Fonksiyon hala SELECT * kullanıyorsa, düzelt
-- C) Exception'ı log'la: RAISE WARNING kullanılıyor, kontrol et

-- =====================================================
-- 6. ALT PLAN: Trigger'ı Geçici Olarak Devre Dışı Bırak
-- =====================================================

-- Eğer hata devam ederse ve acil çözüm gerekiyorsa:
/*
DROP TRIGGER notify_post_like_trigger ON post_likes;
*/

-- Sonra trigger'ı yeniden oluştur (işlemi düzeltip):
/*
CREATE TRIGGER notify_post_like_trigger
    AFTER INSERT ON post_likes
    FOR EACH ROW
    EXECUTE FUNCTION notify_post_like();
*/
