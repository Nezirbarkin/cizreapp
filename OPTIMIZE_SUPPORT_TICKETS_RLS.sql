-- ================================================
-- Support Tickets RLS Performance Optimization
-- ================================================
-- 1. auth.uid() performans sorununu düzelt
-- 2. Duplicate policy'leri temizle
-- 3. Tek, optimize edilmiş policy'ler oluştur

-- ADIM 1: Tüm mevcut policy'leri sil
DROP POLICY IF EXISTS "users_can_insert_support_tickets" ON support_tickets;
DROP POLICY IF EXISTS "users_can_view_own_support_tickets" ON support_tickets;
DROP POLICY IF EXISTS "users_can_update_own_support_tickets" ON support_tickets;
DROP POLICY IF EXISTS "users_can_delete_own_support_tickets" ON support_tickets;
DROP POLICY IF EXISTS "admin_can_view_all_support_tickets" ON support_tickets;
DROP POLICY IF EXISTS "support_tickets_insert_policy" ON support_tickets;
DROP POLICY IF EXISTS "support_tickets_select_own_policy" ON support_tickets;
DROP POLICY IF EXISTS "support_tickets_update_policy" ON support_tickets;
DROP POLICY IF EXISTS "support_tickets_delete_policy" ON support_tickets;
DROP POLICY IF EXISTS "Enable insert for authenticated users only" ON support_tickets;
DROP POLICY IF EXISTS "Enable read access for own tickets" ON support_tickets;
DROP POLICY IF EXISTS "Enable update for own tickets" ON support_tickets;
DROP POLICY IF EXISTS "Users can create support tickets" ON support_tickets;
DROP POLICY IF EXISTS "Users can view own support tickets" ON support_tickets;

-- ADIM 2: Optimize edilmiş policy'leri oluştur
-- Not: (select auth.uid()) kullanarak performans optimizasyonu

-- SELECT: Kullanıcı kendi ticket'larını VEYA admin tüm ticket'ları görebilir
CREATE POLICY "support_tickets_select_optimized"
ON support_tickets
FOR SELECT
TO authenticated
USING (
    user_id = (SELECT auth.uid())
    OR 
    EXISTS (
        SELECT 1 FROM profiles
        WHERE profiles.id = (SELECT auth.uid())
        AND profiles.is_admin = true
    )
);

-- INSERT: Sadece kendi user_id'siyle oluşturabilir
CREATE POLICY "support_tickets_insert_optimized"
ON support_tickets
FOR INSERT
TO authenticated
WITH CHECK (user_id = (SELECT auth.uid()));

-- UPDATE: Kendi ticket'ını VEYA admin güncelleyebilir
CREATE POLICY "support_tickets_update_optimized"
ON support_tickets
FOR UPDATE
TO authenticated
USING (
    user_id = (SELECT auth.uid())
    OR 
    EXISTS (
        SELECT 1 FROM profiles
        WHERE profiles.id = (SELECT auth.uid())
        AND profiles.is_admin = true
    )
)
WITH CHECK (
    user_id = (SELECT auth.uid())
    OR 
    EXISTS (
        SELECT 1 FROM profiles
        WHERE profiles.id = (SELECT auth.uid())
        AND profiles.is_admin = true
    )
);

-- DELETE: Kendi ticket'ını VEYA admin silebilir
CREATE POLICY "support_tickets_delete_optimized"
ON support_tickets
FOR DELETE
TO authenticated
USING (
    user_id = (SELECT auth.uid())
    OR 
    EXISTS (
        SELECT 1 FROM profiles
        WHERE profiles.id = (SELECT auth.uid())
        AND profiles.is_admin = true
    )
);

-- ADIM 3: RLS aktif olduğundan emin ol
ALTER TABLE support_tickets ENABLE ROW LEVEL SECURITY;

-- ADIM 4: Sonuçları kontrol et
SELECT 
    schemaname,
    tablename,
    policyname,
    cmd,
    roles
FROM pg_policies 
WHERE tablename = 'support_tickets'
ORDER BY cmd, policyname;

-- Başarı mesajı
SELECT '✅ Support tickets RLS policies optimized successfully!' as status;
SELECT '✅ Auth.uid() subquery optimization applied' as optimization_1;
SELECT '✅ Multiple permissive policies merged into single policies' as optimization_2;
