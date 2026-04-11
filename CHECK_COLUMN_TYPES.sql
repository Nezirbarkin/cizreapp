-- =====================================================
-- QUICK DIAGNOSIS: Tablo tiplerini kontrol et
-- =====================================================

-- messages ve conversations tablo tipleri
SELECT 
    t.table_name,
    c.column_name, 
    c.data_type,
    c.udt_name
FROM information_schema.tables t
JOIN information_schema.columns c ON c.table_name = t.table_name AND c.table_schema = t.table_schema
WHERE t.table_schema = 'public' 
  AND t.table_name IN ('messages', 'conversations')
  AND c.column_name IN ('id', 'conversation_id', 'user_id', 'other_user_id', 'sender_id')
ORDER BY t.table_name, c.column_name;
