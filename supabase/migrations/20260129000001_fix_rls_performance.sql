-- Fix RLS Performance Issues
-- Replace auth.uid() with (select auth.uid()) in all RLS policies
-- Merge multiple permissive policies into single policies

-- First, ensure is_admin column exists in profiles table
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'profiles' AND column_name = 'is_admin'
    ) THEN
        ALTER TABLE profiles ADD COLUMN is_admin BOOLEAN DEFAULT false;
    END IF;
END $$;

-- =====================================================
-- user_reports table - Fix auth_rls_initplan and merge policies
-- =====================================================

-- Drop ALL existing SELECT policies to avoid duplicates
DROP POLICY IF EXISTS "Kullanıcılar kendi şikayetlerini görebilir" ON user_reports;
DROP POLICY IF EXISTS "Admin tüm şikayetleri görebilir" ON user_reports;
DROP POLICY IF EXISTS "user_reports_select_unified" ON user_reports;

-- Create SINGLE unified SELECT policy (user sees own OR admin sees all)
CREATE POLICY "user_reports_select_unified"
ON user_reports FOR SELECT
USING (
  (select auth.uid()) = reporter_id OR
  EXISTS (
    SELECT 1 FROM profiles
    WHERE id = (select auth.uid()) AND is_admin = true
  )
);

DROP POLICY IF EXISTS "Kullanıcılar şikayet oluşturabilir" ON user_reports;
CREATE POLICY "Kullanıcılar şikayet oluşturabilir"
ON user_reports FOR INSERT
WITH CHECK ((select auth.uid()) = reporter_id);

DROP POLICY IF EXISTS "Admin şikayetleri güncelleyebilir" ON user_reports;
CREATE POLICY "Admin şikayetleri güncelleyebilir"
ON user_reports FOR UPDATE
USING (
  EXISTS (
    SELECT 1 FROM profiles
    WHERE id = (select auth.uid()) AND is_admin = true
  )
);

DROP POLICY IF EXISTS "Admin şikayetleri silebilir" ON user_reports;
CREATE POLICY "Admin şikayetleri silebilir"
ON user_reports FOR DELETE
USING (
  EXISTS (
    SELECT 1 FROM profiles
    WHERE id = (select auth.uid()) AND is_admin = true
  )
);

-- =====================================================
-- support_tickets table - Fix auth_rls_initplan and merge policies
-- =====================================================

-- Drop ALL existing SELECT policies to avoid duplicates
DROP POLICY IF EXISTS "Admin tüm destek taleplerini görebilir" ON support_tickets;
DROP POLICY IF EXISTS "Kullanıcılar kendi taleplerini görebilir veya admin" ON support_tickets;
DROP POLICY IF EXISTS "support_tickets_select_unified" ON support_tickets;

-- Create SINGLE unified SELECT policy
CREATE POLICY "support_tickets_select_unified"
ON support_tickets FOR SELECT
USING (
  (select auth.uid()) = user_id OR
  EXISTS (
    SELECT 1 FROM profiles 
    WHERE id = (select auth.uid()) AND is_admin = true
  )
);

-- Drop ALL existing UPDATE policies to avoid duplicates
DROP POLICY IF EXISTS "Admin destek taleplerini güncelleyebilir" ON support_tickets;
DROP POLICY IF EXISTS "Admin veya kullanıcı güncelleyebilir" ON support_tickets;
DROP POLICY IF EXISTS "support_tickets_update_unified" ON support_tickets;

-- Create SINGLE unified UPDATE policy
CREATE POLICY "support_tickets_update_unified"
ON support_tickets FOR UPDATE
USING (
  (select auth.uid()) = user_id OR
  EXISTS (
    SELECT 1 FROM profiles 
    WHERE id = (select auth.uid()) AND is_admin = true
  )
)
WITH CHECK (
  (select auth.uid()) = user_id OR
  EXISTS (
    SELECT 1 FROM profiles 
    WHERE id = (select auth.uid()) AND is_admin = true
  )
);

-- Drop and recreate DELETE policy
DROP POLICY IF EXISTS "Admin destek taleplerini silebilir" ON support_tickets;
CREATE POLICY "Admin destek taleplerini silebilir"
ON support_tickets FOR DELETE
USING (
  EXISTS (
    SELECT 1 FROM profiles 
    WHERE id = (select auth.uid()) AND is_admin = true
  )
);

-- =====================================================
-- profiles table - Fix auth_rls_initplan and merge policies
-- =====================================================

