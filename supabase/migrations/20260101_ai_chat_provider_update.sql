-- =====================================================
-- AI CHAT SYSTEM - SAĞLAYICI GÜNCELLEMESİ
-- =====================================================
-- Gemini → Groq → OpenRouter fallback mekanizması
-- Text: sırayla dene | Vision/Image: destekleyene git
-- =====================================================

-- 1. ai_settings tablosuna yeni sağlayıcı alanları ekle
ALTER TABLE public.ai_settings
  ADD COLUMN IF NOT EXISTS groq_text_model TEXT NOT NULL DEFAULT 'llama-3.3-70b-versatile',
  ADD COLUMN IF NOT EXISTS groq_vision_model TEXT NOT NULL DEFAULT 'llama-3.2-90b-vision-preview',
  ADD COLUMN IF NOT EXISTS openrouter_text_model TEXT NOT NULL DEFAULT 'google/gemini-2.0-flash-exp:free',
  ADD COLUMN IF NOT EXISTS openrouter_vision_model TEXT NOT NULL DEFAULT 'google/gemini-2.0-flash-exp:free',
  ADD COLUMN IF NOT EXISTS openrouter_image_model TEXT NOT NULL DEFAULT 'stable-diffusion-xl';

-- 2. provider CHECK kısıtlamasını güncelle (gemini, openai, groq, openrouter)
ALTER TABLE public.ai_settings DROP CONSTRAINT IF EXISTS ai_settings_provider_check;
ALTER TABLE public.ai_settings ADD CONSTRAINT ai_settings_provider_check 
  CHECK (provider IN ('gemini', 'openai', 'groq', 'openrouter'));

-- 3. ai_conversations provider CHECK kısıtlamasını güncelle
ALTER TABLE public.ai_conversations DROP CONSTRAINT IF EXISTS ai_conversations_provider_check;
ALTER TABLE public.ai_conversations ADD CONSTRAINT ai_conversations_provider_check
  CHECK (provider IN ('gemini', 'openai', 'groq', 'openrouter'));

-- 4. ai_messages provider alanını güncelle (CHECK yok, string olarak kalabilir)

-- 5. Vault anahtarları için environment variable isimleri:
-- GEMINI_API_KEY (zaten var)
-- GROQ_API_KEY (yeni)
-- OPENROUTER_API_KEY (yeni)
-- OPENAI_API_KEY (zaten var, opsiyonel)

-- 6. Varsayılan sağlayıcıyı güncelle (gemini kalır birincil)
UPDATE public.ai_settings SET 
  text_model = 'gemini-2.0-flash',
  vision_model = 'gemini-2.0-flash'
WHERE id = 1;

-- =====================================================
-- NOT: Aşağıdaki komutları terminalde çalıştırın
-- =====================================================
-- supabase secrets set GROQ_API_KEY=gsk_...sizin-anahtariniz...
-- supabase secrets set OPENROUTER_API_KEY=sk-or-...sizin-anahtariniz...
-- =====================================================