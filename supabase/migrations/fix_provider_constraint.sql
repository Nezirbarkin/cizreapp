-- Provider constraint'ini "auto" değerini de içerecek şekilde güncelle

-- Mevcut constraint'i kaldır
ALTER TABLE public.ai_conversations DROP CONSTRAINT IF EXISTS ai_conversations_provider_check;

-- Yeni constraint ekle (auto dahil)
ALTER TABLE public.ai_conversations ADD CONSTRAINT ai_conversations_provider_check 
CHECK (provider IN ('auto', 'gemini', 'groq', 'openrouter', 'openai'));
