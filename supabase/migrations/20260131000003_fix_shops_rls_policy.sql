-- Fix shops RLS policy for UPDATE to allow IBAN updates
-- Problem: The UPDATE policy was missing WITH CHECK clause
-- This caused updates to fail silently when sellers tried to save IBAN info

DO $$
BEGIN
    -- Drop existing policy
    DROP POLICY IF EXISTS "Shop owners can update own shop" ON public.shops;
    
    -- Create new policy with both USING and WITH CHECK
    CREATE POLICY "Shop owners can update own shop" ON public.shops
        FOR UPDATE
        USING (owner_id = (select auth.uid()))
        WITH CHECK (owner_id = (select auth.uid()));
END $$;

-- Also ensure all shops policies are properly set
DO $$
BEGIN
    -- SELECT policy - anyone can see active shops
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE tablename = 'shops' 
        AND policyname = 'shops_select_policy'
    ) THEN
        CREATE POLICY "shops_select_policy" ON public.shops
            FOR SELECT USING (is_active = true);
    END IF;

    -- INSERT policy - sellers can insert shops with their owner_id
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE tablename = 'shops' 
        AND policyname = 'shops_insert_policy'
    ) THEN
        CREATE POLICY "shops_insert_policy" ON public.shops
            FOR INSERT WITH CHECK (owner_id = (select auth.uid()));
    END IF;

    -- DELETE policy - sellers can delete their own shops
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE tablename = 'shops' 
        AND policyname = 'shops_delete_policy'
    ) THEN
        CREATE POLICY "shops_delete_policy" ON public.shops
            FOR DELETE USING (owner_id = (select auth.uid()));
    END IF;
END $$;

-- Grant necessary permissions
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT ALL ON public.shops TO authenticated;
