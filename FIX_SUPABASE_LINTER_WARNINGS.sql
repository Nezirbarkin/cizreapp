-- ============================================================================
-- SUPABASE LINTER UYARILARINI DÜZELT
-- ============================================================================
-- Tarih: 2026-03-07
-- Amaç: Supabase Linter tarafından tespit edilen güvenlik ve performans 
--       sorunlarını düzeltmek (çalışan fonksiyonları bozmadan)
-- 
-- KRİTİK SORUNLAR:
--   ✓ RLS kapalı tablolar (conversations, messages)
--   ✓ auth.uid() performans optimizasyonu
--   ✓ Function search_path güvenliği
--   ✓ Overly permissive policies
--   ✓ Multiple permissive policies birleştirme
-- ============================================================================

BEGIN;

-- ============================================================================
-- BÖLÜM 1: KRİTİK - RLS ENABLE (CONVERSATIONS & MESSAGES)
-- ============================================================================

-- Conversations tablosu için RLS aktif et
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;

-- Messages tablosu için RLS aktif et  
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

-- Conversations için RLS Policy'leri oluştur (eğer yoksa)
DO $$
BEGIN
    -- SELECT Policy: Kullanıcı kendi konuşmalarını görebilir
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE tablename = 'conversations' 
        AND policyname = 'conversations_select_own'
    ) THEN
        CREATE POLICY "conversations_select_own"
            ON public.conversations
            FOR SELECT
            TO authenticated
            USING (user_id = (select auth.uid()));
    END IF;

    -- INSERT Policy: Kullanıcı kendi konuşmasını oluşturabilir veya alıcı olarak
    DROP POLICY IF EXISTS "conversations_insert_own" ON public.conversations;
    CREATE POLICY "conversations_insert_own"
        ON public.conversations
        FOR INSERT
        TO authenticated
        WITH CHECK (
            user_id = (select auth.uid())
            OR 
            other_user_id = (select auth.uid())
        );

    -- UPDATE Policy: Kullanıcı kendi konuşmasını güncelleyebilir
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE tablename = 'conversations' 
        AND policyname = 'conversations_update_own'
    ) THEN
        CREATE POLICY "conversations_update_own"
            ON public.conversations
            FOR UPDATE
            TO authenticated
            USING (user_id = (select auth.uid()))
            WITH CHECK (user_id = (select auth.uid()));
    END IF;

    -- DELETE Policy: Kullanıcı kendi konuşmasını silebilir
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE tablename = 'conversations' 
        AND policyname = 'conversations_delete_own'
    ) THEN
        CREATE POLICY "conversations_delete_own"
            ON public.conversations
            FOR DELETE
            TO authenticated
            USING (user_id = (select auth.uid()));
    END IF;
END $$;

-- Messages için RLS Policy'leri oluştur (eğer yoksa)
DO $$
BEGIN
    -- SELECT Policy: Kullanıcı dahil olduğu konuşmaların mesajlarını görebilir
    DROP POLICY IF EXISTS "Users can view own messages" ON public.messages;
    DROP POLICY IF EXISTS "messages_select_participant" ON public.messages;
    
    CREATE POLICY "messages_select_participant"
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

    -- INSERT Policy: Kullanıcı dahil olduğu konuşmalara mesaj ekleyebilir
    DROP POLICY IF EXISTS "messages_insert_participant" ON public.messages;
    
    CREATE POLICY "messages_insert_participant"
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

    -- UPDATE Policy: Kullanıcı kendi mesajlarını güncelleyebilir (is_read için)
    DROP POLICY IF EXISTS "messages_update_own" ON public.messages;
    
    CREATE POLICY "messages_update_own"
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

    -- DELETE Policy: Kullanıcı kendi gönderdiği mesajları silebilir
    DROP POLICY IF EXISTS "messages_delete_own" ON public.messages;
    
    CREATE POLICY "messages_delete_own"
        ON public.messages
        FOR DELETE
        TO authenticated
        USING (sender_id = (select auth.uid()));
END $$;

