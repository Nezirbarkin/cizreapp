-- ============================================================================
-- SUPABASE LINTER TÜM PERFORMANS UYARILARINI DÜZELT
-- ============================================================================
-- Tarih: 2026-03-07
-- Amaç: Supabase Linter WARN seviyesindeki TÜM performans uyarılarını düzelt
-- 
-- DÜZELTİLEN UYARILAR:
--   1. auth_rls_initplan  → auth.uid() yerine (select auth.uid()) kullanımı
--   2. multiple_permissive_policies → Aynı tablo+rol+komut için birden fazla
--      permissive policy'yi tek policy'ye indir
--
-- STRATEJİ:
--   - FOR ALL sadece TÜM operasyonlar aynı koşula sahipse kullanılır
--   - SELECT koşulu farklıysa, her operasyon türü için ayrı TEK policy
--   - Agresif DROP: Bilinen tüm eski policy isimlerini temizle
--   - (select auth.uid()) her yerde kullanılır
--
-- ÖNCESİNDE BACKUP ALINMASI ÖNERİLİR!
-- ============================================================================

BEGIN;

-- ============================================================================
-- BÖLÜM 1: NOTIFICATIONS
-- ============================================================================
-- Sorun: auth_rls_initplan + multiple permissive (DELETE, INSERT, UPDATE)
-- Çözüm: Her operasyon için TAM OLARAK TEK policy
--   - SELECT: user_id = auth.uid()
--   - INSERT: true (trigger/sistem bildirimleri için kasıtlı permissive)
--   - UPDATE: user_id = auth.uid()
--   - DELETE: user_id = auth.uid()

