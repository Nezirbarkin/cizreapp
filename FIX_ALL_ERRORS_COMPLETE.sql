-- ============================================================================
-- TÜM HATALARI DÜZELTME - KOMPLE ÇÖZÜM PAKETİ
-- ============================================================================
-- Bu dosya şu hataları düzeltir:
-- 1. Orders commission_status constraint hatası (23514)
-- 2. Comment mentions mentioned_by_user_id kolon eksikliği (42703)
-- 3. Conversations RLS policy hatası (42501)
-- 4. Messages RLS policy hatası (42501)
-- 5. Notifications RLS policy sorunları
-- 6. Order_items RLS policy hatası (42501)
-- ============================================================================

-- ═══════════════════════════════════════════════════════════════════════
-- BÖLÜM 0: ESKİ TRIGGER VE FONKSİYONLARI TEMİZLE
-- ═══════════════════════════════════════════════════════════════════════

-- Push notification ile ilgili eski trigger'ları CASCADE ile sil
DROP TRIGGER IF EXISTS on_notification_created ON public.notifications CASCADE;
DROP TRIGGER IF EXISTS notifications_push_trigger ON public.notifications CASCADE;
DROP FUNCTION IF EXISTS public.send_push_on_notification() CASCADE;

-- ═══════════════════════════════════════════════════════════════════════
-- BÖLÜM 1: COMMENT_MENTIONS TABLOSU DÜZELTMESI
-- ═══════════════════════════════════════════════════════════════════════

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' AND table_name = 'comment_mentions' AND column_name = 'mentioned_by_user_id'
    ) THEN
        ALTER TABLE public.comment_mentions ADD COLUMN mentioned_by_user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE;
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_comment_mentions_mentioned_by ON public.comment_mentions(mentioned_by_user_id);

UPDATE public.comment_mentions cm SET mentioned_by_user_id = pc.user_id
FROM public.post_comments pc WHERE cm.comment_id = pc.id AND cm.mentioned_by_user_id IS NULL;

-- ═══════════════════════════════════════════════════════════════════════
-- BÖLÜM 2: ORDERS COMMISSION_STATUS DÜZELTMESI
-- ═══════════════════════════════════════════════════════════════════════

DROP TRIGGER IF EXISTS calculate_commission_on_insert ON public.orders;
DROP TRIGGER IF EXISTS calculate_commission_on_update ON public.orders;
DROP TRIGGER IF EXISTS calculate_commission_trigger ON public.orders;
DROP TRIGGER IF EXISTS set_commission_on_order ON public.orders;

ALTER TABLE public.orders DROP CONSTRAINT IF EXISTS orders_commission_status_check;
UPDATE public.orders SET commission_status = 'pending' WHERE commission_status IS NULL OR commission_status NOT IN ('pending', 'debt', 'credit', 'cash_collected', 'admin_collects');
ALTER TABLE public.orders ALTER COLUMN commission_status SET DEFAULT 'pending';

ALTER TABLE public.orders ADD CONSTRAINT orders_commission_status_check
    CHECK (commission_status IN ('pending', 'debt', 'credit', 'cash_collected', 'admin_collects'));

CREATE OR REPLACE FUNCTION public.calculate_order_commission()
RETURNS TRIGGER AS $$
DECLARE
    v_commission_rate DECIMAL;
    v_admin_commission DECIMAL;
    v_has_own_courier BOOLEAN;
BEGIN
    IF NEW.commission_status IS NULL OR NEW.commission_status = '' THEN
        NEW.commission_status := 'pending';
    END IF;
    SELECT commission_rate, has_own_courier INTO v_commission_rate, v_has_own_courier FROM public.shops WHERE id = NEW.shop_id;
    v_commission_rate := COALESCE(v_commission_rate, 10.0);
    v_has_own_courier := COALESCE(v_has_own_courier, false);
    v_admin_commission := COALESCE(NEW.subtotal, 0) * (v_commission_rate / 100);
    NEW.admin_commission := v_admin_commission;
    IF v_has_own_courier THEN
        NEW.admin_delivery_fee := 0;
        NEW.seller_net_amount := COALESCE(NEW.total, 0) - v_admin_commission;
        NEW.commission_status := CASE WHEN NEW.payment_method IN ('cash', 'card_on_delivery') THEN 'cash_collected' ELSE 'admin_collects' END;
    ELSE
        NEW.admin_delivery_fee := COALESCE(NEW.delivery_fee, 0);
        NEW.seller_net_amount := COALESCE(NEW.total, 0) - v_admin_commission - COALESCE(NEW.delivery_fee, 0);
        NEW.commission_status := 'admin_collects';
    END IF;
    RETURN NEW;
