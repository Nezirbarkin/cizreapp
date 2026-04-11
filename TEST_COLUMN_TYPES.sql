-- =====================================================
-- TEST: Sütun tiplerini kesin doğrula
-- =====================================================

-- Test 1: conversations.id UUID mi?
SELECT 
    'TEST_1_CONVERSATIONS_ID' as test_name,
    id, 
    pg_typeof(id) as column_type,
    id::text as id_as_text,
    id::UUID as id_as_uuid
FROM public.conversations
LIMIT 1;

-- Test 2: messages.conversation_id UUID mi?
SELECT 
    'TEST_2_MESSAGES_CONVERSATION_ID' as test_name,
    conversation_id,
    pg_typeof(conversation_id) as column_type,
    conversation_id::text as conv_id_as_text,
    conversation_id::UUID as conv_id_as_uuid
FROM public.messages
LIMIT 1;

-- Test 3: Sorunlu sorgu simülasyonu
-- Bu TAMAMEN messages tablosundaki gerçek tipleri kullanır
SELECT 
    'TEST_3_SELECT_SIMULATION' as test_name,
    m.conversation_id,
    c.id,
    (m.conversation_id = c.id) as comparison_result
FROM public.messages m
JOIN public.conversations c ON c.id = m.conversation_id
LIMIT 1;

-- Test 4: conversations.user_id ve other_user_id tipleri
SELECT 
    'TEST_4_CONVERSATIONS_USER_IDS' as test_name,
    user_id,
    pg_typeof(user_id) as user_id_type,
    other_user_id,
    pg_typeof(other_user_id) as other_user_id_type
FROM public.conversations
LIMIT 1;
