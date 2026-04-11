-- ================================================
-- KAYIT VE EMAİL DOĞRULAMA SORUNLARININ ÇÖZÜMÜ
-- ================================================
-- Sorun 1: PostgrestException - new row violates row-level security policy for table "profiles"
-- Sorun 2: Email onaylama sonrası beyaz ekran
-- ================================================

-- ================================================
-- ADIM 1: HANDLE_NEW_USER TRIGGER FONKSİYONUNU DÜZELT
-- ================================================
-- Email alanı eksik, onu ekleyelim

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP FUNCTION IF EXISTS public.handle_new_user();

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
SECURITY DEFINER -- Trigger service_role yetkisiyle çalışır, RLS bypass edilir
SET search_path = public
LANGUAGE plpgsql
AS $$
BEGIN
  -- Yeni kullanıcı için profil oluştur
  INSERT INTO public.profiles (
    id, 
    email,           -- EKSİK OLAN ALAN!
    username, 
    full_name, 
    avatar_url, 
    bio, 
    is_private, 
    created_at, 
    updated_at
  )
  VALUES (
    NEW.id,
    NEW.email,       -- Email'i auth.users tablosundan al
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
    -- Profil zaten varsa, güncelle (özellikle email'i güncelle)
    UPDATE public.profiles
    SET
      email = NEW.email,  -- Email'i güncelle
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
-- ADIM 2: RLS POLİCY'LERİNİ KONTROL ET
-- ================================================

-- Mevcut INSERT policy'leri göster
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
WHERE tablename = 'profiles' AND cmd = 'INSERT'
ORDER BY policyname;

-- Eğer INSERT policy yoksa veya hatalıysa, düzelt
-- (Trigger SECURITY DEFINER ile çalıştığı için bu policy trigger'ı etkilemez)
-- Ama kullanıcı manuel profil oluşturmak isterse diye olmalı

DROP POLICY IF EXISTS "Users can insert their own profile" ON profiles;
DROP POLICY IF EXISTS "Users can insert own profile" ON profiles;

-- Authenticated kullanıcılar kendi profillerini oluşturabilir
CREATE POLICY "Users can insert own profile"
ON profiles
FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = id);

-- ================================================
-- ADIM 3: MEVCUT KULLANICILAR İÇİN EMAIL ALANINI GÜNCELLE
-- ================================================
-- Eğer mevcut kullanıcıların profillerinde email yoksa, güncelle

DO $$
DECLARE
  user_record RECORD;
BEGIN
  FOR user_record IN 
    SELECT u.id, u.email
    FROM auth.users u
    LEFT JOIN profiles p ON u.id = p.id
    WHERE p.email IS NULL OR p.email = ''
  LOOP
    UPDATE profiles
    SET email = user_record.email, updated_at = NOW()
    WHERE id = user_record.id;
    
    RAISE NOTICE 'Updated email for user: %', user_record.id;
  END LOOP;
END $$;

-- ================================================
-- VERİFİKASYON
-- ================================================

-- 1. Trigger'ın oluşturulduğunu kontrol et
SELECT 
    trigger_name,
    event_manipulation,
    event_object_table,
    action_statement
FROM information_schema.triggers
WHERE trigger_name = 'on_auth_user_created';

-- 2. Profillerde email alanının dolu olduğunu kontrol et
SELECT 
    COUNT(*) as total_profiles,
    COUNT(email) as profiles_with_email,
    COUNT(*) - COUNT(email) as profiles_without_email
FROM profiles;

-- 3. Email'i olmayan profilleri listele
SELECT id, username, full_name, email, created_at
FROM profiles
WHERE email IS NULL OR email = ''
LIMIT 10;

-- ================================================
-- NOTLAR
-- ================================================
-- 1. Bu SQL dosyasını Supabase SQL Editor'de çalıştırın
-- 2. Flutter kodunda artık manuel profil oluşturmaya gerek yok
-- 3. Email confirm beyaz ekran sorunu için Flutter tarafında düzenleme yapılacak
-- 4. Deep link (cizreapp://verify) Android manifest'te zaten tanımlı
