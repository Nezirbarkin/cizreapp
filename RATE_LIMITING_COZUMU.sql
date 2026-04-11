-- ================================================
-- RATE LIMITING HATASI ÇÖZÜMÜ
-- Hata: "Çok fazla işlem yaptınız, lütfen 1 dakika bekleyin"
-- ================================================

-- Supabase rate limiting koruması devrede
-- Çözüm 1: Supabase Dashboard'da script'i adım adım çalıştırın

-- ================================================
-- ADIM 1: Önce Mevcut Durumu Kontrol Edin (5 saniye bekle)
-- ================================================

-- 5 saniye bekle ve sonra çalıştır
-- Trigger var mı?
SELECT 
    trigger_name,
    event_manipulation,
    event_object_table
FROM information_schema.triggers
WHERE trigger_name = 'on_auth_user_created';

-- ================================================
-- ADIM 2: Eski Trigger'ı Kaldırın (5 saniye bekle)
-- ================================================

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP FUNCTION IF EXISTS public.handle_new_user();

-- ================================================
-- ADIM 3: Yeni Trigger Fonksiyonunu Oluşturun (10 saniye bekle)
-- ================================================

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql
AS $$
BEGIN
  INSERT INTO public.profiles (
    id, 
    email,
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
    NEW.email,
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
    UPDATE public.profiles
    SET
      email = NEW.email,
      username = COALESCE(NEW.raw_user_meta_data->>'username', username),
      full_name = COALESCE(NEW.raw_user_meta_data->>'full_name', full_name),
      avatar_url = COALESCE(NEW.raw_user_meta_data->>'avatar_url', avatar_url),
      updated_at = NOW()
    WHERE id = NEW.id;
    RETURN NEW;
  WHEN OTHERS THEN
    RAISE WARNING 'Error creating profile for user %: %', NEW.id, SQLERRM;
    RETURN NEW;
END;
$$;

-- ================================================
-- ADIM 4: Trigger'ı Oluşturun (5 saniye bekle)
-- ================================================

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();

-- ================================================
-- ADIM 5: Mevcut Email'leri Güncelleyin (10 saniye bekle)
-- ================================================

DO $$
DECLARE
  user_record RECORD;
  updated_count INTEGER := 0;
BEGIN
  FOR user_record IN 
    SELECT u.id, u.email
    FROM auth.users u
    LEFT JOIN profiles p ON u.id = p.id
    WHERE p.email IS NULL OR p.email = ''
    LIMIT 100  -- Her seferinde max 100 kayıt
  LOOP
    UPDATE profiles
    SET email = user_record.email, updated_at = NOW()
    WHERE id = user_record.id;
    
    updated_count := updated_count + 1;
  END LOOP;
  
  RAISE NOTICE 'Updated % profiles', updated_count;
END $$;

-- ================================================
-- ADIM 6: Kontrol
-- ================================================

-- Sonuçları kontrol et
SELECT 
    COUNT(*) as total_profiles,
    COUNT(email) as profiles_with_email,
    COUNT(*) - COUNT(email) as profiles_without_email
FROM profiles;

-- Email'i olmayanlar (varsa)
SELECT id, username, email
FROM profiles
WHERE email IS NULL OR email = ''
LIMIT 5;

-- ================================================
-- NOTLAR
-- ================================================
-- 1. Her adımdan sonra 5-10 saniye bekleyin
-- 2. Hala rate limiting hatası alırsanız, 1 dakika bekleyip tekrar deneyin
-- 3. Script'i çalıştırırken biraz su için 😊
