-- ============================================================================
-- NOTIFICATION TRIGGERS - Beğeni, Yorum, Takip Bildirimleri
-- ============================================================================
-- Sorun: Kullanıcı bir şey yaptığında (beğeni, yorum, takip) notification gitmiyor.
-- Çözüm: SQL trigger ile notifications tablosuna otomatik kayıt ekle.

-- 1. Function: Post beğenildiğinde notification oluştur
CREATE OR REPLACE FUNCTION notify_post_like()
RETURNS TRIGGER AS $$
DECLARE
    post_owner_id UUID;
    liker_info JSONB;
BEGIN
    -- Post sahibini bul (kendini beğenirse notification gönderme)
    SELECT user_id INTO post_owner_id
    FROM public.posts
    WHERE id = NEW.post_id;

    -- Kendi postunu beğenirse notification gönderme
    IF post_owner_id IS NULL OR post_owner_id = NEW.user_id THEN
        RETURN NEW;
    END IF;

    -- Beğeneni bilgiyi al
    SELECT jsonb_build_object(
        'id', p.id,
        'username', p.username,
        'full_name', COALESCE(p.full_name, p.username),
        'avatar_url', p.avatar_url
    ) INTO liker_info
    FROM public.profiles p
    WHERE p.id = NEW.user_id;

    -- Notification ekle
    INSERT INTO public.notifications (
        user_id,
        type,
        title,
        content,
        actor_id,
        actor_name,
        actor_avatar,
        entity_id,
        is_read,
        created_at
    ) VALUES (
        post_owner_id,
        'post_like',
        (liker_info->>'full_name') || ' senin gönderini beğendi',
        'Beğeni',
        NEW.user_id,
        liker_info->>'full_name',
        liker_info->>'avatar_url',
        NEW.post_id,
        false,
        NOW()
    );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public;

-- 2. Function: Yorum yapıldığında notification oluştur
CREATE OR REPLACE FUNCTION notify_post_comment()
RETURNS TRIGGER AS $$
DECLARE
    post_owner_id UUID;
    commenter_info JSONB;
BEGIN
    -- Post sahibini bul
    SELECT user_id INTO post_owner_id
    FROM public.posts
    WHERE id = NEW.post_id;

    -- Kendi postuna yorum yaparsa notification gönderme
    IF post_owner_id IS NULL OR post_owner_id = NEW.user_id THEN
        RETURN NEW;
    END IF;

    -- Yorum yapanı bilgiyi al
    SELECT jsonb_build_object(
        'id', p.id,
        'username', p.username,
        'full_name', COALESCE(p.full_name, p.username),
        'avatar_url', p.avatar_url
    ) INTO commenter_info
    FROM public.profiles p
    WHERE p.id = NEW.user_id;

    -- Notification ekle
    INSERT INTO public.notifications (
        user_id,
        type,
        title,
        content,
        actor_id,
        actor_name,
        actor_avatar,
        entity_id,
        is_read,
        created_at
    ) VALUES (
        post_owner_id,
        'post_comment',
        (commenter_info->>'full_name') || ' gönderine yorum yaptı',
        SUBSTRING(NEW.content FROM 1 FOR 100),
        NEW.user_id,
        commenter_info->>'full_name',
        commenter_info->>'avatar_url',
        NEW.post_id,
        false,
        NOW()
    );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public;

-- 3. Function: Takip edildiğinde notification oluştur
CREATE OR REPLACE FUNCTION notify_new_follower()
RETURNS TRIGGER AS $$
DECLARE
    follower_info JSONB;
BEGIN
    -- Kendini takip edemez (guard clause)
    IF NEW.follower_id = NEW.following_id THEN
        RETURN NEW;
    END IF;

    -- Takip edenin bilgisini al
    SELECT jsonb_build_object(
        'id', p.id,
        'username', p.username,
        'full_name', COALESCE(p.full_name, p.username),
        'avatar_url', p.avatar_url
    ) INTO follower_info
    FROM public.profiles p
    WHERE p.id = NEW.follower_id;

    -- Notification ekle
    INSERT INTO public.notifications (
        user_id,
        type,
        title,
        content,
        actor_id,
        actor_name,
        actor_avatar,
        is_read,
        created_at
    ) VALUES (
        NEW.following_id,
        'new_follower',
        (follower_info->>'full_name') || ' seni takip etti',
        'Yeni takipçi',
        NEW.follower_id,
        follower_info->>'full_name',
        follower_info->>'avatar_url',
        false,
        NOW()
    );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public;

-- 4. Function: Mention bildirimi oluştur (comment_mentions tablosu için)
CREATE OR REPLACE FUNCTION notify_comment_mention()
RETURNS TRIGGER AS $$
DECLARE
    commenter_info JSONB;
    comment_content TEXT;
BEGIN
    -- Kendini mention ederse notification gönderme
    IF NEW.mentioned_user_id = NEW.mentioned_by_user_id THEN
        RETURN NEW;
    END IF;

    -- Yorum içeriğini al
    SELECT content INTO comment_content
    FROM public.post_comments
    WHERE id = NEW.comment_id;

    -- Yorum yapanın bilgisini al
    SELECT jsonb_build_object(
        'id', p.id,
        'username', p.username,
        'full_name', COALESCE(p.full_name, p.username),
        'avatar_url', p.avatar_url
    ) INTO commenter_info
    FROM public.profiles p
    WHERE p.id = NEW.mentioned_by_user_id;

    -- Notification ekle
    INSERT INTO public.notifications (
        user_id,
        type,
        title,
        content,
        actor_id,
        actor_name,
        actor_avatar,
        entity_id,
        is_read,
        created_at
    ) VALUES (
        NEW.mentioned_user_id,
        'comment_mention',
        (commenter_info->>'full_name') || ' seni bir yorumda bahsetti',
        COALESCE(SUBSTRING(comment_content FROM 1 FOR 100), 'Mention'),
        NEW.mentioned_by_user_id,
        commenter_info->>'full_name',
        commenter_info->>'avatar_url',
        NEW.comment_id,
        false,
        NOW()
    );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public;

