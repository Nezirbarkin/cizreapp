-- ============================================================================
-- HTTP_POST ve TİP KISITLAMA KONTROL
-- ============================================================================

-- 1. Tüm schemalardaki http_post fonksiyonlarını bul
SELECT 
  n.nspname AS schema_adi,
  p.proname AS fonksiyon_adi,
  pg_catalog.pg_get_function_arguments(p.oid) AS parametreler,
  pg_catalog.pg_get_function_result(p.oid) AS donus_tipi
FROM pg_catalog.pg_proc p
JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
WHERE p.proname = 'http_post'
ORDER BY n.nspname;

-- 2. notifications tablosundaki check constraint'i bul (hangi tipler izinli?)
SELECT 
  conname AS constraint_adi,
  pg_get_constraintdef(oid) AS constraint_tanimi
FROM pg_constraint
WHERE conrelid = 'notifications'::regclass
AND contype = 'c';

-- 3. 09d4668c kullanıcısının FCM token'ı
SELECT id, username, fcm_token
FROM profiles
WHERE id = '09d4668c-639e-417c-9304-fdd0ce5a045d';
