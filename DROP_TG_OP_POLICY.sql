-- ============================================================================
-- TG_OP KULLANAN HATALI POLICY'Yİ SİL
-- ============================================================================
-- Bu dosya, RLS policy içinde TG_OP kullanan hatalı policy'yi siler.

BEGIN;

-- Hatalı policy'yi sil
DROP POLICY IF EXISTS "notifications_manage_own" ON public.notifications;

-- Diğer olası hatalı policy isimlerini temizle
DROP POLICY IF EXISTS "notifications_manage" ON public.notifications;
DROP POLICY IF EXISTS "notifications_all" ON public.notifications;
DROP POLICY IF EXISTS "Users can manage own notifications" ON public.notifications;

-- Doğru policy'leri oluştur (FOR ALL kullanmadan, ayrı ayrı)
DO $$
BEGIN
    -- DROP all existing notifications policies
    DROP POLICY IF EXISTS "notifications_select" ON public.notifications;
    DROP POLICY IF EXISTS "notifications_insert" ON public.notifications;
    DROP POLICY IF EXISTS "notifications_update" ON public.notifications;
    DROP POLICY IF EXISTS "notifications_delete" ON public.notifications;
    DROP POLICY IF EXISTS "notifications_select_policy" ON public.notifications;
    DROP POLICY IF EXISTS "notifications_insert_policy" ON public.notifications;
    DROP POLICY IF EXISTS "notifications_update_policy" ON public.notifications;
    DROP POLICY IF EXISTS "notifications_delete_policy" ON public.notifications;
    DROP POLICY IF EXISTS "notifications_manage_own" ON public.notifications;
    DROP POLICY IF EXISTS "Users can view own notifications" ON public.notifications;
    DROP POLICY IF EXISTS "Users can update own notifications" ON public.notifications;
    DROP POLICY IF EXISTS "Anyone can insert notifications" ON public.notifications;
    DROP POLICY IF EXISTS "Enable insert for authenticated users only" ON public.notifications;
    DROP POLICY IF EXISTS "Enable select for authenticated users only" ON public.notifications;
    DROP POLICY IF EXISTS "Enable update for authenticated users only" ON public.notifications;
    DROP POLICY IF EXISTS "Enable delete for authenticated users only" ON public.notifications;

    -- CREATE correct policies (separate, no FOR ALL with TG_OP)
    
    -- SELECT: Sadece kendi bildirimlerini görebilir
    CREATE POLICY "notifications_select"
        ON public.notifications
        FOR SELECT
        TO authenticated
        USING (user_id = (select auth.uid()));

    -- INSERT: Herkes bildirim ekleyebilir (trigger'lar için)
    CREATE POLICY "notifications_insert"
        ON public.notifications
        FOR INSERT
        TO authenticated
        WITH CHECK (true);

    -- UPDATE: Sadece kendi bildirimlerini güncelleyebilir
    CREATE POLICY "notifications_update"
        ON public.notifications
        FOR UPDATE
        TO authenticated
        USING (user_id = (select auth.uid()))
        WITH CHECK (user_id = (select auth.uid()));

    -- DELETE: Sadece kendi bildirimlerini silebilir
    CREATE POLICY "notifications_delete"
        ON public.notifications
        FOR DELETE
        TO authenticated
        USING (user_id = (select auth.uid()));
END $$;

COMMIT;

-- Doğrulama
SELECT 
    policyname, 
    cmd, 
    roles 
FROM pg_policies 
WHERE tablename = 'notifications'
ORDER BY cmd;
