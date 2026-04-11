-- ============================================
-- TANILAMA: Mevcut tablo, trigger ve fonksiyon durumu
-- Supabase SQL Editor'de çalıştırın ve sonucu paylaşın
-- ============================================

-- 1. profiles tablosunun kolonları
SELECT 'PROFILES_COLUMNS' as check_type, column_name, data_type
FROM information_schema.columns 
WHERE table_schema = 'public' AND table_name = 'profiles'
ORDER BY ordinal_position;

-- 2. registration_otps tablosu var mı?
SELECT 'REGISTRATION_OTPS_EXISTS' as check_type, 
  EXISTS(
    SELECT 1 FROM information_schema.tables 
    WHERE table_schema = 'public' AND table_name = 'registration_otps'
  ) as table_exists;

-- 3. password_reset_otps tablosu var mı?
SELECT 'PASSWORD_RESET_OTPS_EXISTS' as check_type, 
  EXISTS(
    SELECT 1 FROM information_schema.tables 
    WHERE table_schema = 'public' AND table_name = 'password_reset_otps'
  ) as table_exists;

-- 4. auth.users üzerindeki trigger'lar
SELECT 'AUTH_TRIGGERS' as check_type, trigger_name, event_manipulation, action_statement
FROM information_schema.triggers
WHERE event_object_schema = 'auth' AND event_object_table = 'users';

-- 5. handle_new_user fonksiyonu var mı?
SELECT 'HANDLE_NEW_USER_EXISTS' as check_type,
  EXISTS(
    SELECT 1 FROM pg_proc 
    WHERE proname = 'handle_new_user' 
    AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')
  ) as function_exists;

-- 6. verify_registration_otp fonksiyonu var mı?
SELECT 'VERIFY_REG_OTP_EXISTS' as check_type,
  EXISTS(
    SELECT 1 FROM pg_proc 
    WHERE proname = 'verify_registration_otp' 
    AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')
  ) as function_exists;

-- 7. verify_password_reset_otp fonksiyonu var mı?
SELECT 'VERIFY_PWD_RESET_OTP_EXISTS' as check_type,
  EXISTS(
    SELECT 1 FROM pg_proc 
    WHERE proname = 'verify_password_reset_otp' 
    AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')
  ) as function_exists;

-- 8. Profil sayısı
SELECT 'PROFILE_COUNT' as check_type, COUNT(*) as total FROM public.profiles;

-- 9. Auth user sayısı
SELECT 'AUTH_USER_COUNT' as check_type, COUNT(*) as total FROM auth.users;
