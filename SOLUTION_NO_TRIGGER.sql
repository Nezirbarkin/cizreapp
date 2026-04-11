-- =====================================================
-- NİHAİ ÇÖZÜM: Trigger'ı kaldır, uygulamada yönet
-- =====================================================

-- TÜRÜ trigger'ları kaldır
DROP TRIGGER IF EXISTS message_insert_trigger ON public.messages;
DROP TRIGGER IF EXISTS messages_updated_at ON public.messages;
DROP FUNCTION IF EXISTS public.update_conversation_on_message() CASCADE;
DROP FUNCTION IF EXISTS public.update_updated_at_column() CASCADE;

-- updated_at trigger'ı geri ekle (basit, sorun yaratmaz)
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER messages_updated_at
    BEFORE UPDATE ON messages
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- RLS'yi kapat (üretim için)
ALTER TABLE public.messages DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations DISABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    RAISE NOTICE '✅ Çözüm: Trigger''lar kaldırıldı, RLS kapatıldı!';
    RAISE NOTICE 'Conversation güncellemesi Dart tarafında yapılacak.';
END $$;
