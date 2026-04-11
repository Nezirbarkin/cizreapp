-- ================================================
-- PROFILES KAYIT HATASI ÇÖZÜMÜ
-- Hata: new row violates row-level security policy
-- ================================================

-- 1. MEVCUT DURUMU KONTROL ET
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
WHERE tablename = 'profiles'
ORDER BY cmd, policyname;

-- 2. RLS DURUMUNU KONTROL ET
SELECT 
    tablename,
    rowsecurity
FROM pg_tables 
WHERE tablename = 'profiles';

-- ================================================
-- ÇÖZÜM 1: RLS POLICY'LERİNİ DÜZELT
-- ================================================

-- Eski INSERT policy'lerini kaldır
DROP POLICY IF EXISTS "Users can insert their own profile" ON profiles;
DROP POLICY IF EXISTS "Enable insert for authenticated users only" ON profiles;
DROP POLICY IF EXISTS "Allow user to create their own profile" ON profiles;
DROP POLICY IF EXISTS "Users can create their own profile" ON profiles;

-- Yeni INSERT policy oluştur (authenticated kullanıcılar kendi profillerini oluşturabilir)
CREATE POLICY "Users can insert their own profile"
ON profiles
FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = id);

-- SELECT policy'si de olduğundan emin ol
DROP POLICY IF EXISTS "Public profiles are viewable by everyone" ON profiles;
DROP POLICY IF EXISTS "Users can view all profiles" ON profiles;

CREATE POLICY "Public profiles are viewable by everyone"
ON profiles
FOR SELECT
USING (true);

-- UPDATE policy'si (kullanıcılar kendi profillerini güncelleyebilir)
DROP POLICY IF EXISTS "Users can update own profile" ON profiles;

CREATE POLICY "Users can update own profile"
ON profiles
FOR UPDATE
TO authenticated
USING (auth.uid() = id)
WITH CHECK (auth.uid() = id);

-- ================================================
-- ÇÖZÜM 2: OTOMATIK PROFIL OLUŞTURMA (ÖNERİLEN)
-- ================================================
-- Bu çözüm daha güvenli çünkü trigger service_role ile çalışır

-- Önce eski trigger'ı kaldır
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP FUNCTION IF EXISTS public.handle_new_user();

-- Yeni kullanıcı için otomatik profil oluşturma fonksiyonu
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
SECURITY DEFINER -- Bu önemli: trigger service_role yetkisiyle çalışır
SET search_path = public
LANGUAGE plpgsql
AS $$
BEGIN
  INSERT INTO public.profiles (id, username, full_name, avatar_url, bio, is_private, created_at, updated_at)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'username', ''),
    COALESCE(NEW.raw_user_meta_data->>'full_name', ''),
    COALESCE(NEW.raw_user_meta_data->>'avatar_url', ''),
    COALESCE(NEW.raw_user_meta_data->>'bio', ''),
    COALESCE((NEW.raw_user_meta_data->>'is_private')::boolean, false),
    NOW(),
    NOW()
  );
  RETURN NEW;
EXCEPTION
  WHEN unique_violation THEN
    -- Profil zaten varsa, güncelle
    UPDATE public.profiles
    SET
      username = COALESCE(NEW.raw_user_meta_data->>'username', username),
      full_name = COALESCE(NEW.raw_user_meta_data->>'full_name', full_name),
      avatar_url = COALESCE(NEW.raw_user_meta_data->>'avatar_url', avatar_url),
      bio = COALESCE(NEW.raw_user_meta_data->>'bio', bio),
      updated_at = NOW()
    WHERE id = NEW.id;
    RETURN NEW;
  WHEN OTHERS THEN
    -- Hata durumunda bile kullanıcı kaydının devam etmesini sağla
    RAISE WARNING 'Error creating profile for user %: %', NEW.id, SQLERRM;
    RETURN NEW;
END;
$$;

-- Trigger'ı oluştur
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();

-- ================================================
-- ÇÖZÜM 3: GEÇİCİ ÇÖZÜM - RLS'İ GEÇİCİ OLARAK DEVRE DIŞI BIRAK
-- (Sadece test için, production'da önerilmez)
-- ================================================
-- ALTER TABLE profiles DISABLE ROW LEVEL SECURITY;

-- ================================================
-- VERİFİKASYON
-- ================================================

-- Policy'lerin düzgün oluşturulduğunu kontrol et
SELECT 
    tablename,
    policyname,
    permissive,
    roles,
    cmd,
    qual,
    with_check
FROM pg_policies 
WHERE tablename = 'profiles'
ORDER BY cmd, policyname;

-- Trigger'ın oluşturulduğunu kontrol et
SELECT 
    trigger_name,
    event_manipulation,
    event_object_table,
    action_statement
FROM information_schema.triggers
WHERE trigger_name = 'on_auth_user_created';

-- Test için profil sayısını kontrol et
SELECT COUNT(*) as total_profiles FROM profiles;

-- ================================================
-- NOTLAR
-- ================================================
-- 1. Çözüm 2 (otomatik profil oluşturma) önerilir çünkü:
--    - Daha güvenli (service_role yetkisi ile çalışır)
--    - RLS bypass edilir
--    - Kullanıcı deneyimi daha iyi (otomatik oluşturulur)
--
-- 2. Eğer Çözüm 2'yi kullanıyorsanız, Flutter kodunda
--    manuel profil oluşturma kodunu kaldırabilirsiniz
--
-- 3. username unique olmalı, bunu kontrol etmek için:
--    ALTER TABLE profiles ADD CONSTRAINT profiles_username_key UNIQUE (username);
