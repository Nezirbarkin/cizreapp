-- Shops tablosuna is_verified kolonu ekle ve RLS policy'lerini güncelle

-- is_verified kolonu yoksa ekle
DO $$ 
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' 
        AND table_name = 'shops' 
        AND column_name = 'is_verified'
    ) THEN
        ALTER TABLE public.shops 
        ADD COLUMN is_verified BOOLEAN DEFAULT FALSE;
        
        COMMENT ON COLUMN public.shops.is_verified IS 'Dükkanın admin tarafından doğrulanıp doğrulanmadığı';
    END IF;
END $$;

-- Admin'in is_verified güncelleyebilmesi için UPDATE policy'yi kontrol et
-- Mevcut UPDATE policy'leri listele ve gerekirse güncelle
DO $$
BEGIN
    -- Tüm eski UPDATE policy'lerini sil
    DROP POLICY IF EXISTS "shops_update_admin" ON public.shops;
    DROP POLICY IF EXISTS "shops_update_owner" ON public.shops;
    DROP POLICY IF EXISTS "shops_update_combined" ON public.shops;
    DROP POLICY IF EXISTS "shops_update_unified" ON public.shops;
    
    -- Birleşik UPDATE policy oluştur
    CREATE POLICY "shops_update_combined" ON public.shops
        FOR UPDATE TO authenticated
        USING (
            -- Dükkan sahibi kendi dükkanını güncelleyebilir
            owner_id = (SELECT auth.uid())
            OR
            -- Admin her dükkanı güncelleyebilir
            EXISTS (
                SELECT 1 FROM public.profiles
                WHERE id = (SELECT auth.uid())
                AND role = 'admin'
            )
        )
        WITH CHECK (
            -- Dükkan sahibi kendi dükkanını güncelleyebilir
            owner_id = (SELECT auth.uid())
            OR
            -- Admin her dükkanı güncelleyebilir
            EXISTS (
                SELECT 1 FROM public.profiles
                WHERE id = (SELECT auth.uid())
                AND role = 'admin'
            )
        );
END $$;
