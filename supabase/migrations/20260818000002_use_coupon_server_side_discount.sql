-- use_coupon(): istemcinin gönderdiği p_discount_amount'a güvenmeyi bırak,
-- indirimi sunucuda siparişin gerçek subtotal'ı + kuponun kurallarına göre
-- yeniden hesapla. Eskiden istemci manipüle edilmiş bir indirim tutarı
-- gönderirse doğrudan coupon_usages'a yazılıyordu (raporlama/limit
-- sayımı için güvenilmez bir defter oluşturuyordu). Ayrıca siparişin
-- gerçekten bu kullanıcıya ve kuponun mağazasına ait olduğu doğrulanır.
--
-- Not: orders.total/orders.discount hâlâ istemci tarafından hesaplanıp
-- INSERT edildiği için (sipariş oluşturma tam server-authoritative değil)
-- bu migration yalnızca coupon_usages defterini sağlamlaştırır; daha
-- kapsamlı bir "sipariş toplamını sunucuda doğrula" işi ayrı bir konudur.

-- Canlıdaki fonksiyon parametre varsayılanlarıyla mevcut olabilir
-- (repo migration geçmişiyle senkron değil); CREATE OR REPLACE varsayılanları
-- kaldıramadığı için önce güvenli şekilde düşür.
DROP FUNCTION IF EXISTS use_coupon(UUID, UUID, UUID, NUMERIC);

CREATE OR REPLACE FUNCTION use_coupon(p_coupon_id UUID, p_order_id UUID, p_user_id UUID, p_discount_amount NUMERIC)
RETURNS VOID AS $$
DECLARE
    v_coupon RECORD;
    v_order RECORD;
    v_user_usage_count INT;
    v_computed_discount NUMERIC;
BEGIN
    SELECT * INTO v_coupon FROM public.shop_coupons WHERE id = p_coupon_id FOR UPDATE;

    IF v_coupon.id IS NULL OR v_coupon.is_active = false THEN
        RAISE EXCEPTION 'Kupon artık geçerli değil';
    END IF;

    SELECT id, shop_id, subtotal, user_id INTO v_order
    FROM public.orders WHERE id = p_order_id;

    IF v_order.id IS NULL THEN
        RAISE EXCEPTION 'Sipariş bulunamadı';
    END IF;

    IF v_order.user_id != p_user_id THEN
        RAISE EXCEPTION 'Yetkisiz işlem';
    END IF;

    IF v_order.shop_id != v_coupon.shop_id THEN
        RAISE EXCEPTION 'Kupon bu siparişin mağazasına ait değil';
    END IF;

    IF v_coupon.usage_limit IS NOT NULL AND v_coupon.usage_count >= v_coupon.usage_limit THEN
        RAISE EXCEPTION 'Bu kuponun kullanım limiti doldu';
    END IF;

    IF v_coupon.usage_per_user IS NOT NULL THEN
        SELECT count(*) INTO v_user_usage_count FROM public.coupon_usages
        WHERE coupon_id = p_coupon_id AND user_id = p_user_id;

        IF v_user_usage_count >= v_coupon.usage_per_user THEN
            RAISE EXCEPTION 'Bu kuponu daha önce kullandınız';
        END IF;
    END IF;

    -- İndirimi istemciden gelen p_discount_amount'a güvenmeden sunucuda
    -- yeniden hesapla (Dart AppliedCoupon.discountFor ile birebir aynı mantık).
    IF v_coupon.discount_type = 'percentage' THEN
        v_computed_discount := v_order.subtotal * (v_coupon.discount_value / 100.0);
        IF v_coupon.maximum_discount_amount IS NOT NULL AND v_computed_discount > v_coupon.maximum_discount_amount THEN
            v_computed_discount := v_coupon.maximum_discount_amount;
        END IF;
    ELSE
        v_computed_discount := v_coupon.discount_value;
    END IF;

    IF v_computed_discount > v_order.subtotal THEN
        v_computed_discount := v_order.subtotal;
    END IF;
    IF v_computed_discount < 0 THEN
        v_computed_discount := 0;
    END IF;

    INSERT INTO public.coupon_usages (coupon_id, order_id, user_id, discount_amount)
    VALUES (p_coupon_id, p_order_id, p_user_id, v_computed_discount);

    UPDATE public.shop_coupons SET usage_count = usage_count + 1 WHERE id = p_coupon_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public;

GRANT EXECUTE ON FUNCTION use_coupon(UUID, UUID, UUID, NUMERIC) TO authenticated;

COMMENT ON FUNCTION use_coupon(UUID, UUID, UUID, NUMERIC) IS 'Kupon kullanımını kaydeder; indirim tutarını istemciden gelen parametreye değil, siparişin subtotal''ı + kupon kurallarına göre sunucuda yeniden hesaplanmış değere göre yazar.';
