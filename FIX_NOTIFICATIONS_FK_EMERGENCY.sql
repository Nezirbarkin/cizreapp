-- ============================================================================
-- ACİL DÜZELTME - FOREIGN KEY CONSTRAINT'LERİ KALDIR
-- ============================================================================
-- NOTIFICATIONS foreign key constraint'lerini geçici olarak kaldırır
-- Böylece notifications trigger'ları çalışmaya devam eder
-- ============================================================================

-- 1. actor_id foreign key'i kaldır (veya NO ACTION yap)
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.table_constraints 
        WHERE constraint_schema = 'public' 
          AND table_name = 'notifications' 
          AND constraint_name = 'notifications_actor_id_fkey'
    ) THEN
        ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_actor_id_fkey;
        RAISE NOTICE 'actor_id foreign key KALDIRILDI';
    END IF;
END $$;

-- 2. user_id foreign key'i kaldır
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.table_constraints 
        WHERE constraint_schema = 'public' 
          AND table_name = 'notifications' 
          AND constraint_name = 'notifications_user_id_fkey'
    ) THEN
        ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_user_id_fkey;
        RAISE NOTICE 'user_id foreign key KALDIRILDI';
    END IF;
END $$;

-- 3. processed_by foreign key'i kaldır (varsa)
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.table_constraints 
        WHERE constraint_schema = 'public' 
          AND table_name = 'notifications' 
          AND constraint_name = 'notifications_processed_by_fkey'
    ) THEN
        ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_processed_by_fkey;
        RAISE NOTICE 'processed_by foreign key KALDIRILDI';
    END IF;
END $$;

-- Sonuç
DO $$
BEGIN
    RAISE NOTICE '================================================================';
    RAISE NOTICE 'ACİL DÜZELTME TAMAMLANDI!';
    RAISE NOTICE '================================================================';
    RAISE NOTICE 'Notifications foreign key constraint''leri KALDIRILDI';
    RAISE NOTICE 'Notifications trigger''ları çalışmaya devam edecek';
    RAISE NOTICE 'actor_id kontrolü YAPILMAYACAK (geçici çözüm)';
    RAISE NOTICE '================================================================';
END $$;
