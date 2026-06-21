-- ============================================================================
-- KURYE SİPARİŞLER SORUNU ÇÖZÜMÜ
-- ============================================================================

-- Sorun: Kurye shops tablosunu göremez çünkü RLS politikası izin vermez
-- Çözüm: Shops tablosuna kurye SELECT izni ekle

-- Mevcut shops SELECT policy'yi kontrol et
SELECT policyname, cmd FROM pg_policies 
WHERE tablename = 'shops' AND schemaname = 'public';

-- Shops tablosuna kurye SELECT izni ekle
-- Mevcut policy'yi güncelle (orders_select_policy gibi)
DROP POLICY IF EXISTS "shops_select_policy" ON shops;

CREATE POLICY "shops_select_policy" ON shops
FOR SELECT TO authenticated
USING (
    -- Dükkan sahibi kendi dükkanını görebilir
    owner_id = auth.uid()
    -- Admin tüm dükkanları görebilir (role kontrolü)
    OR EXISTS (
        SELECT 1 FROM profiles 
        WHERE profiles.id = auth.uid() 
        AND profiles.role = 'admin'
    )
);

-- Doğrulama
SELECT 'Shops policy updated - Couriers can view shops' as status;
SELECT policyname, cmd FROM pg_policies 
WHERE tablename = 'shops' AND schemaname = 'public';