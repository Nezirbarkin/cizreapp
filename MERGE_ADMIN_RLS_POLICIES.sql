-- ============================================
-- Admin RLS Politikalarını Mevcut Politikalarla Birleştir
-- Multiple Permissive Policies uyarısını çözmek için
-- ============================================

-- POSTS tablosu - UPDATE politikalarını birleştir
DROP POLICY IF EXISTS "posts_update_own" ON posts;
CREATE POLICY "posts_update_own"
ON posts
FOR UPDATE
TO authenticated
USING (
    auth.uid() = user_id OR
    EXISTS (
        SELECT 1 FROM profiles 
        WHERE profiles.id = (select auth.uid()) 
        AND (profiles.role = 'admin' OR profiles.is_admin = true)
    )
)
WITH CHECK (
    auth.uid() = user_id OR
    EXISTS (
        SELECT 1 FROM profiles 
        WHERE profiles.id = (select auth.uid()) 
        AND (profiles.role = 'admin' OR profiles.is_admin = true)
    )
);

-- Gereksiz "Admins can pin posts" politikasını kaldır
DROP POLICY IF EXISTS "Admins can pin posts" ON posts;

-- PRODUCTS tablosu - UPDATE politikalarını birleştir
-- Not: Products tablosunda shop_id var, owner kontrolü shop üzerinden yapılacak
DROP POLICY IF EXISTS "products_update_policy" ON products;
CREATE POLICY "products_update_policy"
ON products
FOR UPDATE
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM shops 
        WHERE shops.id = products.shop_id 
        AND shops.owner_id = auth.uid()
    ) OR
    EXISTS (
        SELECT 1 FROM profiles 
        WHERE profiles.id = (select auth.uid()) 
        AND (profiles.role = 'admin' OR profiles.is_admin = true)
    )
)
WITH CHECK (
    EXISTS (
        SELECT 1 FROM shops 
        WHERE shops.id = products.shop_id 
        AND shops.owner_id = auth.uid()
    ) OR
    EXISTS (
        SELECT 1 FROM profiles 
        WHERE profiles.id = (select auth.uid()) 
        AND (profiles.role = 'admin' OR profiles.is_admin = true)
    )
);

DROP POLICY IF EXISTS "Admins can pin products" ON products;

-- SHOPS tablosu - UPDATE politikalarını birleştir
DROP POLICY IF EXISTS "shops_update_policy" ON shops;
CREATE POLICY "shops_update_policy"
ON shops
FOR UPDATE
TO authenticated
USING (
    owner_id = auth.uid() OR
    EXISTS (
        SELECT 1 FROM profiles 
        WHERE profiles.id = (select auth.uid()) 
        AND (profiles.role = 'admin' OR profiles.is_admin = true)
    )
)
WITH CHECK (
    owner_id = auth.uid() OR
    EXISTS (
        SELECT 1 FROM profiles 
        WHERE profiles.id = (select auth.uid()) 
        AND (profiles.role = 'admin' OR profiles.is_admin = true)
    )
);

DROP POLICY IF EXISTS "Admins can pin shops" ON shops;

-- STORIES tablosu - DELETE politikalarını birleştir
DROP POLICY IF EXISTS "stories_delete_policy" ON stories;
CREATE POLICY "stories_delete_policy"
ON stories
FOR DELETE
TO authenticated
USING (
    user_id = auth.uid() OR
    EXISTS (
        SELECT 1 FROM profiles 
        WHERE profiles.id = (select auth.uid()) 
        AND (profiles.role = 'admin' OR profiles.is_admin = true)
    )
);

DROP POLICY IF EXISTS "Admins can delete all stories" ON stories;

-- STORIES tablosu - UPDATE politikalarını birleştir
DROP POLICY IF EXISTS "stories_update_policy" ON stories;
CREATE POLICY "stories_update_policy"
ON stories
FOR UPDATE
TO authenticated
USING (
    user_id = auth.uid() OR
    EXISTS (
        SELECT 1 FROM profiles 
        WHERE profiles.id = (select auth.uid()) 
        AND (profiles.role = 'admin' OR profiles.is_admin = true)
    )
)
WITH CHECK (
    user_id = auth.uid() OR
    EXISTS (
        SELECT 1 FROM profiles 
        WHERE profiles.id = (select auth.uid()) 
        AND (profiles.role = 'admin' OR profiles.is_admin = true)
    )
);

DROP POLICY IF EXISTS "Admins can pin stories" ON stories;