-- Drop ALL existing UPDATE policies to avoid duplicates
DROP POLICY IF EXISTS "Admins can update all profiles" ON profiles;
DROP POLICY IF EXISTS "Users can update own profile" ON profiles;
DROP POLICY IF EXISTS "profiles_update_unified" ON profiles;

-- Create SINGLE unified UPDATE policy (user updates own OR admin updates all)
CREATE POLICY "profiles_update_unified"
ON profiles FOR UPDATE
USING (
  (select auth.uid()) = id OR
  EXISTS (
    SELECT 1 FROM profiles
    WHERE id = (select auth.uid()) AND is_admin = true
  )
)
WITH CHECK (
  (select auth.uid()) = id OR
  EXISTS (
    SELECT 1 FROM profiles
    WHERE id = (select auth.uid()) AND is_admin = true
  )
);

DROP POLICY IF EXISTS "Admins can delete profiles" ON profiles;
CREATE POLICY "Admins can delete profiles"
ON profiles FOR DELETE
USING (
  EXISTS (
    SELECT 1 FROM profiles
    WHERE id = (select auth.uid()) AND is_admin = true
  )
);

-- =====================================================
-- categories table - Fix auth_rls_initplan
-- =====================================================

DROP POLICY IF EXISTS "categories_admin_insert_policy" ON categories;
CREATE POLICY "categories_admin_insert_policy"
ON categories FOR INSERT
WITH CHECK (
  EXISTS (
    SELECT 1 FROM profiles 
    WHERE id = (select auth.uid()) AND is_admin = true
  )
);

DROP POLICY IF EXISTS "categories_admin_update_policy" ON categories;
CREATE POLICY "categories_admin_update_policy"
ON categories FOR UPDATE
USING (
  EXISTS (
    SELECT 1 FROM profiles 
    WHERE id = (select auth.uid()) AND is_admin = true
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1 FROM profiles 
    WHERE id = (select auth.uid()) AND is_admin = true
  )
);

DROP POLICY IF EXISTS "categories_admin_delete_policy" ON categories;
CREATE POLICY "categories_admin_delete_policy"
ON categories FOR DELETE
USING (
  EXISTS (
    SELECT 1 FROM profiles 
    WHERE id = (select auth.uid()) AND is_admin = true
  )
);

-- =====================================================
-- orders table - Fix auth_rls_initplan and merge policies
-- =====================================================

-- Drop ALL existing policies (all variations)
DROP POLICY IF EXISTS "orders_select_policy" ON orders;
DROP POLICY IF EXISTS "orders_select_unified" ON orders;
DROP POLICY IF EXISTS "Users can delete own orders" ON orders;
DROP POLICY IF EXISTS "orders_delete_policy" ON orders;
DROP POLICY IF EXISTS "orders_delete_unified" ON orders;
DROP POLICY IF EXISTS "Users can insert own orders" ON orders;
DROP POLICY IF EXISTS "orders_insert_policy" ON orders;
DROP POLICY IF EXISTS "orders_insert_unified" ON orders;
DROP POLICY IF EXISTS "orders_update_policy" ON orders;
DROP POLICY IF EXISTS "orders_update_unified" ON orders;

-- Create unified policies only if they don't exist
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
        AND tablename = 'orders'
        AND policyname = 'orders_select_unified'
    ) THEN
        CREATE POLICY "orders_select_unified"
        ON orders FOR SELECT
        USING ((select auth.uid()) = user_id);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
        AND tablename = 'orders'
        AND policyname = 'orders_insert_unified'
    ) THEN
        CREATE POLICY "orders_insert_unified"
        ON orders FOR INSERT
        WITH CHECK ((select auth.uid()) = user_id);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
        AND tablename = 'orders'
        AND policyname = 'orders_update_unified'
    ) THEN
        CREATE POLICY "orders_update_unified"
        ON orders FOR UPDATE
        USING ((select auth.uid()) = user_id)
        WITH CHECK ((select auth.uid()) = user_id);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
        AND tablename = 'orders'
        AND policyname = 'orders_delete_unified'
    ) THEN
        CREATE POLICY "orders_delete_unified"
        ON orders FOR DELETE
        USING ((select auth.uid()) = user_id);
    END IF;
END $$;

-- =====================================================
-- account_deletion_codes table - Fix auth_rls_initplan
-- =====================================================

DROP POLICY IF EXISTS "Users can view own deletion codes" ON account_deletion_codes;
CREATE POLICY "Users can view own deletion codes"
ON account_deletion_codes FOR SELECT
USING ((select auth.uid()) = user_id);
