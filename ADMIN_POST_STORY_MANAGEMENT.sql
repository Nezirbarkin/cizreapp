-- ============================================
-- Admin Panel - Gönderi ve Hikaye Yönetimi
-- Silme ve Sabitleme İşlemleri için RPC Fonksiyonları
-- Performans ve Güvenlik Optimize Edildi
-- ============================================

-- 1. Admin için Gönderi Silme Fonksiyonu
CREATE OR REPLACE FUNCTION admin_delete_post(post_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    current_user_id UUID;
    is_admin BOOLEAN;
    deleted_post RECORD;
BEGIN
    current_user_id := auth.uid();
    
    SELECT EXISTS (
        SELECT 1 FROM profiles 
        WHERE id = current_user_id 
        AND (role = 'admin' OR is_admin = true)
    ) INTO is_admin;
    
    IF NOT is_admin THEN
        RAISE EXCEPTION 'Yetkisiz erişim: Sadece adminler gönderi silebilir';
    END IF;
    
    DELETE FROM post_likes WHERE post_id = admin_delete_post.post_id;
    DELETE FROM post_views WHERE post_id = admin_delete_post.post_id;
    DELETE FROM comments WHERE post_id = admin_delete_post.post_id;
    DELETE FROM saved_posts WHERE post_id = admin_delete_post.post_id;
    
    DELETE FROM posts WHERE id = admin_delete_post.post_id RETURNING * INTO deleted_post;
    
    RETURN jsonb_build_object(
        'success', true,
        'message', 'Gönderi başarıyla silindi',
        'post_id', admin_delete_post.post_id
    );
END;
$$;

-- 2. Admin için Hikaye Silme Fonksiyonu
CREATE OR REPLACE FUNCTION admin_delete_story(story_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    current_user_id UUID;
    is_admin BOOLEAN;
    deleted_story RECORD;
BEGIN
    current_user_id := auth.uid();
    
    SELECT EXISTS (
        SELECT 1 FROM profiles 
        WHERE id = current_user_id 
        AND (role = 'admin' OR is_admin = true)
    ) INTO is_admin;
    
    IF NOT is_admin THEN
        RAISE EXCEPTION 'Yetkisiz erişim: Sadece adminler hikaye silebilir';
    END IF;
    
    DELETE FROM story_views WHERE story_id = admin_delete_story.story_id;
    DELETE FROM stories WHERE id = admin_delete_story.story_id RETURNING * INTO deleted_story;
    
    RETURN jsonb_build_object(
        'success', true,
        'message', 'Hikaye başarıyla silindi',
        'story_id', admin_delete_story.story_id
    );
END;
$$;

-- 3. Admin için Gönderi Sabitleme Fonksiyonu
CREATE OR REPLACE FUNCTION admin_pin_post(post_id UUID, pinned BOOLEAN)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    current_user_id UUID;
    is_admin BOOLEAN;
BEGIN
    current_user_id := auth.uid();
    
    SELECT EXISTS (
        SELECT 1 FROM profiles 
        WHERE id = current_user_id 
        AND (role = 'admin' OR is_admin = true)
    ) INTO is_admin;
    
    IF NOT is_admin THEN
        RAISE EXCEPTION 'Yetkisiz erişim: Sadece adminler gönderi sabitleyebilir';
    END IF;
    
    UPDATE posts SET is_pinned = admin_pin_post.pinned WHERE id = admin_pin_post.post_id;
    
    RETURN jsonb_build_object(
        'success', true,
        'message', CASE WHEN admin_pin_post.pinned THEN 'Gönderi sabitlendi' ELSE 'Sabitleme kaldırıldı' END,
        'post_id', admin_pin_post.post_id,
        'is_pinned', admin_pin_post.pinned
    );
END;
$$;

-- 4. Admin için Hikaye Sabitleme Fonksiyonu
CREATE OR REPLACE FUNCTION admin_pin_story(story_id UUID, pinned BOOLEAN)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    current_user_id UUID;
    is_admin BOOLEAN;
BEGIN
    current_user_id := auth.uid();
    
    SELECT EXISTS (
        SELECT 1 FROM profiles 
        WHERE id = current_user_id 
        AND (role = 'admin' OR is_admin = true)
    ) INTO is_admin;
    
    IF NOT is_admin THEN
        RAISE EXCEPTION 'Yetkisiz erişim: Sadece adminler hikaye sabitleyebilir';
    END IF;
    
    UPDATE stories SET is_pinned = admin_pin_story.pinned WHERE id = admin_pin_story.story_id;
    
    RETURN jsonb_build_object(
        'success', true,
        'message', CASE WHEN admin_pin_story.pinned THEN 'Hikaye sabitlendi' ELSE 'Sabitleme kaldırıldı' END,
        'story_id', admin_pin_story.story_id,
        'is_pinned', admin_pin_story.pinned
    );
END;
$$;

-- 5. Admin için Ürün Sabitleme Fonksiyonu
CREATE OR REPLACE FUNCTION admin_pin_product(product_id UUID, pinned BOOLEAN)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    current_user_id UUID;
    is_admin BOOLEAN;
BEGIN
    current_user_id := auth.uid();
    
    SELECT EXISTS (
        SELECT 1 FROM profiles 
        WHERE id = current_user_id 
        AND (role = 'admin' OR is_admin = true)
    ) INTO is_admin;
    
    IF NOT is_admin THEN
        RAISE EXCEPTION 'Yetkisiz erişim: Sadece adminler ürün sabitleyebilir';
    END IF;
    
    UPDATE products SET is_pinned = admin_pin_product.pinned WHERE id = admin_pin_product.product_id;
    
    RETURN jsonb_build_object(
        'success', true,
        'message', CASE WHEN admin_pin_product.pinned THEN 'Ürün sabitlendi' ELSE 'Sabitleme kaldırıldı' END,
        'product_id', admin_pin_product.product_id,
        'is_pinned', admin_pin_product.pinned
    );
END;
$$;

-- 6. Admin için Dükkan Sabitleme Fonksiyonu
CREATE OR REPLACE FUNCTION admin_pin_shop(shop_id UUID, pinned BOOLEAN)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    current_user_id UUID;
    is_admin BOOLEAN;
BEGIN
    current_user_id := auth.uid();
    
    SELECT EXISTS (
        SELECT 1 FROM profiles 
        WHERE id = current_user_id 
        AND (role = 'admin' OR is_admin = true)
    ) INTO is_admin;
    
    IF NOT is_admin THEN
        RAISE EXCEPTION 'Yetkisiz erişim: Sadece adminler dükkan sabitleyebilir';
    END IF;
    
    UPDATE shops SET is_pinned = admin_pin_shop.pinned WHERE id = admin_pin_shop.shop_id;
    
    RETURN jsonb_build_object(
        'success', true,
        'message', CASE WHEN admin_pin_shop.pinned THEN 'Dükkan sabitlendi' ELSE 'Sabitleme kaldırıldı' END,
        'shop_id', admin_pin_shop.shop_id,
        'is_pinned', admin_pin_shop.pinned
    );
END;
$$;

-- ============================================
-- RLS Politikaları Güncellemeleri
-- (select auth.uid()) kullanılarak performans optimize edildi
-- ============================================

-- Posts tablosu için admin DELETE politikası
DROP POLICY IF EXISTS "Admins can delete all posts" ON posts;
CREATE POLICY "Admins can delete all posts"
ON posts
FOR DELETE
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM profiles 
        WHERE profiles.id = (select auth.uid()) 
        AND (profiles.role = 'admin' OR profiles.is_admin = true)
    )
);