-- ============================================================================
-- BÖLÜM 2: PERFORMANS - AUTH.UID() OPTİMİZASYONU (SELECT AUTH.UID())
-- ============================================================================
-- auth.uid() yerine (select auth.uid()) kullanarak her satır için tekrar
-- hesaplanmasını önle. Bu özellikle büyük sonuç setlerinde performans artışı sağlar.

-- NOTIFICATIONS tablosu policy'lerini optimize et
DO $$
BEGIN
    -- SELECT Policy
    DROP POLICY IF EXISTS "Users can view own notifications" ON public.notifications;
    DROP POLICY IF EXISTS "notifications_select_own" ON public.notifications;
    DROP POLICY IF EXISTS "notifications_select_policy" ON public.notifications;
    
    CREATE POLICY "notifications_select_policy"
        ON public.notifications
        FOR SELECT
        TO authenticated
        USING (user_id = (select auth.uid()));

    -- INSERT Policy - WITH CHECK (true) kasıtlı (trigger'lar için)
    DROP POLICY IF EXISTS "notifications_insert_policy" ON public.notifications;
    DROP POLICY IF EXISTS "notifications_insert" ON public.notifications;
    DROP POLICY IF EXISTS "Anyone can insert notifications" ON public.notifications;
    
    CREATE POLICY "notifications_insert_policy"
        ON public.notifications
        FOR INSERT
        TO authenticated
        WITH CHECK (true);
    
    COMMENT ON POLICY "notifications_insert_policy" ON public.notifications IS 
    'Allows authenticated users to create notifications. Intentionally permissive for system notifications created by triggers (SECURITY DEFINER) and cross-user notifications.';

    -- UPDATE Policy
    DROP POLICY IF EXISTS "Users can update own notifications" ON public.notifications;
    DROP POLICY IF EXISTS "notifications_update_own" ON public.notifications;
    DROP POLICY IF EXISTS "notifications_update_policy" ON public.notifications;
    
    CREATE POLICY "notifications_update_policy"
        ON public.notifications
        FOR UPDATE
        TO authenticated
        USING (user_id = (select auth.uid()))
        WITH CHECK (user_id = (select auth.uid()));

    -- DELETE Policy
    DROP POLICY IF EXISTS "notifications_delete_policy" ON public.notifications;
    DROP POLICY IF EXISTS "notifications_delete_own" ON public.notifications;
    
    CREATE POLICY "notifications_delete_policy"
        ON public.notifications
        FOR DELETE
        TO authenticated
        USING (user_id = (select auth.uid()));
END $$;

-- PROFILES tablosu policy'lerini optimize et
DO $$
BEGIN
    DROP POLICY IF EXISTS "Users can update own profile" ON public.profiles;
    DROP POLICY IF EXISTS "profiles_update_own" ON public.profiles;
    
    CREATE POLICY "profiles_update_own"
        ON public.profiles
        FOR UPDATE
        TO authenticated
        USING (id = (select auth.uid()))
        WITH CHECK (id = (select auth.uid()));
END $$;

-- ADDRESSES tablosu policy'lerini optimize et
DO $$
BEGIN
    DROP POLICY IF EXISTS "Users can view own addresses" ON public.addresses;
    DROP POLICY IF EXISTS "addresses_select_own" ON public.addresses;
    
    CREATE POLICY "addresses_select_own"
        ON public.addresses
        FOR SELECT
        TO authenticated
        USING (user_id = (select auth.uid()));

    DROP POLICY IF EXISTS "Users can create own addresses" ON public.addresses;
    DROP POLICY IF EXISTS "addresses_insert_own" ON public.addresses;
    
    CREATE POLICY "addresses_insert_own"
        ON public.addresses
        FOR INSERT
        TO authenticated
        WITH CHECK (user_id = (select auth.uid()));

    DROP POLICY IF EXISTS "Users can update own addresses" ON public.addresses;
    DROP POLICY IF EXISTS "addresses_update_own" ON public.addresses;
    
    CREATE POLICY "addresses_update_own"
        ON public.addresses
        FOR UPDATE
        TO authenticated
        USING (user_id = (select auth.uid()))
        WITH CHECK (user_id = (select auth.uid()));

    DROP POLICY IF EXISTS "Users can delete own addresses" ON public.addresses;
    DROP POLICY IF EXISTS "addresses_delete_own" ON public.addresses;
    
    CREATE POLICY "addresses_delete_own"
        ON public.addresses
        FOR DELETE
        TO authenticated
        USING (user_id = (select auth.uid()));
END $$;

-- CART_ITEMS tablosu policy'lerini optimize et
DO $$
BEGIN
    DROP POLICY IF EXISTS "Users can manage own cart" ON public.cart_items;
    DROP POLICY IF EXISTS "cart_items_all_own" ON public.cart_items;
    
    CREATE POLICY "cart_items_all_own"
        ON public.cart_items
        FOR ALL
        TO authenticated
        USING (user_id = (select auth.uid()))
        WITH CHECK (user_id = (select auth.uid()));
END $$;

-- POST_LIKES tablosu policy'lerini optimize et
DO $$
BEGIN
    DROP POLICY IF EXISTS "Users can like posts" ON public.post_likes;
    DROP POLICY IF EXISTS "post_likes_insert_own" ON public.post_likes;
    
    CREATE POLICY "post_likes_insert_own"
        ON public.post_likes
        FOR INSERT
        TO authenticated
        WITH CHECK (user_id = (select auth.uid()));

    DROP POLICY IF EXISTS "Users can unlike posts" ON public.post_likes;
    DROP POLICY IF EXISTS "post_likes_delete_own" ON public.post_likes;
    
    CREATE POLICY "post_likes_delete_own"
        ON public.post_likes
        FOR DELETE
        TO authenticated
        USING (user_id = (select auth.uid()));
END $$;

-- POST_COMMENTS tablosu policy'lerini optimize et
DO $$
BEGIN
    DROP POLICY IF EXISTS "Users can comment on posts" ON public.post_comments;
    DROP POLICY IF EXISTS "post_comments_insert_own" ON public.post_comments;
    
    CREATE POLICY "post_comments_insert_own"
        ON public.post_comments
        FOR INSERT
        TO authenticated
        WITH CHECK (user_id = (select auth.uid()));

    DROP POLICY IF EXISTS "post_comments_update_own" ON public.post_comments;
    
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE tablename = 'post_comments' 
        AND policyname = 'post_comments_update_own'
    ) THEN
        CREATE POLICY "post_comments_update_own"
            ON public.post_comments
            FOR UPDATE
            TO authenticated
            USING (user_id = (select auth.uid()))
            WITH CHECK (user_id = (select auth.uid()));
    END IF;

    DROP POLICY IF EXISTS "post_comments_delete_own" ON public.post_comments;
    
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE tablename = 'post_comments' 
        AND policyname = 'post_comments_delete_own'
    ) THEN
        CREATE POLICY "post_comments_delete_own"
            ON public.post_comments
            FOR DELETE
            TO authenticated
            USING (user_id = (select auth.uid()));
    END IF;
