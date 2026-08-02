-- ============================================================================
-- Mevcut Notifications Tablosu Constraint'lerini Kontrol Et
-- ============================================================================
-- Bu SQL dosyasını Supabase SQL Editor'de çalıştırın ve sonucu bana gönderin.
-- Sonucu kopyalayıp bana gönderin, size özel bir güncelleme SQL'i hazırlayacağım.

-- 1. Mevcut type check constraint'ini bul
SELECT 
    conname AS constraint_name,
    pg_get_constraintdef(oid) AS constraint_definition
FROM pg_constraint 
WHERE conrelid = 'public.notifications'::regclass 
AND contype = 'c';

-- 2. Mevcut tüm bildirim türlerini göster
SELECT DISTINCT type FROM public.notifications ORDER BY type;

-- 3. Tablo yapısını göster
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns 
WHERE table_schema = 'public' AND table_name = 'notifications'
ORDER BY ordinal_position;