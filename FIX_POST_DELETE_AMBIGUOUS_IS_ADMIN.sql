-- ============================================
-- GÖNERİ SİLME HATASI DÜZELTME
-- Sorun: "column reference 'post_id' is ambiguous" 
-- Çözüm: Tablolar için alias kullan ve fonksiyon parametresine tam erişim sağla
-- ============================================

-- Önce eski fonksiyonları sil
DROP FUNCTION IF EXISTS admin_delete_post(UUID) CASCADE;
DROP FUNCTION IF EXISTS admin_delete_story(UUID) CASCADE;
DROP FUNCTION IF EXISTS admin_pin_post(UUID, BOOLEAN) CASCADE;
DROP FUNCTION IF EXISTS admin_pin_story(UUID, BOOLEAN) CASCADE;
DROP FUNCTION IF EXISTS admin_pin_product(UUID, BOOLEAN) CASCADE;
DROP FUNCTION IF EXISTS admin_pin_shop(UUID, BOOLEAN) CASCADE;

-- 1. admin_delete_post fonksiyonunu oluştur
CREATE OR REPLACE FUNCTION admin_delete_post(post_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_current_user_id UUID;
    v_is_admin BOOLEAN;
    v_deleted_post RECORD;
BEGIN
    v_current_user_id := auth.uid();
    
    SELECT EXISTS (
        SELECT 1 FROM profiles AS pr
        WHERE pr.id = v_current_user_id
        AND (pr.role = 'admin' OR pr.is_admin = true)
    ) INTO v_is_admin;
    
    IF NOT v_is_admin THEN
        RAISE EXCEPTION 'Yetkisiz erişim: Sadece adminler gönderi silebilir';
    END IF;
    
    DELETE FROM post_likes AS pl WHERE pl.post_id = admin_delete_post.post_id;
    DELETE FROM post_views AS pv WHERE pv.post_id = admin_delete_post.post_id;
    DELETE FROM comments AS c WHERE c.post_id = admin_delete_post.post_id;
    DELETE FROM saved_posts AS sp WHERE sp.post_id = admin_delete_post.post_id;
    
    DELETE FROM posts AS p WHERE p.id = admin_delete_post.post_id RETURNING * INTO v_deleted_post;
    
    RETURN jsonb_build_object(
        'success', true,
        'message', 'Gönderi başarıyla silindi',
        'post_id', admin_delete_post.post_id
    );
END;
$$;

-- 2. admin_delete_story fonksiyonunu oluştur
CREATE OR REPLACE FUNCTION admin_delete_story(story_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_current_user_id UUID;
    v_is_admin BOOLEAN;
    v_deleted_story RECORD;
BEGIN
    v_current_user_id := auth.uid();
    
    SELECT EXISTS (
        SELECT 1 FROM profiles AS pr
        WHERE pr.id = v_current_user_id
        AND (pr.role = 'admin' OR pr.is_admin = true)
    ) INTO v_is_admin;
    
    IF NOT v_is_admin THEN
        RAISE EXCEPTION 'Yetkisiz erişim: Sadece adminler hikaye silebilir';
    END IF;
    
    DELETE FROM story_views AS sv WHERE sv.story_id = admin_delete_story.story_id;
    DELETE FROM stories AS s WHERE s.id = admin_delete_story.story_id RETURNING * INTO v_deleted_story;
    
    RETURN jsonb_build_object(
        'success', true,
        'message', 'Hikaye başarıyla silindi',
        'story_id', admin_delete_story.story_id
    );
END;
$$;

-- 3. admin_pin_post fonksiyonunu oluştur
CREATE OR REPLACE FUNCTION admin_pin_post(post_id UUID, pinned BOOLEAN)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_current_user_id UUID;
    v_is_admin BOOLEAN;
BEGIN
    v_current_user_id := auth.uid();
    
    SELECT EXISTS (
        SELECT 1 FROM profiles AS pr
        WHERE pr.id = v_current_user_id
        AND (pr.role = 'admin' OR pr.is_admin = true)
    ) INTO v_is_admin;
    
    IF NOT v_is_admin THEN
        RAISE EXCEPTION 'Yetkisiz erişim: Sadece adminler gönderi sabitleyebilir';
    END IF;
    
    UPDATE posts AS p SET is_pinned = admin_pin_post.pinned WHERE p.id = admin_pin_post.post_id;
    
    RETURN jsonb_build_object(
        'success', true,
        'message', CASE WHEN admin_pin_post.pinned THEN 'Gönderi sabitlendi' ELSE 'Sabitleme kaldırıldı' END,
        'post_id', admin_pin_post.post_id,
        'is_pinned', admin_pin_post.pinned
    );
END;
$$;

-- 4. admin_pin_story fonksiyonunu oluştur
CREATE OR REPLACE FUNCTION admin_pin_story(story_id UUID, pinned BOOLEAN)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_current_user_id UUID;
    v_is_admin BOOLEAN;
BEGIN
    v_current_user_id := auth.uid();
    
    SELECT EXISTS (
        SELECT 1 FROM profiles AS pr
        WHERE pr.id = v_current_user_id
        AND (pr.role = 'admin' OR pr.is_admin = true)
    ) INTO v_is_admin;
    
    IF NOT v_is_admin THEN
        RAISE EXCEPTION 'Yetkisiz erişim: Sadece adminler hikaye sabitleyebilir';
    END IF;
    
    UPDATE stories AS s SET is_pinned = admin_pin_story.pinned WHERE s.id = admin_pin_story.story_id;
    
    RETURN jsonb_build_object(
        'success', true,
        'message', CASE WHEN admin_pin_story.pinned THEN 'Hikaye sabitlendi' ELSE 'Sabitleme kaldırıldı' END,
        'story_id', admin_pin_story.story_id,
        'is_pinned', admin_pin_story.pinned
    );
END;
$$;

-- 5. admin_pin_product fonksiyonunu oluştur
CREATE OR REPLACE FUNCTION admin_pin_product(product_id UUID, pinned BOOLEAN)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_current_user_id UUID;
    v_is_admin BOOLEAN;
BEGIN
    v_current_user_id := auth.uid();
    
    SELECT EXISTS (
        SELECT 1 FROM profiles AS pr
        WHERE pr.id = v_current_user_id
        AND (pr.role = 'admin' OR pr.is_admin = true)
    ) INTO v_is_admin;
    
    IF NOT v_is_admin THEN
        RAISE EXCEPTION 'Yetkisiz erişim: Sadece adminler ürün sabitleyebilir';
    END IF;
    
    UPDATE products AS prd SET is_pinned = admin_pin_product.pinned WHERE prd.id = admin_pin_product.product_id;
    
    RETURN jsonb_build_object(
        'success', true,
        'message', CASE WHEN admin_pin_product.pinned THEN 'Ürün sabitlendi' ELSE 'Sabitleme kaldırıldı' END,
        'product_id', admin_pin_product.product_id,
        'is_pinned', admin_pin_product.pinned
    );
END;
$$;

-- 6. admin_pin_shop fonksiyonunu oluştur
CREATE OR REPLACE FUNCTION admin_pin_shop(shop_id UUID, pinned BOOLEAN)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_current_user_id UUID;
    v_is_admin BOOLEAN;
BEGIN
    v_current_user_id := auth.uid();
    
    SELECT EXISTS (
        SELECT 1 FROM profiles AS pr
        WHERE pr.id = v_current_user_id
        AND (pr.role = 'admin' OR pr.is_admin = true)
    ) INTO v_is_admin;
    
    IF NOT v_is_admin THEN
        RAISE EXCEPTION 'Yetkisiz erişim: Sadece adminler dükkan sabitleyebilir';
    END IF;
    
    UPDATE shops AS sh SET is_pinned = admin_pin_shop.pinned WHERE sh.id = admin_pin_shop.shop_id;
    
    RETURN jsonb_build_object(
        'success', true,
        'message', CASE WHEN admin_pin_shop.pinned THEN 'Dükkan sabitlendi' ELSE 'Sabitleme kaldırıldı' END,
        'shop_id', admin_pin_shop.shop_id,
        'is_pinned', admin_pin_shop.pinned
    );
END;
$$;

-- Execute izinleri
GRANT EXECUTE ON FUNCTION admin_delete_post(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION admin_delete_story(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION admin_pin_post(UUID, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION admin_pin_story(UUID, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION admin_pin_product(UUID, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION admin_pin_shop(UUID, BOOLEAN) TO authenticated;

-- Başarı mesajı
DO $$
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Gonderi silme hatasi duzeltildi!';
    RAISE NOTICE '========================================';
END $$;
