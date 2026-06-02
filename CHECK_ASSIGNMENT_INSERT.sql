-- courier_assignments INSERT politikasını kontrol et
SELECT policyname, cmd, permissive, roles, qual, with_check
FROM pg_policies
WHERE tablename = 'courier_assignments'
  AND schemaname = 'public'
ORDER BY policyname, cmd;

-- Ayrıca: Satıcı (seller) siparişi on_the_way yapabiliyor mu?
-- Satıcının auth.uid'si ile orders update yapabiliyor mu?
-- Bu sorgu satıcının owner olduğu dükkanların siparişlerini kontrol eder
SELECT o.id, o.status, s.name as shop_name, s.owner_id
FROM orders o
JOIN shops s ON o.shop_id = s.id
WHERE s.owner_id = '87b92e63-4b80-4526-8c5e-ffe99a335dbc'
ORDER BY o.created_at DESC
LIMIT 5;

-- Kurye test4'ün courier_assignments'a INSERT yapabiliyor mu?
-- RLS policy: "Couriers can create assignments" WITH CHECK (courier_id = auth.uid())
-- Bu kuryenin kendi ID'si ile atama yapmasına izin verir
-- Ama otomatik atama satıcı tarafından yapılıyorsa, satıcının INSERT yetkisi yok!