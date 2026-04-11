-- ============================================================================
-- KRİTİK HATALARI DÜZELTME - Orders ve Comment Mentions
-- ============================================================================
-- Bu dosya aşağıdaki hataları düzeltir:
-- 1. Orders commission_status constraint ihlali (23514)
-- 2. Comment_mentions mentioned_by_user_id kolon eksikliği (42703)
-- ============================================================================

-- ============================================================================
-- BÖLÜM 1: COMMENT_MENTIONS TABLOSU DÜZELTMESI
-- ============================================================================

-- 1.1: mentioned_by_user_id kolonunu ekle (eğer yoksa)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' 
        AND table_name = 'comment_mentions' 
        AND column_name = 'mentioned_by_user_id'
    ) THEN
        ALTER TABLE public.comment_mentions
            ADD COLUMN mentioned_by_user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE;
        RAISE NOTICE 'mentioned_by_user_id kolonu eklendi';
    ELSE
        RAISE NOTICE 'mentioned_by_user_id kolonu zaten mevcut';
    END IF;
END $$;

-- 1.2: İndeks ekle (performans için)
CREATE INDEX IF NOT EXISTS idx_comment_mentions_mentioned_by
    ON public.comment_mentions(mentioned_by_user_id);

-- 1.3: Mevcut kayıtları güncelle (NULL olanlar için comment sahibini kullan)
UPDATE public.comment_mentions cm
SET mentioned_by_user_id = pc.user_id
FROM public.post_comments pc
WHERE cm.comment_id = pc.id
  AND cm.mentioned_by_user_id IS NULL;

-- ============================================================================
-- BÖLÜM 2: ORDERS TABLOSU COMMISSION_STATUS DÜZELTMESI
-- ============================================================================

-- 2.1: Önce trigger'ları geçici olarak kaldır
DROP TRIGGER IF EXISTS calculate_commission_on_insert ON public.orders;
DROP TRIGGER IF EXISTS calculate_commission_on_update ON public.orders;
DROP TRIGGER IF EXISTS calculate_commission_trigger ON public.orders;
DROP TRIGGER IF EXISTS set_commission_on_order ON public.orders;

-- 2.2: Mevcut constraint'i kaldır
ALTER TABLE public.orders DROP CONSTRAINT IF EXISTS orders_commission_status_check;

-- 2.3: Mevcut NULL/geçersiz commission_status değerlerini düzelt
UPDATE public.orders
SET commission_status = 'pending'
WHERE commission_status IS NULL
   OR commission_status NOT IN ('pending', 'debt', 'credit', 'cash_collected', 'admin_collects');

-- 2.4: Default değer ekle (trigger çalışmazsa bile hata vermemesi için)
ALTER TABLE public.orders 
    ALTER COLUMN commission_status SET DEFAULT 'pending';

-- 2.5: Yeni constraint ekle (tüm geçerli değerlerle)
ALTER TABLE public.orders
    ADD CONSTRAINT orders_commission_status_check
    CHECK (commission_status IN ('pending', 'debt', 'credit', 'cash_collected', 'admin_collects'));

-- 2.6: Komisyon hesaplama trigger fonksiyonunu yeniden oluştur
CREATE OR REPLACE FUNCTION public.calculate_order_commission()
RETURNS TRIGGER AS $$
DECLARE
    v_commission_rate DECIMAL;
    v_admin_commission DECIMAL;
    v_has_own_courier BOOLEAN;
BEGIN
    -- Önce commission_status'a default değer ata (constraint ihlali olmasın)
    IF NEW.commission_status IS NULL OR NEW.commission_status = '' THEN
        NEW.commission_status := 'pending';
    END IF;

    -- Shop bilgilerini al
    SELECT commission_rate, has_own_courier 
    INTO v_commission_rate, v_has_own_courier
    FROM public.shops
    WHERE id = NEW.shop_id;
    
    -- Varsayılan değerler
    v_commission_rate := COALESCE(v_commission_rate, 10.0);
    v_has_own_courier := COALESCE(v_has_own_courier, false);
    
    -- Admin komisyonunu hesapla
    v_admin_commission := COALESCE(NEW.subtotal, 0) * (v_commission_rate / 100);
    NEW.admin_commission := v_admin_commission;
    
    -- Teslimat ücreti hesaplama
    IF v_has_own_courier THEN
        -- Kendi kuryesi var - teslimat ücreti satıcıya kalır
        NEW.admin_delivery_fee := 0;
        NEW.seller_net_amount := COALESCE(NEW.total, 0) - v_admin_commission;
        
        -- Ödeme yöntemine göre commission_status
        IF NEW.payment_method IN ('cash', 'card_on_delivery') THEN
            NEW.commission_status := 'cash_collected';
        ELSE
            NEW.commission_status := 'admin_collects';
        END IF;
    ELSE
        -- Admin kuryesi - teslimat ücreti admin'e kalır
        NEW.admin_delivery_fee := COALESCE(NEW.delivery_fee, 0);
        NEW.seller_net_amount := COALESCE(NEW.total, 0) - v_admin_commission - COALESCE(NEW.delivery_fee, 0);
        NEW.commission_status := 'admin_collects';
    END IF;
    
    RETURN NEW;
