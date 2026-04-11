-- search_path uyarılarını düzelt
ALTER FUNCTION public.verify_registration_otp(TEXT, TEXT) SET search_path = public;
ALTER FUNCTION public.verify_password_reset_otp(TEXT, TEXT) SET search_path = public;
