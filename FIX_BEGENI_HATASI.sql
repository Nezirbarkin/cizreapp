-- =====================================================
-- BEĞENİ HATASI DÜZELTMESİ
-- =====================================================
-- Hata: record "v_prefs" has no field "push_enabled"
-- Sebebi: Mevcut trigger fonksiyonlarında notification_preferences'tan
--          SELECT * yapılıyor ama alanlara erişirken sorun çıkıyor
-- =====================================================

-- =====================================================
-- 1. DÜZELTİLMİŞ send_push_on_notification FONKSİYONU
-- =====================================================

CREATE OR REPLACE FUNCTION send_push_on_notification()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_push_enabled boolean := true; -- Default: push gönder
BEGIN
    -- Kullanıcının bildirim tercihlerini kontrol et
    -- Sadece push_enabled alanını seç (SELECT * kullanma)
    SELECT COALESCE(push_enabled, true) INTO v_push_enabled
    FROM notification_preferences
    WHERE user_id = NEW.user_id
    LIMIT 1;
    
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
-- 2. MEVCUT POST_LIKES TRIGGER'LARINI KONTROL ET
-- =====================================================

-- Mevcut post_likes trigger'larını gör
SELECT 
    trigger_name,
    event_manipulation,
    action_timing,
    action_statement
FROM information_schema.triggers
WHERE event_object_table = 'post_likes'
AND trigger_schema = 'public';

-- =====================================================
-- 3. HATA VEREN FONKSIYONU BUL VE DÜZ RTLE
-- =====================================================

-- Eğer post_likes tablosunda hatalı bir trigger varsa, önce trigger'ı kaldır:
-- Bu sorguyu çalıştırıp trigger ismini öğren, sonra aşağıdaki gibi kaldır

-- Örnek:
-- DROP TRIGGER IF EXISTS on_post_liked_notify ON post_likes;

-- Sonra hatalı fonksiyonu düzelt veya kaldır:
-- DROP FUNCTION IF EXISTS notify_post_liked();

-- =====================================================
-- 4. DÜZELTME: Tüm Bildirimlerde SELECT * Yerine Alan Adı Kullan
-- =====================================================

-- Eğer başka fonksiyonlar da SELECT * kullanıyorsa onları da düzelt
-- Örnek hatalı kod:
--   SELECT * INTO v_prefs FROM notification_preferences WHERE user_id = ...
--   IF v_prefs.push_enabled = true THEN ...  -- HATA!
--
-- Doğru kod:
--   SELECT push_enabled INTO v_push_enabled FROM notification_preferences WHERE user_id = ...
--   IF v_push_enabled = true THEN ...  -- DOĞRU!

-- =====================================================
-- 5. TÜM HATA VEREN FONKSİYONLARI BUL
-- =====================================================

-- notification_preferences kullanan tüm fonksiyonları bul:
SELECT 
    routine_name,
    routine_type
FROM information_schema.routines
WHERE routine_schema = 'public'
AND routine_definition ILIKE '%notification_preferences%'
AND routine_definition ILIKE '%SELECT%*%'
ORDER BY routine_name;

-- =====================================================
-- 6. BASİT ÇÖZÜM: NULL KONTROLLÜ PUSH GÖNDERME
-- =====================================================

CREATE OR REPLACE FUNCTION send_push_notification_safe(
    p_user_id uuid,
    p_title text,
    p_body text,
    p_data jsonb DEFAULT '{}'::jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_push_enabled boolean;
BEGIN
    -- Tercihleri kontrol et
    SELECT COALESCE(push_enabled, true) INTO v_push_enabled
    FROM notification_preferences
    WHERE user_id = p_user_id;
    
    -- Tercih yoksa default true kullan
    v_push_enabled := COALESCE(v_push_enabled, true);
    
    -- Push gönder
    IF v_push_enabled = true THEN
        PERFORM send_fcm_push_notification(p_user_id, p_title, p_body, p_data);
    END IF;
END;
$$;

-- =====================================================
-- 7. TESPİT: Hangi Fonksiyon Hata Veriyor?
-- =====================================================

-- Hata mesajında hangi fonksiyon/trigger adı geçiyor?
-- Örnek hata:
-- "Exception: Beğeni eklenirken hata: PostgrestException..."
-- Bu durumda post_likes tablosunda bir trigger var ve hata veriyor

-- Çözüm: O trigger'ı ve fonksiyonunu yeniden yaz
-- Örnek:

CREATE OR REPLACE FUNCTION handle_post_like_notification()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_post_owner_id uuid;
    v_likes_enabled boolean;
    v_push_enabled boolean;
BEGIN
    -- Post sahibini bul
    SELECT user_id INTO v_post_owner_id
    FROM posts
    WHERE id = NEW.post_id;
    
    -- Kendi postuna beğeni ise çık
    IF v_post_owner_id IS NULL OR v_post_owner_id = NEW.user_id THEN
        RETURN NEW;
    END IF;
    
    -- Tercihleri kontrol et (SELECT * değil, belirli alanlar!)
    SELECT 
        COALESCE(likes_enabled, true),
        COALESCE(push_enabled, true)
    INTO v_likes_enabled, v_push_enabled
    FROM notification_preferences
    WHERE user_id = v_post_owner_id;
    
    -- Varsayılan değerler
    v_likes_enabled := COALESCE(v_likes_enabled, true);
    v_push_enabled := COALESCE(v_push_enabled, true);
    
    -- Her iki tercih de açıksa bildirim gönder
    IF v_likes_enabled = true AND v_push_enabled = true THEN
        -- Notifications tablosuna ekle
        INSERT INTO notifications (user_id, type, title, body, data)
        VALUES (
            v_post_owner_id,
            'like',
            '❤️ Beğeni',
            'Birisi postunuzu beğendi',
            jsonb_build_object('post_id', NEW.post_id, 'user_id', NEW.user_id)
        );
    END IF;
    
    RETURN NEW;
END;
$$;

-- =====================================================
-- SONUÇ: Hangi Trigger'ı Güncellemelisiniz?
-- =====================================================

-- 1. Önce mevcut trigger'ları kontrol edin:
SELECT * FROM information_schema.triggers 
WHERE event_object_table = 'post_likes';

-- 2. Hatalı trigger'ı kaldırın:
-- DROP TRIGGER IF EXISTS [trigger_name] ON post_likes;

-- 3. Yeni trigger oluşturun:
-- CREATE TRIGGER post_like_notification_trigger
--     AFTER INSERT ON post_likes
--     FOR EACH ROW
--     EXECUTE FUNCTION handle_post_like_notification();
