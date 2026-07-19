-- Dijital ürünlerde satıcının belirleyebileceği "kullanıcı başına sipariş limiti".
-- Özellikle 0 TL (ücretsiz) ürünlerde kötüye kullanımı önlemek için kullanılır.
-- NULL = limitsiz.

ALTER TABLE products
  ADD COLUMN IF NOT EXISTS max_orders_per_user INTEGER CHECK (max_orders_per_user IS NULL OR max_orders_per_user > 0);

CREATE OR REPLACE FUNCTION create_digital_order(
  p_user_id UUID,
  p_product_id UUID,
  p_target_url TEXT,
  p_quantity INTEGER
) RETURNS TABLE (
  digital_order_id UUID,
  provider_id UUID,
  smm_service_id TEXT,
  total_price NUMERIC,
  transaction_id UUID,
  balance_after NUMERIC
) AS $$
DECLARE
  v_product products%ROWTYPE;
  v_digital_order_id UUID := gen_random_uuid();
  v_unit_price NUMERIC(12,4);
  v_total_price NUMERIC(12,2);
  v_deduct_row RECORD;
  v_existing_orders INTEGER;
BEGIN
  SELECT * INTO v_product FROM products WHERE id = p_product_id AND is_available = true FOR UPDATE;
  IF v_product IS NULL THEN
    RAISE EXCEPTION 'Ürün bulunamadı veya satışta değil';
  END IF;
  IF v_product.product_type != 'digital' THEN
    RAISE EXCEPTION 'Bu ürün dijital ürün değil';
  END IF;
  IF p_quantity IS NULL OR p_quantity < v_product.min_quantity OR p_quantity > v_product.max_quantity THEN
    RAISE EXCEPTION 'Miktar % - % aralığında olmalıdır', v_product.min_quantity, v_product.max_quantity;
  END IF;
  IF p_target_url IS NULL OR length(trim(p_target_url)) = 0 THEN
    RAISE EXCEPTION 'Link zorunludur';
  END IF;

  IF v_product.max_orders_per_user IS NOT NULL THEN
    SELECT count(*) INTO v_existing_orders
    FROM digital_orders
    WHERE user_id = p_user_id
      AND product_id = p_product_id
      AND status NOT IN ('failed', 'refunded');
    IF v_existing_orders >= v_product.max_orders_per_user THEN
      RAISE EXCEPTION 'Bu ürün için sipariş limitinize ulaştınız (maksimum %)', v_product.max_orders_per_user;
    END IF;
  END IF;

  v_unit_price := ROUND(v_product.price_per_1000 / 1000.0, 4);
  v_total_price := ROUND(v_unit_price * p_quantity, 2);

  -- Bakiyeyi atomik düş (mevcut deduct_from_balance RPC'si reuse edilir).
  -- Yetersiz bakiyede exception fırlatır -> tüm transaction rollback olur, digital_orders kaydı oluşmaz.
  SELECT * INTO v_deduct_row FROM deduct_from_balance(
    p_user_id,
    v_total_price,
    'order_payment',
    'digital_order',
    v_digital_order_id,
    'Dijital ürün siparişi - ' || v_product.name
  );

  INSERT INTO digital_orders (
    id, user_id, product_id, provider_id, target_url, quantity,
    unit_price, total_price, status, balance_transaction_id
  ) VALUES (
    v_digital_order_id, p_user_id, p_product_id, v_product.smm_provider_id, trim(p_target_url), p_quantity,
    v_unit_price, v_total_price, 'pending', v_deduct_row.transaction_id
  );

  RETURN QUERY SELECT v_digital_order_id, v_product.smm_provider_id, v_product.smm_service_id,
    v_total_price, v_deduct_row.transaction_id, v_deduct_row.balance_after;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;
