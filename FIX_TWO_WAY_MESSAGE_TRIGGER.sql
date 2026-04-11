-- =====================================================
-- İKİ YÖNLÜ MESAJ TRIGGER'I
-- =====================================================
-- Bu trigger mesaj gönderildiğinde hem gönderenin hem de alıcının
-- conversation'ını günceller
-- =====================================================

-- Önceki trigger'ı kaldır
DROP TRIGGER IF EXISTS message_insert_trigger ON public.messages;
DROP FUNCTION IF EXISTS public.update_conversation_on_message();
DROP FUNCTION IF EXISTS public.update_updated_at_column();

-- updated_at güncelleme fonksiyonu
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger oluştur
CREATE TRIGGER messages_updated_at
    BEFORE UPDATE ON public.messages
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- İKİ YÖNLÜ conversation güncelleme fonksiyonu
CREATE OR REPLACE FUNCTION update_conversation_on_message()
RETURNS TRIGGER AS $$
DECLARE
    v_sender_user_id UUID;
    v_other_user_id UUID;
    v_sender_username TEXT;
    v_recipient_conv_id UUID;
BEGIN
    -- Conversation'daki kullanıcıları bul
    SELECT user_id, other_user_id INTO v_sender_user_id, v_other_user_id
    FROM conversations
    WHERE id = NEW.conversation_id;
    
    -- Gönderen kullanıcı adını al
    SELECT username INTO v_sender_username
    FROM profiles
    WHERE id = NEW.sender_id;
    
    -- 1. GÖNDERENİN CONVERSATION'INI GÜNCELLE
    UPDATE conversations
    SET last_message_time = NOW(),
        last_message = NEW.content,
        updated_at = NOW()
    WHERE id = NEW.conversation_id;
    
    -- 2. ALICININ CONVERSATION'INI BUL VEYA OLUŞTUR
    -- Alıcının conversation'ını bul (user_id = other_user_id, other_user_id = sender_id)
    SELECT id INTO v_recipient_conv_id
    FROM conversations
    WHERE user_id = v_other_user_id
      AND other_user_id = v_sender_user_id;
    
    -- Eğer alıcının conversation'ı yoksa, oluştur
    IF v_recipient_conv_id IS NULL THEN
        INSERT INTO conversations (user_id, other_user_id, last_message, last_message_time, unread_count, created_at, updated_at)
        VALUES (v_other_user_id, v_sender_user_id, NEW.content, NOW(), 1, NOW(), NOW())
        RETURNING id INTO v_recipient_conv_id;
    ELSE
        -- Alıcının conversation'ını güncelle (unread_count artır)
        UPDATE conversations
        SET last_message_time = NOW(),
            last_message = NEW.content,
            unread_count = COALESCE(unread_count, 0) + 1,
            updated_at = NOW()
        WHERE id = v_recipient_conv_id;
    END IF;
    
    -- 3. ALICIYA BİLDİRİM GÖNDER
    IF v_other_user_id IS NOT NULL AND v_other_user_id != NEW.sender_id THEN
        INSERT INTO notifications (
            user_id,
            type,
            title,
            content,
            is_read,
            data,
            created_at
        )
        VALUES (
            v_other_user_id,
            'message',
            '📨 Yeni Mesaj',
            COALESCE(v_sender_username, 'Bir kullanıcı') || ': ' || 
            CASE WHEN LENGTH(NEW.content) > 50 THEN LEFT(NEW.content, 50) || '...' ELSE NEW.content END,
            false,
            jsonb_build_object(
                'conversation_id', v_recipient_conv_id,
                'message_id', NEW.id,
                'sender_id', NEW.sender_id
            ),
            NOW()
        );
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger'ı oluştur
CREATE TRIGGER message_insert_trigger
    AFTER INSERT ON public.messages
    FOR EACH ROW
    EXECUTE FUNCTION update_conversation_on_message();

-- Realtime ekle
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' 
        AND schemaname = 'public' 
        AND tablename = 'messages'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.messages;
    END IF;
END $$;

-- =====================================================
-- TEST
-- =====================================================

-- Son 5 bildirimi göster
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
LIMIT 5;

-- =====================================================
-- TAMAMLANDİ!
-- =====================================================
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '═══════════════════════════════════════════════';
    RAISE NOTICE '✅ İKİ YÖNLÜ MESAJ SİSTEMİ AKTİF!';
    RAISE NOTICE '═══════════════════════════════════════════════';
    RAISE NOTICE '✅ Gönderen conversation güncellenir';
    RAISE NOTICE '✅ Alıcı conversation oluşturulur/güncellenir';
    RAISE NOTICE '✅ Bildirim gönderilir';
    RAISE NOTICE '═══════════════════════════════════════════════';
    RAISE NOTICE '';
END $$;
