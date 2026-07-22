-- "2 al biri bakiye" kampanyası: bir üründe bu kampanya aktifse, sepette o üründen
-- her 2 adet alımda 1 adedin tutarı sipariş sonrası kullanıcının bakiyesine iade edilir.

ALTER TABLE public.products ADD COLUMN IF NOT EXISTS campaign_type TEXT;

ALTER TYPE public.balance_transaction_type ADD VALUE IF NOT EXISTS 'campaign_reward';

CREATE OR REPLACE FUNCTION apply_campaign_rewards_for_order(p_order_id UUID)
RETURNS VOID AS $$
DECLARE
    v_item RECORD;
    v_user_id UUID;
    v_reward_units INT;
    v_reward_amount NUMERIC;
    v_already_applied BOOLEAN;
BEGIN
    SELECT EXISTS (
        SELECT 1 FROM public.balance_transactions
        WHERE reference_type = 'campaign_reward_order' AND reference_id = p_order_id
    ) INTO v_already_applied;

    IF v_already_applied THEN
        RETURN; -- Bu sipariş için ödül zaten verildi, tekrar verme
    END IF;

    SELECT user_id INTO v_user_id FROM public.orders WHERE id = p_order_id;
    IF v_user_id IS NULL THEN
        RETURN;
    END IF;

    FOR v_item IN
        SELECT oi.quantity, oi.price, p.id AS product_id
        FROM public.order_items oi
        JOIN public.products p ON p.id = oi.product_id
        WHERE oi.order_id = p_order_id
          AND p.campaign_type = 'buy2_get1_balance'
    LOOP
        v_reward_units := v_item.quantity / 2; -- her 2 adette 1 adet bedeli
        IF v_reward_units > 0 THEN
            v_reward_amount := v_reward_units * v_item.price;
            PERFORM add_to_balance(
                v_user_id,
                v_reward_amount,
                'campaign_reward'::balance_transaction_type,
                'campaign_reward_order',
                p_order_id,
                '2 al biri bakiye kampanyası ödülü'
            );
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public;

GRANT EXECUTE ON FUNCTION apply_campaign_rewards_for_order(UUID) TO authenticated;
