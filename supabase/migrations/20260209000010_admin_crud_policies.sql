-- =============================================
-- Admin CRUD Policies - UPDATE ve DELETE İşlemleri
-- =============================================
-- Admin kullanıcısının tüm kayıtları düzenleyip silebilmesi için RLS politikaları
-- NOT: auth.uid() yerine (SELECT auth.uid()) kullanılarak performans optimizasyonu yapıldı

-- =============================================
-- 1. PROFILES - Kullanıcı Rol Değiştirme ve Silme
-- =============================================

-- Kullanıcı rol güncelleme (sadece admin)
DROP POLICY IF EXISTS "profiles_admin_update" ON profiles;
CREATE POLICY "profiles_admin_update" ON profiles
    FOR UPDATE
    TO authenticated
    USING (
        (SELECT role FROM profiles WHERE id = (SELECT auth.uid())) = 'admin'
    )
    WITH CHECK (
        (SELECT role FROM profiles WHERE id = (SELECT auth.uid())) = 'admin'
    );

-- Kullanıcı silme (sadece admin)
DROP POLICY IF EXISTS "profiles_admin_delete" ON profiles;
CREATE POLICY "profiles_admin_delete" ON profiles
    FOR DELETE
    TO authenticated
    USING (
        (SELECT role FROM profiles WHERE id = (SELECT auth.uid())) = 'admin'
    );

-- =============================================
-- 2. POSTS - Gönderi Silme
-- =============================================

-- Gönderi silme (kendi gönderileri veya admin)
DROP POLICY IF EXISTS "posts_delete_policy" ON posts;
CREATE POLICY "posts_delete_policy" ON posts
    FOR DELETE
    TO authenticated
    USING (
        user_id = (SELECT auth.uid()) OR 
        (SELECT role FROM profiles WHERE id = (SELECT auth.uid())) = 'admin'
    );

-- =============================================
-- 3. STORIES - Hikaye Silme
-- =============================================

-- Hikaye silme (kendi hikayeleri veya admin)
DROP POLICY IF EXISTS "stories_delete_policy" ON stories;
CREATE POLICY "stories_delete_policy" ON stories
    FOR DELETE
    TO authenticated
    USING (
        user_id = (SELECT auth.uid()) OR 
        (SELECT role FROM profiles WHERE id = (SELECT auth.uid())) = 'admin'
    );

-- =============================================
-- 4. PRODUCTS - Ürün Düzenleme ve Silme
-- =============================================

-- Ürün güncelleme (mağaza sahibi veya admin)
DROP POLICY IF EXISTS "products_update_policy" ON products;
CREATE POLICY "products_update_policy" ON products
    FOR UPDATE
    TO authenticated
    USING (
        shop_id IN (SELECT id FROM shops WHERE owner_id = (SELECT auth.uid())) OR
        (SELECT role FROM profiles WHERE id = (SELECT auth.uid())) = 'admin'
    )
    WITH CHECK (
        shop_id IN (SELECT id FROM shops WHERE owner_id = (SELECT auth.uid())) OR
        (SELECT role FROM profiles WHERE id = (SELECT auth.uid())) = 'admin'
    );

-- Ürün silme (mağaza sahibi veya admin)
DROP POLICY IF EXISTS "products_delete_policy" ON products;
CREATE POLICY "products_delete_policy" ON products
    FOR DELETE
    TO authenticated
    USING (
        shop_id IN (SELECT id FROM shops WHERE owner_id = (SELECT auth.uid())) OR
        (SELECT role FROM profiles WHERE id = (SELECT auth.uid())) = 'admin'
    );

-- =============================================
-- 5. SHOPS - Mağaza Düzenleme ve Silme (Bonus)
-- =============================================

-- Mağaza güncelleme (mağaza sahibi veya admin)
DROP POLICY IF EXISTS "shops_update_policy" ON shops;
CREATE POLICY "shops_update_policy" ON shops
    FOR UPDATE
    TO authenticated
    USING (
        owner_id = (SELECT auth.uid()) OR
        (SELECT role FROM profiles WHERE id = (SELECT auth.uid())) = 'admin'
    )
    WITH CHECK (
        owner_id = (SELECT auth.uid()) OR
        (SELECT role FROM profiles WHERE id = (SELECT auth.uid())) = 'admin'
    );