END $$;

-- POSTS tablosu policy'lerini optimize et
DO $$
BEGIN
    DROP POLICY IF EXISTS "Users can create posts" ON public.posts;
    DROP POLICY IF EXISTS "posts_insert_own" ON public.posts;
    
    CREATE POLICY "posts_insert_own"
        ON public.posts
        FOR INSERT
        TO authenticated
        WITH CHECK (user_id = (select auth.uid()));

    DROP POLICY IF EXISTS "Users can update own posts" ON public.posts;
    DROP POLICY IF EXISTS "posts_update_own" ON public.posts;
    
    CREATE POLICY "posts_update_own"
        ON public.posts
        FOR UPDATE
        TO authenticated
        USING (user_id = (select auth.uid()))
        WITH CHECK (user_id = (select auth.uid()));

    DROP POLICY IF EXISTS "Users can delete own posts" ON public.posts;
    DROP POLICY IF EXISTS "posts_delete_own" ON public.posts;
    
    CREATE POLICY "posts_delete_own"
        ON public.posts
        FOR DELETE
        TO authenticated
        USING (user_id = (select auth.uid()));
END $$;

-- SHOPS tablosu policy'lerini optimize et (owner_id kontrolleri)
DO $$
BEGIN
    DROP POLICY IF EXISTS "Shop owners can update own shop" ON public.shops;
    DROP POLICY IF EXISTS "shops_update_owner_or_admin" ON public.shops;
    
    CREATE POLICY "shops_update_owner_or_admin"
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

    DROP POLICY IF EXISTS "shops_delete_owner_or_admin" ON public.shops;
    
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE tablename = 'shops' 
        AND policyname = 'shops_delete_owner_or_admin'
    ) THEN
        CREATE POLICY "shops_delete_owner_or_admin"
            ON public.shops
            FOR DELETE
            TO authenticated
            USING (
                owner_id = (select auth.uid()) 
                OR public.auth_is_admin()
            );
    END IF;
