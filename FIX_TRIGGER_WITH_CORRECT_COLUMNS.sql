-- =====================================================
-- TAM ÇÖZÜM: Trigger + Bildirim (DOĞRU KOLON ADLARIYLA)
-- =====================================================
-- Bu SQL:
-- 1. RLS'yi kapatır
-- 2. Trigger'ı doğru kolon adlarıyla ekler
-- 3. Mesaj bildirimleri için sistem kurar

-- ============================================
-- ADIM 1: Temizlik
-- ============================================
DROP TRIGGER IF EXISTS message_insert_trigger ON public.messages;
DROP TRIGGER IF EXISTS messages_updated_at ON public.messages;
DROP FUNCTION IF EXISTS public.update_conversation_on_message() CASCADE;
DROP FUNCTION IF EXISTS public.update_updated_at_column() CASCADE;

-- RLS'yi kapat
ALTER TABLE public.messages DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations DISABLE ROW LEVEL SECURITY;

-- ============================================
-- ADIM 2: updated_at trigger'ı
-- ============================================
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER messages_updated_at
    BEFORE UPDATE ON public.messages
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- ============================================
-- ADIM 3: Conversation güncelleme trigger'ı
-- ============================================
CREATE OR REPLACE FUNCTION update_conversation_on_message()
RETURNS TRIGGER AS $$
DECLARE
    v_other_user_id UUID;
    v_sender_username TEXT;
BEGIN
    -- Diğer kullanıcı ID'sini bul
    SELECT other_user_id INTO v_other_user_id
    FROM conversations
    WHERE id = NEW.conversation_id;
    
    -- Gönderen kullanıcı adını al
    SELECT username INTO v_sender_username
    FROM profiles
    WHERE id = NEW.sender_id;
    
    -- Conversation tablosunu güncelle (DOĞRU KOLON ADLARI)
    UPDATE conversations
    SET last_message_time = NOW(),
        last_message = NEW.content,
        unread_count = COALESCE(unread_count, 0) + 1
    WHERE id = NEW.conversation_id
      AND other_user_id != NEW.sender_id;
    
    -- Ayrıca sender için de güncelle (unread_count artmaz ama son mesaj güncellenir)
    UPDATE conversations
    SET last_message_time = NOW(),
        last_message = NEW.content
    WHERE id = NEW.conversation_id
      AND other_user_id = NEW.sender_id;
    
    -- Bildirim oluştur (alıcı için)
    INSERT INTO notifications (
        user_id,
        type,
        title,
        body,
        data,
        created_at
    )
    SELECT 
        v_other_user_id,
        'message',
        'Yeni Mesaj',
        COALESCE(v_sender_username, 'Bir kullanıcı') || ': ' || 
        CASE WHEN LENGTH(NEW.content) > 50 THEN LEFT(NEW.content, 50) || '...' ELSE NEW.content END,
        jsonb_build_object(
            'conversation_id', NEW.conversation_id,
            'message_id', NEW.id,
            'sender_id', NEW.sender_id
        ),
        NOW()
    WHERE v_other_user_id IS NOT NULL
      AND v_other_user_id != NEW.sender_id;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger'ı oluştur
CREATE TRIGGER message_insert_trigger
    AFTER INSERT ON public.messages
    FOR EACH ROW
    EXECUTE FUNCTION update_conversation_on_message();

-- ============================================
-- ADIM 4: Realtime kontrolü
-- ============================================
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

-- ============================================
-- SONUÇ
-- ============================================
DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '═══════════════════════════════════════════════';
    RAISE NOTICE '✅ TAM ÇÖZÜM UYGULANDI!';
    RAISE NOTICE '═══════════════════════════════════════════════';
    RAISE NOTICE '✅ RLS kapatıldı';
    RAISE NOTICE '✅ Trigger eklendi (dogru kolon adlariyla)';
    RAISE NOTICE '✅ Bildirim sistemi aktif';
    RAISE NOTICE '✅ Realtime aktif';
    RAISE NOTICE '';
    RAISE NOTICE 'Kolon adlari: last_message, last_message_time';
    RAISE NOTICE '═══════════════════════════════════════════════';
    RAISE NOTICE '';
END $$;
