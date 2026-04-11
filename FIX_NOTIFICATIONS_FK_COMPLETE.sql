-- ============================================================================
-- NOTIFICATIONS FOREIGN KEY TAM DÜZELTME
-- ============================================================================
-- 1. Actor ID'yi profiles tablosuna ekle (eğer yoksa)
-- 2. Foreign key'i profiles.id'ye değiştir
-- ============================================================================

-- 1. Önce auth.users'ta olan ama profiles'ta olmayan ID'leri profiles'e ekle
INSERT INTO public.profiles (id, username, full_name, created_at, updated_at)
SELECT 
    id,
    email || '_user' as username,
    COALESCE(raw_user_meta_data->>'full_name', email) as full_name,
    created_at,
    updated_at
FROM auth.users
WHERE NOT EXISTS (
    SELECT 1 FROM public.profiles WHERE public.profiles.id = auth.users.id
);

-- 2. Mevcut foreign key'i kaldır
DO $$
BEGIN
    -- actor_id foreign key
    IF EXISTS (
        SELECT 1 FROM information_schema.table_constraints 
        WHERE constraint_schema = 'public' 
          AND table_name = 'notifications' 
          AND constraint_name = 'notifications_actor_id_fkey'
    ) THEN
        ALTER TABLE public.notifications DROP CONSTRAINT notifications_actor_id_fkey;
        RAISE NOTICE 'notifications_actor_id_fkey kaldırıldı';
    END IF;
    
    -- user_id foreign key
    IF EXISTS (
        SELECT 1 FROM information_schema.table_constraints 
        WHERE constraint_schema = 'public' 
          AND table_name = 'notifications' 
          AND constraint_name = 'notifications_user_id_fkey'
    ) THEN
        ALTER TABLE public.notifications DROP CONSTRAINT notifications_user_id_fkey;
        RAISE NOTICE 'notifications_user_id_fkey kaldırıldı';
    END IF;
    
    -- processed_by foreign key (varsa)
    IF EXISTS (
        SELECT 1 FROM information_schema.table_constraints 
        WHERE constraint_schema = 'public' 
          AND table_name = 'notifications' 
          AND constraint_name = 'notifications_processed_by_fkey'
    ) THEN
        ALTER TABLE public.notifications DROP CONSTRAINT notifications_processed_by_fkey;
        RAISE NOTICE 'notifications_processed_by_fkey kaldırıldı';
    END IF;
END $$;

-- 3. Yeni foreign key'leri profiles.id'ye ekle
ALTER TABLE public.notifications
  ADD CONSTRAINT notifications_actor_id_fkey
  FOREIGN KEY (actor_id) REFERENCES public.profiles(id) ON DELETE SET NULL;

ALTER TABLE public.notifications
  ADD CONSTRAINT notifications_user_id_fkey
  FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;

-- 4. processed_by sütunu varsa onun için de foreign key ekle
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' 
          AND table_name = 'notifications' 
          AND column_name = 'processed_by'
    ) THEN
        ALTER TABLE public.notifications
          ADD CONSTRAINT notifications_processed_by_fkey
          FOREIGN KEY (processed_by) REFERENCES public.profiles(id) ON DELETE SET NULL;
        RAISE NOTICE 'processed_by foreign key eklendi';
    END IF;
END $$;

-- 5. Sonuç
DO $$
BEGIN
    RAISE NOTICE '================================================================';
    RAISE NOTICE 'NOTIFICATIONS FOREIGN KEY DÜZELTME TAMAMLANDI!';
    RAISE NOTICE '================================================================';
    RAISE NOTICE '1. auth.users''ta olan ama profiles''ta olmayan kullanıcılar eklendi';
    RAISE NOTICE '2. actor_id FK -> profiles.id';
    RAISE NOTICE '3. user_id FK -> profiles.id';
    RAISE NOTICE '4. processed_by FK -> profiles.id (sütun varsa)';
    RAISE NOTICE '================================================================';
END $$;