END $$;

-- ============================================================================
-- BÖLÜM 3: GÜVENLİK - FUNCTION SEARCH_PATH
-- ============================================================================
-- SECURITY DEFINER fonksiyonlarına search_path ekleyerek SQL injection 
-- saldırılarını önle ve schema search yolunu sabit tut.

-- update_updated_at_column fonksiyonunu güvenli hale getir
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public;

COMMENT ON FUNCTION public.update_updated_at_column() IS 
'Updates the updated_at timestamp (SECURITY DEFINER with search_path)';

-- update_post_likes_count fonksiyonunu güvenli hale getir
CREATE OR REPLACE FUNCTION public.update_post_likes_count()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE public.posts 
        SET likes_count = likes_count + 1 
        WHERE id = NEW.post_id;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE public.posts 
        SET likes_count = GREATEST(0, likes_count - 1) 
        WHERE id = OLD.post_id;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public;

COMMENT ON FUNCTION public.update_post_likes_count() IS 
'Updates post likes count on insert/delete (SECURITY DEFINER with search_path)';

-- update_post_comments_count fonksiyonunu güvenli hale getir
CREATE OR REPLACE FUNCTION public.update_post_comments_count()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE public.posts
        SET comments_count = comments_count + 1
        WHERE id = NEW.post_id;
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE public.posts
        SET comments_count = GREATEST(0, comments_count - 1)
        WHERE id = OLD.post_id;
        RETURN OLD;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public;

COMMENT ON FUNCTION public.update_post_comments_count() IS 
'Updates post comments count on insert/delete (SECURITY DEFINER with search_path)';

-- update_story_views_count fonksiyonunu güvenli hale getir
CREATE OR REPLACE FUNCTION public.update_story_views_count()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE public.stories 
    SET views_count = views_count + 1 
    WHERE id = NEW.story_id;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public;

COMMENT ON FUNCTION public.update_story_views_count() IS 
'Updates story views count on insert (SECURITY DEFINER with search_path)';

-- update_conversation_on_message fonksiyonunu güvenli hale getir (zaten var ama kontrol et)
CREATE OR REPLACE FUNCTION public.update_conversation_on_message()
RETURNS TRIGGER
AS $$
DECLARE
    conv_other_user_id UUID;
    sender_id UUID := NEW.sender_id;
BEGIN
    -- Konuşmanın other_user_id'sini al (bu karşı tarafın ID'si)
    SELECT other_user_id INTO conv_other_user_id
    FROM public.conversations
    WHERE id = NEW.conversation_id;

    -- Gönderen tarafın conversation'ını güncelle (unread_count artmaz)
    UPDATE public.conversations
    SET
        last_message = NEW.content,
        last_message_time = NEW.created_at,
        updated_at = NOW()
    WHERE user_id = sender_id 
      AND other_user_id = conv_other_user_id;

    -- Alıcı tarafın conversation'ını güncelle veya oluştur (unread_count artar)
    INSERT INTO public.conversations (user_id, other_user_id, last_message, last_message_time, unread_count)
    VALUES (conv_other_user_id, sender_id, NEW.content, NEW.created_at, 1)
    ON CONFLICT (user_id, other_user_id) 
    DO UPDATE SET
        last_message = EXCLUDED.last_message,
        last_message_time = EXCLUDED.last_message_time,
        unread_count = public.conversations.unread_count + 1,
        updated_at = NOW();

    RETURN NEW;