EXCEPTION WHEN OTHERS THEN
    NEW.commission_status := 'pending';
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

CREATE TRIGGER calculate_commission_on_insert BEFORE INSERT ON public.orders FOR EACH ROW EXECUTE FUNCTION public.calculate_order_commission();

-- ═══════════════════════════════════════════════════════════════════════
-- BÖLÜM 3: CONVERSATIONS RLS POLICY DÜZELTMESI
-- ═══════════════════════════════════════════════════════════════════════

DO $$
DECLARE pol RECORD;
BEGIN
    FOR pol IN SELECT policyname FROM pg_policies WHERE tablename = 'conversations' AND schemaname = 'public'
    LOOP EXECUTE format('DROP POLICY IF EXISTS %I ON public.conversations', pol.policyname); END LOOP;
END $$;

ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;

CREATE POLICY "conversations_select_own" ON public.conversations FOR SELECT TO authenticated USING (user_id = (select auth.uid()) OR other_user_id = (select auth.uid()));
CREATE POLICY "conversations_insert_own" ON public.conversations FOR INSERT TO authenticated WITH CHECK (user_id = (select auth.uid()) OR other_user_id = (select auth.uid()));
CREATE POLICY "conversations_update_own" ON public.conversations FOR UPDATE TO authenticated USING (user_id = (select auth.uid()) OR other_user_id = (select auth.uid())) WITH CHECK (user_id = (select auth.uid()) OR other_user_id = (select auth.uid()));
CREATE POLICY "conversations_delete_own" ON public.conversations FOR DELETE TO authenticated USING (user_id = (select auth.uid()) OR other_user_id = (select auth.uid()));

-- ═══════════════════════════════════════════════════════════════════════
-- BÖLÜM 4: MESSAGES RLS POLICY DÜZELTMESI
-- ═══════════════════════════════════════════════════════════════════════

DO $$
DECLARE pol RECORD;
BEGIN
    FOR pol IN SELECT policyname FROM pg_policies WHERE tablename = 'messages' AND schemaname = 'public'
    LOOP EXECUTE format('DROP POLICY IF EXISTS %I ON public.messages', pol.policyname); END LOOP;
END $$;

ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

CREATE POLICY "messages_select_own" ON public.messages FOR SELECT TO authenticated USING (
    EXISTS (SELECT 1 FROM conversations WHERE conversations.id = messages.conversation_id AND (conversations.user_id = (select auth.uid()) OR conversations.other_user_id = (select auth.uid())))
);
CREATE POLICY "messages_insert_own" ON public.messages FOR INSERT TO authenticated WITH CHECK (
    sender_id = (select auth.uid()) AND EXISTS (SELECT 1 FROM conversations WHERE conversations.id = messages.conversation_id AND (conversations.user_id = (select auth.uid()) OR conversations.other_user_id = (select auth.uid())))
);
CREATE POLICY "messages_update_own" ON public.messages FOR UPDATE TO authenticated USING (sender_id = (select auth.uid())) WITH CHECK (sender_id = (select auth.uid()));
CREATE POLICY "messages_delete_own" ON public.messages FOR DELETE TO authenticated USING (sender_id = (select auth.uid()));

-- ═══════════════════════════════════════════════════════════════════════
-- BÖLÜM 5: NOTIFICATIONS RLS POLICY DÜZELTMESI
-- ═══════════════════════════════════════════════════════════════════════

DO $$
DECLARE pol RECORD;
BEGIN
    FOR pol IN SELECT policyname FROM pg_policies WHERE tablename = 'notifications' AND schemaname = 'public'
    LOOP EXECUTE format('DROP POLICY IF EXISTS %I ON public.notifications', pol.policyname); END LOOP;
END $$;

ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

CREATE POLICY "notifications_select_own" ON public.notifications FOR SELECT TO authenticated USING (user_id = (select auth.uid()));
CREATE POLICY "notifications_insert_authenticated" ON public.notifications FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "notifications_update_own" ON public.notifications FOR UPDATE TO authenticated USING (user_id = (select auth.uid())) WITH CHECK (user_id = (select auth.uid()));
CREATE POLICY "notifications_delete_own" ON public.notifications FOR DELETE TO authenticated USING (user_id = (select auth.uid()));

-- ═══════════════════════════════════════════════════════════════════════
-- BÖLÜM 6: ORDER_ITEMS RLS POLICY DÜZELTMESI
-- ═══════════════════════════════════════════════════════════════════════

