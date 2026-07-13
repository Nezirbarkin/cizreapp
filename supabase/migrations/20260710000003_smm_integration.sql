-- Dijital ürün (SMM panel API) entegrasyonu
-- smm_providers, shops.can_use_own_smm_api, products dijital alanları, digital_orders, create_digital_order RPC

-- 1) shops.can_use_own_smm_api - smm_providers policy'leri bu sütunu kullandığı için önce eklenir.
-- Sadece admin değiştirebilir.
ALTER TABLE shops ADD COLUMN IF NOT EXISTS can_use_own_smm_api BOOLEAN NOT NULL DEFAULT false;

CREATE OR REPLACE FUNCTION prevent_seller_self_grant_smm()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.can_use_own_smm_api IS DISTINCT FROM OLD.can_use_own_smm_api
     AND (SELECT role FROM profiles WHERE id = auth.uid()) IS DISTINCT FROM 'admin' THEN
    NEW.can_use_own_smm_api := OLD.can_use_own_smm_api;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS trg_prevent_seller_self_grant_smm ON shops;
CREATE TRIGGER trg_prevent_seller_self_grant_smm
  BEFORE UPDATE ON shops
  FOR EACH ROW EXECUTE FUNCTION prevent_seller_self_grant_smm();

-- 2) smm_providers
CREATE TYPE smm_owner_type AS ENUM ('admin', 'seller');

CREATE TABLE smm_providers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_type smm_owner_type NOT NULL,
  owner_id UUID NOT NULL, -- owner_type='admin' -> profiles.id, owner_type='seller' -> shops.id
  name TEXT NOT NULL,
  api_url TEXT NOT NULL DEFAULT 'https://smmget.com/api/v2',
  api_key TEXT NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE smm_providers ENABLE ROW LEVEL SECURITY;

-- api_key hiçbir client rolüne (authenticated/anon) SELECT ile açılmaz; sadece service_role okuyabilir.
REVOKE ALL ON smm_providers FROM authenticated, anon;
GRANT SELECT (id, owner_type, owner_id, name, api_url, is_active, created_at, updated_at) ON smm_providers TO authenticated;
GRANT INSERT (owner_type, owner_id, name, api_url, api_key, is_active) ON smm_providers TO authenticated;
GRANT UPDATE (name, api_url, api_key, is_active) ON smm_providers TO authenticated;
GRANT DELETE ON smm_providers TO authenticated;

CREATE POLICY smm_providers_select ON smm_providers FOR SELECT TO authenticated
  USING (
    (SELECT role FROM profiles WHERE id = (SELECT auth.uid())) = 'admin'
    OR (owner_type = 'seller' AND owner_id IN (SELECT id FROM shops WHERE owner_id = (SELECT auth.uid())))
  );

CREATE POLICY smm_providers_insert ON smm_providers FOR INSERT TO authenticated
  WITH CHECK (
    (SELECT role FROM profiles WHERE id = (SELECT auth.uid())) = 'admin'
    OR (
      owner_type = 'seller'
      AND owner_id IN (
        SELECT id FROM shops WHERE owner_id = (SELECT auth.uid()) AND can_use_own_smm_api = true
      )
    )
  );

CREATE POLICY smm_providers_update ON smm_providers FOR UPDATE TO authenticated
  USING (
    (SELECT role FROM profiles WHERE id = (SELECT auth.uid())) = 'admin'
    OR (
      owner_type = 'seller'
      AND owner_id IN (
        SELECT id FROM shops WHERE owner_id = (SELECT auth.uid()) AND can_use_own_smm_api = true
      )
    )
  )
  WITH CHECK (
    (SELECT role FROM profiles WHERE id = (SELECT auth.uid())) = 'admin'
    OR (
      owner_type = 'seller'
      AND owner_id IN (
        SELECT id FROM shops WHERE owner_id = (SELECT auth.uid()) AND can_use_own_smm_api = true
      )
    )
  );

CREATE POLICY smm_providers_delete ON smm_providers FOR DELETE TO authenticated
  USING ((SELECT role FROM profiles WHERE id = (SELECT auth.uid())) = 'admin');

-- 3) products - dijital ürün alanları
ALTER TABLE products
  ADD COLUMN IF NOT EXISTS smm_provider_id UUID REFERENCES smm_providers(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS smm_service_id TEXT,
  ADD COLUMN IF NOT EXISTS price_per_1000 NUMERIC(12,2),
  ADD COLUMN IF NOT EXISTS min_quantity INTEGER,
  ADD COLUMN IF NOT EXISTS max_quantity INTEGER;

ALTER TABLE products DROP CONSTRAINT IF EXISTS products_product_type_check;
ALTER TABLE products ADD CONSTRAINT products_product_type_check
  CHECK (product_type IN ('normal', 'clothing', 'shoes', 'digital'));

ALTER TABLE products DROP CONSTRAINT IF EXISTS chk_digital_fields;
ALTER TABLE products ADD CONSTRAINT chk_digital_fields
  CHECK (
    product_type != 'digital'
    OR (
      smm_provider_id IS NOT NULL AND smm_service_id IS NOT NULL
      AND price_per_1000 IS NOT NULL AND min_quantity IS NOT NULL AND max_quantity IS NOT NULL
    )
  );

-- 4) digital_orders - kendi kendine yeten sipariş kaydı (mevcut orders tablosuna bağımlı değil)
CREATE TYPE digital_order_status AS ENUM (
  'pending', 'in_progress', 'completed', 'partial', 'canceled', 'refunded', 'failed'
);

CREATE TABLE digital_orders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES profiles(id),
  product_id UUID NOT NULL REFERENCES products(id),
  provider_id UUID NOT NULL REFERENCES smm_providers(id),
  target_url TEXT NOT NULL,
  quantity INTEGER NOT NULL,
  unit_price NUMERIC(12,4) NOT NULL,
  total_price NUMERIC(12,2) NOT NULL,
  external_order_id TEXT,
  status digital_order_status NOT NULL DEFAULT 'pending',
  start_count INTEGER,
  remains INTEGER,
  last_checked_at TIMESTAMPTZ,
  error_message TEXT,
  balance_transaction_id UUID,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_digital_orders_status ON digital_orders(status) WHERE status IN ('pending', 'in_progress');
CREATE INDEX idx_digital_orders_user ON digital_orders(user_id);
CREATE INDEX idx_digital_orders_provider ON digital_orders(provider_id);

ALTER TABLE digital_orders ENABLE ROW LEVEL SECURITY;

-- Sadece SELECT policy tanımlı; tüm INSERT/UPDATE Edge Function'ların service-role client'ıyla yapılır.
CREATE POLICY digital_orders_select ON digital_orders FOR SELECT TO authenticated
  USING (
    user_id = (SELECT auth.uid())
    OR (SELECT role FROM profiles WHERE id = (SELECT auth.uid())) = 'admin'
    OR provider_id IN (
      SELECT sp.id FROM smm_providers sp
      JOIN shops s ON s.id = sp.owner_id AND sp.owner_type = 'seller'
      WHERE s.owner_id = (SELECT auth.uid())
    )
  );

-- 5) create_digital_order - ürün doğrulama + atomik bakiye düşme + digital_orders insert
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

REVOKE ALL ON FUNCTION create_digital_order(UUID, UUID, TEXT, INTEGER) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION create_digital_order(UUID, UUID, TEXT, INTEGER) TO authenticated, service_role;
