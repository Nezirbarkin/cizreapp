-- =====================================================
-- KAPSAMLI TANI: Mesaj sistemi tam analiz
-- Her sorguyu tek tek çalıştırın ve sonuçları paylaşın
-- =====================================================

-- SORGU 1: messages tablosu sütun tipleri
SELECT 'SORGU_1_MESSAGES_COLUMNS' as query_id;
SELECT column_name, data_type, udt_name
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'messages'
ORDER BY ordinal_position;

-- SORGU 2: conversations tablosu sütun tipleri
SELECT 'SORGU_2_CONVERSATIONS_COLUMNS' as query_id;
SELECT column_name, data_type, udt_name
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'conversations'
ORDER BY ordinal_position;

-- SORGU 3: messages tablosundaki trigger'lar
SELECT 'SORGU_3_MESSAGES_TRIGGERS' as query_id;
SELECT trigger_name, event_manipulation, action_timing, action_statement
FROM information_schema.triggers
WHERE event_object_schema = 'public' AND event_object_table = 'messages';

-- SORGU 4: messages RLS politikaları
SELECT 'SORGU_4_MESSAGES_POLICIES' as query_id;
SELECT policyname, cmd, qual, with_check
FROM pg_policies
WHERE tablename = 'messages' AND schemaname = 'public';

-- SORGU 5: conversations RLS politikaları
SELECT 'SORGU_5_CONVERSATIONS_POLICIES' as query_id;
SELECT policyname, cmd, qual, with_check
FROM pg_policies
WHERE tablename = 'conversations' AND schemaname = 'public';

-- SORGU 6: Tüm send_message fonksiyonları
SELECT 'SORGU_6_SEND_MESSAGE_FUNCTIONS' as query_id;
SELECT routine_name, data_type as return_type, security_type,
       (SELECT string_agg(parameter_name || ' ' || udt_name, ', ' ORDER BY ordinal_position)
        FROM information_schema.parameters p2
        WHERE p2.specific_name = r.specific_name AND p2.parameter_mode = 'IN') as params
FROM information_schema.routines r
WHERE routine_schema = 'public' AND routine_name LIKE '%message%';

-- SORGU 7: update_conversation_on_message fonksiyonunun tanımı
SELECT 'SORGU_7_TRIGGER_FUNCTION' as query_id;
SELECT routine_name, security_type, routine_definition
FROM information_schema.routines
WHERE routine_schema = 'public' AND routine_name = 'update_conversation_on_message';

-- SORGU 8: conversations tablosundaki foreign key'ler ve constraint'ler
SELECT 'SORGU_8_CONVERSATIONS_CONSTRAINTS' as query_id;
SELECT constraint_name, constraint_type
FROM information_schema.table_constraints
WHERE table_schema = 'public' AND table_name = 'conversations';

-- SORGU 9: messages tablosundaki foreign key'ler
SELECT 'SORGU_9_MESSAGES_CONSTRAINTS' as query_id;
SELECT constraint_name, constraint_type
FROM information_schema.table_constraints
WHERE table_schema = 'public' AND table_name = 'messages';
