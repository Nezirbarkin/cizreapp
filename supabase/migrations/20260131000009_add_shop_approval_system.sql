-- Dükkan onay sistemi için is_approved alanı ekle

-- is_approved kolonu ekle (yoksa)
DO $$ 
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' 
        AND table_name = 'shops' 
        AND column_name = 'is_approved'
    ) THEN
        ALTER TABLE public.shops 
        ADD COLUMN is_approved BOOLEAN DEFAULT FALSE;
        
        COMMENT ON COLUMN public.shops.is_approved IS 'Admin tarafından onaylanmış dükkanlar müşterilere gösterilir';
    END IF;
END $$;

-- Dükkanları listelerken sadece onaylı ve aktif olanları getirmek için SELECT policy
DO $$
BEGIN
    DROP POLICY IF EXISTS "shops_select_own" ON public.shops;
    DROP POLICY IF EXISTS "shops_select_public" ON public.shops;
    DROP POLICY IF EXISTS "shops_select_combined" ON public.shops;
    
    -- Müşteri ve satıcılar için: Sadece onaylı ve aktif dükkanları görebilir
    -- Admin ise tüm dükkanları görebilir
    CREATE POLICY "shops_select_combined" ON public.shops
        FOR SELECT TO authenticated
        USING (
            -- Admin tüm dükkanları görebilir
            EXISTS (
                SELECT 1 FROM public.profiles
                WHERE id = (SELECT auth.uid())
                AND role = 'admin'
            )
            OR
            -- Dükkan sahibi kendi dükkanını görebilir (onay beklerken)
            owner_id = (SELECT auth.uid())
            OR
            -- Diğer kullanıcılar sadece onaylı ve aktif dükkanları görebilir
            (is_approved = true AND is_active = true)
        );
END $$;