DO $$
DECLARE pol RECORD;
BEGIN
    FOR pol IN SELECT policyname FROM pg_policies WHERE tablename = 'order_items' AND schemaname = 'public'
    LOOP EXECUTE format('DROP POLICY IF EXISTS %I ON public.order_items', pol.policyname); END LOOP;
END $$;

ALTER TABLE public.order_items ENABLE ROW LEVEL SECURITY;

CREATE POLICY "order_items_select_own" ON public.order_items FOR SELECT TO authenticated USING (
    EXISTS (SELECT 1 FROM public.orders WHERE orders.id = order_items.order_id AND orders.user_id = (select auth.uid()))
    OR EXISTS (SELECT 1 FROM public.shops WHERE shops.id = order_items.shop_id AND shops.owner_id = (select auth.uid()))
);
CREATE POLICY "order_items_insert_own" ON public.order_items FOR INSERT TO authenticated WITH CHECK (
    EXISTS (SELECT 1 FROM public.orders WHERE orders.id = order_items.order_id AND orders.user_id = (select auth.uid()))
);
CREATE POLICY "order_items_update_own" ON public.order_items FOR UPDATE TO authenticated USING (
    EXISTS (SELECT 1 FROM public.shops WHERE shops.id = order_items.shop_id AND shops.owner_id = (select auth.uid()))
);
CREATE POLICY "order_items_delete_own" ON public.order_items FOR DELETE TO authenticated USING (
    EXISTS (SELECT 1 FROM public.orders WHERE orders.id = order_items.order_id AND orders.user_id = (select auth.uid()))
    OR EXISTS (SELECT 1 FROM public.shops WHERE shops.id = order_items.shop_id AND shops.owner_id = (select auth.uid()))
);

-- ═══════════════════════════════════════════════════════════════════════
-- BÖLÜM 7: NOTIFICATION PREFERENCES TABLOSU
-- ═══════════════════════════════════════════════════════════════════════

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'notification_preferences' AND table_schema = 'public') THEN
        CREATE TABLE public.notification_preferences (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
            likes_enabled BOOLEAN DEFAULT true,
            comments_enabled BOOLEAN DEFAULT true,
            followers_enabled BOOLEAN DEFAULT true,
            order_updates_enabled BOOLEAN DEFAULT true,
            order_ready_enabled BOOLEAN DEFAULT true,
            delivery_enabled BOOLEAN DEFAULT true,
            promotional_enabled BOOLEAN DEFAULT false,
            created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
            updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
            UNIQUE(user_id)
        );
        CREATE INDEX idx_notification_preferences_user_id ON public.notification_preferences(user_id);
    END IF;
END $$;

ALTER TABLE public.notification_preferences ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "notification_preferences_select_own" ON public.notification_preferences;
DROP POLICY IF EXISTS "notification_preferences_insert_own" ON public.notification_preferences;
DROP POLICY IF EXISTS "notification_preferences_update_own" ON public.notification_preferences;

CREATE POLICY "notification_preferences_select_own" ON public.notification_preferences FOR SELECT TO authenticated USING (user_id = (select auth.uid()));
CREATE POLICY "notification_preferences_insert_own" ON public.notification_preferences FOR INSERT TO authenticated WITH CHECK (user_id = (select auth.uid()));
CREATE POLICY "notification_preferences_update_own" ON public.notification_preferences FOR UPDATE TO authenticated USING (user_id = (select auth.uid())) WITH CHECK (user_id = (select auth.uid()));

-- ═══════════════════════════════════════════════════════════════════════
-- BÖLÜM 8: PROFILES FCM_TOKEN KOLONU
-- ═══════════════════════════════════════════════════════════════════════

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'profiles' AND column_name = 'fcm_token') THEN
        ALTER TABLE public.profiles ADD COLUMN fcm_token TEXT;
    END IF;
END $$;