-- Posts tablosu için admin UPDATE politikası (is_pinned için)
DROP POLICY IF EXISTS "Admins can pin posts" ON posts;
CREATE POLICY "Admins can pin posts"
ON posts
FOR UPDATE
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM profiles 
        WHERE profiles.id = (select auth.uid()) 
        AND (profiles.role = 'admin' OR profiles.is_admin = true)
    )
)
WITH CHECK (
    EXISTS (
        SELECT 1 FROM profiles 
        WHERE profiles.id = (select auth.uid()) 
        AND (profiles.role = 'admin' OR profiles.is_admin = true)
    )
);

-- Stories tablosu için admin DELETE politikası
DROP POLICY IF EXISTS "Admins can delete all stories" ON stories;
CREATE POLICY "Admins can delete all stories"
ON stories
FOR DELETE
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM profiles 
        WHERE profiles.id = (select auth.uid()) 
        AND (profiles.role = 'admin' OR profiles.is_admin = true)
    )
);

-- Stories tablosu için admin UPDATE politikası (is_pinned için)
DROP POLICY IF EXISTS "Admins can pin stories" ON stories;
CREATE POLICY "Admins can pin stories"
ON stories
FOR UPDATE
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM profiles 
        WHERE profiles.id = (select auth.uid()) 
        AND (profiles.role = 'admin' OR profiles.is_admin = true)
    )
)
WITH CHECK (
    EXISTS (
        SELECT 1 FROM profiles 
        WHERE profiles.id = (select auth.uid()) 
        AND (profiles.role = 'admin' OR profiles.is_admin = true)
    )
);

-- Products tablosu için admin UPDATE politikası (is_pinned için)
DROP POLICY IF EXISTS "Admins can pin products" ON products;
CREATE POLICY "Admins can pin products"
ON products
FOR UPDATE
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM profiles 
        WHERE profiles.id = (select auth.uid()) 
        AND (profiles.role = 'admin' OR profiles.is_admin = true)
    )
)
WITH CHECK (
    EXISTS (
        SELECT 1 FROM profiles 
        WHERE profiles.id = (select auth.uid()) 
        AND (profiles.role = 'admin' OR profiles.is_admin = true)
    )
);

-- Shops tablosu için admin UPDATE politikası (is_pinned için)
DROP POLICY IF EXISTS "Admins can pin shops" ON shops;
CREATE POLICY "Admins can pin shops"
ON shops
FOR UPDATE
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM profiles 
        WHERE profiles.id = (select auth.uid()) 
        AND (profiles.role = 'admin' OR profiles.is_admin = true)
    )
)
WITH CHECK (
    EXISTS (
        SELECT 1 FROM profiles 
        WHERE profiles.id = (select auth.uid()) 
        AND (profiles.role = 'admin' OR profiles.is_admin = true)
    )
);

-- ============================================
-- Execute izinleri
-- ============================================

GRANT EXECUTE ON FUNCTION admin_delete_post(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION admin_delete_story(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION admin_pin_post(UUID, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION admin_pin_story(UUID, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION admin_pin_product(UUID, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION admin_pin_shop(UUID, BOOLEAN) TO authenticated;
