-- =====================================================
-- ADIM 2: TRIGGER'I RLS OLMADAN EKLE
-- =====================================================
-- Bu SQL, conversation tablosunu güncellemek için
-- trigger ekler ama RLS'i KAPALI tutar
--
-- RLS olmadan trigger'da UUID karşılaştırma sorunu olmaz

-- Conversation güncelleme trigger'ı
CREATE OR REPLACE FUNCTION update_conversation_on_message()
RETURNS TRIGGER AS $$
DECLARE
    v_other_user_id UUID;
BEGIN
    -- Diğer kullanıcı ID'sini bul
    SELECT other_user_id INTO v_other_user_id
    FROM conversations
    WHERE id = NEW.conversation_id;
    
    -- Conversation tablosunu güncelle
    UPDATE conversations
    SET last_message_at = NOW(),
        last_message_content = NEW.content,
        last_message_sender_id = NEW.sender_id
    WHERE id = NEW.conversation_id;
    
    -- Okunmamış mesaj sayısını artır (alıcı için)
    UPDATE conversations
    SET unread_count = COALESCE(unread_count, 0) + 1
    WHERE id = NEW.conversation_id
      AND other_user_id != NEW.sender_id;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger'ı oluştur
DROP TRIGGER IF EXISTS message_insert_trigger ON public.messages;
CREATE TRIGGER message_insert_trigger
    AFTER INSERT ON public.messages
    FOR EACH ROW
    EXECUTE FUNCTION update_conversation_on_message();

DO $$
BEGIN
    RAISE NOTICE '✅ Trigger eklendi (RLS olmadan çalışır)';
    RAISE NOTICE '   - Conversation güncellemesi otomatik';
    RAISE NOTICE '   - Okunmamış sayacı artar';
    RAISE NOTICE '   - RLS kapalı, UUID sorunu olmaz';
END $$;
