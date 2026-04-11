-- ============================================
-- FIX: Trigger'ı yeniden bağla + handle_new_user'ı güncelle + eksik profilleri oluştur
-- Supabase SQL Editor'de çalıştırın
-- ============================================

-- 1. handle_new_user fonksiyonunu güncelle (gender dahil)
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
  v_username := COALESCE(NEW.raw_user_meta_data->>'username', '');
  v_full_name := COALESCE(NEW.raw_user_meta_data->>'full_name', '');
  v_gender := COALESCE(NEW.raw_user_meta_data->>'gender', NULL);

  INSERT INTO public.profiles (
    id, email, username, full_name, gender, avatar_url, bio, is_private, created_at, updated_at
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

  RETURN NEW;
EXCEPTION
  WHEN unique_violation THEN
    UPDATE public.profiles
    SET email = NEW.email,
        full_name = COALESCE(v_full_name, full_name),
        gender = COALESCE(v_gender, gender),
        updated_at = NOW()
    WHERE id = NEW.id;
    RETURN NEW;
  WHEN others THEN
    RAISE WARNING 'handle_new_user error: %', SQLERRM;
    RETURN NEW;
END;
$$;

-- 2. Trigger'ı yeniden bağla
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();

-- 3. Eksik profilleri oluştur (profili olmayan auth kullanıcıları için)
INSERT INTO public.profiles (id, email, username, full_name, created_at, updated_at)
SELECT 
  u.id,
  u.email,
  COALESCE(u.raw_user_meta_data->>'username', ''),
  COALESCE(u.raw_user_meta_data->>'full_name', ''),
  NOW(),
  NOW()
FROM auth.users u
LEFT JOIN public.profiles p ON p.id = u.id
WHERE p.id IS NULL;
