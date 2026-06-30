-- ============================================================================
-- GELEN SİPARİŞLER SATICIYA GÖSTERİLMİYOR - DEBUG
-- ============================================================================
-- Bu SQL'i Supabase SQL Editor'de çalıştırın ve sonuçları paylaşın.
-- ============================================================================

-- 1. Aktif oturumdaki kullanıcı ID'sini göster
SELECT auth.uid() as current_user_id;

-- 2. Bu kullanıcıya ait mağaza var mı?
SELECT id, name, owner_id, has_own_courier, is_accepting_orders
FROM shops
WHERE owner_id = auth.uid();

-- 3. Bu kullanıcının görmesi gereken siparişleri göster (RLS'siz, admin yetkisiyle)
SELECT o.id, o.status, o.shop_id, o.created_at, o.user_id,
       s.name as shop_name, s.owner_id as shop_owner_id
FROM orders o
JOIN shops s ON s.id = o.shop_id
WHERE s.owner_id = auth.uid()
ORDER BY o.created_at DESC
LIMIT 20;

-- 4. orders tablosundaki TÜM politikaları listele
SELECT policyname, cmd, permissive, roles, qual
FROM pg_policies
WHERE tablename = 'orders'
  AND schemaname = 'public'
ORDER BY policyname;

-- 5. orders_select_policy'nin tam tanımını göster
SELECT
    policyname,
    cmd,
    qual::text as using_expression,
    with_check::text as with_check_expression
FROM pg_policies
WHERE tablename = 'orders'
  AND schemaname = 'public'
  AND policyname = 'orders_select_policy';

-- 6. orders tablosunda RLS aktif mi?
SELECT relname, relrowsecurity, relforcerowsecurity
FROM pg_class
WHERE relname = 'orders'
  AND relnamespace = 'public'::regnamespace;

-- 7. shops tablosundaki politikalar (satıcının kendi mağazasını görmesi için)
SELECT policyname, cmd, permissive, roles, qual
FROM pg_policies
WHERE tablename = 'shops'
  AND schemaname = 'public'
ORDER BY policyname;

-- 8. Realtime publication'da orders tablosu var mı?
SELECT * FROM pg_publication_tables
WHERE pubname = 'supabase_realtime'
  AND tablename = 'orders';

-- ============================================================================
-- EĞER SİPARİŞLER GÖRÜNMÜYORSA, AŞAĞIDAKİ FIX'İ ÇALIŞTIRIN
-- ============================================================================
-- Bazı RLS policy'leri satıcının orders tablosundaki siparişleri görmesini
-- engelleyebilir. Aşağıdaki komutlar güvenli SELECT policy'sini yeniden oluşturur.

-- Önce mevcut policy'yi sil
DROP POLICY IF EXISTS "orders_select_policy" ON orders;

-- Satıcının kendi mağazasının siparişlerini görebildiği policy
CREATE POLICY "orders_select_policy" ON orders
FOR SELECT TO authenticated
USING (
    -- Müşteri kendi siparişlerini görebilir
    user_id = auth.uid()
    -- Satıcı kendi mağazasının siparişlerini görebilir
    OR EXISTS (
        SELECT 1 FROM shops
        WHERE shops.id = orders.shop_id
        AND shops.owner_id = auth.uid()
    )
    -- Admin her şeyi görebilir
    OR EXISTS (
        SELECT 1 FROM profiles
        WHERE profiles.id = auth.uid()
        AND profiles.role = 'admin'
    )
);

SELECT 'orders_select_policy yeniden oluşturuldu' as result;