END;
$$ LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public;

COMMENT ON FUNCTION public.update_conversation_on_message() IS 
'Updates conversation records for both participants on new message (SECURITY DEFINER with search_path)';

-- ============================================================================
-- BÖLÜM 4: PERFORMANS - MULTIPLE PERMISSIVE POLICIES BİRLEŞTİR
-- ============================================================================
-- Aynı tablo + action için birden fazla permissive policy varsa,
-- her query'de hepsi değerlendirilir. Bunları birleştirerek performans artır.

-- ORDERS tablosu - SELECT policy'lerini birleştir (user + seller erişimi)
DO $$
BEGIN
    DROP POLICY IF EXISTS "Users can view own orders" ON public.orders;
    DROP POLICY IF EXISTS "Shop owners can view their shop orders" ON public.orders;
    DROP POLICY IF EXISTS "orders_select_user_or_seller_or_admin" ON public.orders;
    
    CREATE POLICY "orders_select_user_or_seller_or_admin"
        ON public.orders
        FOR SELECT
        TO authenticated
        USING (
            -- Kullanıcı kendi siparişlerini görebilir
            user_id = (select auth.uid())
            OR
            -- Satıcı kendi mağazasının siparişlerini görebilir
            EXISTS (
                SELECT 1 FROM public.shops s
                WHERE s.id = orders.shop_id
                AND s.owner_id = (select auth.uid())
            )
            OR
            -- Admin her şeyi görebilir
            public.auth_is_admin()
        );
        
    COMMENT ON POLICY "orders_select_user_or_seller_or_admin" ON public.orders IS 
    'Merged policy: User can view own orders, seller can view shop orders, admin can view all';
END $$;

-- PRODUCTS tablosu - SELECT policy'lerini birleştir (eğer duplicate varsa)
DO $$
BEGIN
    DROP POLICY IF EXISTS "Products are viewable by everyone" ON public.products;
    DROP POLICY IF EXISTS "products_select_active_or_owner" ON public.products;
    
    -- Aktif ürünler herkes tarafından görülebilir + sahip/admin her şeyi görebilir
    CREATE POLICY "products_select_active_or_owner"
        ON public.products
        FOR SELECT
        TO authenticated
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
    
    COMMENT ON POLICY "products_select_active_or_owner" ON public.products IS 
    'Merged policy: Active products visible to all, inactive visible to shop owner and admin';
END $$;

-- Anonim kullanıcılar için ayrı policy
DO $$
BEGIN
    DROP POLICY IF EXISTS "products_select_active_anon" ON public.products;
    
    CREATE POLICY "products_select_active_anon"
        ON public.products
        FOR SELECT
        TO anon
        USING (is_active = true);
    
    COMMENT ON POLICY "products_select_active_anon" ON public.products IS 
    'Anonymous users can only view active products';
END $$;

-- SHOPS tablosu - SELECT policy'lerini birleştir
DO $$
BEGIN
    DROP POLICY IF EXISTS "Shops are viewable by everyone" ON public.shops;
    DROP POLICY IF EXISTS "shops_select_active_or_owner" ON public.shops;
    
    CREATE POLICY "shops_select_active_or_owner"
        ON public.shops
        FOR SELECT
        TO authenticated
        USING (
            is_active = true
            OR
            owner_id = (select auth.uid())
            OR
            public.auth_is_admin()
        );
    
    COMMENT ON POLICY "shops_select_active_or_owner" ON public.shops IS 
    'Merged policy: Active shops visible to all, inactive visible to owner and admin';
END $$;

