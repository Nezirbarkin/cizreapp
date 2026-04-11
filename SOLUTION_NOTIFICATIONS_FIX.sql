-- =====================================================
-- TAM ÇÖZÜM: NOTIFICATIONS BODY → CONTENT DÜZELTMESİ
-- =====================================================
-- Bu dosya mesaj bildirimlerindeki "body" hatalarını çözer
-- =====================================================

-- =====================================================
-- ADIM 1: ÖZEL MESAJ BİLDİRİMİ İÇİN YENİ FONKSİYON
-- =====================================================
CREATE OR REPLACE FUNCTION notify_message_received()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_other_user_id UUID;
    v_sender_username TEXT;
    v_messages_enabled boolean;
BEGIN
    -- Diğer kullanıcı ID'sini bul
    SELECT other_user_id INTO v_other_user_id
    FROM conversations
    WHERE id = NEW.conversation_id;
    
    -- Gönderen kullanıcı adını al
    SELECT username INTO v_sender_username
    FROM profiles
    WHERE id = NEW.sender_id;
    
    -- Mesaj bildirimleri ayarını kontrol et
    SELECT COALESCE(messages_enabled, true) INTO v_messages_enabled
    FROM notification_preferences
    WHERE user_id = v_other_user_id;
    
    v_messages_enabled := COALESCE(v_messages_enabled, true);
    
    -- Sadece alıcıya bildirim gönder (mesajı atan kişiye değil)
    IF v_messages_enabled = true AND v_other_user_id IS NOT NULL AND v_other_user_id != NEW.sender_id THEN
        INSERT INTO notifications (user_id, type, title, content, is_read)
        VALUES (
            v_other_user_id,
            'message',
            '📨 Yeni Mesaj',
            COALESCE(v_sender_username, 'Bir kullanıcı') || ': ' || 
            CASE WHEN LENGTH(NEW.content) > 50 THEN LEFT(NEW.content, 50) || '...' ELSE NEW.content END,
            false
        );
    END IF;
    
    RETURN NEW;
EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'notify_message_received error: %', SQLERRM;
    RETURN NEW;
END;
$$;

-- =====================================================
-- ADIM 2: MESAJ TRIGGER'I GÜNCELLEME
-- =====================================================
-- Önceki trigger'ı kaldır
DROP TRIGGER IF EXISTS message_notification_trigger ON public.messages;

-- Yeni trigger'ı oluştur
CREATE TRIGGER message_notification_trigger
    AFTER INSERT ON public.messages
    FOR EACH ROW
    EXECUTE FUNCTION notify_message_received();

-- =====================================================
-- ADIM 3: KULLANICI MESAJ BİLDİRİM AYARLARI SÜTUNU EKLE (EKSİKSE)
-- =====================================================
ALTER TABLE notification_preferences 
ADD COLUMN IF NOT EXISTS messages_enabled boolean DEFAULT true;

-- =====================================================
-- ADIM 4: RLS POLİCİ GÜNCELLEME (EĞER VARSA)
-- =====================================================
-- Bildirimlere erişim için RLS policy
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;

-- Kullanıcı sadece kendi bildirimlerini görebilir
DROP POLICY IF EXISTS "Users can view own notifications" ON notifications;
CREATE POLICY "Users can view own notifications" ON notifications
    FOR SELECT USING (auth.uid()::text = user_id::text);

-- Sistem (triggerlar) bildirim ekleyebilir
DROP POLICY IF EXISTS "System can insert notifications" ON notifications;
CREATE POLICY "System can insert notifications" ON notifications
    FOR INSERT WITH CHECK (true);

-- =====================================================
-- ADIM 5: TEST
-- =====================================================

-- Test bildirimi oluştur (kendi user_id'nizi yazın)
-- INSERT INTO notifications (user_id, type, title, content, is_read)
-- VALUES (
--     'BURAYA_USER_ID',
--     'test',
--     'Test Bildirim',
--     'Bu bir testtir',
--     false
-- );

-- Son 10 bildirimi kontrol et
SELECT 
    id,
    user_id,
    type,
    title,
    content,
    is_read,
    created_at
FROM notifications
ORDER BY created_at DESC
LIMIT 10;

-- =====================================================
-- TAMAMLANDI!
-- =====================================================
✅ Mesaj bildirim sorunu çözüldü!
✅ "body" yerine "content" kullanılıyor!
✅ RLS politikaları güncellendi!
✅ Şimdi mesaj atmayı güvenle test edebilirsiniz!