-- ============================================================================
-- SİPARİŞ DEĞERLENDİRME SİSTEMİ GELİŞTİRMELERİ
-- ============================================================================
-- 1) Sipariş tesliminde otomatik değerlendirme kaydı
-- 2) Satıcı yorumlara cevap verebilir
-- 3) Push notification desteği

-- 1. shop_reviews tablosuna satıcı cevabı alanları ekle
ALTER TABLE shop_reviews
ADD COLUMN IF NOT EXISTS seller_reply TEXT,
ADD COLUMN IF NOT EXISTS seller_replied_at TIMESTAMP WITH TIME ZONE,
ADD COLUMN IF NOT EXISTS order_id UUID REFERENCES orders(id) ON DELETE SET NULL;

-- 2. Mevcut unique constraint'i kaldır ve yeni ekle
-- Eski constraint: (shop_id, user_id) -> Bir kullanıcı bir mağazaya 1 yorum
-- Yeni constraint: (shop_id, user_id, order_id) -> Bir kullanıcı her siparişe 1 yorum
-- ÖNEMLİ: Önce constraint'i kaldır (constraint index'e bağlı)
ALTER TABLE shop_reviews DROP CONSTRAINT IF EXISTS shop_reviews_shop_id_user_id_key;
-- Sonra index'i kaldır (artık gerekli değil)
DROP INDEX IF EXISTS shop_reviews_shop_id_user_id_key;

-- order_id NULL olabilir (eski yorumlar için) bu yüzden partial unique index kullan
CREATE UNIQUE INDEX IF NOT EXISTS shop_reviews_order_unique
ON shop_reviews(shop_id, user_id, order_id)
WHERE order_id IS NOT NULL;

-- order_id NULL olan yorumlar için eski constraint'i koru
-- (eski sistemden kalan yorumlar - bir kullanıcı bir mağazaya 1 yorum)
CREATE UNIQUE INDEX IF NOT EXISTS shop_reviews_legacy_unique
ON shop_reviews(shop_id, user_id)
WHERE order_id IS NULL;

-- Index ekle
CREATE INDEX IF NOT EXISTS idx_shop_reviews_order_id ON shop_reviews(order_id);

-- 2. Satıcı cevabı güncellendiğinde updated_at'i güncelle
CREATE OR REPLACE FUNCTION update_shop_review_seller_reply()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.seller_reply IS DISTINCT FROM OLD.seller_reply AND NEW.seller_reply IS NOT NULL THEN
        NEW.seller_replied_at = NOW();
        NEW.updated_at = NOW();
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public;

DROP TRIGGER IF EXISTS shop_review_seller_reply_trigger ON shop_reviews;
CREATE TRIGGER shop_review_seller_reply_trigger
    BEFORE UPDATE ON shop_reviews
    FOR EACH ROW
    EXECUTE FUNCTION update_shop_review_seller_reply();

-- 3. Yeni yorum eklendiğinde satıcıya bildirim gönder
CREATE OR REPLACE FUNCTION notify_seller_on_new_review()
RETURNS TRIGGER AS $$
DECLARE
    v_seller_id UUID;
    v_shop_name TEXT;
    v_user_name TEXT;
BEGIN
    -- Satıcı ID'sini al
    SELECT owner_id, name INTO v_seller_id, v_shop_name
    FROM shops
    WHERE id = NEW.shop_id;
    
    -- Kullanıcı adını al
    SELECT full_name INTO v_user_name
    FROM profiles
    WHERE id = NEW.user_id;
    
    -- Satıcıya bildirim gönder
    INSERT INTO notifications (
        user_id,
        type,
        title,
        content,
        entity_id,
        actor_id,
        created_at
    ) VALUES (
        v_seller_id,
        'shop_review',
        'Yeni Mağaza Yorumu',
        COALESCE(v_user_name, 'Bir kullanıcı') || ' mağazanıza ' || NEW.rating || ' yıldız verdi',
        NEW.id,
        NEW.user_id,
        NOW()
    );
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public;

DROP TRIGGER IF EXISTS notify_seller_new_review_trigger ON shop_reviews;
CREATE TRIGGER notify_seller_new_review_trigger
    AFTER INSERT ON shop_reviews
    FOR EACH ROW
    EXECUTE FUNCTION notify_seller_on_new_review();

-- 4. Satıcı cevap verdiğinde müşteriye bildirim gönder
CREATE OR REPLACE FUNCTION notify_user_on_seller_reply()
RETURNS TRIGGER AS $$
DECLARE
    v_shop_name TEXT;
