-- ============================================
-- SATICILARIN KURYE ATAMASI YAPABILMESI ICIN RLS POLITIKASI
-- Bu politika satıcilarin kendi dükkanlarinin siparislerine kurye atayabilmesini saglar
-- ============================================

-- 1. Mevcut INSERT politikalarini kontrol et
SELECT policyname, cmd, permissive, roles, qual, with_check
FROM pg_policies
WHERE tablename = 'courier_assignments'
  AND schemaname = 'public'
  AND cmd = 'INSERT'
ORDER BY policyname;

-- 2. Satıcılar kendi siparişlerine kurye atayabilir
CREATE POLICY "Sellers can assign couriers to own orders"
  ON courier_assignments
  FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM orders o
      JOIN shops s ON o.shop_id = s.id
      WHERE o.id = courier_assignments.order_id
      AND s.owner_id = auth.uid()
    )
  );

-- 3. Satıcılar sipariş durumunu güncelleyebilmeli (on_the_way yapabilmeli)
-- Mevcut orders_update_policy zaten satıcılara izin veriyor:
-- (shop_id IN (SELECT shops.id FROM shops WHERE shops.owner_id = auth.uid()))
-- Bu nedenle ekstra politika gerekmez

-- 4. Doğrulama: Tüm courier_assignments politikalarını listele
SELECT policyname, cmd, permissive, roles, qual, with_check
FROM pg_policies
WHERE tablename = 'courier_assignments'
  AND schemaname = 'public'
ORDER BY policyname, cmd;