-- 5. Function: Yeni sipariş bildirimi (mağaza sahibine)
CREATE OR REPLACE FUNCTION notify_new_order()
RETURNS TRIGGER AS $$
DECLARE
    shop_owner_id UUID;
    customer_info JSONB;
BEGIN
    -- Dükkan sahibini bul
    SELECT owner_id INTO shop_owner_id
    FROM public.shops
    WHERE id = NEW.shop_id;

    IF shop_owner_id IS NULL THEN
        RETURN NEW;
    END IF;

    -- Müşteri bilgisini al
    SELECT jsonb_build_object(
        'id', p.id,
        'username', p.username,
        'full_name', COALESCE(p.full_name, p.username),
        'avatar_url', p.avatar_url
    ) INTO customer_info
    FROM public.profiles p
    WHERE p.id = NEW.user_id;

    -- Notification ekle
    INSERT INTO public.notifications (
        user_id,
        type,
        title,
        content,
        actor_id,
        actor_name,
        actor_avatar,
        entity_id,
        is_read,
        created_at
    ) VALUES (
        shop_owner_id,
        'new_order',
        'Mağazana yeni bir sipariş var!',
        'Sipariş #' || SUBSTRING(NEW.id::text FROM 1 FOR 8),
        NEW.user_id,
        customer_info->>'full_name',
        customer_info->>'avatar_url',
        NEW.id,
        false,
        NOW()
    );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public;

-- 6. Function: Sipariş durum değişikliği bildirimi (müşteriye)
CREATE OR REPLACE FUNCTION notify_order_status_change()
RETURNS TRIGGER AS $$
DECLARE
    order_user_id UUID;
    status_text TEXT;
BEGIN
    -- Sadece status değiştiyse ve pending -> diğer durumlara geçişse
    IF (OLD.status = NEW.status) OR (NEW.status = 'pending') THEN
        RETURN NEW;
    END IF;

    -- Kullanıcı ID
    order_user_id := NEW.user_id;

    -- Durum metni
    CASE NEW.status
        WHEN 'confirmed' THEN status_text := 'Siparişin onaylandı ✓';
        WHEN 'preparing' THEN status_text := 'Siparişin hazırlanıyor 🍳';
        WHEN 'ready' THEN status_text := 'Siparişin hazır 📦';
        WHEN 'on_the_way' THEN status_text := 'Siparişin yolda 🚚';
        WHEN 'delivered' THEN status_text := 'Siparişin teslim edildi ✓';
        WHEN 'cancelled' THEN status_text := 'Sipariş iptal edildi ❌';
        ELSE status_text := 'Sipariş durumu güncellendi';
    END CASE;

    -- Notification ekle
    INSERT INTO public.notifications (
        user_id,
        type,
        title,
        content,
        entity_id,
        is_read,
        created_at
    ) VALUES (
        order_user_id,
        'order_status',
        status_text,
        'Sipariş #' || SUBSTRING(NEW.id::text FROM 1 FOR 8),
        NEW.id,
        false,
        NOW()
    );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public;

-- 7. Trigger'ları oluştur

-- Post likes trigger
DROP TRIGGER IF EXISTS notify_post_like_trigger ON public.post_likes;
CREATE TRIGGER notify_post_like_trigger
    AFTER INSERT ON public.post_likes
    FOR EACH ROW
    EXECUTE FUNCTION notify_post_like();

-- Post comments trigger
DROP TRIGGER IF EXISTS notify_post_comment_trigger ON public.post_comments;
CREATE TRIGGER notify_post_comment_trigger
    AFTER INSERT ON public.post_comments
    FOR EACH ROW
    EXECUTE FUNCTION notify_post_comment();

-- Follows trigger
DROP TRIGGER IF EXISTS notify_new_follower_trigger ON public.follows;
CREATE TRIGGER notify_new_follower_trigger
    AFTER INSERT ON public.follows
    FOR EACH ROW
    EXECUTE FUNCTION notify_new_follower();

-- Comment mention trigger (comment_mentions tablosu için)
DROP TRIGGER IF EXISTS notify_comment_mention_trigger ON public.comment_mentions;
CREATE TRIGGER notify_comment_mention_trigger
    AFTER INSERT ON public.comment_mentions
    FOR EACH ROW
    EXECUTE FUNCTION notify_comment_mention();

-- New order trigger
DROP TRIGGER IF EXISTS notify_new_order_trigger ON public.orders;
CREATE TRIGGER notify_new_order_trigger
    AFTER INSERT ON public.orders
    FOR EACH ROW
    EXECUTE FUNCTION notify_new_order();

-- Order status change trigger
DROP TRIGGER IF EXISTS notify_order_status_trigger ON public.orders;
CREATE TRIGGER notify_order_status_trigger
    AFTER UPDATE ON public.orders
    FOR EACH ROW
    WHEN (OLD.status IS DISTINCT FROM NEW.status)
    EXECUTE FUNCTION notify_order_status_change();

DO $$
BEGIN
    RAISE NOTICE 'All notification triggers created successfully! (likes, comments, follows, mentions, orders)';
END $$;
