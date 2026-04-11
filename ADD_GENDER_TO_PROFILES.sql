-- ============================================
-- Profiles tablosuna gender alanı ekleme
-- ============================================

-- 1. Gender kolonunu ekle (varsa hata vermez)
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
    
    COMMENT ON COLUMN public.profiles.gender IS 'Kullanıcının cinsiyeti: male, female, other';
  END IF;
END $$;

-- 2. handle_new_user fonksiyonunu gender alanını da içerecek şekilde güncelle
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
    COALESCE(NEW.raw_user_meta_data->>'username', ''),
    COALESCE(NEW.raw_user_meta_data->>'full_name', ''),
    COALESCE(NEW.raw_user_meta_data->>'gender', NULL),
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
    
  RETURN NEW;
EXCEPTION
  WHEN unique_violation THEN
    -- Username çakışması durumunda güncelle
    UPDATE public.profiles
    SET 
      email = NEW.email,
      full_name = COALESCE(NEW.raw_user_meta_data->>'full_name', full_name),
      gender = COALESCE(NEW.raw_user_meta_data->>'gender', gender),
      updated_at = NOW()
    WHERE id = NEW.id;
    RETURN NEW;
  WHEN others THEN
    RAISE WARNING 'handle_new_user hatası: %', SQLERRM;
    RETURN NEW;
END;
$$;

-- 3. Trigger'ı yeniden oluştur (varsa)
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();

-- 4. İzin kontrolü
COMMENT ON FUNCTION public.handle_new_user() IS 'Yeni kullanıcı kaydında otomatik profil oluşturur - gender alanı dahil';

-- Tamamlandı mesajı
DO $$ 
BEGIN
  RAISE NOTICE '✅ Gender alanı eklendi ve handle_new_user fonksiyonu güncellendi';
END $$;
