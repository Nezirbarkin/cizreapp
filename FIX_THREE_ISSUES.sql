-- =====================================================
-- ÜÇ SORUNU BİRDEN DÜZELT
-- =====================================================
-- 1. Push bildirimde isim/profil göster (actor_name, actor_avatar ekle)
-- 2. Beğeni -1 sorununu kontrol et (trigger'lar ve count)
-- 3. Follow_requests duplicate key hatasını önle (ON CONFLICT ekle)
-- =====================================================

-- =====================================================
-- SORUN 1: Push Bildirimde İsim/Profil Eksik
-- =====================================================
-- Çözüm: send_push_on_notification fonksiyonunu güncelle
-- actor_name ve actor_avatar bilgilerini push payload'a ekle

CREATE OR REPLACE FUNCTION send_push_on_notification()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_prefs record;
    v_should_send boolean := false;
    v_result jsonb;
BEGIN
    -- Bildirim tercihlerini al
    SELECT * INTO v_prefs
    FROM notification_preferences
    WHERE user_id = NEW.user_id;
    
    -- Tercih yoksa varsayılan olarak gönder (true)
    IF v_prefs IS NULL THEN
        v_should_send := true;
    ELSE
        -- Global kontrol önce
        IF v_prefs.push_enabled = false THEN
            v_should_send := false;
        ELSE
            -- Tip bazlı kontrol (GERÇEK FIELD İSİMLERİ)
            CASE NEW.type
                WHEN 'post_like' THEN v_should_send := COALESCE(v_prefs.likes_enabled, true);
                WHEN 'like' THEN v_should_send := COALESCE(v_prefs.likes_enabled, true);
                WHEN 'post_comment' THEN v_should_send := COALESCE(v_prefs.comments_enabled, true);
                WHEN 'comment' THEN v_should_send := COALESCE(v_prefs.comments_enabled, true);
                WHEN 'new_follower' THEN v_should_send := COALESCE(v_prefs.followers_enabled, true);
                WHEN 'follow' THEN v_should_send := COALESCE(v_prefs.followers_enabled, true);
                WHEN 'follow_request' THEN v_should_send := COALESCE(v_prefs.followers_enabled, true);
                WHEN 'follow_request_accepted' THEN v_should_send := COALESCE(v_prefs.followers_enabled, true);
                WHEN 'comment_mention' THEN v_should_send := COALESCE(v_prefs.mentions, true);
                WHEN 'mention' THEN v_should_send := COALESCE(v_prefs.mentions, true);
                WHEN 'message' THEN v_should_send := true;
                WHEN 'new_order' THEN v_should_send := COALESCE(v_prefs.order_updates_enabled, true);
                WHEN 'order_status' THEN v_should_send := COALESCE(v_prefs.order_updates_enabled, true);
                WHEN 'order' THEN v_should_send := COALESCE(v_prefs.order_updates_enabled, true);
                WHEN 'courier_request' THEN v_should_send := true;
                WHEN 'courier_request_approved' THEN v_should_send := true;
                WHEN 'courier_request_rejected' THEN v_should_send := true;
                WHEN 'shop' THEN v_should_send := true;
                WHEN 'promotion' THEN v_should_send := COALESCE(v_prefs.promotional_enabled, true);
                WHEN 'system' THEN v_should_send := true;
                ELSE v_should_send := true;
            END CASE;
        END IF;
    END IF;
    
    -- Push gönderilmeliyse
    IF v_should_send THEN
        RAISE NOTICE 'Sending push for notification % (type: %)', NEW.id, NEW.type;
        
        -- Firebase'e push gönder (actor bilgileri de ekle)
        SELECT send_fcm_push_notification(
            NEW.user_id,
            NEW.title,
            NEW.content,
            jsonb_build_object(
                'type', NEW.type,
                'notification_id', NEW.id::text,
                'actor_id', COALESCE(NEW.actor_id::text, ''),
                'actor_name', COALESCE(NEW.actor_name, ''),
                'actor_avatar', COALESCE(NEW.actor_avatar, ''),
                'entity_id', COALESCE(NEW.entity_id, '')
            )
        ) INTO v_result;
        
        RAISE NOTICE 'Push result: %', v_result::text;
    ELSE
        RAISE NOTICE 'Push disabled for notification % (type: %)', NEW.id, NEW.type;
    END IF;
    
    RETURN NEW;
END;
$$;

-- =====================================================
-- SORUN 2: Beğeni Sayısı Kontrolü
-- =====================================================
-- posts tablosunda likes_count ve comments_count alanları var mı kontrol et

SELECT 
    column_name,
    data_type,
    column_default
FROM information_schema.columns
WHERE table_schema = 'public'
AND table_name = 'posts'
AND column_name IN ('likes_count', 'comments_count');

-- post_likes trigger'larını kontrol et
SELECT 
    trigger_name,
    event_manipulation,
    event_object_table,
    action_statement
FROM information_schema.triggers
WHERE event_object_table IN ('post_likes', 'posts')
ORDER BY event_object_table, trigger_name;

-- Beğeni count güncelleyen function'ları kontrol et
SELECT 
    routine_name,
    routine_type
FROM information_schema.routines
WHERE routine_schema = 'public'
AND (
    routine_name LIKE '%like%count%' 
    OR routine_name LIKE '%update%post%'
    OR routine_name LIKE '%increment%'
    OR routine_name LIKE '%decrement%'
)
ORDER BY routine_name;

-- =====================================================
-- SORUN 3: Follow_requests Duplicate Key Hatası
-- =====================================================
-- Çözüm: follow_requests tablosuna insert eden trigger'ı güncelle
-- veya upsert fonksiyonu oluştur

-- Follow request insert helper fonksiyonu (duplicate'i önler)
CREATE OR REPLACE FUNCTION upsert_follow_request(
    p_follower_id uuid,
    p_following_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_existing_request record;
BEGIN
    -- Zaten var mı kontrol et
    SELECT * INTO v_existing_request
    FROM follow_requests
    WHERE follower_id = p_follower_id
    AND following_id = p_following_id;
    
    -- Varsa ve pending ise, zaten gönderilmiş demektir
    IF v_existing_request IS NOT NULL THEN
        IF v_existing_request.status = 'pending' THEN
            RETURN jsonb_build_object(
                'success', true,
                'message', 'Follow request already exists',
                'request_id', v_existing_request.id
            );
        ELSIF v_existing_request.status = 'rejected' THEN
            -- Reddedilmişse yeniden göndersin (status'u pending yap)
            UPDATE follow_requests
            SET status = 'pending', created_at = NOW()
            WHERE id = v_existing_request.id;
            
            RETURN jsonb_build_object(
                'success', true,
                'message', 'Follow request resent',
                'request_id', v_existing_request.id
            );
        ELSE
            -- accepted veya diğer durumlar
            RETURN jsonb_build_object(
                'success', false,
                'message', 'Follow request already processed',
                'status', v_existing_request.status
            );
        END IF;
    END IF;
    
    -- Yoksa yeni ekle
    INSERT INTO follow_requests (follower_id, following_id, status)
    VALUES (p_follower_id, p_following_id, 'pending')
    RETURNING id INTO v_existing_request;
    
    RETURN jsonb_build_object(
        'success', true,
        'message', 'Follow request created',
        'request_id', v_existing_request.id
    );
END;
$$;

-- =====================================================
-- KONTROL VE TEST
-- =====================================================

-- 1. send_push_on_notification güncellendi mi?
SELECT 
    routine_name,
    routine_type
FROM information_schema.routines
WHERE routine_schema = 'public'
AND routine_name = 'send_push_on_notification';

-- 2. upsert_follow_request fonksiyonu oluşturuldu mu?
SELECT 
    routine_name,
    routine_type,
    routine_definition
FROM information_schema.routines
WHERE routine_schema = 'public'
AND routine_name = 'upsert_follow_request';

-- 3. Mevcut follow_requests unique constraint'ini kontrol et
SELECT
    conname AS constraint_name,
    contype AS constraint_type,
    pg_get_constraintdef(oid) AS constraint_definition
FROM pg_constraint
WHERE conrelid = 'public.follow_requests'::regclass
AND contype = 'u';

-- =====================================================
-- SONUÇ
-- =====================================================
-- ✅ Sorun 1 çözüldü: Push bildirimde actor_name ve actor_avatar artık gönderiliyor
-- ✅ Sorun 2 kontrol edildi: Beğeni count trigger'ları listelendi
-- ✅ Sorun 3 çözüldü: upsert_follow_request fonksiyonu oluşturuldu
-- 
-- KULLANIM:
-- Flutter tarafında follow_requests.insert() yerine bu fonksiyonu çağırın:
-- await supabase.rpc('upsert_follow_request', {
--   'p_follower_id': currentUserId,
--   'p_following_id': targetUserId
-- });
-- =====================================================
