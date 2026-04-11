-- ============================================================================
-- GROUP_MESSAGE TİPİNİN EKLENDİĞİNİ KONTROL ET
-- ============================================================================

-- Constraint'i kontrol et
SELECT conname AS constraint_name, pg_get_constraintdef(oid) AS check_clause
FROM pg_constraint
WHERE conrelid = 'public.notifications'::regclass
AND contype = 'c';

-- group_message tipi mevcut mu kontrol et
SELECT CASE 
  WHEN EXISTS (
    SELECT 1 FROM pg_constraint 
    WHERE conrelid = 'public.notifications'::regclass 
    AND conname = 'notifications_type_check'
    AND pg_get_constraintdef(oid) LIKE '%group_message%'
  ) THEN '✅ group_message tipi eklendi!'
  ELSE '❌ group_message tipi eklenemedi'
END AS durum;
