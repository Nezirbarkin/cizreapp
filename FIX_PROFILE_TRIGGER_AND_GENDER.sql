-- ============================================
-- Profil trigger'ını ve gender desteğini düzelt
-- ============================================

-- 1. Gender kolonunu ekle (yoksa)
DO $$ 
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' 
    AND table_name = 'profiles' 
    AND column_name = 'gender'
  ) THEN
    ALTER TABLE public.profiles 
    ADD COLUMN gender TEXT CHECK (gender IN ('male', 'female', 'other'));
    
    RAISE NOTICE '✅ Gender kolonu eklendi';
  ELSE
    RAISE NOTICE '✅ Gender kolonu zaten mevcut';
  END IF;
END $$;

-- 2. Mevcut trigger'ı ve fonksiyonu sil
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP FUNCTION IF EXISTS public.handle_new_user() CASCADE;

RAISE NOTICE '🗑️ Eski trigger ve fonksiyon silindi';

-- 3. Yeni handle_new_user fonksiyonu (gender dahil)
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
SECURITY DEFINER
SET search_path = public, auth
LANGUAGE plpgsql
AS $$
DECLARE
  v_username TEXT;
  v_full_name TEXT;
  v_gender TEXT;
BEGIN
  -- Metadata'dan bilgileri al
  v_username := COALESCE(NEW.raw_user_meta_data->>'username', '');
  v_full_name := COALESCE(NEW.raw_user_meta_data->>'full_name', '');
  v_gender := COALESCE(NEW.raw_user_meta_data->>'gender', NULL);
  
  -- Debug log
  RAISE LOG 'handle_new_user triggered for user: %, username: %, gender: %', 
    NEW.id, v_username, v_gender;

  -- Profil oluştur
  INSERT INTO public.profiles (
    id, 
    email,
    username, 
    full_name, 
    gender,
    avatar_url, 
    bio, 
    is_private, 
    created_at, 
    updated_at
  )
  VALUES (
    NEW.id,
    NEW.email,
    v_username,
    v_full_name,
    v_gender,
    COALESCE(NEW.raw_user_meta_data->>'avatar_url', ''),
    COALESCE(NEW.raw_user_meta_data->>'bio', ''),
    COALESCE((NEW.raw_user_meta_data->>'is_private')::boolean, false),
    NOW(),
    NOW()
  )
  ON CONFLICT (id) DO UPDATE SET
    email = EXCLUDED.email,
    username = COALESCE(NULLIF(profiles.username, ''), EXCLUDED.username),
    full_name = COALESCE(NULLIF(profiles.full_name, ''), EXCLUDED.full_name),
    gender = COALESCE(profiles.gender, EXCLUDED.gender),
    updated_at = NOW();
    
  RAISE LOG 'Profile created/updated successfully for user: %', NEW.id;
  
  RETURN NEW;
EXCEPTION
  WHEN unique_violation THEN
    -- Username çakışması durumunda güncelle
    RAISE LOG 'Username conflict for user: %, updating existing profile', NEW.id;
    
    UPDATE public.profiles
    SET 
      email = NEW.email,
      full_name = COALESCE(v_full_name, full_name),
      gender = COALESCE(v_gender, gender),
      updated_at = NOW()
    WHERE id = NEW.id;
    
    RETURN NEW;
  WHEN others THEN
    RAISE WARNING 'handle_new_user error for user %: %', NEW.id, SQLERRM;
    RETURN NEW; -- Trigger hatası auth işlemini engellemez
END;
$$;

RAISE NOTICE '✅ handle_new_user fonksiyonu oluşturuldu';

-- 4. Trigger'ı yeniden oluştur
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();

RAISE NOTICE '✅ Trigger oluşturuldu';

-- 5. Fonksiyona comment ekle
COMMENT ON FUNCTION public.handle_new_user() IS 
  'Yeni kullanıcı kayıt olduğunda otomatik profil oluşturur - gender alanı dahil';

-- 6. Test: Trigger'ın aktif olduğunu kontrol et
DO $$
DECLARE
  v_trigger_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO v_trigger_count
  FROM information_schema.triggers
  WHERE trigger_schema = 'auth'
    AND trigger_name = 'on_auth_user_created'
    AND event_object_table = 'users';
    
  IF v_trigger_count > 0 THEN
    RAISE NOTICE '✅ Trigger aktif ve çalışıyor';
  ELSE
    RAISE WARNING '⚠️ Trigger bulunamadı!';
  END IF;
END $$;

-- Tamamlandı mesajı
DO $$ 
BEGIN
  RAISE NOTICE '';
  RAISE NOTICE '========================================';
  RAISE NOTICE '✅ Profil trigger ve gender desteği hazır';
  RAISE NOTICE '========================================';
END $$;
