-- ORDERS INFINITE RECURSION SORUNU ÇÖZÜMÜ
-- Bu SQL dosyasını Supabase SQL Editor'da çalıştırın

-- ADIM 1: Mevcut hatalı policy'leri sil
DROP POLICY IF EXISTS "Users can view own orders" ON orders;
DROP POLICY IF EXISTS "Users can insert own orders" ON orders;
DROP POLICY IF EXISTS "Users can update own orders" ON orders;
DROP POLICY IF EXISTS "Users can delete own orders" ON orders;
DROP POLICY IF EXISTS "Shops can view their orders" ON orders;
DROP POLICY IF EXISTS "Shops can update their orders" ON orders;

-- ADIM 2: Doğru policy'leri oluştur (recursion olmadan)

-- Kullanıcılar sadece kendi siparişlerini görebilir
CREATE POLICY "Users can view own orders" 
ON orders FOR SELECT 
USING (auth.uid() = user_id);

-- Kullanıcılar sadece kendi siparişlerini ekleyebilir
CREATE POLICY "Users can insert own orders" 
ON orders FOR INSERT 
WITH CHECK (auth.uid() = user_id);

-- Kullanıcılar sadece kendi siparişlerini güncelleyebilir
CREATE POLICY "Users can update own orders" 
ON orders FOR UPDATE 
USING (auth.uid() = user_id)
WITH CHECK (auth.uid() = user_id);

-- Kullanıcılar sadece kendi siparişlerini silebilir
CREATE POLICY "Users can delete own orders" 
ON orders FOR DELETE 
USING (auth.uid() = user_id);

-- NOT: Eğer dükkan sahipleri de siparişleri görmeli/güncelleyebilmeliyse:
-- Shops tablosunda shop_owner_id kolonunu kullanarak:

-- Dükkan sahipleri kendi dükkanlarının siparişlerini görebilir
CREATE POLICY "Shops can view their orders"
ON orders FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM shops
    WHERE shops.id = orders.shop_id
    AND shops.owner_id = auth.uid()
  )
);

-- Dükkan sahipleri kendi dükkanlarının siparişlerini güncelleyebilir
CREATE POLICY "Shops can update their orders"
ON orders FOR UPDATE
USING (
  EXISTS (
    SELECT 1 FROM shops
    WHERE shops.id = orders.shop_id
    AND shops.owner_id = auth.uid()
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1 FROM shops
    WHERE shops.id = orders.shop_id
    AND shops.owner_id = auth.uid()
  )
);