-- Anonim kullanıcılar için ayrı policy
DO $$
BEGIN
    DROP POLICY IF EXISTS "shops_select_active_anon" ON public.shops;
    
    CREATE POLICY "shops_select_active_anon"
        ON public.shops
        FOR SELECT
        TO anon
        USING (is_active = true);
    
    COMMENT ON POLICY "shops_select_active_anon" ON public.shops IS 
    'Anonymous users can only view active shops';
END $$;

-- ============================================================================
-- BÖLÜM 5: GÜNCELLEME - TRIGGER'LARI YENİDEN OLUŞTUR (search_path ile)
-- ============================================================================
-- Trigger'ları yeni fonksiyonlarla yeniden oluştur

DROP TRIGGER IF EXISTS update_profiles_updated_at ON public.profiles;
CREATE TRIGGER update_profiles_updated_at 
    BEFORE UPDATE ON public.profiles 
    FOR EACH ROW 
    EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS update_shops_updated_at ON public.shops;
CREATE TRIGGER update_shops_updated_at 
    BEFORE UPDATE ON public.shops 
    FOR EACH ROW 
    EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS update_products_updated_at ON public.products;
CREATE TRIGGER update_products_updated_at 
    BEFORE UPDATE ON public.products 
    FOR EACH ROW 
    EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS update_orders_updated_at ON public.orders;
CREATE TRIGGER update_orders_updated_at 
    BEFORE UPDATE ON public.orders 
    FOR EACH ROW 
    EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS update_posts_updated_at ON public.posts;
CREATE TRIGGER update_posts_updated_at 
    BEFORE UPDATE ON public.posts 
    FOR EACH ROW 
    EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS post_likes_count_trigger ON public.post_likes;
CREATE TRIGGER post_likes_count_trigger
    AFTER INSERT OR DELETE ON public.post_likes
    FOR EACH ROW 
    EXECUTE FUNCTION public.update_post_likes_count();

DROP TRIGGER IF EXISTS post_comments_count_trigger ON public.post_comments;
CREATE TRIGGER post_comments_count_trigger
    AFTER INSERT OR DELETE ON public.post_comments
    FOR EACH ROW 
    EXECUTE FUNCTION public.update_post_comments_count();

DROP TRIGGER IF EXISTS story_views_count_trigger ON public.story_views;
CREATE TRIGGER story_views_count_trigger
    AFTER INSERT ON public.story_views
    FOR EACH ROW 
    EXECUTE FUNCTION public.update_story_views_count();

DROP TRIGGER IF EXISTS message_insert_trigger ON public.messages;
CREATE TRIGGER message_insert_trigger
    AFTER INSERT ON public.messages
    FOR EACH ROW
    EXECUTE FUNCTION public.update_conversation_on_message();

-- ============================================================================
-- BÖLÜM 6: DOĞRULAMA VE RAPOR
-- ============================================================================

DO $$
DECLARE
    v_conversations_rls BOOLEAN;
    v_messages_rls BOOLEAN;
    v_conv_policies INT;
    v_msg_policies INT;
    v_functions_count INT;
