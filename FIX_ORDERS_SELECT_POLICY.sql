-- ============================================================================
-- ORDERS SELECT POLICY DÜZELT
-- ============================================================================

-- Mevcut orders_select_policy'yi sil
DROP POLICY IF EXISTS "orders_select_policy" ON orders;

-- Yeni policy oluştur - HERKES görebilsin (sadece test için)
CREATE POLICY "orders_select_policy" ON orders
FOR SELECT TO authenticated
USING (true);

-- Doğrulama
SELECT policyname, cmd, qual FROM pg_policies 
WHERE tablename = 'orders' AND schemaname = 'public';

-- Şimdi siparişler görünüyor mu test et
SELECT COUNT(*) as order_count FROM orders;