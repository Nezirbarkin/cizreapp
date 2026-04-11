-- =====================================================
-- NÜKLEER SEÇENEK: Tüm trigger'ları kaldır ve test et
-- =====================================================

-- TÜM messages trigger'larını kaldır
DO $$
DECLARE
    trg RECORD;
BEGIN
    FOR trg IN 
        SELECT trigger_name 
        FROM information_schema.triggers 
        WHERE event_object_schema = 'public' 
          AND event_object_table = 'messages'
    LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS %I ON public.messages', trg.trigger_name);
        RAISE NOTICE 'Trigger silindi: %', trg.trigger_name;
    END LOOP;
END $$;

-- Kontrol: Trigger kalmadı mı?
SELECT trigger_name, action_statement
FROM information_schema.triggers
WHERE event_object_schema = 'public' AND event_object_table = 'messages';

DO $$
BEGIN
    RAISE NOTICE '✅ Tüm messages trigger''ları silindi!';
END $$;
