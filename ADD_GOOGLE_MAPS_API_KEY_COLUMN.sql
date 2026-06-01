-- ============================================
-- GOOGLE MAPS API KEY SÜTUNU EKLEME
-- ============================================
-- Bu SQL dosyasını Supabase SQL Editor'de çalıştırın

-- app_about_settings tablosuna google_maps_api_key sütunu ekle
ALTER TABLE app_about_settings 
ADD COLUMN IF NOT EXISTS google_maps_api_key TEXT;

-- Açıklama ekle
COMMENT ON COLUMN app_about_settings.google_maps_api_key IS 
'Google Maps API Key - Harita ve konum özellikleri için gerekli. Admin panel > Hakkında Ayarları > API Anahtarları bölümünden yönetilir.';

-- ============================================
-- SONUÇ
-- ============================================
-- Bu sütun eklendikten sonra:
-- 1. Admin Panel > Hakkında Ayarları > API Anahtarları
-- 2. Google Maps API Key'i girin
-- 3. Kaydet butonuna tıklayın
-- 
-- API Key nasıl alınır:
-- 1. console.cloud.google.com > API & Services > Credentials
-- 2. Create Credentials > API Key
-- 3. Maps SDK for Android ve Maps SDK for iOS API'lerini etkinleştir
-- 4. API Key'i kopyala ve admin panele yapıştır