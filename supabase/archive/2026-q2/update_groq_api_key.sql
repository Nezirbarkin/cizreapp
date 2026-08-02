-- Groq API Key'i manuel olarak güncelle
-- NOT: 'BURAYA_API_KEY' kısmını Groq API key'iniz ile değiştirin

UPDATE public.ai_settings
SET 
  groq_api_key = 'BURAYA_API_KEY',
  groq_key_set = true,
  updated_at = NOW()
WHERE id = 1;
