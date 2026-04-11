-- Profiles tablosu INSERT politikasını düzelt
-- Kayıt sırasında RLS hatası: "new row violates row-level security policy"

-- Önce mevcut INSERT policy'yi kontrol et
SELECT tablename, policyname, permissive, roles, cmd, qual, with_check
FROM pg_policies
WHERE tablename = 'profiles' AND cmd = 'INSERT';

-- Eğer sorunlu bir policy varsa, düzelt
-- Genellikle authenticated kullanıcıların kendi profil satırlarını oluşturabilmesi gerekir

-- Eski INSERT policy'yi kaldır (eğer varsa)
DROP POLICY IF EXISTS "Users can insert their own profile" ON profiles;
DROP POLICY IF EXISTS "Enable insert for authenticated users only" ON profiles;
DROP POLICY IF EXISTS "Allow user to create their own profile" ON profiles;

-- Yeni INSERT policy oluştur
CREATE POLICY "Users can insert their own profile"
ON profiles
FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = id);

-- Policy'nin çalıştığını test et
SELECT 
    schemaname,
    tablename,
    policyname,
    permissive,
    roles,
    cmd,
    qual,
    with_check
FROM pg_policies 
WHERE tablename = 'profiles' AND cmd = 'INSERT';
