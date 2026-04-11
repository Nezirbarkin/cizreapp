-- ============================================================================
-- DİREKT MESAJ PUSH BİLDİRİM TRİGGER KONTROLÜ
-- ============================================================================

-- 1. messages tablosundaki tüm trigger'ları kontrol et
SELECT trigger_name, event_manipulation, action_timing, action_statement
FROM information_schema.triggers
WHERE event_object_table = 'messages'
ORDER BY trigger_name;

-- 2. conversations tablosundaki trigger'ları kontrol et
SELECT trigger_name, event_manipulation, action_timing, action_statement
FROM information_schema.triggers
WHERE event_object_table = 'conversations'
ORDER BY trigger_name;

-- 3. Direkt mesaj push gönderen fonksiyon var mı?
SELECT proname, prosrc
FROM pg_proc
WHERE proname LIKE '%message%push%'
OR proname LIKE '%push%message%'
OR proname LIKE '%notify%message%'
OR proname LIKE '%message%notification%';
