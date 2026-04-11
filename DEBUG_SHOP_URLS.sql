-- Supabase SQL Editor'de çalıştırın
-- Shop kapak ve logo URL'lerini kontrol edin

SELECT 
  id,
  name,
  logo_url,
  cover_image,
  created_at,
  updated_at
FROM shops 
WHERE id = 'c569e5cd-ef0d-4241-a8d5-7395e22aa1de';

-- Eğer URL'ler NULL ise, sorgu yanlışsa bilme gerekebilir
