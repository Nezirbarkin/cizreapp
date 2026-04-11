-- ============================================================================
-- SİPARİŞ DURUM BİLDİRİMİ + DEĞERLENDİRME TRIGGER'LARI
-- ============================================================================
-- Müşteriye: onaylandı, yolda, teslim edildi bildirimleri
-- Teslim edildiğinde: değerlendirme bildirimi
-- ============================================================================

-- 1. notify_order_status_change fonksiyonunu oluştur/güncelle
CREATE OR REPLACE FUNCTION notify_order_status_change()
RETURNS TRIGGER AS $$
DECLARE
    customer_id UUID;
    shop_info JSONB;
    status_text TEXT;
    notification_type TEXT;
BEGIN
    -- Sadece status değiştiyse ve pending'den diğer durumlara geçişse
    IF (OLD.status = NEW.status) OR (NEW.status = 'pending') THEN
        RETURN NEW;
    END IF;

    customer_id := NEW.user_id;

    -- Mağaza bilgisini al
    SELECT jsonb_build_object(
        'name', s.name,
        'logo_url', s.logo_url
    ) INTO shop_info
    FROM public.shops s
    WHERE s.id = NEW.shop_id;

    -- Durum metni ve tipi
    CASE NEW.status
        WHEN 'confirmed' THEN 
            status_text := 'Siparişin onaylandı ✓';
            notification_type := 'order_status';
        WHEN 'preparing' THEN
            -- Hazırlanıyor bildirimi gönderme
            RETURN NEW;
        WHEN 'ready' THEN
            -- Hazır bildirimi gönderme
            RETURN NEW;
        WHEN 'on_the_way' THEN 
            status_text := 'Siparişin yolda 🚚';
            notification_type := 'order_status';
        WHEN 'delivered' THEN 
            status_text := 'Siparişin teslim edildi ✓';
            notification_type := 'review_request';
        WHEN 'cancelled' THEN 
            status_text := 'Sipariş iptal edildi ❌';
            notification_type := 'order_status';
        ELSE 
            status_text := 'Sipariş durumu güncellendi';
            notification_type := 'order_status';
    END CASE;

    -- Teslim edildiğinde değerlendirme bildirimi
    IF NEW.status = 'delivered' THEN
        -- Değerlendirme bildirimi
        INSERT INTO public.notifications (
            user_id, type, title, content, entity_id, is_read, created_at
        ) VALUES (
            customer_id,
            'review_request',
            shop_info->>'name' || ' siparişiniz teslim edildi',
            'Satıcıyı ve ürünü değerlendirin',
            NEW.id,
            false,
            NOW()
        );
    ELSE
        -- Normal durum bildirimi
        INSERT INTO public.notifications (
            user_id, type, title, content, entity_id, is_read, created_at
        ) VALUES (
            customer_id,
            notification_type,
            status_text,
            'Sipariş #' || SUBSTRING(NEW.id::text FROM 1 FOR 8),
            NEW.id,
            false,
            NOW()
        );
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public;

-- 2. Trigger'ı oluştur
DROP TRIGGER IF EXISTS notify_order_status_trigger ON public.orders;
CREATE TRIGGER notify_order_status_trigger
    AFTER UPDATE ON public.orders
    FOR EACH ROW
    WHEN (OLD.status IS DISTINCT FROM NEW.status)
    EXECUTE FUNCTION notify_order_status_change();

-- 3. Kontrol
SELECT 
    '✅ Sipariş durum bildirimi trigger oluşturuldu!' AS durum,
    trigger_name, event_manipulation
FROM information_schema.triggers
WHERE event_object_table = 'orders'
AND trigger_name = 'notify_order_status_trigger';
