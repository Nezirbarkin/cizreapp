-- ================================================
-- RLS PERFORMANS UYARILARI ÇÖZÜMÜ
-- ================================================
-- Bu script Supabase Database Linter uyarılarını düzeltir:
-- 1. auth_rls_initplan - auth.uid() her satırda tekrar değerlendiriliyor
-- 2. multiple_permissive_policies - Aynı role/action'da birden fazla policy
--
-- UYARI: Rate limiting olabilir, adım adım çalıştırın
-- ================================================

-- ================================================
-- BÖLÜM 1: PROFILES TABLOSU RLS POLICY'LERİ
-- ================================================

-- Önce mevcut policy'leri kontrol et
SELECT policyname, cmd, roles, permissive
FROM pg_policies 
WHERE tablename = 'profiles'
ORDER BY cmd, policyname;

-- 1.1. INSERT policy - Tek bir policy yap (multiple_permissive_policies düzelt)
DROP POLICY IF EXISTS "Users can insert own profile" ON profiles;
DROP POLICY IF EXISTS "profiles_insert_policy" ON profiles;
DROP POLICY IF EXISTS "Users can insert their own profile" ON profiles;

-- Optimize edilmiş INSERT policy (auth_rls_initplan düzelt)
CREATE POLICY "Users can insert own profile"
ON profiles
FOR INSERT
TO authenticated
WITH CHECK ((select auth.uid()) = id);  -- (select auth.uid()) ile subquery'a alındı

-- 1.2. UPDATE policy - Tek bir policy yap
DROP POLICY IF EXISTS "Users can update own profile" ON profiles;
DROP POLICY IF EXISTS "profiles_update_unified" ON profiles;
DROP POLICY IF EXISTS "profiles_update_policy" ON profiles;

-- Optimize edilmiş UPDATE policy
CREATE POLICY "Users can update own profile"
ON profiles
FOR UPDATE
TO authenticated
USING ((select auth.uid()) = id)      -- Subquery ile optimize
WITH CHECK ((select auth.uid()) = id);

-- 1.3. SELECT policy - Tek bir unified policy yap
DROP POLICY IF EXISTS "Public profiles are viewable by everyone" ON profiles;
DROP POLICY IF EXISTS "profiles_select_unified" ON profiles;
DROP POLICY IF EXISTS "Users can view all profiles" ON profiles;
DROP POLICY IF EXISTS "profiles_select_policy" ON profiles;

-- Optimize edilmiş SELECT policy (herkes için, anon + authenticated)
CREATE POLICY "profiles_select_unified"
ON profiles
FOR SELECT
USING (true);  -- Herkes profilleri görebilir (public read)

-- ================================================
-- BÖLÜM 2: CONVERSATIONS TABLOSU RLS POLICY'LERİ
-- ================================================

-- Mevcut policy'leri kontrol et
SELECT policyname, cmd, roles, permissive
FROM pg_policies 
WHERE tablename = 'conversations'
ORDER BY cmd, policyname;

-- 2.1. SELECT policy - Tek bir unified policy yap
DROP POLICY IF EXISTS "conversations_select_own" ON conversations;
DROP POLICY IF EXISTS "conversations_select_policy" ON conversations;
DROP POLICY IF EXISTS "conversations_select_unified" ON conversations;

-- Optimize edilmiş SELECT policy
CREATE POLICY "conversations_select_unified"
ON conversations
FOR SELECT
TO authenticated
USING (
  -- Kullanıcının olduğu sohbetleri görebilir (user_id veya other_user_id)
  user_id = (select auth.uid()) OR
  other_user_id = (select auth.uid())
);

-- ================================================
-- BÖLÜM 3: MESSAGES TABLOSU RLS POLICY'LERİ
-- ================================================

-- Mevcut policy'leri kontrol et
SELECT policyname, cmd, roles, permissive
FROM pg_policies 
WHERE tablename = 'messages'
ORDER BY cmd, policyname;

