-- =====================================================
-- CONVERSATIONS TABLOSUNUN VAR OLUP OLMADIĞINI KONTROL ET
-- =====================================================

-- 1. Tüm tabloları listele
SELECT table_name 
FROM information_schema.tables 
WHERE table_schema = 'public' 
  AND table_type = 'BASE TABLE'
ORDER BY table_name;

-- 2. Conversations ile başlayan tabloları ara
SELECT table_name 
FROM information_schema.tables 
WHERE table_schema = 'public' 
  AND table_name LIKE '%conversation%'
ORDER BY table_name;

-- 3. Eğer conversations tablosu varsa sütunlarını göster
SELECT
    column_name,
    data_type,
    is_nullable,
    column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'conversations'
ORDER BY ordinal_position;

-- 4. Messages tablosunu kontrol et
SELECT
    column_name,
    data_type,
    is_nullable,
    column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'messages'
ORDER BY ordinal_position;

-- 5. Messages tablosundaki son 5 kaydı göster (eğer varsa)
SELECT
    id,
    conversation_id,
    sender_id,
    content,
    created_at
FROM public.messages
ORDER BY created_at DESC
LIMIT 5;
