-- ============================================
-- PROFİL OLUŞTURMA TRIGGER'INI AKTİFLEŞTİR
-- ============================================
-- Bu SQL komutu Supabase SQL Editor'da çalıştırılmalıdır
-- Supabase Dashboard → SQL Editor → New Query → Bu kodu yapıştırın → RUN

-- 1. Fonksiyonu güvenli şekilde oluştur (varsa yeniden oluştur)
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (id, email, full_name, username)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'full_name', ''),
    COALESCE(NEW.raw_user_meta_data->>'username', '')
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;

-- 2. Eski trigger'ı kaldır (varsa)
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

-- 3. Yeni trigger'ı oluştur
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();

-- ============================================
-- DOĞRULAMA SORGUSU (Trigger'ın oluştuğunu kontrol etmek için)
-- ============================================
-- Bu sorguyu çalıştırarak trigger'ın oluşup oluşmadığını kontrol edebilirsiniz:
--
-- SELECT trigger_name, event_manipulation 
-- FROM information_schema.triggers 
-- WHERE event_object_table = 'users' 
-- AND trigger_schema = 'auth';
--
-- Sonuç olarak 'on_auth_user_created' görmelisiniz.
