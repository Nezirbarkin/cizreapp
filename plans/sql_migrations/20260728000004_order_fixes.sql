-- =====================================================
-- DOSYA: supabase/migrations/20260728000004_order_fixes.sql
-- AMAÇ: Order items veri kaybı fix + order number unique
-- TARİH: 2026-07-28
-- UYGULAMA: Supabase Dashboard > SQL Editor
-- =====================================================

-- 1. Orders RLS - sadece participant'lar görebilir
DROP POLICY IF EXISTS "Users can view own orders" ON orders;
CREATE POLICY "Users can view own orders" ON orders
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS "Shop owners can view shop orders" ON orders;
CREATE POLICY "Shop owners can view shop orders" ON orders
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM shops s
      WHERE s.id = orders.shop_id
        AND s.owner_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Admins can view all orders" ON orders;
CREATE POLICY "Admins can view all orders" ON orders
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM profiles p
      WHERE p.id = auth.uid() AND p.role = 'admin'
    )
  );

-- 2. Order items RLS - sipariş katılımcıları görebilir
DROP POLICY IF EXISTS "Users can view own order items" ON order_items;
CREATE POLICY "Users can view own order items" ON order_items
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM orders o
      WHERE o.id = order_items.order_id
        AND (
          o.user_id = auth.uid() OR
          EXISTS (
            SELECT 1 FROM shops s
            WHERE s.id = o.shop_id AND s.owner_id = auth.uid()
          ) OR
          EXISTS (
            SELECT 1 FROM profiles p
            WHERE p.id = auth.uid() AND p.role = 'admin'
          )
        )
    )
  );

-- 3. order_number sequence (UUID yerine güvenli unique number)
CREATE SEQUENCE IF NOT EXISTS order_number_seq START 100000;

-- 4. orders insert trigger - otomatik order_number
CREATE OR REPLACE FUNCTION generate_order_number()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.order_number IS NULL OR NEW.order_number = '' THEN
    NEW.order_number := 'ORD' || LPAD(nextval('order_number_seq')::TEXT, 8, '0');
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_generate_order_number ON orders;
CREATE TRIGGER trg_generate_order_number
  BEFORE INSERT ON orders
  FOR EACH ROW
  EXECUTE FUNCTION generate_order_number();

-- 5. order_number unique constraint
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'orders_order_number_unique'
  ) THEN
    ALTER TABLE orders ADD CONSTRAINT orders_order_number_unique UNIQUE (order_number);
  END IF;
END $$;

-- 6. Sipariş oluşturma RPC (transactional - order + items atomik)
CREATE OR REPLACE FUNCTION create_order_with_items(
  p_user_id UUID,
  p_shop_id UUID,
  p_items JSONB,
  p_delivery_address_text TEXT,
  p_address_id UUID,
  p_customer_phone TEXT,
  p_payment_method TEXT,
  p_subtotal NUMERIC,
  p_delivery_fee NUMERIC,
  p_discount NUMERIC,
  p_total NUMERIC,
  p_notes TEXT,
  p_invoice_data JSONB DEFAULT '{}'::JSONB
)
RETURNS TABLE (
  order_id UUID,
  order_number TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_order_id UUID;
  v_order_number TEXT;
  v_item JSONB;
BEGIN
  -- Auth kontrol
  IF auth.uid() IS NULL OR auth.uid() != p_user_id THEN
    RAISE EXCEPTION 'Not authorized' USING ERRCODE = '42501';
  END IF;

  -- Siparişi oluştur
  INSERT INTO orders (
    user_id, shop_id, delivery_address_text, address_id,
    customer_phone, payment_method, payment_status,
    subtotal, delivery_fee, discount, total,
    status, notes,
    invoice_type, invoice_full_name, invoice_tax_number, invoice_tc_no,
    invoice_tax_office, invoice_address, invoice_email
  ) VALUES (
    p_user_id, p_shop_id, p_delivery_address_text, p_address_id,
    p_customer_phone, p_payment_method, 'pending',
    p_subtotal, p_delivery_fee, p_discount, p_total,
    'pending', p_notes,
    p_invoice_data->>'invoice_type',
    p_invoice_data->>'invoice_full_name',
    p_invoice_data->>'invoice_tax_number',
    p_invoice_data->>'invoice_tc_no',
    p_invoice_data->>'invoice_tax_office',
    p_invoice_data->>'invoice_address',
    p_invoice_data->>'invoice_email'
  )
  RETURNING id, order_number INTO v_order_id, v_order_number;

  -- Items ekle (atomik)
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    INSERT INTO order_items (
      order_id, product_id, product_name, price, product_price,
      quantity, subtotal, product_image_url, shop_id, shop_name
    ) VALUES (
      v_order_id,
      (v_item->>'product_id')::UUID,
      v_item->>'product_name',
      (v_item->>'price')::NUMERIC,
      (v_item->>'price')::NUMERIC,
      (v_item->>'quantity')::INTEGER,
      (v_item->>'subtotal')::NUMERIC,
      v_item->>'product_image_url',
      (v_item->>'shop_id')::UUID,
      v_item->>'shop_name'
    );
  END LOOP;

  RETURN QUERY SELECT v_order_id, v_order_number;
END;
$$;

REVOKE ALL ON FUNCTION create_order_with_items(UUID, UUID, JSONB, TEXT, UUID, TEXT, TEXT, NUMERIC, NUMERIC, NUMERIC, NUMERIC, TEXT, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION create_order_with_items(UUID, UUID, JSONB, TEXT, UUID, TEXT, TEXT, NUMERIC, NUMERIC, NUMERIC, NUMERIC, TEXT, JSONB) TO authenticated, service_role;

-- 7. Test query
-- SELECT * FROM create_order_with_items(...);
