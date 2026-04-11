-- =====================================================
-- DEBUG: Mevcut database durumunu analiz et
-- Sorunun tam olarak nerede olduğunu bulmak için
-- =====================================================

-- 1. Mevcut trigger'lar
SELECT 
    'TRIGGERS' as info_type,
    trigger_name,
    event_manipulation,
    action_timing
FROM information_schema.triggers
WHERE event_object_schema = 'public' 
  AND event_object_table = 'messages'
ORDER BY trigger_name;

-- 2. Mevcut RLS durumu
SELECT 
    schemaname,
    tablename,
    relrowse as rls_enabled
FROM pg_class
JOIN pg_namespace ON pg_namespace.oid = pg_class.relnamespace
WHERE pg_class.relname IN ('messages', 'conversations')
  AND pg_namespace.nspname = 'public';

-- 3. Mevcut RLS politikaları
SELECT 
    policyname,
    cmd,
    qual,
    with_check
FROM pg_policies
WHERE tablename IN ('messages', 'conversations')
  AND schemaname = 'public'
ORDER BY tablename, policyname;

-- 4. Mevcut RPC fonksiyonları
SELECT 
    routine_name,
    data_type as return_type,
    (SELECT string_agg(p.parameter_name || ' ' || p.udt_name, ', ' ORDER BY p.ordinal_position)
     FROM information_schema.parameters p
     WHERE p.specific_name = r.specific_name 
       AND p.parameter_mode = 'IN'
    ) as params
FROM information_schema.routines r
WHERE routine_schema = 'public' 
  AND routine_name LIKE '%message%'
ORDER BY routine_name;

-- 5. conversations INSERT politikasının detaylı kontrolü
SELECT 
    policyname,
    with_check,
    pg_get_viewdef('public', 'conversations_insert_policy'::regclass, true) as policy_def
FROM pg_policies
WHERE tablename = 'conversations'
  AND schemaname = 'public'
  AND cmd = 'INSERT';

-- 6. Messages tablosundaki constraint'ler
SELECT 
    conname,
    contype,
    pg_get_constraintdef(oid, true) as definition
FROM pg_constraint
WHERE conrelid = 'public.messages'::regclass
ORDER BY contype, conname;
