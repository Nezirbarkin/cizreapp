-- ============================================================================
-- ADIM 1: Önce mevcut tipleri kontrol edin
-- Bu SQL'i Supabase SQL Editor'da çalıştırın
-- ============================================================================

SELECT DISTINCT type, COUNT(*) as count
FROM public.notifications
GROUP BY type
ORDER BY count DESC;