BEGIN
    -- Sadece satıcı cevabı eklendiğinde
    IF NEW.seller_reply IS DISTINCT FROM OLD.seller_reply AND NEW.seller_reply IS NOT NULL THEN
        -- Mağaza adını al
        SELECT name INTO v_shop_name
        FROM shops
        WHERE id = NEW.shop_id;
        
        -- Kullanıcıya bildirim gönder
        INSERT INTO notifications (
            user_id,
            type,
            title,
            content,
            entity_id,
            created_at
        ) VALUES (
            NEW.user_id,
            'shop_review_reply',
            'Yorumunuza Cevap Verildi',
            COALESCE(v_shop_name, 'Mağaza') || ' yorumunuza cevap verdi',
            NEW.id,
            NOW()
        );
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public;

DROP TRIGGER IF EXISTS notify_user_seller_reply_trigger ON shop_reviews;
CREATE TRIGGER notify_user_seller_reply_trigger
    AFTER UPDATE ON shop_reviews
    FOR EACH ROW
    EXECUTE FUNCTION notify_user_on_seller_reply();

-- 5. RLS Policy'leri güncelle - Satıcılar kendi mağaza yorumlarını görebilir ve cevaplayabilir
DROP POLICY IF EXISTS "Sellers can view their shop reviews" ON shop_reviews;
CREATE POLICY "Sellers can view their shop reviews" ON shop_reviews
FOR SELECT
TO authenticated
USING (
    shop_id IN (
        SELECT id FROM shops WHERE owner_id = (select auth.uid())
    )
);

DROP POLICY IF EXISTS "Sellers can reply to their shop reviews" ON shop_reviews;
CREATE POLICY "Sellers can reply to their shop reviews" ON shop_reviews
FOR UPDATE
TO authenticated
USING (
    shop_id IN (
        SELECT id FROM shops WHERE owner_id = (select auth.uid())
    )
)
WITH CHECK (
    shop_id IN (
        SELECT id FROM shops WHERE owner_id = (select auth.uid())
    )
);

-- 6. Sipariş ile ilişkili değerlendirme kontrolü için fonksiyon
CREATE OR REPLACE FUNCTION can_review_order(p_user_id UUID, p_shop_id UUID, p_order_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
    v_order_exists BOOLEAN;
    v_already_reviewed BOOLEAN;
BEGIN
    -- Siparişin var olup olmadığını ve teslim edilip edilmediğini kontrol et
    SELECT EXISTS(
        SELECT 1 FROM orders
        WHERE id = p_order_id
        AND user_id = p_user_id
        AND shop_id = p_shop_id
        AND status = 'delivered'
    ) INTO v_order_exists;
    
    IF NOT v_order_exists THEN
        RETURN FALSE;
    END IF;
    
    -- Bu sipariş için zaten yorum yapılmış mı kontrol et
    SELECT EXISTS(
        SELECT 1 FROM shop_reviews
        WHERE user_id = p_user_id
        AND shop_id = p_shop_id
        AND order_id = p_order_id
    ) INTO v_already_reviewed;
    
    RETURN NOT v_already_reviewed;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public;

-- 7. Kullanıcının bekleyen değerlendirmelerini getiren fonksiyon
CREATE OR REPLACE FUNCTION get_pending_reviews(p_user_id UUID)
RETURNS TABLE (
    order_id UUID,
    shop_id UUID,
    shop_name TEXT,
    shop_logo TEXT,
    order_date TIMESTAMP WITH TIME ZONE,
    delivered_at TIMESTAMP WITH TIME ZONE
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        o.id as order_id,
        o.shop_id,
        s.name as shop_name,
        s.logo_url as shop_logo,
        o.created_at as order_date,
        o.updated_at as delivered_at
    FROM orders o
    JOIN shops s ON s.id = o.shop_id
    LEFT JOIN shop_reviews sr ON sr.shop_id = o.shop_id AND sr.user_id = o.user_id AND sr.order_id = o.id
    WHERE o.user_id = p_user_id
    AND o.status = 'delivered'
    AND sr.id IS NULL  -- Henüz değerlendirilmemiş
    AND o.updated_at >= NOW() - INTERVAL '30 days' -- Son 30 gün içinde teslim edilenler
    ORDER BY o.updated_at DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public;

-- 8. Notifications tablosuna yeni type'ları ekle
-- Önce mevcut constraint'i kontrol et ve kaldır
DO $$
BEGIN
    -- notifications_type_check constraint'ini kaldır
    ALTER TABLE notifications DROP CONSTRAINT IF EXISTS notifications_type_check;
    
    -- Yeni constraint ekle (eski tipler + yeni tipler)
    ALTER TABLE notifications ADD CONSTRAINT notifications_type_check
    CHECK (type IN (
        'like',
        'comment',
        'follow',
        'mention',
        'story_mention',
        'order_update',
        'shop_review',
        'shop_review_reply'
    ));
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Constraint güncelleme hatası: %', SQLERRM;
END $$;

-- 9. Onay mesajı
SELECT 'Sipariş değerlendirme sistemi başarıyla oluşturuldu!' as status;