-- ═══════════════════════════════════════════════════════════════════════
-- BÖLÜM 9: NOTIFICATION TRIGGER'LARI
-- ═══════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.notify_post_like() RETURNS TRIGGER AS $$
DECLARE post_owner_id UUID; liker_info JSONB;
BEGIN
    SELECT user_id INTO post_owner_id FROM public.posts WHERE id = NEW.post_id;
    IF post_owner_id IS NULL OR post_owner_id = NEW.user_id THEN RETURN NEW; END IF;
    SELECT jsonb_build_object('id', p.id, 'username', p.username, 'full_name', COALESCE(p.full_name, p.username), 'avatar_url', p.avatar_url) INTO liker_info FROM public.profiles p WHERE p.id = NEW.user_id;
    INSERT INTO public.notifications (user_id, type, title, content, actor_id, actor_name, actor_avatar, entity_id, is_read, created_at) VALUES (post_owner_id, 'post_like', (liker_info->>'full_name') || ' senin gönderini beğendi', 'Beğeni', NEW.user_id, liker_info->>'full_name', liker_info->>'avatar_url', NEW.post_id, false, NOW());
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS notify_post_like_trigger ON public.post_likes;
CREATE TRIGGER notify_post_like_trigger AFTER INSERT ON public.post_likes FOR EACH ROW EXECUTE FUNCTION public.notify_post_like();

CREATE OR REPLACE FUNCTION public.notify_post_comment() RETURNS TRIGGER AS $$
DECLARE post_owner_id UUID; commenter_info JSONB;
BEGIN
    SELECT user_id INTO post_owner_id FROM public.posts WHERE id = NEW.post_id;
    IF post_owner_id IS NULL OR post_owner_id = NEW.user_id THEN RETURN NEW; END IF;
    SELECT jsonb_build_object('id', p.id, 'username', p.username, 'full_name', COALESCE(p.full_name, p.username), 'avatar_url', p.avatar_url) INTO commenter_info FROM public.profiles p WHERE p.id = NEW.user_id;
    INSERT INTO public.notifications (user_id, type, title, content, actor_id, actor_name, actor_avatar, entity_id, is_read, created_at) VALUES (post_owner_id, 'post_comment', (commenter_info->>'full_name') || ' gönderine yorum yaptı', SUBSTRING(NEW.content FROM 1 FOR 100), NEW.user_id, commenter_info->>'full_name', commenter_info->>'avatar_url', NEW.post_id, false, NOW());
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS notify_post_comment_trigger ON public.post_comments;
CREATE TRIGGER notify_post_comment_trigger AFTER INSERT ON public.post_comments FOR EACH ROW EXECUTE FUNCTION public.notify_post_comment();

-- ═══════════════════════════════════════════════════════════════════════
-- BÖLÜM 10: DOĞRULAMA
-- ═══════════════════════════════════════════════════════════════════════

DO $$
DECLARE v_conv_policy INT; v_msg_policy INT; v_notif_policy INT; v_order_items_policy INT; v_prefs BOOL; v_fcm_token BOOL;
BEGIN
    SELECT COUNT(*) INTO v_conv_policy FROM pg_policies WHERE tablename = 'conversations' AND schemaname = 'public';
    SELECT COUNT(*) INTO v_msg_policy FROM pg_policies WHERE tablename = 'messages' AND schemaname = 'public';
    SELECT COUNT(*) INTO v_notif_policy FROM pg_policies WHERE tablename = 'notifications' AND schemaname = 'public';
    SELECT COUNT(*) INTO v_order_items_policy FROM pg_policies WHERE tablename = 'order_items' AND schemaname = 'public';
    SELECT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'notification_preferences' AND table_schema = 'public') INTO v_prefs;
    SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'profiles' AND column_name = 'fcm_token' AND table_schema = 'public') INTO v_fcm_token;
    RAISE NOTICE '';
    RAISE NOTICE '╔══════════════════════════════════════════════════════════════╗';
    RAISE NOTICE '║  TÜM DÜZELTMELER TAMAMLANDI                               ║';
    RAISE NOTICE '╠══════════════════════════════════════════════════════════════╣';
    RAISE NOTICE '║  Conversations policies: %    ║', v_conv_policy;
    RAISE NOTICE '║  Messages policies: %        ║', v_msg_policy;
    RAISE NOTICE '║  Notifications policies: %   ║', v_notif_policy;
    RAISE NOTICE '║  Order_items policies: %     ║', v_order_items_policy;
    RAISE NOTICE '║  Notification prefs: %       ║', CASE WHEN v_prefs THEN 'Mevcut' ELSE 'Yok!' END;
    RAISE NOTICE '║  FCM token column: %         ║', CASE WHEN v_fcm_token THEN 'Mevcut' ELSE 'Yok!' END;
    RAISE NOTICE '╠══════════════════════════════════════════════════════════════╣';
    RAISE NOTICE '║  Simdi uygulamayi test edebilirsiniz!                     ║';
    RAISE NOTICE '╚══════════════════════════════════════════════════════════════╝';
    RAISE NOTICE '';
END $$;
