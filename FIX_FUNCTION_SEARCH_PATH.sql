-- Supabase Security Linter Uyarılarını Düzelt
-- ==============================================

-- 1) Function Search Path Mutable uyarılarını düzelt
-- Bu fonksiyonlara SET search_path = '' ekle

ALTER FUNCTION public.verify_registration_otp SET search_path = '';
ALTER FUNCTION public.verify_password_reset_otp SET search_path = '';

-- 2) Leaked Password Protection 
-- Bu ayar Supabase Dashboard > Authentication > Settings > Password Protection 
-- bölümünden "Enable Leaked Password Protection" seçeneğini açarak yapılır.
-- SQL ile yapılamaz, Dashboard üzerinden yapılmalıdır.
-- 
-- Adımlar:
-- 1. Supabase Dashboard'a gidin
-- 2. Authentication > Settings
-- 3. "Password Protection" bölümünü bulun  
-- 4. "Enable Leaked Password Protection" seçeneğini açın
-- 5. Save butonuna tıklayın
