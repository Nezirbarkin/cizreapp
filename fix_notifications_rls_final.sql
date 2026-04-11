-- ================================================
-- NOTIFICATIONS RLS DÜZELTMESİ
-- ================================================

-- 1. Mevcut RLS policy'leri kontrol et
SELECT 
    policyname, 
    cmd, 
    permissive, 
    qual::text,
    with_check::text
FROM pg_policies 
WHERE tablename = 'notifications';

-- 2. RLS'in aktif olduğundan emin ol
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

-- 3. Mevcut INSERT policy'lerini kaldır (varsa)
DROP POLICY IF EXISTS "notifications_insert_policy" ON public.notifications;
DROP POLICY IF EXISTS "Users can create notifications" ON public.notifications;
DROP POLICY IF EXISTS "Allow insert notifications" ON public.notifications;
DROP POLICY IF EXISTS "Enable insert notifications" ON public.notifications;

-- 4. Herkesin bildirim ekleyebilmesi için INSERT policy oluştur
-- (Bildirimler genelde server-side trigger veya client-side insert ile oluşturulur)
CREATE POLICY "Anyone can insert notifications"
ON public.notifications
FOR INSERT
TO authenticated
WITH CHECK (true);

-- 5. Kullanıcılar sadece KENDİ bildirimlerini görebilsin
DROP POLICY IF EXISTS "Users can view own notifications" ON public.notifications;
CREATE POLICY "Users can view own notifications"
ON public.notifications
FOR SELECT
TO authenticated
USING (user_id = auth.uid());

-- 6. Kullanıcılar kendi bildirimlerini güncelleyebilsin (okundu olarak işaretle)
DROP POLICY IF EXISTS "Users can update own notifications" ON public.notifications;
CREATE POLICY "Users can update own notifications"
ON public.notifications
FOR UPDATE
TO authenticated
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

-- 7. Kullanıcılar kendi bildirimlerini silebilsin
DROP POLICY IF EXISTS "Users can delete own notifications" ON public.notifications;
CREATE POLICY "Users can delete own notifications"
ON public.notifications
FOR DELETE
TO authenticated
USING (user_id = auth.uid());

-- 8. Kontrol
SELECT 
    policyname, 
    cmd, 
    permissive
FROM pg_policies 
WHERE tablename = 'notifications';

SELECT '✅ Notifications RLS düzeltildi - Artık bildirimler oluşturulabilir' as sonuc;
