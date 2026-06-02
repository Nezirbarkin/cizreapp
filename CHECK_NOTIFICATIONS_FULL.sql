-- ============================================================================
-- NOTIFICATIONS RLS DURUM KONTROLÜ - DETAYLI
-- Bu SQL'i Supabase SQL Editor'de çalıştır ve TÜM sonucu paylaş
-- ============================================================================

-- 1. Tüm policy'leri listele
SELECT 
    policyname,
    cmd,
    roles,
    qual,
    with_check
FROM pg_policies
WHERE tablename = 'notifications'
  AND schemaname = 'public'
ORDER BY cmd;

-- 2. RLS etkin mi kontrol et
SELECT relname, relrowsecurity, relforcerowsecurity
FROM pg_class
WHERE relname = 'notifications'
  AND relnamespace = 'public'::regnamespace;

-- 3. notifications tablosu sütun yapısı
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_name = 'notifications'
  AND table_schema = 'public'
ORDER BY ordinal_position;