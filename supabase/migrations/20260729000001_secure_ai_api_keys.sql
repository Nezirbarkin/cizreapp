-- =====================================================
-- AI sağlayıcı API anahtarlarını world-readable tablodan kaldır.
--
-- Sorun: ai_settings tablosuna eklenen gemini_api_key, groq_api_key,
-- openrouter_api_key, openai_api_key düz metin sütunları "Anyone can read
-- ai settings" (USING (true)) politikası altında anon da dahil herkesçe
-- okunabilir durumdaydı. Anon key uygulamaya gömülü olduğu için sıfır
-- kimlik doğrulamayla tüm AI sağlayıcı anahtarları sızıyordu.
--
-- Çözüm: Mevcut değerleri (varsa) vault.secrets'e taşı, ardından düz metin
-- sütunlarını DROP et. *_key_set boolean sütunları korunur (istemci yalnızca
-- "anahtar ayarlı mı" bilgisini okur). Anahtarların kendisi artık vault'ta;
-- gelecekteki AI chat edge function'ları vault.decrypted_secrets üzerinden
-- okumalıdır (asla cihaza inmez).
--
-- Not: Bu sütunlar kodun hiçbir yerinde okunmuyordu (client import yok,
-- edge function yok, DB fonksiyonu yok) — düzeltme fonksiyonel gerileme
-- yaratmaz.
-- =====================================================

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_extension WHERE extname = 'supabase_vault'
  ) THEN
    -- Mevcut düz metin değerlerini vault'a taşı (varsa).
    -- vault.secrets.secret write-only olduğu için buradan geri okunamaz,
    -- ancak ai_settings'ten normal SELECT ile okuyup vault'a yazabiliriz.
    INSERT INTO vault.secrets (name, secret, description)
    SELECT 'GEMINI_API_KEY', gemini_api_key, 'Google Gemini API anahtari - text/vision/image'
    FROM public.ai_settings
    WHERE gemini_api_key IS NOT NULL AND gemini_api_key <> ''
    ON CONFLICT (name) DO UPDATE
      SET secret = EXCLUDED.secret, description = EXCLUDED.description;

    INSERT INTO vault.secrets (name, secret, description)
    SELECT 'GROQ_API_KEY', groq_api_key, 'Groq API anahtari - text/vision fallback'
    FROM public.ai_settings
    WHERE groq_api_key IS NOT NULL AND groq_api_key <> ''
    ON CONFLICT (name) DO UPDATE
      SET secret = EXCLUDED.secret, description = EXCLUDED.description;

    INSERT INTO vault.secrets (name, secret, description)
    SELECT 'OPENROUTER_API_KEY', openrouter_api_key, 'OpenRouter API anahtari - coklu model yedek'
    FROM public.ai_settings
    WHERE openrouter_api_key IS NOT NULL AND openrouter_api_key <> ''
    ON CONFLICT (name) DO UPDATE
      SET secret = EXCLUDED.secret, description = EXCLUDED.description;

    INSERT INTO vault.secrets (name, secret, description)
    SELECT 'OPENAI_API_KEY', openai_api_key, 'OpenAI API anahtari - son care fallback'
    FROM public.ai_settings
    WHERE openai_api_key IS NOT NULL AND openai_api_key <> ''
    ON CONFLICT (name) DO UPDATE
      SET secret = EXCLUDED.secret, description = EXCLUDED.description;

    RAISE NOTICE 'AI anahtarlari vault.secrets''e tasiandi.';
  ELSE
    -- vault extension aktif degil: migration'i patlatma, manuel fallback bildir.
    RAISE NOTICE 'supabase_vault extension aktif degil. AI anahtarlarini Supabase Dashboard -> Edge Functions Secrets uzerinden manuel ekleyin (GEMINI_API_KEY, GROQ_API_KEY, OPENROUTER_API_KEY, OPENAI_API_KEY). Duz metin sütunlar yine de kaldirilacak.';
  END IF;
END $$;

-- Düz metin sütunlarını kaldır. *_key_set boolean sütunları korunur.
ALTER TABLE public.ai_settings
  DROP COLUMN IF EXISTS gemini_api_key,
  DROP COLUMN IF EXISTS groq_api_key,
  DROP COLUMN IF EXISTS openrouter_api_key,
  DROP COLUMN IF EXISTS openai_api_key;