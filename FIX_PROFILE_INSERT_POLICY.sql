-- ============================================================================
-- PROFİL INSERT POLICY DÜZELTME
-- ============================================================================
-- Bu dosya, yeni kayıt olan kullanıcıların kendi profilini oluşturabilmesi
-- için gerekli RLS policy'yi ekler.

-- Mevcut policy'leri kontrol et
SELECT tablename, policyname, permissive, roles, cmd, qual, with_check
FROM pg_policies
WHERE tablename = 'profiles';

-- Kullanıcıların kendi profilini oluşturabilmesi için INSERT policy
-- Eğer zaten varsa önce sil
DROP POLICY IF EXISTS "Users can insert own profile" ON profiles;

-- Yeni policy oluştur: Kullanıcılar sadece kendi ID'si ile profil oluşturabilir
-- Performance optimization: (select auth.uid()) kullan
CREATE POLICY "Users can insert own profile" ON profiles
FOR INSERT
TO authenticated
WITH CHECK ((select auth.uid()) = id);

-- Politikayı kontrol et
SELECT tablename, policyname, permissive, roles, cmd, qual, with_check
FROM pg_policies
WHERE tablename = 'profiles' AND policyname = 'Users can insert own profile';

-- ============================================================================
-- EK BİLGİ
-- ============================================================================
-- Bu policy sayesinde:
-- 1. Kullanıcılar sadece kendi ID'leri ile profil oluşturabilir
-- 2. Başka kullanıcının adına profil oluşturamazlar
-- 3. Register sırasında profil oluşturma işlemi başarılı olacak
-- 4. Profil ekranında otomatik profil oluşturma işlemi çalışacak
-- 5. Performance optimized - (select auth.uid()) ile suboptimal query önlendi
