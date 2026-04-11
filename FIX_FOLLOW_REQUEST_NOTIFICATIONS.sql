-- =====================================================
-- TAKİP İSTEĞİ BİLDİRİM SİSTEMİ - TAM ÇÖZÜM
-- =====================================================

-- 1. Eksik notification_type değerlerini ekle
ALTER TYPE notification_type ADD VALUE IF NOT EXISTS 'follow_request';
ALTER TYPE notification_type ADD VALUE IF NOT EXISTS 'follow_request_accepted';

-- 2. Duplicate push trigger'ı kaldır
DROP TRIGGER IF EXISTS notifications_push_trigger ON notifications;

-- 3. notify_follow_request_trigger fonksiyonunu güncelle (content field kullanımı)
CREATE OR REPLACE FUNCTION notify_follow_request_trigger()
RETURNS TRIGGER AS $$
DECLARE
    follower_profile JSONB;
    following_profile JSONB;
BEGIN
    -- Sadece yeni istekler için bildirim gönder (pending status)
    IF TG_OP = 'INSERT' AND NEW.status = 'pending' THEN
        -- Follower profili
        SELECT row_to_json(p) INTO follower_profile
        FROM profiles p
        WHERE p.id = NEW.follower_id;
        
        INSERT INTO notifications (user_id, type, title, content, actor_id, actor_name, actor_avatar, entity_id)
        VALUES (
            NEW.following_id,
            'follow_request',
            'Takip isteği',
            'seni takip etmek istiyor',
            NEW.follower_id,
            COALESCE(follower_profile->>'username', 'Bir kullanıcı'),
            follower_profile->>'avatar_url',
            NEW.id::text
        );
    END IF;
    
    -- İstek kabul edildiğinde bildirim gönder
    IF TG_OP = 'UPDATE' AND OLD.status = 'pending' AND NEW.status = 'accepted' THEN
        INSERT INTO notifications (user_id, type, title, content, actor_id, actor_name, actor_avatar, entity_id)
        VALUES (
            NEW.follower_id,
            'follow_request_accepted',
            'Takip isteği kabul edildi',
            'seni takip etmeye başladı',
            NEW.following_id,
            COALESCE((SELECT username FROM profiles WHERE id = NEW.following_id), 'Bir kullanıcı'),
            (SELECT avatar_url FROM profiles WHERE id = NEW.following_id),
            NEW.id::text
        );
        
        -- Otomatik olarak follows tablosuna ekle
        INSERT INTO follows (follower_id, following_id, created_at)
        VALUES (NEW.follower_id, NEW.following_id, NEW.created_at)
        ON CONFLICT (follower_id, following_id) DO NOTHING;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 4. Kontrol: Notification type enum'da yeni değerler var mı?
SELECT 
    enumlabel as notification_type
FROM pg_enum
WHERE enumtypid = 'public.notification_type'::regtype
AND enumlabel IN ('follow_request', 'follow_request_accepted')
ORDER BY enumlabel;

-- 5. Kontrol: notifications tablosu trigger'ları
SELECT 
    trigger_name,
    event_manipulation,
    action_timing
FROM information_schema.triggers
WHERE event_object_table = 'notifications'
AND trigger_schema = 'public'
ORDER BY trigger_name;

-- =====================================================
-- SONUÇ
-- =====================================================
-- ✅ follow_request ve follow_request_accepted tipleri eklendi
-- ✅ Duplicate push trigger kaldırıldı
-- ✅ Takip isteği onaylandığında bildirim gidecek
-- =====================================================
