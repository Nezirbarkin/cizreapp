-- ============================================
-- KURYE SİPARİŞ GÖRÜNÜRLÜĞÜ - RLS POLİTİKALARI
-- Kuryelerin siparişleri görebilmesi için gerekli politikalar
-- Supabase SQL Editor'de sırasıyla çalıştırın
-- ============================================

-- ============================================
-- ADIM 1: Mevcut RLS politikalarını kontrol et
-- ============================================

-- Orders tablosu politikaları
SELECT 
    policyname,
    cmd,
    permissive,
    roles,
    qual,
    with_check
FROM pg_policies
WHERE tablename = 'orders'
  AND schemaname = 'public'
ORDER BY cmd;

-- Shops tablosu politikaları
SELECT 
    policyname,
    cmd,
    permissive,
    roles,
    qual,
    with_check
FROM pg_policies
WHERE tablename = 'shops'
  AND schemaname = 'public'
ORDER BY cmd;

-- Courier_assignments tablosu politikaları
SELECT 
    policyname,
    cmd,
    permissive,
    roles,
    qual,
    with_check
FROM pg_policies
WHERE tablename = 'courier_assignments'
  AND schemaname = 'public'
ORDER BY cmd;

-- Notifications tablosu politikaları
SELECT 
    policyname,
    cmd,
    permissive,
    roles,
    qual,
    with_check
FROM pg_policies
WHERE tablename = 'notifications'
  AND schemaname = 'public'
ORDER BY cmd;

-- ============================================
-- ADIM 2: Kurye rolündeki kullanıcıların siparişleri görebilmesi
-- ============================================

-- Kuryeler, kuryesi olmayan satıcıların siparişlerini görebilir
-- NOT: Eğer bu politika zaten varsa hata verecektir - o zaman IGNORE edin
CREATE POLICY "Couriers can view orders for delivery"
  ON orders
  FOR SELECT
  USING (
    -- Sipariş durumu confirmed, preparing, ready, on_the_way veya delivered olan
    -- ve dükkanın kendi kuryesi olmayan siparişler
    status IN ('confirmed', 'preparing', 'ready', 'on_the_way', 'delivered')
    AND EXISTS (
      SELECT 1 FROM shops s
      WHERE s.id = orders.shop_id
      AND s.has_own_courier IS DISTINCT FROM true
    )
  );

-- ============================================
-- ADIM 3: Kuryelerin shops tablosunu görebilmesi
-- ============================================

-- Kuryeler shops tablosunu görebilir (kuryesi olmayanları filtrelemek için)
CREATE POLICY "Couriers can view shops for delivery"
  ON shops
  FOR SELECT
  USING (true);

-- ============================================
-- ADIM 4: Kuryelerin tüm atamaları görebilmesi
-- ============================================

-- Kuryeler tüm courier_assignments'ı görebilir
-- (atanmış siparişleri filtrelemek için gerekli)
CREATE POLICY "Couriers can view all courier assignments"
  ON courier_assignments
  FOR SELECT
  USING (true);

-- ============================================
-- ADIM 5: Kuryelerin bildirim alabilmesi
-- ============================================

-- Kuryeler kendi bildirimlerini görebilir
CREATE POLICY "Couriers can view own notifications"
  ON notifications
  FOR SELECT
  USING (auth.uid() = user_id);

-- ============================================
-- ADIM 6: Kuryelerin sipariş alabilmesi (courier_assignments insert)
-- ============================================

-- Bu politika zaten tanımlı olabilir, eğer varsa IGNORE edin
-- CREATE POLICY "Couriers can create assignments"
--   ON courier_assignments
--   FOR INSERT
--   WITH CHECK (courier_id = auth.uid());

-- ============================================
-- ADIM 7: Sipariş durumu güncellenirken kuryenin siparişe erişebilmesi
-- ============================================

-- Kuryeler atandıkları siparişlerin durumunu görebilir
CREATE POLICY "Couriers can view assigned orders"
  ON orders
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM courier_assignments ca
      WHERE ca.order_id = orders.id
      AND ca.courier_id = auth.uid()
    )
  );

-- ============================================
-- DOĞRULAMA: Politikaların doğru eklendiğini kontrol et
-- ============================================

SELECT 
    schemaname,
    tablename,
    policyname,
    permissive,
    roles,
    cmd
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('orders', 'shops', 'courier_assignments', 'notifications')
ORDER BY tablename, cmd;