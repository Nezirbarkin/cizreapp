-- =====================================================
-- DIAGNOSTIC: Messages tablosunun gerçek tiplerini kontrol et
-- Bu SQL'i Supabase SQL Editor'da çalıştırın
-- =====================================================

-- 1. messages tablosundaki sütun tipleri
SELECT 
    column_name, 
    data_type, 
    udt_name,
    is_nullable
FROM information_schema.columns
WHERE table_schema = 'public' 
  AND table_name = 'messages'
ORDER BY ordinal_position;

-- 2. conversations tablosundaki sütun tipleri
SELECT 
    column_name, 
    data_type, 
    udt_name,
    is_nullable
FROM information_schema.columns
WHERE table_schema = 'public' 
  AND table_name = 'conversations'
ORDER BY ordinal_position;

-- 3. Mevcut trigger'lar
SELECT 
    trigger_name,
    event_manipulation,
    action_timing,
    action_statement
FROM information_schema.triggers
WHERE event_object_schema = 'public' 
  AND event_object_table = 'messages';

-- 4. Mevcut RLS policies (messages tablosu)
SELECT 
    policyname,
    permissive,
    roles,
    cmd,
    qual,
    with_check
FROM pg_policies
WHERE tablename = 'messages'
ORDER BY policyname;

-- 5. send_message_direct fonksiyonunun mevcut versiyonu
SELECT 
    routine_name,
    routine_definition,
    data_type as return_type,
    security_type
FROM information_schema.routines
WHERE routine_schema = 'public' 
  AND routine_name = 'send_message_direct';
