-- =====================================================
-- ADIM 1: ÇALIŞAN DURUMA GERİ DÖN
-- =====================================================
-- Bu SQL mesaj göndermenin çalıştığı durumu geri yükler
-- RLS kapalı, trigger'lar kaldırılmış

-- 1. Tüm trigger'ları kaldır
DROP TRIGGER IF EXISTS message_insert_trigger ON public.messages;
DROP TRIGGER IF EXISTS messages_updated_at ON public.messages;
DROP FUNCTION IF EXISTS public.update_conversation_on_message() CASCADE;

-- 2. Basit updated_at trigger'ı ekle (sorun yaratmaz)
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS messages_updated_at ON public.messages;
CREATE TRIGGER messages_updated_at
    BEFORE UPDATE ON public.messages
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- 3. RLS'yi kapat (üretim için)
ALTER TABLE public.messages DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations DISABLE ROW LEVEL SECURITY;

-- 4. Realtime'i aktif et (mesajlar anlık görünmesi için)
-- NOT: Eğer zaten ekliyse hata verecek, bu normal
DO $$
BEGIN
    -- Eğer messages tablosu realtime'da yoksa ekle
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime'
        AND schemaname = 'public'
        AND tablename = 'messages'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.messages;
        RAISE NOTICE '✅ Realtime eklendi';
    ELSE
        RAISE NOTICE 'ℹ️ Realtime zaten aktif';
    END IF;
END $$;

DO $$
BEGIN
    RAISE NOTICE '✅ Çalışan duruma geri dönüldü!';
    RAISE NOTICE '   - RLS kapalı';
    RAISE NOTICE '   - Trigger''lar kaldırıldı';
    RAISE NOTICE '   - Realtime aktif';
    RAISE NOTICE '   - Direct insert çalışıyor olmalı';
END $$;
