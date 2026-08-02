-- Gemini API Key'i manuel olarak güncelle
-- NOT: 'BURAYA_API_KEY' kısmını Gemini API key'iniz ile değiştirin

UPDATE public.ai_settings
SET 
  gemini_api_key = 'BURAYA_API_KEY',
  gemini_key_set = true,
  updated_at = NOW()
WHERE id = 1;
