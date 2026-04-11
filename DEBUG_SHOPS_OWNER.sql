-- Supabase SQL Editor'de çalıştırın!
-- Shop ID'sinin owner_id'sini kontrol edin

-- Değişkenler
-- Shop ID: c569e5cd-ef0d-4241-a8d5-7395e22aa1de
-- Auth UID: a3623ff5-57fd-4529-b03e-44a68629926c

SELECT 
  id,
  owner_id,
  name,
  created_at
FROM shops 
WHERE id = 'c569e5cd-ef0d-4241-a8d5-7395e22aa1de';

-- Eğer yukarıda owner_id farklıysa, düzeltmek için:
-- UPDATE shops 
-- SET owner_id = 'a3623ff5-57fd-4529-b03e-44a68629926c'
-- WHERE id = 'c569e5cd-ef0d-4241-a8d5-7395e22aa1de';
