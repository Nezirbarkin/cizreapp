-- =====================================================
-- REALTIME CHECK: messages tablosu için replication kontrolü
-- =====================================================

-- 1. Realtime publications kontrolü
SELECT pubname 
FROM pg_publication 
WHERE pubname IN ('supabase_realtime', 'messages_publication');

-- 2. Messages tablosunun replication durumunu kontrol et
SELECT schemaname, tablename, pubname 
FROM pg_publication_tables 
WHERE pubname IN ('supabase_realtime', 'messages_publication')
  AND schemaname = 'public';

-- 3. Eğer yoksa, realtime replication'ı etkinleştir
-- (Bu komutu sadece sonuç yoksa çalıştırın)
-- ALTER PUBLICATION supabase_realtime ADD TABLE public.messages;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables 
        WHERE pubname = 'supabase_realtime' 
        AND schemaname = 'public' 
        AND tablename = 'messages'
    ) THEN
        RAISE NOTICE '⚠️ messages tablosu realtime için yayınlanmıyor!';
        RAISE NOTICE 'Şu SQL'i çalıştırın: ALTER PUBLICATION supabase_realtime ADD TABLE public.messages;';
    ELSE
        RAISE NOTICE '✅ messages tablosu realtime için yayınlanıyor!';
    END IF;
END $$;
