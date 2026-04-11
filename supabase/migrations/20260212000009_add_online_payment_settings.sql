-- ============================================================================
-- ONLINE ÖDEME AYARLARI - App Settings
-- ============================================================================
-- app_about_settings tablosuna iyzico online ödeme ayarları eklenir
-- Tarih: 2026-02-12

-- ============================================================================
-- 1. ONLINE ÖDEME AYARLARI EKLE
-- ============================================================================
ALTER TABLE public.app_about_settings
  ADD COLUMN IF NOT EXISTS online_payment_enabled BOOLEAN DEFAULT true,
  ADD COLUMN IF NOT EXISTS iyzico_api_key TEXT,
  ADD COLUMN IF NOT EXISTS iyzico_secret_key TEXT,
  ADD COLUMN IF NOT EXISTS iyzico_api_url TEXT DEFAULT 'https://sandbox-api.iyzipay.com';

-- Varsayılan değerleri güncelle
UPDATE public.app_about_settings
SET 
  online_payment_enabled = true,
  iyzico_api_url = 'https://sandbox-api.iyzipay.com'
WHERE online_payment_enabled IS NULL;

-- ============================================================================
-- 2. YORUM EKLE
-- ============================================================================
COMMENT ON COLUMN public.app_about_settings.online_payment_enabled IS 
  'Online ödeme sisteminin (iyzico) aktif olup olmadığı';
COMMENT ON COLUMN public.app_about_settings.iyzico_api_key IS 
  'iyzico API Key (sandbox veya production)';
COMMENT ON COLUMN public.app_about_settings.iyzico_secret_key IS 
  'iyzico Secret Key (sandbox veya production)';
COMMENT ON COLUMN public.app_about_settings.iyzico_api_url IS 
  'iyzico API URL (sandbox: https://sandbox-api.iyzipay.com, prod: https://api.iyzipay.com)';

DO $$
BEGIN
    RAISE NOTICE '✅ Online ödeme ayarları app_about_settings tablosuna eklendi';
    RAISE NOTICE '   - online_payment_enabled (aktif/pasif)';
    RAISE NOTICE '   - iyzico_api_key';
    RAISE NOTICE '   - iyzico_secret_key';
    RAISE NOTICE '   - iyzico_api_url';
END $$;