-- 3.1. SELECT policy
DROP POLICY IF EXISTS "messages_select_policy" ON messages;
DROP POLICY IF EXISTS "messages_select_unified" ON messages;

CREATE POLICY "messages_select_unified"
ON messages
FOR SELECT
TO authenticated
USING (
  conversation_id IN (
    SELECT id FROM conversations
    WHERE user_id = (select auth.uid()) OR other_user_id = (select auth.uid())
  )
);

-- 3.2. INSERT policy
DROP POLICY IF EXISTS "messages_insert_policy" ON messages;
DROP POLICY IF EXISTS "messages_insert_unified" ON messages;

CREATE POLICY "messages_insert_unified"
ON messages
FOR INSERT
TO authenticated
WITH CHECK (
  sender_id = (select auth.uid()) AND
  conversation_id IN (
    SELECT id FROM conversations
    WHERE user_id = (select auth.uid()) OR other_user_id = (select auth.uid())
  )
);

-- 3.3. UPDATE policy
DROP POLICY IF EXISTS "messages_update_policy" ON messages;
DROP POLICY IF EXISTS "messages_update_unified" ON messages;

CREATE POLICY "messages_update_unified"
ON messages
FOR UPDATE
TO authenticated
USING ((select auth.uid()) = sender_id)
WITH CHECK ((select auth.uid()) = sender_id);

-- 3.4. DELETE policy
DROP POLICY IF EXISTS "messages_delete_policy" ON messages;
DROP POLICY IF EXISTS "messages_delete_unified" ON messages;

CREATE POLICY "messages_delete_unified"
ON messages
FOR DELETE
TO authenticated
USING ((select auth.uid()) = sender_id);

-- ================================================
-- BÖLÜM 4: DOĞRULAMA
-- ================================================

-- 4.1. Profiles policy'leri kontrol
SELECT 
    policyname, 
    cmd, 
    array_to_string(roles, ', ') as roles,
    permissive
FROM pg_policies 
WHERE tablename = 'profiles'
ORDER BY cmd, policyname;

-- 4.2. Conversations policy'leri kontrol
SELECT 
    policyname, 
    cmd, 
    array_to_string(roles, ', ') as roles,
    permissive
FROM pg_policies 
WHERE tablename = 'conversations'
ORDER BY cmd, policyname;

-- 4.3. Messages policy'leri kontrol
SELECT 
    policyname, 
    cmd, 
    array_to_string(roles, ', ') as roles,
    permissive
FROM pg_policies 
WHERE tablename = 'messages'
ORDER BY cmd, policyname;

-- 4.4. Her role/action için policy sayısı kontrol (multiple_permissive_policies kontrolü)
WITH policy_counts AS (
  SELECT
    schemaname,
    tablename,
    cmd,
    roles,
    COUNT(*) as policy_count
  FROM pg_policies
  WHERE permissive = 'YES'  -- PostgreSQL'te 'YES'/'NO' olarak saklanır
  GROUP BY schemaname, tablename, cmd, roles
  HAVING COUNT(*) > 1
)
SELECT * FROM policy_counts;

-- Sonuç boş olmalı (duplicate policy kalmadı)

-- ================================================
-- AÇIKLAMALAR
-- ================================================

/*
1. auth_rls_initplan Çözümü:
   - auth.uid() → (select auth.uid())
   - Subquery ile auth.uid() bir kez değerlendirilir ve cache'lenir
   - Her satır için tekrar hesaplanmaz

2. multiple_permissive_policies Çözümü:
   - Aynı role/action için birden fazla policy tek bir policy'de birleştirildi
   - Örn: "Public profiles are viewable by everyone" + "profiles_select_unified"
         → Tek bir "profiles_select_unified" policy

3. Dikkat:
   - Bu değişiklikler var olan permission mantığını DEĞİŞTİRMEZ
   - Sadece performans optimizasyonudur
   - Test ederek onaylayın
*/