-- Mağaza silme (mağaza sahibi veya admin)
DROP POLICY IF EXISTS "shops_delete_policy" ON shops;
CREATE POLICY "shops_delete_policy" ON shops
    FOR DELETE
    TO authenticated
    USING (
        owner_id = (SELECT auth.uid()) OR
        (SELECT role FROM profiles WHERE id = (SELECT auth.uid())) = 'admin'
    );

-- =============================================
-- 6. USER_REPORTS - Kullanıcı Şikayeti Yönetimi
-- =============================================

-- Şikayet güncelleme (sadece admin - durum değiştirme için)
DROP POLICY IF EXISTS "user_reports_update_policy" ON user_reports;
CREATE POLICY "user_reports_update_policy" ON user_reports
    FOR UPDATE
    TO authenticated
    USING (
        (SELECT role FROM profiles WHERE id = (SELECT auth.uid())) = 'admin'
    )
    WITH CHECK (
        (SELECT role FROM profiles WHERE id = (SELECT auth.uid())) = 'admin'
    );

-- Şikayet silme (sadece admin)
DROP POLICY IF EXISTS "user_reports_delete_policy" ON user_reports;
CREATE POLICY "user_reports_delete_policy" ON user_reports
    FOR DELETE
    TO authenticated
    USING (
        (SELECT role FROM profiles WHERE id = (SELECT auth.uid())) = 'admin'
    );

-- =============================================
-- 7. SUPPORT_TICKETS - Destek Talepleri Yönetimi
-- =============================================

-- Destek talebi güncelleme (talep sahibi veya admin)
DROP POLICY IF EXISTS "support_tickets_update_policy" ON support_tickets;
CREATE POLICY "support_tickets_update_policy" ON support_tickets
    FOR UPDATE
    TO authenticated
    USING (
        user_id = (SELECT auth.uid()) OR
        (SELECT role FROM profiles WHERE id = (SELECT auth.uid())) = 'admin'
    )
    WITH CHECK (
        user_id = (SELECT auth.uid()) OR
        (SELECT role FROM profiles WHERE id = (SELECT auth.uid())) = 'admin'
    );

-- Destek talebi silme (sadece admin)
DROP POLICY IF EXISTS "support_tickets_delete_policy" ON support_tickets;
CREATE POLICY "support_tickets_delete_policy" ON support_tickets
    FOR DELETE
    TO authenticated
    USING (
        (SELECT role FROM profiles WHERE id = (SELECT auth.uid())) = 'admin'
    );

-- =============================================
-- Doğrulama ve Log
-- =============================================

DO $$
DECLARE
    v_admin_count INT;
    v_user_count INT;
    v_post_count INT;
    v_story_count INT;
    v_product_count INT;
    v_shop_count INT;
BEGIN
    SELECT COUNT(*) INTO v_admin_count FROM profiles WHERE role = 'admin';
    SELECT COUNT(*) INTO v_user_count FROM profiles;
    SELECT COUNT(*) INTO v_post_count FROM posts;
    SELECT COUNT(*) INTO v_story_count FROM stories;
    SELECT COUNT(*) INTO v_product_count FROM products;
    SELECT COUNT(*) INTO v_shop_count FROM shops;
    
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Admin CRUD Policies Created!';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Admin kullanıcıları: %', v_admin_count;
    RAISE NOTICE 'Toplam kullanıcı: %', v_user_count;
    RAISE NOTICE 'Toplam gönderi: %', v_post_count;
    RAISE NOTICE 'Toplam hikaye: %', v_story_count;
    RAISE NOTICE 'Toplam ürün: %', v_product_count;
    RAISE NOTICE 'Toplam mağaza: %', v_shop_count;
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Admin şimdi şunları yapabilir:';
    RAISE NOTICE '  ✓ Kullanıcı rollerini değiştirebilir';
    RAISE NOTICE '  ✓ Kullanıcıları silebilir';
    RAISE NOTICE '  ✓ Gönderileri silebilir';
    RAISE NOTICE '  ✓ Hikayeleri silebilir';
    RAISE NOTICE '  ✓ Ürünleri düzenleyebilir/silebilir';
    RAISE NOTICE '  ✓ Mağazaları düzenleyebilir/silebilir';
    RAISE NOTICE '  ✓ Şikayetleri yönetebilir';
    RAISE NOTICE '  ✓ Destek taleplerini yönetebilir';
    RAISE NOTICE '========================================';
END $$;