DO $$
BEGIN
    -- Agresif temizlik - tüm olası eski policy isimlerini DROP et
    DROP POLICY IF EXISTS "notifications_select_policy" ON public.notifications;
    DROP POLICY IF EXISTS "notifications_insert_policy" ON public.notifications;
    DROP POLICY IF EXISTS "notifications_update_policy" ON public.notifications;
    DROP POLICY IF EXISTS "notifications_delete_policy" ON public.notifications;
    DROP POLICY IF EXISTS "notifications_select_own" ON public.notifications;
    DROP POLICY IF EXISTS "notifications_insert_own" ON public.notifications;
    DROP POLICY IF EXISTS "notifications_update_own" ON public.notifications;
    DROP POLICY IF EXISTS "notifications_delete_own" ON public.notifications;
    DROP POLICY IF EXISTS "notifications_manage_own" ON public.notifications;
    DROP POLICY IF EXISTS "Users can view own notifications" ON public.notifications;
    DROP POLICY IF EXISTS "Users can update own notifications" ON public.notifications;
    DROP POLICY IF EXISTS "Anyone can insert notifications" ON public.notifications;
    DROP POLICY IF EXISTS "notifications_insert" ON public.notifications;
    DROP POLICY IF EXISTS "Enable insert for authenticated users only" ON public.notifications;
    DROP POLICY IF EXISTS "Enable select for authenticated users only" ON public.notifications;
    DROP POLICY IF EXISTS "Enable update for authenticated users only" ON public.notifications;
    DROP POLICY IF EXISTS "Enable delete for authenticated users only" ON public.notifications;

    -- SELECT: Kullanıcı kendi bildirimlerini görebilir
    CREATE POLICY "notifications_select"
        ON public.notifications
        FOR SELECT
        TO authenticated
        USING (user_id = (select auth.uid()));

    -- INSERT: Herkes bildirim ekleyebilir (trigger'lar ve sistem bildirimleri için)
    CREATE POLICY "notifications_insert"
        ON public.notifications
        FOR INSERT
        TO authenticated
        WITH CHECK (true);

    COMMENT ON POLICY "notifications_insert" ON public.notifications IS 
        'Intentionally permissive: System notifications created by SECURITY DEFINER triggers need cross-user insert.';

    -- UPDATE: Kullanıcı kendi bildirimlerini güncelleyebilir (okundu işareti vb.)
    CREATE POLICY "notifications_update"
        ON public.notifications
        FOR UPDATE
        TO authenticated
        USING (user_id = (select auth.uid()))
        WITH CHECK (user_id = (select auth.uid()));

    -- DELETE: Kullanıcı kendi bildirimlerini silebilir
    CREATE POLICY "notifications_delete"
        ON public.notifications
        FOR DELETE
        TO authenticated
        USING (user_id = (select auth.uid()));
END $$;

-- ============================================================================
-- BÖLÜM 2: PRODUCTS
-- ============================================================================
-- Sorun: anon SELECT + authenticated SELECT = 2 SELECT policy
-- Çözüm: Tek SELECT policy (TO public = anon + authenticated)

DO $$
BEGIN
    DROP POLICY IF EXISTS "products_select_active_or_owner" ON public.products;
    DROP POLICY IF EXISTS "products_select_active_anon" ON public.products;
    DROP POLICY IF EXISTS "products_select_all" ON public.products;
    DROP POLICY IF EXISTS "Products are viewable by everyone" ON public.products;
    DROP POLICY IF EXISTS "Users can view own products" ON public.products;
    DROP POLICY IF EXISTS "Enable select for all users" ON public.products;

    -- Birleştirilmiş SELECT Policy: public (anon + authenticated)
    CREATE POLICY "products_select"
        ON public.products
        FOR SELECT
        TO public
        USING (
            is_active = true
            OR
            EXISTS (
                SELECT 1 FROM public.shops s
                WHERE s.id = products.shop_id
                AND s.owner_id = (select auth.uid())
            )
            OR
            public.auth_is_admin()
        );

    COMMENT ON POLICY "products_select" ON public.products IS 
        'Merged: Active products visible to all (anon+auth), inactive to shop owner and admin.';
END $$;

-- ============================================================================
-- BÖLÜM 3: SHOPS
-- ============================================================================
-- Sorun: anon SELECT + authenticated SELECT/DELETE/UPDATE = çoklu policy
-- Çözüm: Tek SELECT (TO public), tek UPDATE, tek DELETE

DO $$
BEGIN
    DROP POLICY IF EXISTS "shops_select_active_or_owner" ON public.shops;
    DROP POLICY IF EXISTS "shops_select_active_anon" ON public.shops;
    DROP POLICY IF EXISTS "shops_select_all" ON public.shops;
    DROP POLICY IF EXISTS "shops_manage_owner_or_admin" ON public.shops;
    DROP POLICY IF EXISTS "shops_update_owner_or_admin" ON public.shops;
    DROP POLICY IF EXISTS "shops_delete_owner_or_admin" ON public.shops;
    DROP POLICY IF EXISTS "Shops are viewable by everyone" ON public.shops;
    DROP POLICY IF EXISTS "Shop owners can update own shop" ON public.shops;
    DROP POLICY IF EXISTS "Shop owners can delete own shop" ON public.shops;
    DROP POLICY IF EXISTS "Enable select for all users" ON public.shops;

    -- SELECT: Aktif mağazalar herkese, inaktifler sahip/admin'e
    CREATE POLICY "shops_select"
        ON public.shops
        FOR SELECT
        TO public
        USING (
            is_active = true
            OR
            owner_id = (select auth.uid())
            OR
            public.auth_is_admin()
        );

    -- UPDATE: Sahip veya admin
    CREATE POLICY "shops_update"
        ON public.shops
        FOR UPDATE
        TO authenticated
        USING (
            owner_id = (select auth.uid())
            OR public.auth_is_admin()
        )
        WITH CHECK (
            owner_id = (select auth.uid())
            OR public.auth_is_admin()
        );

    -- DELETE: Sahip veya admin
    CREATE POLICY "shops_delete"
        ON public.shops
        FOR DELETE
        TO authenticated
        USING (
            owner_id = (select auth.uid())
            OR public.auth_is_admin()
        );

    COMMENT ON POLICY "shops_select" ON public.shops IS 
        'Merged: Active shops visible to all (anon+auth), inactive to owner and admin.';
END $$;

-- ============================================================================
-- BÖLÜM 4: ADDRESSES
-- ============================================================================
-- Sorun: authenticated INSERT + SELECT = 2 policy (aynı koşul)
-- Çözüm: Tüm koşullar aynı (user_id = auth.uid()) → FOR ALL

DO $$
BEGIN
    DROP POLICY IF EXISTS "Users can view own addresses" ON public.addresses;
    DROP POLICY IF EXISTS "addresses_select_own" ON public.addresses;
    DROP POLICY IF EXISTS "Users can create own addresses" ON public.addresses;
    DROP POLICY IF EXISTS "addresses_insert_own" ON public.addresses;
    DROP POLICY IF EXISTS "Users can update own addresses" ON public.addresses;
    DROP POLICY IF EXISTS "addresses_update_own" ON public.addresses;
    DROP POLICY IF EXISTS "Users can delete own addresses" ON public.addresses;
    DROP POLICY IF EXISTS "addresses_delete_own" ON public.addresses;
    DROP POLICY IF EXISTS "addresses_manage_own" ON public.addresses;
    DROP POLICY IF EXISTS "Enable select for authenticated users only" ON public.addresses;
    DROP POLICY IF EXISTS "Enable insert for authenticated users only" ON public.addresses;
    DROP POLICY IF EXISTS "Enable update for authenticated users only" ON public.addresses;
    DROP POLICY IF EXISTS "Enable delete for authenticated users only" ON public.addresses;

    -- FOR ALL: Tüm operasyonlar aynı koşula sahip
    CREATE POLICY "addresses_all"
        ON public.addresses
        FOR ALL
        TO authenticated
        USING (user_id = (select auth.uid()))
        WITH CHECK (user_id = (select auth.uid()));

    COMMENT ON POLICY "addresses_all" ON public.addresses IS 
        'Single FOR ALL policy: User can manage (SELECT/INSERT/UPDATE/DELETE) own addresses.';
END $$;

-- ============================================================================
-- BÖLÜM 5: CART_ITEMS
-- ============================================================================
-- Sorun: authenticated DELETE + INSERT + SELECT + UPDATE = 4 policy (aynı koşul)
-- Çözüm: FOR ALL (tüm koşullar aynı)

DO $$
BEGIN
    DROP POLICY IF EXISTS "Users can manage own cart" ON public.cart_items;
    DROP POLICY IF EXISTS "cart_items_all_own" ON public.cart_items;
    DROP POLICY IF EXISTS "cart_items_select_own" ON public.cart_items;
    DROP POLICY IF EXISTS "cart_items_insert_own" ON public.cart_items;
    DROP POLICY IF EXISTS "cart_items_update_own" ON public.cart_items;
    DROP POLICY IF EXISTS "cart_items_delete_own" ON public.cart_items;
    DROP POLICY IF EXISTS "Enable select for authenticated users only" ON public.cart_items;
    DROP POLICY IF EXISTS "Enable insert for authenticated users only" ON public.cart_items;
    DROP POLICY IF EXISTS "Enable update for authenticated users only" ON public.cart_items;
    DROP POLICY IF EXISTS "Enable delete for authenticated users only" ON public.cart_items;

    -- FOR ALL: Tüm operasyonlar aynı koşula sahip
    CREATE POLICY "cart_items_all"
        ON public.cart_items
        FOR ALL
        TO authenticated
        USING (user_id = (select auth.uid()))
        WITH CHECK (user_id = (select auth.uid()));

    COMMENT ON POLICY "cart_items_all" ON public.cart_items IS 
        'Single FOR ALL policy: User can manage (SELECT/INSERT/UPDATE/DELETE) own cart items.';
END $$;

-- ============================================================================
-- BÖLÜM 6: ORDERS
-- ============================================================================
-- Sorun: authenticated SELECT policy'leri (user + seller ayrı) 
-- Çözüm: Tek SELECT policy (user OR seller OR admin)

DO $$
BEGIN
    DROP POLICY IF EXISTS "Users can view own orders" ON public.orders;
    DROP POLICY IF EXISTS "Shop owners can view their shop orders" ON public.orders;
    DROP POLICY IF EXISTS "orders_select_user_or_seller_or_admin" ON public.orders;
    DROP POLICY IF EXISTS "orders_select_user_seller_admin" ON public.orders;
    DROP POLICY IF EXISTS "orders_select_own" ON public.orders;
    DROP POLICY IF EXISTS "Enable select for authenticated users only" ON public.orders;

    -- Birleştirilmiş SELECT Policy
    CREATE POLICY "orders_select"
        ON public.orders
        FOR SELECT
        TO authenticated
        USING (
            user_id = (select auth.uid())
            OR
            EXISTS (
                SELECT 1 FROM public.shops s
                WHERE s.id = orders.shop_id
                AND s.owner_id = (select auth.uid())
            )
            OR
            public.auth_is_admin()
        );

    COMMENT ON POLICY "orders_select" ON public.orders IS 
        'Merged: User sees own orders, seller sees shop orders, admin sees all.';
END $$;

-- ============================================================================
-- BÖLÜM 7: POSTS
-- ============================================================================
-- Sorun: authenticated DELETE + INSERT = 2+ policy
-- Çözüm: SELECT ayrı (farklı koşul), INSERT/UPDATE/DELETE ayrı ayrı tek policy

DO $$
BEGIN
    DROP POLICY IF EXISTS "Users can create posts" ON public.posts;
    DROP POLICY IF EXISTS "posts_insert_own" ON public.posts;
    DROP POLICY IF EXISTS "Users can update own posts" ON public.posts;
    DROP POLICY IF EXISTS "posts_update_own" ON public.posts;
    DROP POLICY IF EXISTS "Users can delete own posts" ON public.posts;
    DROP POLICY IF EXISTS "posts_delete_own" ON public.posts;
    DROP POLICY IF EXISTS "posts_select_all" ON public.posts;
    DROP POLICY IF EXISTS "posts_select_visible" ON public.posts;
    DROP POLICY IF EXISTS "posts_manage_own" ON public.posts;
    DROP POLICY IF EXISTS "Everyone can view public posts" ON public.posts;
    DROP POLICY IF EXISTS "Enable select for all users" ON public.posts;
    DROP POLICY IF EXISTS "Enable insert for authenticated users only" ON public.posts;
    DROP POLICY IF EXISTS "Enable update for authenticated users only" ON public.posts;
    DROP POLICY IF EXISTS "Enable delete for authenticated users only" ON public.posts;

    -- SELECT: Public postlar herkese, kendi postları + admin
    CREATE POLICY "posts_select"
        ON public.posts
        FOR SELECT
        TO public
        USING (
            is_public = true
            OR
            user_id = (select auth.uid())
            OR
            public.auth_is_admin()
        );

    -- INSERT: Kendi postunu oluşturabilir
    CREATE POLICY "posts_insert"
        ON public.posts
        FOR INSERT
        TO authenticated
        WITH CHECK (user_id = (select auth.uid()));

    -- UPDATE: Kendi postunu güncelleyebilir
    CREATE POLICY "posts_update"
        ON public.posts
        FOR UPDATE
        TO authenticated
        USING (user_id = (select auth.uid()))
        WITH CHECK (user_id = (select auth.uid()));

    -- DELETE: Kendi postunu silebilir
    CREATE POLICY "posts_delete"
        ON public.posts
        FOR DELETE
        TO authenticated
        USING (user_id = (select auth.uid()));

    COMMENT ON POLICY "posts_select" ON public.posts IS 
        'Public posts visible to all, private posts visible to owner and admin.';
END $$;

-- ============================================================================
-- BÖLÜM 8: PROFILES
-- ============================================================================
-- Sorun: authenticated UPDATE policy'leri (birden fazla)
-- Çözüm: Tek SELECT (public), tek UPDATE

DO $$
BEGIN
    DROP POLICY IF EXISTS "Users can update own profile" ON public.profiles;
    DROP POLICY IF EXISTS "profiles_update_own" ON public.profiles;
    DROP POLICY IF EXISTS "Users can view all profiles" ON public.profiles;
    DROP POLICY IF EXISTS "profiles_select_all" ON public.profiles;
    DROP POLICY IF EXISTS "Enable select for all users" ON public.profiles;
    DROP POLICY IF EXISTS "Enable update for authenticated users only" ON public.profiles;

    -- SELECT: Herkes profilleri görebilir
    CREATE POLICY "profiles_select"
        ON public.profiles
        FOR SELECT
        TO public
        USING (true);

    -- UPDATE: Kendi profilini güncelleyebilir
    CREATE POLICY "profiles_update"
        ON public.profiles
        FOR UPDATE
        TO authenticated
        USING (id = (select auth.uid()))
        WITH CHECK (id = (select auth.uid()));

    COMMENT ON POLICY "profiles_update" ON public.profiles IS 
        'User can update own profile only.';
END $$;

-- ============================================================================
-- BÖLÜM 9: POST_LIKES
-- ============================================================================
-- Tüm koşullar aynı → FOR ALL kullanılabilir

DO $$
BEGIN
    DROP POLICY IF EXISTS "Users can like posts" ON public.post_likes;
    DROP POLICY IF EXISTS "post_likes_insert_own" ON public.post_likes;
    DROP POLICY IF EXISTS "Users can unlike posts" ON public.post_likes;
    DROP POLICY IF EXISTS "post_likes_delete_own" ON public.post_likes;
    DROP POLICY IF EXISTS "post_likes_select_own" ON public.post_likes;
    DROP POLICY IF EXISTS "post_likes_manage_own" ON public.post_likes;
    DROP POLICY IF EXISTS "Enable insert for authenticated users only" ON public.post_likes;
    DROP POLICY IF EXISTS "Enable delete for authenticated users only" ON public.post_likes;
    DROP POLICY IF EXISTS "Enable select for authenticated users only" ON public.post_likes;

    -- Herkes like'ları görebilir (post sayfasında gösterim)
    CREATE POLICY "post_likes_select"
        ON public.post_likes
        FOR SELECT
        TO public
        USING (true);

    -- INSERT: Kendi adına like ekleyebilir
    CREATE POLICY "post_likes_insert"
        ON public.post_likes
        FOR INSERT
        TO authenticated
        WITH CHECK (user_id = (select auth.uid()));

    -- DELETE: Kendi like'ını kaldırabilir
    CREATE POLICY "post_likes_delete"
        ON public.post_likes
        FOR DELETE
        TO authenticated
        USING (user_id = (select auth.uid()));

    COMMENT ON POLICY "post_likes_select" ON public.post_likes IS 
        'All likes are publicly visible.';
END $$;

-- ============================================================================
-- BÖLÜM 10: POST_COMMENTS
-- ============================================================================
-- SELECT herkese açık, diğerleri user_id kontrolü

DO $$
BEGIN
    DROP POLICY IF EXISTS "Users can comment on posts" ON public.post_comments;
    DROP POLICY IF EXISTS "post_comments_insert_own" ON public.post_comments;
    DROP POLICY IF EXISTS "post_comments_update_own" ON public.post_comments;
    DROP POLICY IF EXISTS "post_comments_delete_own" ON public.post_comments;
    DROP POLICY IF EXISTS "post_comments_select_own" ON public.post_comments;
    DROP POLICY IF EXISTS "post_comments_select_all" ON public.post_comments;
    DROP POLICY IF EXISTS "post_comments_manage_own" ON public.post_comments;
    DROP POLICY IF EXISTS "Enable select for all users" ON public.post_comments;
    DROP POLICY IF EXISTS "Enable insert for authenticated users only" ON public.post_comments;
    DROP POLICY IF EXISTS "Enable update for authenticated users only" ON public.post_comments;
    DROP POLICY IF EXISTS "Enable delete for authenticated users only" ON public.post_comments;

    -- SELECT: Herkes yorumları görebilir
    CREATE POLICY "post_comments_select"
        ON public.post_comments
        FOR SELECT
        TO public
        USING (true);

    -- INSERT: Kendi adına yorum ekleyebilir
    CREATE POLICY "post_comments_insert"
        ON public.post_comments
        FOR INSERT
        TO authenticated
        WITH CHECK (user_id = (select auth.uid()));

    -- UPDATE: Kendi yorumunu güncelleyebilir
    CREATE POLICY "post_comments_update"
        ON public.post_comments
        FOR UPDATE
        TO authenticated
        USING (user_id = (select auth.uid()))
        WITH CHECK (user_id = (select auth.uid()));

    -- DELETE: Kendi yorumunu silebilir
    CREATE POLICY "post_comments_delete"
        ON public.post_comments
        FOR DELETE
        TO authenticated
        USING (user_id = (select auth.uid()));
END $$;

-- ============================================================================
-- BÖLÜM 11: CONVERSATIONS
-- ============================================================================
-- Tüm koşullar aynı (user_id OR other_user_id) → FOR ALL

DO $$
BEGIN
    DROP POLICY IF EXISTS "conversations_select_own" ON public.conversations;
    DROP POLICY IF EXISTS "conversations_insert_own" ON public.conversations;
    DROP POLICY IF EXISTS "conversations_update_own" ON public.conversations;
    DROP POLICY IF EXISTS "conversations_delete_own" ON public.conversations;
    DROP POLICY IF EXISTS "conversations_manage_own" ON public.conversations;
    DROP POLICY IF EXISTS "Enable select for authenticated users only" ON public.conversations;
    DROP POLICY IF EXISTS "Enable insert for authenticated users only" ON public.conversations;
    DROP POLICY IF EXISTS "Enable update for authenticated users only" ON public.conversations;
    DROP POLICY IF EXISTS "Enable delete for authenticated users only" ON public.conversations;

    -- FOR ALL: Tüm operasyonlar aynı koşula sahip
    CREATE POLICY "conversations_all"
        ON public.conversations
        FOR ALL
        TO authenticated
        USING (
            user_id = (select auth.uid())
            OR
            other_user_id = (select auth.uid())
        )
        WITH CHECK (
            user_id = (select auth.uid())
            OR
            other_user_id = (select auth.uid())
        );

    COMMENT ON POLICY "conversations_all" ON public.conversations IS 
        'Single FOR ALL policy: Participants can manage their conversations.';
END $$;

-- ============================================================================
-- BÖLÜM 12: MESSAGES
-- ============================================================================
-- SELECT farklı (participant), INSERT farklı (sender + participant) → ayrı ayrı

DO $$
BEGIN
    DROP POLICY IF EXISTS "Users can view own messages" ON public.messages;
    DROP POLICY IF EXISTS "messages_select_participant" ON public.messages;
    DROP POLICY IF EXISTS "messages_insert_participant" ON public.messages;
    DROP POLICY IF EXISTS "messages_update_own" ON public.messages;
    DROP POLICY IF EXISTS "messages_delete_own" ON public.messages;
    DROP POLICY IF EXISTS "messages_manage_participant" ON public.messages;
    DROP POLICY IF EXISTS "Enable select for authenticated users only" ON public.messages;
    DROP POLICY IF EXISTS "Enable insert for authenticated users only" ON public.messages;
    DROP POLICY IF EXISTS "Enable update for authenticated users only" ON public.messages;
    DROP POLICY IF EXISTS "Enable delete for authenticated users only" ON public.messages;

    -- SELECT: Konuşma katılımcıları mesajları görebilir
    CREATE POLICY "messages_select"
        ON public.messages
        FOR SELECT
        TO authenticated
        USING (
            EXISTS (
                SELECT 1 FROM public.conversations c
                WHERE c.id = messages.conversation_id
                AND (c.user_id = (select auth.uid()) OR c.other_user_id = (select auth.uid()))
            )
        );

    -- INSERT: Gönderen olarak, katılımcı olduğu konuşmaya mesaj ekleyebilir
    CREATE POLICY "messages_insert"
        ON public.messages
        FOR INSERT
        TO authenticated
        WITH CHECK (
            sender_id = (select auth.uid())
            AND
            EXISTS (
                SELECT 1 FROM public.conversations c
                WHERE c.id = messages.conversation_id
                AND (c.user_id = (select auth.uid()) OR c.other_user_id = (select auth.uid()))
            )
        );

    -- UPDATE: Konuşma katılımcısı mesajı güncelleyebilir (is_read vb.)
    CREATE POLICY "messages_update"
        ON public.messages
        FOR UPDATE
        TO authenticated
        USING (
            EXISTS (
                SELECT 1 FROM public.conversations c
                WHERE c.id = messages.conversation_id
                AND (c.user_id = (select auth.uid()) OR c.other_user_id = (select auth.uid()))
            )
        );

    -- DELETE: Gönderen kendi mesajını silebilir
    CREATE POLICY "messages_delete"
        ON public.messages
        FOR DELETE
        TO authenticated
        USING (sender_id = (select auth.uid()));
END $$;

-- ============================================================================
-- BÖLÜM 13: DOĞRULAMA RAPORU
-- ============================================================================

DO $$
DECLARE
    v_total_policies INT;
    v_tables_with_multiple TEXT := '';
    rec RECORD;
BEGIN
    -- Toplam policy sayısı
    SELECT COUNT(*) INTO v_total_policies
    FROM pg_policies
    WHERE schemaname = 'public';

    -- Hala multiple permissive policy olan tablolar var mı kontrol et
    FOR rec IN
        SELECT tablename, cmd, roles::text, COUNT(*) as cnt
        FROM pg_policies
        WHERE schemaname = 'public'
        AND permissive = 'PERMISSIVE'
        GROUP BY tablename, cmd, roles::text
        HAVING COUNT(*) > 1
    LOOP
        v_tables_with_multiple := v_tables_with_multiple || 
            E'\n     ⚠️  ' || rec.tablename || ' (' || rec.cmd || ') → ' || rec.cnt || ' policies';
    END LOOP;

    RAISE NOTICE '';
    RAISE NOTICE '╔═══════════════════════════════════════════════════════════════════╗';
    RAISE NOTICE '║    SUPABASE LINTER PERFORMANS UYARILARI DÜZELTİLDİ               ║';
    RAISE NOTICE '╠═══════════════════════════════════════════════════════════════════╣';
    RAISE NOTICE '║                                                                   ║';
    RAISE NOTICE '║  ✅ auth_rls_initplan: auth.uid() → (select auth.uid())           ║';
    RAISE NOTICE '║     Tüm policy''lerde optimize edildi                             ║';
    RAISE NOTICE '║                                                                   ║';
    RAISE NOTICE '║  ✅ multiple_permissive_policies: Birleştirildi                   ║';
    RAISE NOTICE '║     - notifications: 4 tek policy (SELECT/INSERT/UPDATE/DELETE)  ║';
    RAISE NOTICE '║     - products: anon+auth → 1 SELECT (TO public)                ║';
    RAISE NOTICE '║     - shops: anon+auth → 1 SELECT + 1 UPDATE + 1 DELETE         ║';
    RAISE NOTICE '║     - addresses: FOR ALL (tek policy)                             ║';
    RAISE NOTICE '║     - cart_items: FOR ALL (tek policy)                             ║';
    RAISE NOTICE '║     - orders: 2+ SELECT → 1 SELECT                               ║';
    RAISE NOTICE '║     - posts: 1 SELECT + 1 INSERT + 1 UPDATE + 1 DELETE           ║';
    RAISE NOTICE '║     - profiles: 1 SELECT + 1 UPDATE                               ║';
    RAISE NOTICE '║     - conversations: FOR ALL (tek policy)                         ║';
    RAISE NOTICE '║     - messages: 4 tek policy (SELECT/INSERT/UPDATE/DELETE)        ║';
    RAISE NOTICE '║                                                                   ║';
    RAISE NOTICE '║  📊 Toplam policy sayısı: %                                      ║', v_total_policies;
    RAISE NOTICE '║                                                                   ║';

    IF v_tables_with_multiple = '' THEN
        RAISE NOTICE '║  ✅ Multiple permissive policy uyarısı KALMADI!                  ║';
    ELSE
        RAISE NOTICE '║  ⚠️  Hala multiple permissive policy olan tablolar:%             ║', v_tables_with_multiple;
    END IF;

    RAISE NOTICE '║                                                                   ║';
    RAISE NOTICE '╚═══════════════════════════════════════════════════════════════════╝';
    RAISE NOTICE '';
    RAISE NOTICE '✨ İşlem tamamlandı! Linter''i tekrar çalıştırarak doğrulayın.';
    RAISE NOTICE '';
END $$;

COMMIT;
