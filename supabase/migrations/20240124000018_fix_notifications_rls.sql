-- ============================================================================
-- NOTIFICATIONS - Fix RLS Policy for INSERT
-- Bildirim eklemek için RLS policy düzeltmesi
-- ============================================================================

-- Mevcut policy'leri kontrol et ve gerekiyorsa düzelt
DROP POLICY IF EXISTS "Service can create notifications" ON public.notifications;

-- Herkes (authenticated users) bildirim ekleyebilir
-- Bu, uygulamanın bildirim oluşturabilmesi için gereklidir
CREATE POLICY "Authenticated users can insert notifications"
ON public.notifications
FOR INSERT
TO authenticated
WITH CHECK (true);

-- Alternatif: Service role ile insert için (eğer yukarı çalışmazsa)
-- DROP POLICY IF EXISTS "Authenticated users can insert notifications" ON public.notifications;
-- CREATE POLICY "Allow insert for notification creation"
-- ON public.notifications
-- FOR INSERT
-- WITH CHECK (true);
