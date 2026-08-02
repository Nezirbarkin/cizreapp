-- =====================================================
-- API ANAHTARLARI - ai_settings TABLOSUNA EKLEME
-- =====================================================
-- API anahtarlarını doğrudan ai_settings tablosuna ekler
-- Sadece admin erişebilir (RLS ile korunur)
-- =====================================================

-- 1. ai_settings tablosuna API anahtarı sütunları ekle
ALTER TABLE public.ai_settings
  ADD COLUMN IF NOT EXISTS gemini_api_key TEXT,
  ADD COLUMN IF NOT EXISTS groq_api_key TEXT,
  ADD COLUMN IF NOT EXISTS openrouter_api_key TEXT,
  ADD COLUMN IF NOT EXISTS openai_api_key TEXT;

-- 2. key_set boolean alanları ekle (admin UI için)
ALTER TABLE public.ai_settings
  ADD COLUMN IF NOT EXISTS gemini_key_set BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS groq_key_set BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS openrouter_key_set BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS openai_key_set BOOLEAN NOT NULL DEFAULT false;

-- 3. Mevcut boolean key_set alanlarını güncelle (anahtar varsa true yap)
UPDATE public.ai_settings SET
  gemini_key_set = (gemini_api_key IS NOT NULL AND gemini_api_key != ''),
  groq_key_set = (groq_api_key IS NOT NULL AND groq_api_key != ''),
  openrouter_key_set = (openrouter_api_key IS NOT NULL AND openrouter_api_key != ''),
  openai_key_set = (openai_api_key IS NOT NULL AND openai_api_key != '')
WHERE id = 1;