-- Profiles tablosundaki role kolonunun tipini ve mevcut değerleri kontrol et
SELECT column_name, data_type, udt_name 
FROM information_schema.columns 
WHERE table_name = 'profiles' AND column_name = 'role';

-- Mevcut role değerlerini listele
SELECT DISTINCT role FROM public.profiles LIMIT 20;

-- is_admin kolonu var mı kontrol et
SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'profiles' AND column_name = 'is_admin';