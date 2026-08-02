-- =====================================================
-- API ANAHTARLARI - MANUEL EKLEME (SQL Editor)
-- =====================================================
-- Bu SQL'i Supabase Dashboard → SQL Editor'de çalıştırın
-- HER SATIRI AYRI AYRI ÇALIŞTIRIN (tek seferde değil!)
--
-- ⚠️ ÖNEMLİ: '<ANAHTARINIZI_BURAYA_YAPISTIRIN>' kısmını
-- gerçek API anahtarınızla değiştirin!
-- =====================================================

-- 1. Gemini API Anahtarı (ZORUNLU)
-- https://aistudio.google.com/app/apikey adresinden alın
-- Örnek: AIzaSyA1B2C3D4E5F6G7H8I9J0...
INSERT INTO vault.secrets (name, secret, description)
VALUES (
  'GEMINI_API_KEY',
  '<ANAHTARINIZI_BURAYA_YAPISTIRIN>',
  'Google Gemini API anahtarı - text, vision ve image generation'
) ON CONFLICT (name) DO UPDATE SET secret = EXCLUDED.secret, description = EXCLUDED.description;

-- 2. Groq API Anahtarı (ÖNERİLEN)
-- https://console.groq.com/keys adresinden alın
-- Örnek: gsk_A1B2C3D4E5F6G7H8...
INSERT INTO vault.secrets (name, secret, description)
VALUES (
  'GROQ_API_KEY',
  '<ANAHTARINIZI_BURAYA_YAPISTIRIN>',
  'Groq API anahtarı - hızlı text ve vision fallback'
) ON CONFLICT (name) DO UPDATE SET secret = EXCLUDED.secret, description = EXCLUDED.secrets;

-- 3. OpenRouter API Anahtarı (ÖNERİLEN)
-- https://openrouter.ai/keys adresinden alın
-- Örnek: sk-or-A1B2C3D4E5F6G7H8...
INSERT INTO vault.secrets (name, secret, description)
VALUES (
  'OPENROUTER_API_KEY',
  '<ANAHTARINIZI_BURAYA_YAPISTIRIN>',
  'OpenRouter API anahtarı - çoklu model yedek'
) ON CONFLICT (name) DO UPDATE SET secret = EXCLUDED.secret, description = EXCLUDED.description;

-- 4. OpenAI API Anahtarı (OPSİYONEL - son çare)
-- https://platform.openai.com/api-keys adresinden alın
-- Örnek: sk-proj-A1B2C3D4E5F6G7H8...
INSERT INTO vault.secrets (name, secret, description)
VALUES (
  'OPENAI_API_KEY',
  '<ANAHTARINIZI_BURAYA_YAPISTIRIN>',
  'OpenAI API anahtarı - son çare fallback'
) ON CONFLICT (name) DO UPDATE SET secret = EXCLUDED.secret, description = EXCLUDED.description;

-- =====================================================
-- DOĞRULAMA: Eklenen anahtarları kontrol edin
-- (NOT: vault.secrets'den secret değeri okunamaz,
-- sadece name ve description listelenir)
-- =====================================================
SELECT name, description, created_at FROM vault.secrets ORDER BY created_at DESC;

-- =====================================================
-- ⚠️ vault.secrets EĞER ÇALIŞMAZSA ALTERNATİF YÖNTEM
-- =====================================================
-- Bazı Supabase versiyonlarında vault extension aktif olmayabilir.
-- Bu durumda, Edge Function environment variable'larını
-- Supabase Dashboard üzerinden ayarlayın:
--
-- 1. Supabase Dashboard → Projenizi açın
-- 2. Sol menüden "Edge Functions" seçin
-- 3. Üst menüden "Secrets" tabına geçin
-- 4. "Add a new secret" butonuna tıklayın
-- 5. Her anahtar için:
--    - Name: GEMINI_API_KEY
--    - Value: AIzaSy...sizin-anahtariniz...
--    - "Add" butonuna tıklayın
-- 6. Diğer anahtarlar için tekrarlayın
-- =====================================================