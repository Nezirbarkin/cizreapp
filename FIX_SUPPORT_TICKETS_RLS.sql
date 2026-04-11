-- ================================================
-- Support Tickets RLS Policy Fix
-- ================================================
-- Kullanıcıların destek talebi oluşturabilmesi için

-- 1. Mevcut policy'leri kontrol et
SELECT 
    schemaname,
    tablename,
    policyname,
    permissive,
    roles,
    cmd,
    qual,
    with_check
FROM pg_policies 
WHERE tablename = 'support_tickets';

-- 2. Kullanıcıların kendi ticket'larını görebilmesi için SELECT policy
DROP POLICY IF EXISTS "users_can_view_own_support_tickets" ON support_tickets;

CREATE POLICY "users_can_view_own_support_tickets"
ON support_tickets
FOR SELECT
USING (auth.uid() = user_id);

-- 3. Kullanıcıların kendi ticket'larını görebilmesi için UPDATE policy
DROP POLICY IF EXISTS "users_can_update_own_support_tickets" ON support_tickets;

CREATE POLICY "users_can_update_own_support_tickets"
ON support_tickets
FOR UPDATE
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

-- 4. Kullanıcıların kendi ticket'larını görebilmesi için INSERT policy (EN ÖNEMLİ - BU EKSİK)
DROP POLICY IF EXISTS "users_can_insert_support_tickets" ON support_tickets;

CREATE POLICY "users_can_insert_support_tickets"
ON support_tickets
FOR INSERT
WITH CHECK (auth.uid() = user_id);

-- 5. Kullanıcıların kendi ticket'larını görebilmesi için DELETE policy
DROP POLICY IF EXISTS "users_can_delete_own_support_tickets" ON support_tickets;

CREATE POLICY "users_can_delete_own_support_tickets"
ON support_tickets
FOR DELETE
USING (auth.uid() = user_id);

-- 6. Adminlerin tüm ticket'ları görebilmesi için policy
DROP POLICY IF EXISTS "admin_can_view_all_support_tickets" ON support_tickets;

CREATE POLICY "admin_can_view_all_support_tickets"
ON support_tickets
FOR ALL
USING (
    EXISTS (
        SELECT 1 FROM profiles
        WHERE profiles.id = auth.uid()
        AND profiles.is_admin = true
    )
);

-- 7. RLS'in aktif olduğunu kontrol et
ALTER TABLE support_tickets ENABLE ROW LEVEL SECURITY;

-- 8. Test - Geçerli kullanıcı için sorgu çalıştır
SELECT 
    id,
    subject,
    status,
    user_id,
    created_at
FROM support_tickets
WHERE user_id = auth.uid();

-- Sonuç
SELECT 'Support tickets RLS policies configured successfully' as status;
