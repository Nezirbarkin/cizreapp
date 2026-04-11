-- Profil oluşturma trigger'ını kontrol et ve düzelt

-- 1. Mevcut trigger'ı kontrol et
-- Eğer handle_new_user trigger'ı varsa ve full_name'i email'den alıyorsa düzelt

-- 2. Yeni trigger fonksiyonu oluştur (mevcut olanı değiştir)
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  -- Yeni kullanıcı için profil oluştur
  -- SADECE auth.users'tan gelen bilgileri kullan, profiles'taki mevcut veriyi koruyarak
  INSERT INTO public.profiles (id, email, created_at, updated_at)
  VALUES (
    NEW.id,
    NEW.email,
    NOW(),
    NOW()
  )
  ON CONFLICT (id) DO NOTHING; -- Eğer profil zaten varsa (register_screen.dart'tan oluşturulduysa) dokunma
  
  RETURN NEW;
END;
$$;

-- 3. Trigger'ı güncelle (eğer yoksa oluştur)
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();

-- NOT: Bu değişiklik, register_screen.dart'ın profili oluşturmasına izin verir
-- Trigger sadece email field'ını set eder, full_name ve username'i korur
