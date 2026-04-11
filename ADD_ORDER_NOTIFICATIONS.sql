-- ============================================================================
-- CizreApp - Sipariş Bildirimlerini Ekle
-- ============================================================================
-- Bu SQL, sipariş durum değişikliklerinde bildirim gönderir.
-- 
-- Kullanıcılar:
-- 1. Müşteri -> Sipariş durum değişiklikleri (onaylandı, yolda, teslim edildi vb.)
-- 2. Mağaza sahibi -> Yeni sipariş bildirimleri
-- ============================================================================

-- 1. Mevcut trigger'ları temizle (varsa)
DROP TRIGGER IF EXISTS notify_order_status_trigger ON public.orders;
DROP TRIGGER IF EXISTS notify_new_order_trigger ON public.orders;

-- 2. Function: Sipariş durum değişikliği bildirimi (müşteriye)
CREATE OR REPLACE FUNCTION notify_order_status_change()
RETURNS TRIGGER AS $$
DECLARE
    status_text TEXT;
    shop_name TEXT;
BEGIN
    -- Sadece önemli durumlarda bildirim gönder (müşteri rahatsız olmasın)
    -- confirmed, on_the_way, delivered, cancelled
    CASE NEW.status
        WHEN 'confirmed' THEN status_text := 'Siparişiniz onaylandı';
        WHEN 'on_the_way' THEN status_text := 'Siparişiniz yolda';
        WHEN 'delivered' THEN status_text := 'Siparişiniz teslim edildi';
        WHEN 'cancelled' THEN status_text := 'Siparişiniz iptal edildi';
        ELSE RETURN NEW; -- Diğer durumlar için bildirim gönderme
    END CASE;

    -- Mağaza adını al
    SELECT name INTO shop_name
    FROM public.shops
    WHERE id = NEW.shop_id;

    -- Bildirim ekle (müşteriye)
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
        NEW.user_id,
        'order_status',
        COALESCE(shop_name, 'Mağaza') || ' - ' || status_text,
        'Sipariş #' || substring(NEW.id::text, 1, 8) || ' durumu: ' || NEW.status,
        NEW.shop_id,
        COALESCE(shop_name, 'Mağaza'),
        NULL,
        NEW.id,
        false,
        NOW()
    );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- 3. Function: Yeni sipariş bildirimi (mağaza sahibine)
CREATE OR REPLACE FUNCTION notify_new_order()
RETURNS TRIGGER AS $$
DECLARE
    customer_name TEXT;
    customer_avatar TEXT;
BEGIN
    -- Müşteri bilgilerini al
    SELECT COALESCE(full_name, username, 'Müşteri'), avatar_url
    INTO customer_name, customer_avatar
    FROM public.profiles
    WHERE id = NEW.user_id;

    -- Bildirim ekle (mağaza sahibine)
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
        (SELECT owner_id FROM public.shops WHERE id = NEW.shop_id),
        'new_order',
        'Yeni sipariş aldınız!',
        customer_name || ' yeni bir sipariş oluşturdu',
        NEW.user_id,
        customer_name,
        customer_avatar,
        NEW.id,
        false,
        NOW()
    );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- 4. Trigger'ları oluştur
CREATE TRIGGER notify_order_status_trigger
    AFTER UPDATE ON public.orders
    FOR EACH ROW
    WHEN (OLD.status IS DISTINCT FROM NEW.status)
    EXECUTE FUNCTION notify_order_status_change();

CREATE TRIGGER notify_new_order_trigger
    AFTER INSERT ON public.orders
    FOR EACH ROW
    EXECUTE FUNCTION notify_new_order();

-- ============================================================================
-- AÇIKLAMA
-- ============================================================================
-- Bildirim tipleri:
-- - 'order_status': Müşteriye sipariş durumu değişikliği bildirimi
--   Sadece: confirmed, on_the_way, delivered, cancelled
-- - 'new_order': Mağaza sahibine yeni sipariş bildirimi
--
-- Müşteriye bildirim giden durumlar:
-- - confirmed: Onaylandı
-- - on_the_way: Yolda
-- - delivered: Teslim edildi
-- - cancelled: İptal edildi
--
-- Bildirim gönderilmeyen durumlar (gereksiz bildirim olmasın):
-- - pending, preparing, ready
-- ============================================================================
