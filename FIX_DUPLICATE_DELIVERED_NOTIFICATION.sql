-- ============================================================================
-- DUPLİKATE TESLİM EDİLDİ BİLDİRİMİNİ DÜZELT
-- ============================================================================
-- Problem: Sipariş teslim edildiğinde 3 aynı bildirim geliyor
-- Çözüm: Eski fonksiyonu tamamen kaldır, yeniden oluştur
-- ============================================================================

-- 1. Eski fonksiyonu kaldır
DROP FUNCTION IF EXISTS public.notify_order_status_change() CASCADE;

-- 2. Trigger'ı kaldır (yeni oluşturacağız)
DROP TRIGGER IF EXISTS notify_order_status_trigger ON public.orders;

-- 3. Yeni fonksiyon oluştur (delivered durumunda review_request)
CREATE OR REPLACE FUNCTION notify_order_status_change()
RETURNS TRIGGER AS $$
DECLARE
    order_user_id UUID;
    status_text TEXT;
    first_product_name TEXT;
    first_product_image TEXT;
BEGIN
    -- Sadece status değiştiyse ve pending -> diğer durumlara geçişse
    IF (OLD.status = NEW.status) OR (NEW.status = 'pending') THEN
        RETURN NEW;
    END IF;

    -- Kullanıcı ID
    order_user_id := NEW.user_id;

    -- DELIVERED durumunda değerlendirme bildirimi gönder (DEĞERLİNDİRME İÇİN TEK BİLDİRİM)
    IF NEW.status = 'delivered' THEN
        -- İlk ürünün adını al (varsa)
        SELECT product_name, product_image_url INTO first_product_name, first_product_image
        FROM order_items
        WHERE order_id = NEW.id
        LIMIT 1;
        
        -- Değerlendirme bildirimi ekle (review_request tipi)
        INSERT INTO public.notifications (
            user_id,
            type,
            title,
            content,
            entity_id,
            entity_image,
            is_read,
            created_at
        ) VALUES (
            order_user_id,
            'review_request',
            'Siparişiniz Teslim Edildi! 🎉',
            'Ürünü ve satıcıyı değerlendirmek için tıklayın',
            NEW.id,
            first_product_image,
            false,
            NOW()
        );
        
        RETURN NEW;
    END IF;

    -- Diğer durumlar için bildirimler
    CASE NEW.status
        WHEN 'confirmed' THEN status_text := 'Siparişin onaylandı ✓';
        WHEN 'preparing' THEN status_text := 'Siparişin hazırlanıyor 🍳';
        WHEN 'ready' THEN status_text := 'Siparişin hazır 📦';
        WHEN 'on_the_way' THEN status_text := 'Siparişin yolda 🚚';
        WHEN 'cancelled' THEN status_text := 'Sipariş iptal edildi ❌';
        ELSE RETURN NEW;
    END CASE;

    -- Notification ekle (delivered hariç)
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

-- 4. Trigger'ı oluştur
CREATE TRIGGER notify_order_status_trigger
    AFTER UPDATE ON public.orders
    FOR EACH ROW
    WHEN (OLD.status IS DISTINCT FROM NEW.status)
    EXECUTE FUNCTION notify_order_status_change();

-- 5. Eski duplicate bildirimleri temizle (isteğe bağlı)
-- DELETE FROM public.notifications WHERE type = 'order_status' AND title LIKE '%teslim%';

SELECT '✅ Teslim edildi bildirimi düzeltildi' as result;
