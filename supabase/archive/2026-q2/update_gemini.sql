-- Gemini API Key'i güncelle
UPDATE public.ai_settings
SET 
  gemini_api_key = 'YOUR_GEMINI_API_KEY_HERE',
  gemini_key_set = true,
  updated_at = NOW()
WHERE id = 1;