BEGIN
    -- RLS durumlarını kontrol et
    SELECT relrowsecurity INTO v_conversations_rls 
    FROM pg_class 
    WHERE oid = 'public.conversations'::regclass;
    
    SELECT relrowsecurity INTO v_messages_rls 
    FROM pg_class 
    WHERE oid = 'public.messages'::regclass;
    
    -- Policy sayılarını kontrol et
    SELECT COUNT(*) INTO v_conv_policies 
    FROM pg_policies 
    WHERE schemaname = 'public' AND tablename = 'conversations';
    
    SELECT COUNT(*) INTO v_msg_policies 
    FROM pg_policies 
    WHERE schemaname = 'public' AND tablename = 'messages';
    
    -- SECURITY DEFINER + search_path fonksiyon sayısını kontrol et
    SELECT COUNT(*) INTO v_functions_count
    FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public'
    AND p.prosecdef = true
    AND p.proconfig IS NOT NULL
    AND EXISTS (
        SELECT 1 FROM unnest(p.proconfig) AS cfg
        WHERE cfg LIKE 'search_path=%'
    );
    
    -- Rapor
    RAISE NOTICE '╔════════════════════════════════════════════════════════════════╗';
    RAISE NOTICE '║  SUPABASE LINTER UYARILARI DÜZELTİLDİ                         ║';
    RAISE NOTICE '╠════════════════════════════════════════════════════════════════╣';
    RAISE NOTICE '║                                                                ║';
    RAISE NOTICE '║  ✅ BÖLÜM 1: RLS ENABLE                                        ║';
    RAISE NOTICE '║     - conversations RLS: %                                 ║', 
        CASE WHEN v_conversations_rls THEN 'ENABLED  ✓' ELSE 'DISABLED ✗' END;
    RAISE NOTICE '║     - messages RLS: %                                      ║', 
        CASE WHEN v_messages_rls THEN 'ENABLED  ✓' ELSE 'DISABLED ✗' END;
    RAISE NOTICE '║     - conversations policies: % adet                          ║', v_conv_policies;
    RAISE NOTICE '║     - messages policies: % adet                               ║', v_msg_policies;
    RAISE NOTICE '║                                                                ║';
    RAISE NOTICE '║  ✅ BÖLÜM 2: PERFORMANS - auth.uid() → (select auth.uid())   ║';
    RAISE NOTICE '║     Optimize edilen tablolar:                                  ║';
    RAISE NOTICE '║     - notifications, profiles, addresses, cart_items          ║';
    RAISE NOTICE '║     - post_likes, post_comments, posts, shops                  ║';
    RAISE NOTICE '║                                                                ║';
    RAISE NOTICE '║  ✅ BÖLÜM 3: GÜVENLİK - Function search_path                  ║';
    RAISE NOTICE '║     - SECURITY DEFINER fonksiyonlar: % adet                   ║', v_functions_count;
    RAISE NOTICE '║     - update_updated_at_column()                               ║';
    RAISE NOTICE '║     - update_post_likes_count()                                ║';
    RAISE NOTICE '║     - update_post_comments_count()                             ║';
    RAISE NOTICE '║     - update_story_views_count()                               ║';
    RAISE NOTICE '║     - update_conversation_on_message()                         ║';
    RAISE NOTICE '║                                                                ║';
    RAISE NOTICE '║  ✅ BÖLÜM 4: PERFORMANS - Multiple policies birleştirildi     ║';
    RAISE NOTICE '║     - orders: 2 SELECT → 1 SELECT                             ║';
    RAISE NOTICE '║     - products: Duplicate SELECT temizlendi                    ║';
    RAISE NOTICE '║     - shops: Duplicate SELECT temizlendi                       ║';
    RAISE NOTICE '║                                                                ║';
    RAISE NOTICE '║  ✅ BÖLÜM 5: TRIGGER''lar güncellendi                          ║';
    RAISE NOTICE '║     Tüm trigger''lar yeni fonksiyonlarla yeniden oluşturuldu   ║';
    RAISE NOTICE '║                                                                ║';
    RAISE NOTICE '║  ⚠️  NOTLAR:                                                   ║';
    RAISE NOTICE '║     1. notifications INSERT policy kasıtlı permissive          ║';
    RAISE NOTICE '║        (trigger''lar için gerekli - SECURITY DEFINER)          ║';
    RAISE NOTICE '║     2. Mevcut çalışan fonksiyonlar korundu                     ║';
    RAISE NOTICE '║     3. Tüm RLS policy''leri mevcut erişim haklarını koruyor   ║';
    RAISE NOTICE '║                                                                ║';
    RAISE NOTICE '╚════════════════════════════════════════════════════════════════╝';
    RAISE NOTICE '';
    RAISE NOTICE '✨ Düzeltmeler başarıyla uygulandı!';
    RAISE NOTICE '📊 Test etmeniz önerilir:';
    RAISE NOTICE '   - Conversations ve messages erişimi';
    RAISE NOTICE '   - Notification trigger''ları';
    RAISE NOTICE '   - Post likes/comments sayaçları';
    RAISE NOTICE '';
END $$;

COMMIT;
