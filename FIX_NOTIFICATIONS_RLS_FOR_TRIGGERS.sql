-- ============================================================================
-- FIX: Notifications RLS Policy - Herkesin INSERT yapabilmesi
-- ============================================================================
-- Problem: Bildirim oluştururken RLS hatası
-- Error: new row violates row-level security policy for table "notifications"
-- Çözüm: INSERT politikasını düzelt
-- ============================================================================

-- Mevcut politikaları kaldır
DO $$ 
DECLARE
    pol RECORD;
BEGIN
    FOR pol IN (
        SELECT policyname FROM pg_policies 
        WHERE tablename = 'notifications' AND schemaname = 'public'
    )
    LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON public.notifications', pol.policyname);
    END LOOP;
END $$;

-- Yeni politikalar oluştur

-- SELECT: Kullanıcı kendi bildirimlerini görebilir
CREATE POLICY "Users can view own notifications"
ON public.notifications
FOR SELECT
TO authenticated
USING (user_id = auth.uid());

-- INSERT: Authenticated kullanıcılar bildirim oluşturabilir (başkasına da)
CREATE POLICY "Users can insert notifications"
ON public.notifications
FOR INSERT
TO authenticated
WITH CHECK (true);

-- UPDATE: Kullanıcı kendi bildirimlerini güncelleyebilir (okundu işareti vs)
CREATE POLICY "Users can update own notifications"
ON public.notifications
FOR UPDATE
TO authenticated
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

-- DELETE: Kullanıcı kendi bildirimlerini silebilir
CREATE POLICY "Users can delete own notifications"
ON public.notifications
FOR DELETE
TO authenticated
USING (user_id = auth.uid());

-- Service role tam erişim
CREATE POLICY "Service role full access"
ON public.notifications
FOR ALL
TO service_role
USING (true)
WITH CHECK (true);

-- RLS etkin olduğundan emin ol
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

SELECT '✅ Notifications RLS politikaları düzeltildi' as result;
