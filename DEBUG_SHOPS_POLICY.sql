-- Shops tablosunun policy'lerini kontrol et
SELECT policyname, cmd, permissive FROM pg_policies 
WHERE tablename = 'shops' AND schemaname = 'public';

-- Shops tablosunda RLS etkin mi?
SELECT relname, relrowsecurity FROM pg_class WHERE relname = 'shops';

-- Alternatif: Kurye rolüne özel basit bir policy ekle
DROP POLICY IF EXISTS "couriers_can_view_shops" ON shops;

CREATE POLICY "couriers_can_view_shops" ON shops
FOR SELECT TO authenticated
USING (
    -- Kuryeler tüm dükkanları görebilsin (has_own_courier kontrolü için)
    -- Sadece SELECT izni, başka bir şey yapamazlar
    true
);

-- Doğrulama
SELECT policyname, cmd FROM pg_policies 
WHERE tablename = 'shops' AND schemaname = 'public';