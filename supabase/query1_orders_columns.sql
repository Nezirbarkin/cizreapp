-- =====================================================
-- QUERY 1: ORDERS TABLOSU YAPISI
-- Bu sorguyu SQL Editor'da çalıştırıp sonucu gönderin
-- =====================================================
SELECT column_name, data_type
FROM information_schema.columns 
WHERE table_schema = 'public' 
  AND table_name = 'orders' 
ORDER BY ordinal_position;
