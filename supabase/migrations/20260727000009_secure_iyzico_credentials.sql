-- iyzico kimlik bilgilerini public ayarlar tablosundan kaldır.
-- Anahtarlar yalnızca Supabase Edge Function Secrets üzerinden yönetilir:
-- IYZICO_API_KEY ve IYZICO_SECRET_KEY.

ALTER TABLE public.app_about_settings
  DROP COLUMN IF EXISTS iyzico_api_key,
  DROP COLUMN IF EXISTS iyzico_secret_key;

COMMENT ON COLUMN public.app_about_settings.iyzico_api_url IS
  'iyzico API ortam URL''si. Gizli anahtarlar yalnız Edge Function Secrets içindedir.';
