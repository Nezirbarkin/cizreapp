-- ================================================
-- KRİTİK SQL - RLS Enable (Basit)
-- ================================================

-- 1. conversations ve messages tabloları için RLS enable
-- NOT: Mevcut policy'leri koruyoruz, sadece RLS'i aktif ediyoruz

ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

-- 2. Kontrol
SELECT tablename, rowsecurity
FROM pg_tables
WHERE schemaname = 'public'
AND tablename IN ('conversations', 'messages');

SELECT '✅ RLS enabled for conversations and messages' as status;
