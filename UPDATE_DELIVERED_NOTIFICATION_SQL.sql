-- ============================================================================
-- FIX: Sadece teslim edildi bildirimini değerlendirme isteği olarak değiştir
-- ============================================================================
-- Problem: "Siparişin teslim edildi ✓" yerine değerlendirme bildirimi gelsin
-- Çözüm: Trigger fonksiyonunu güncelle, sadece delivered durumunda değiştir
-- ============================================================================

-- Trigger fonksiyonunu güncelle
CREATE OR REPLACE FUNCTION notify_order_status_change()
RETURNS TRIGGER AS $$
DECLARE
    order_user_id UUID;
    status_text TEXT;
    first_product_name TEXT;
BEGIN
    -- Sadece status değiştiyse ve pending -> diğer durumlara geçişse
    IF (OLD.status = NEW.status) OR (NEW.status = 'pending') THEN
        RETURN NEW;
    END IF;

    -- Kullanıcı ID
    order_user_id := NEW.user_id;

    -- DELIVERED durumunda değerlendirme bildirimi gönder
    IF NEW.status = 'delivered' THEN
        -- İlk ürünün adını al (varsa)
        SELECT product_name INTO first_product_name
        FROM order_items
        WHERE order_id = NEW.id
        LIMIT 1;
        
        -- Değerlendirme bildirimi ekle
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
            COALESCE(first_product_name || ' - ', '') || 'Ürünü ve satıcıyı değerlendirmek için tıklayın',
            NEW.id,
            (SELECT product_image_url FROM order_items WHERE order_id = NEW.id LIMIT 1),
            false,
            NOW()
        );
        
        RETURN NEW;
    END IF;

    -- Diğer durumlar için eski bildirimler devam etsin
    -- Durum metni
    CASE NEW.status
        WHEN 'confirmed' THEN status_text := 'Siparişin onaylandı ✓';
        WHEN 'preparing' THEN status_text := 'Siparişin hazırlanıyor 🍳';
        WHEN 'ready' THEN status_text := 'Siparişin hazır 📦';
        WHEN 'on_the_way' THEN status_text := 'Siparişin yolda 🚚';
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

-- ============================================================================
-- SONUÇ:
-- - confirmed: "Siparişin onaylandı ✓" (aynı)
-- - preparing: "Siparişin hazırlanıyor 🍳" (aynı)
-- - ready: "Siparişin hazır 📦" (aynı)
-- - on_the_way: "Siparişin yolda 🚚" (aynı)
-- - cancelled: "Sipariş iptal edildi ❌" (aynı)
-- - delivered: "Siparişiniz Teslim Edildi! 🎉" - "Ürünü ve satıcıyı değerlendirmek için tıklayın" ✨ YENİ!
-- ============================================================================