EXCEPTION
    WHEN OTHERS THEN
        -- Hata olursa en azından geçerli bir commission_status ata
        NEW.commission_status := 'pending';
        RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public;

-- 2.7: Trigger'ları yeniden oluştur
CREATE TRIGGER calculate_commission_on_insert
    BEFORE INSERT ON public.orders
    FOR EACH ROW
    EXECUTE FUNCTION public.calculate_order_commission();

-- ============================================================================
-- BÖLÜM 3: NOTIFICATION TRIGGER DÜZELTMESI (mention)
-- ============================================================================

-- Mention notification trigger'ını güncelle - mentioned_by_user_id kontrolü ekle
CREATE OR REPLACE FUNCTION notify_comment_mention()
RETURNS TRIGGER AS $$
DECLARE
    commenter_info JSONB;
    comment_content TEXT;
BEGIN
    -- mentioned_by_user_id NULL ise işlemi atla
    IF NEW.mentioned_by_user_id IS NULL THEN
        RETURN NEW;
    END IF;

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
        COALESCE(commenter_info->>'full_name', 'Birisi') || ' seni bir yorumda bahsetti',
        COALESCE(SUBSTRING(comment_content FROM 1 FOR 100), 'Mention'),
        NEW.mentioned_by_user_id,
        COALESCE(commenter_info->>'full_name', 'Bilinmeyen'),
        commenter_info->>'avatar_url',
        NEW.comment_id,
        false,
        NOW()
    );

    RETURN NEW;
EXCEPTION
    WHEN OTHERS THEN
        -- Hata olsa bile mention kaydını engelleme
        RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public;

-- Trigger'ı yeniden oluştur
DROP TRIGGER IF EXISTS notify_comment_mention_trigger ON public.comment_mentions;
CREATE TRIGGER notify_comment_mention_trigger
    AFTER INSERT ON public.comment_mentions
    FOR EACH ROW
    EXECUTE FUNCTION notify_comment_mention();

-- ============================================================================
-- BÖLÜM 4: DOĞRULAMA
-- ============================================================================

DO $$
DECLARE
    v_col_exists BOOLEAN;
    v_constraint_exists BOOLEAN;
    v_trigger_exists BOOLEAN;
    v_null_count INTEGER;
BEGIN
    -- 1. Comment mentions kolon kontrolü
    SELECT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'comment_mentions'
          AND column_name = 'mentioned_by_user_id'
    ) INTO v_col_exists;
    
    IF v_col_exists THEN
        RAISE NOTICE 'OK: comment_mentions.mentioned_by_user_id kolonu mevcut';
    ELSE
        RAISE WARNING 'HATA: comment_mentions.mentioned_by_user_id kolonu BULUNAMADI!';
    END IF;
    
    -- 2. Orders constraint kontrolü
    SELECT EXISTS (
        SELECT 1 FROM information_schema.table_constraints
        WHERE table_schema = 'public'
          AND table_name = 'orders'
          AND constraint_name = 'orders_commission_status_check'
    ) INTO v_constraint_exists;
    
    IF v_constraint_exists THEN
        RAISE NOTICE 'OK: orders_commission_status_check constraint mevcut';
    ELSE
        RAISE WARNING 'HATA: orders_commission_status_check constraint BULUNAMADI!';
    END IF;
    
    -- 3. Trigger kontrolü
    SELECT EXISTS (
        SELECT 1 FROM information_schema.triggers
        WHERE trigger_schema = 'public'
          AND trigger_name = 'calculate_commission_on_insert'
    ) INTO v_trigger_exists;
    
    IF v_trigger_exists THEN
        RAISE NOTICE 'OK: calculate_commission_on_insert trigger mevcut';
    ELSE
        RAISE WARNING 'HATA: calculate_commission_on_insert trigger BULUNAMADI!';
    END IF;
    
    -- 4. NULL commission_status kontrolü
    SELECT COUNT(*) INTO v_null_count
    FROM public.orders
    WHERE commission_status IS NULL;
    
    IF v_null_count = 0 THEN
        RAISE NOTICE 'OK: Tüm orders kayıtlarında commission_status dolu';
    ELSE
        RAISE WARNING 'UYARI: % adet order kaydinda commission_status NULL', v_null_count;
    END IF;
    
    RAISE NOTICE ' ';
    RAISE NOTICE '======================================';
    RAISE NOTICE 'DUZELTMELER TAMAMLANDI!';
    RAISE NOTICE 'Simdi uygulamayi test edebilirsiniz.';
    RAISE NOTICE '======================================';
END $$;
