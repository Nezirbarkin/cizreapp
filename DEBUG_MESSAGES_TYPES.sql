-- =====================================================
-- DEBUG: Messages ve Conversations Tip Kontrolü
-- =====================================================

-- 1. conversations.id tipi
SELECT 
    'conversations.id' as column_info,
    column_name, 
    data_type, 
    udt_name,
    is_nullable
FROM information_schema.columns
WHERE table_schema = 'public' 
  AND table_name = 'conversations'
  AND column_name = 'id'

UNION ALL

-- 2. messages.conversation_id tipi
SELECT 
    'messages.conversation_id',
    column_name, 
    data_type, 
    udt_name,
    is_nullable
FROM information_schema.columns
WHERE table_schema = 'public' 
  AND table_name = 'messages'
  AND column_name = 'conversation_id'

UNION ALL

-- 3. messages.sender_id tipi
SELECT 
    'messages.sender_id',
    column_name, 
    data_type, 
    udt_name,
    is_nullable
FROM information_schema.columns
WHERE table_schema = 'public' 
  AND table_name = 'messages'
  AND column_name = 'sender_id';

-- 4. Messages tablosundaki tüm constraint'ler
SELECT 
    'Constraints' as info_type,
    constraint_name,
    constraint_type
FROM information_schema.table_constraints
WHERE table_schema = 'public' 
  AND table_name = 'messages';

-- 5. Messages tablosundaki trigger'lar
SELECT 
    'Triggers' as info_type,
    trigger_name,
    event_manipulation,
    action_statement
FROM information_schema.triggers
WHERE event_object_schema = 'public' 
  AND event_object_table = 'messages';
