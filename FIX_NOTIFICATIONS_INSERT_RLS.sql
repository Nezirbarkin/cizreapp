-- ============================================================================
-- NOTIFICATIONS INSERT RLS DÜZELTME
-- Sorun: INSERT policy "TO public" ile tanımlanmış, authenticated rolü için
-- düzgün çalışmıyor. Ayrıca WITH CHECK (auth.uid() IS NOT NULL) çok kısıtlı -
-- SECURITY DEFINER trigger'lar auth.uid() döndüremeyebilir.
-- Çözüm: Policy'yi "TO authenticated, WITH CHECK (true)" olarak yeniden oluştur
-- Diğer policy'lere (SELECT, UPDATE, DELETE, Service role) dokunulmuyor
-- ============================================================================

-- Mevcut INSERT policy'yi kaldır (sadece INSERT, diğerlerine dokunma)
DROP POLICY IF EXISTS "Authenticated users can create notifications" ON public.notifications;

-- Yeni INSERT policy - authenticated kullanıcılar bildirim oluşturabilir
-- WITH CHECK (true) kasıtlı: SECURITY DEFINER trigger'lar ve cross-user bildirimler için gerekli
CREATE POLICY "Authenticated users can create notifications"
    ON public.notifications
    FOR INSERT
    TO authenticated
    WITH CHECK (true);

-- Doğrulama
SELECT 
    policyname,
    cmd,
    roles,
    qual,
    with_check
FROM pg_policies
WHERE tablename = 'notifications'
  AND schemaname = 'public'
ORDER BY cmd;