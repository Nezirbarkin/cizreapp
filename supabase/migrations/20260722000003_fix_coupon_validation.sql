-- Kupon sistemi hataları: süre (start_date/end_date), kullanım limiti (usage_limit),
-- kullanıcı başına limit (usage_per_user) ve yüzde indirim tavanı (maximum_discount_amount)
-- hiç kontrol edilmiyordu; istemci tarafı tek başına kupon kabul ediyordu (manipülasyona açık).

CREATE OR REPLACE FUNCTION validate_coupon(p_shop_id UUID, p_code TEXT, p_subtotal NUMERIC, p_user_id UUID)
RETURNS TABLE (
    id UUID,
    discount_type TEXT,
    discount_value NUMERIC,
    maximum_discount_amount NUMERIC,
    minimum_order_amount NUMERIC
) AS $$
DECLARE
    v_coupon RECORD;
    v_user_usage_count INT;
BEGIN
    SELECT * INTO v_coupon FROM public.shop_coupons
    WHERE shop_id = p_shop_id AND code = p_code AND is_active = true
    LIMIT 1;

    IF v_coupon.id IS NULL THEN
        RAISE EXCEPTION 'Geçersiz kupon kodu';
    END IF;

    IF v_coupon.start_date IS NOT NULL AND v_coupon.start_date > NOW() THEN
        RAISE EXCEPTION 'Bu kupon henüz başlamadı';
    END IF;

    IF v_coupon.end_date IS NOT NULL AND v_coupon.end_date < NOW() THEN
        RAISE EXCEPTION 'Bu kuponun süresi dolmuş';
    END IF;

    IF v_coupon.minimum_order_amount IS NOT NULL AND p_subtotal < v_coupon.minimum_order_amount THEN
        RAISE EXCEPTION 'Bu kupon için minimum ₺%.2f tutarında alışveriş yapmalısınız', v_coupon.minimum_order_amount;
    END IF;

    IF v_coupon.usage_limit IS NOT NULL AND v_coupon.usage_count >= v_coupon.usage_limit THEN
        RAISE EXCEPTION 'Bu kuponun kullanım limiti doldu';
    END IF;

    IF v_coupon.usage_per_user IS NOT NULL THEN
        SELECT count(*) INTO v_user_usage_count FROM public.coupon_usages
        WHERE coupon_id = v_coupon.id AND user_id = p_user_id;

        IF v_user_usage_count >= v_coupon.usage_per_user THEN
            RAISE EXCEPTION 'Bu kuponu daha önce kullandınız';
        END IF;
    END IF;

    RETURN QUERY SELECT v_coupon.id, v_coupon.discount_type::TEXT, v_coupon.discount_value,
        v_coupon.maximum_discount_amount, v_coupon.minimum_order_amount;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public;

GRANT EXECUTE ON FUNCTION validate_coupon(UUID, TEXT, NUMERIC, UUID) TO authenticated;

-- Sipariş oluşturulduktan sonra kuponu kullanılmış olarak kaydeder;
-- limitleri satır kilidiyle (FOR UPDATE) tekrar kontrol ederek yarış durumunu/aynı kuponun
-- birden fazla sekmeden aynı anda kullanılmasını engeller.
CREATE OR REPLACE FUNCTION use_coupon(p_coupon_id UUID, p_order_id UUID, p_user_id UUID, p_discount_amount NUMERIC)
RETURNS VOID AS $$
DECLARE
    v_coupon RECORD;
    v_user_usage_count INT;
BEGIN
    SELECT * INTO v_coupon FROM public.shop_coupons WHERE id = p_coupon_id FOR UPDATE;

    IF v_coupon.id IS NULL OR v_coupon.is_active = false THEN
        RAISE EXCEPTION 'Kupon artık geçerli değil';
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

    INSERT INTO public.coupon_usages (coupon_id, order_id, user_id, discount_amount)
    VALUES (p_coupon_id, p_order_id, p_user_id, p_discount_amount);

    UPDATE public.shop_coupons SET usage_count = usage_count + 1 WHERE id = p_coupon_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public;

GRANT EXECUTE ON FUNCTION use_coupon(UUID, UUID, UUID, NUMERIC) TO authenticated;
