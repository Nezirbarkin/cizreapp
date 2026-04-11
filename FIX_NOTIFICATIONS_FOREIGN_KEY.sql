-- ============================================================================
-- NOTIFICATIONS ACTOR_ID FOREIGN KEY DÜZELTME
-- ============================================================================
-- Sorun: notifications.actor_id -> users.id referans ediyor ama trigger'lar profiles.id kullanıyor
-- Çözüm: Foreign key'i profiles.id'ye değiştir

-- 1. Mevcut foreign key'i kaldır
ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_actor_id_fkey;

-- 2. Yeni foreign key'i profiles.id'ye ekle
ALTER TABLE public.notifications
  ADD CONSTRAINT notifications_actor_id_fkey
  FOREIGN KEY (actor_id) REFERENCES public.profiles(id) ON DELETE SET NULL;

-- 3. user_id foreign key'i de kontrol et ve düzelt
ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_user_id_fkey;
ALTER TABLE public.notifications
  ADD CONSTRAINT notifications_user_id_fkey
  FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;

-- 4. processed_by sütunu varsa foreign key'i düzelt
DO $$
BEGIN
    -- Sütunun var olup olmadığını kontrol et
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'notifications'
          AND column_name = 'processed_by'
    ) THEN
        -- Mevcut foreign key'i kaldır
        IF EXISTS (
            SELECT 1
            FROM information_schema.table_constraints tc
            JOIN information_schema.key_column_usage kcu
                ON tc.constraint_name = kcu.constraint_name
            WHERE tc.table_schema = 'public'
              AND tc.table_name = 'notifications'
              AND tc.constraint_type = 'FOREIGN KEY'
              AND kcu.column_name = 'processed_by'
        ) THEN
            EXECUTE 'ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_processed_by_fkey';
        END IF;
        
        -- Yeni foreign key'i ekle
        EXECUTE 'ALTER TABLE public.notifications
            ADD CONSTRAINT notifications_processed_by_fkey
            FOREIGN KEY (processed_by) REFERENCES public.profiles(id) ON DELETE SET NULL';
            
        RAISE NOTICE 'processed_by foreign key düzeltildi';
    ELSE
        RAISE NOTICE 'processed_by sütunu bulunamadı, atlanıyor';
    END IF;
END $$;

-- 5. Kontrol
DO $$
BEGIN
    RAISE NOTICE '================================================================';
    RAISE NOTICE 'NOTIFICATIONS FOREIGN KEY DÜZELTME TAMAMLANDI!';
    RAISE NOTICE '================================================================';
    RAISE NOTICE 'actor_id -> profiles.id';
    RAISE NOTICE 'user_id -> profiles.id';
    RAISE NOTICE 'processed_by -> profiles.id';
    RAISE NOTICE '================================================================';
END $$;
