-- ============================================================================
-- YENİ SİPARİŞ BİLDİRİMİ TRİGGER'I OLUŞTUR
-- ============================================================================
-- orders tablosunda notify_new_order trigger'ı eksik
-- Bu SQL'i Supabase Dashboard > SQL Editor'de çalıştırın
-- ============================================================================

-- 1. notify_new_order fonksiyonunu oluştur (veya güncelle)
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

    -- Notification ekle (bu otomatik olarak push trigger'ı tetikleyecek)
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

-- 2. Trigger'ı oluştur
DROP TRIGGER IF EXISTS notify_new_order_trigger ON public.orders;
CREATE TRIGGER notify_new_order_trigger
    AFTER INSERT ON public.orders
    FOR EACH ROW
    EXECUTE FUNCTION notify_new_order();

-- 3. Kontrol
SELECT 
    'Trigger başarıyla oluşturuldu!' AS durum,
    trigger_name, 
    event_manipulation, 
    action_statement
FROM information_schema.triggers
WHERE event_object_table = 'orders'
AND trigger_name = 'notify_new_order_trigger';
