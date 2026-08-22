-- ============================================================================
-- FIX NOTIFICATIONS TYPE CHECK CONSTRAINT
-- Mevcut satırlar constraint'e uymuyor, constraint'i kaldır ve text olarak bırak
-- ============================================================================

-- 1. Mevcut CHECK constraint'i kaldır (herhangi bir isimle)
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN (
        SELECT con.conname
        FROM pg_constraint con
        JOIN pg_class rel ON rel.oid = con.conrelid
        JOIN pg_namespace nsp ON nsp.oid = rel.relnamespace
        WHERE rel.relname = 'notifications'
        AND nsp.nspname = 'public'
        AND con.contype = 'c'
        AND con.conname LIKE '%type%'
    ) LOOP
        EXECUTE 'ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS ' || r.conname;
        RAISE NOTICE 'Dropped constraint: %', r.conname;
    END LOOP;
END $$;

-- 2. CHECK constraint olmadan bırak (type TEXT olarak kalır, tüm değerler kabul edilir)
-- Bu sayede post_share dahil her türlü bildirim tipi kullanılabilir
COMMENT ON COLUMN public.notifications.type IS 'Bildirim tipi: like, comment, follow, mention, order, shop, post_share, vb.';
