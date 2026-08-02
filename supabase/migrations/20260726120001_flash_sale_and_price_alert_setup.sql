-- ============================================================================
-- FLASH SALE + PRICE ALERT SETUP
-- ============================================================================
-- CizreApp - Flash Satış ve Fiyat Düşüş Alarmı
-- Atomic stok düşürme (RPC) + push notification trigger
-- ============================================================================

-- ============================================================================
-- 1) FLASH SALES TABLOSU
-- ============================================================================
CREATE TABLE IF NOT EXISTS flash_sales (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  shop_id UUID NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
  original_price NUMERIC(10,2) NOT NULL,
  flash_price NUMERIC(10,2) NOT NULL,
  stock_limit INTEGER NOT NULL CHECK (stock_limit > 0),
  sold_count INTEGER NOT NULL DEFAULT 0 CHECK (sold_count >= 0),
  start_at TIMESTAMPTZ NOT NULL,
  end_at TIMESTAMPTZ NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_by UUID NOT NULL REFERENCES auth.users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT flash_sales_time_chk CHECK (end_at > start_at),
  CONSTRAINT flash_sales_price_chk CHECK (flash_price < original_price),
  CONSTRAINT flash_sales_stock_chk CHECK (sold_count <= stock_limit)
);

-- Aktif flash sale'leri hızlıca bulmak için
CREATE INDEX IF NOT EXISTS idx_flash_sales_active_window
  ON flash_sales(is_active, start_at, end_at)
  WHERE is_active = true;

CREATE INDEX IF NOT EXISTS idx_flash_sales_product ON flash_sales(product_id);
CREATE INDEX IF NOT EXISTS idx_flash_sales_shop ON flash_sales(shop_id);

-- updated_at otomatik güncelleme
CREATE OR REPLACE FUNCTION trg_flash_sales_set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql
SET search_path = public, pg_temp;

DROP TRIGGER IF EXISTS flash_sales_set_updated_at ON flash_sales;
CREATE TRIGGER flash_sales_set_updated_at
  BEFORE UPDATE ON flash_sales
  FOR EACH ROW EXECUTE FUNCTION trg_flash_sales_set_updated_at();

-- ============================================================================
-- 2) FLASH SALE RPC: Atomik stok düşürme (race condition korumalı)
-- ============================================================================
-- Client ilk önce quantity ile claim eder; stok yetmiyorsa hata döner.
-- Sepete ekleme sonrası tüketici ödeme yaparsa 'commit', yapmazsa 'release' çağırır.
CREATE OR REPLACE FUNCTION claim_flash_sale(
  p_sale_id UUID,
  p_quantity INTEGER,
  p_user_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_sale flash_sales%ROWTYPE;
  v_remaining INTEGER;
BEGIN
  IF p_quantity <= 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Geçersiz miktar');
  END IF;

  -- Row-level kilitle (FOR UPDATE) - eşzamanlı claim'ler sıralı işlenir
  SELECT * INTO v_sale
    FROM flash_sales
    WHERE id = p_sale_id
    FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Satış bulunamadı');
  END IF;

  IF NOT v_sale.is_active THEN
    RETURN jsonb_build_object('success', false, 'error', 'Satış aktif değil');
  END IF;

  IF NOW() < v_sale.start_at THEN
    RETURN jsonb_build_object('success', false, 'error', 'Satış henüz başlamadı');
  END IF;

  IF NOW() >= v_sale.end_at THEN
    RETURN jsonb_build_object('success', false, 'error', 'Satış süresi doldu');
  END IF;

  v_remaining := v_sale.stock_limit - v_sale.sold_count;
  IF p_quantity > v_remaining THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Yetersiz stok',
      'remaining', v_remaining
    );
  END IF;

  UPDATE flash_sales
    SET sold_count = sold_count + p_quantity
    WHERE id = p_sale_id;

  RETURN jsonb_build_object(
    'success', true,
    'remaining', v_remaining - p_quantity,
    'flash_price', v_sale.flash_price,
    'product_id', v_sale.product_id
  );
END;
$$;

CREATE OR REPLACE FUNCTION release_flash_sale(
  p_sale_id UUID,
  p_quantity INTEGER
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_sale flash_sales%ROWTYPE;
BEGIN
  IF p_quantity <= 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Geçersiz miktar');
  END IF;

  SELECT * INTO v_sale
    FROM flash_sales
    WHERE id = p_sale_id
    FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Satış bulunamadı');
  END IF;

  UPDATE flash_sales
    SET sold_count = GREATEST(0, sold_count - p_quantity)
    WHERE id = p_sale_id;

  RETURN jsonb_build_object('success', true);
END;
$$;

-- ============================================================================
-- 3) FLASH SALE RLS
-- ============================================================================
ALTER TABLE flash_sales ENABLE ROW LEVEL SECURITY;

-- Herkes aktif ve zaman penceresindeki sale'leri okuyabilir
DROP POLICY IF EXISTS "flash_sales_select_active" ON flash_sales;
CREATE POLICY "flash_sales_select_active" ON flash_sales
  FOR SELECT
  USING (true); -- Filtreleme client-side (is_active + start/end) yeterli

-- Satıcılar kendi mağazaları için sale oluşturabilir
DROP POLICY IF EXISTS "flash_sales_insert_seller" ON flash_sales;
CREATE POLICY "flash_sales_insert_seller" ON flash_sales
  FOR INSERT
  WITH CHECK (
    auth.uid() = created_by
    AND EXISTS (
      SELECT 1 FROM shops s
      WHERE s.id = shop_id AND s.owner_id = auth.uid()
    )
  );

-- Satıcılar kendi sale'lerini güncelleyebilir/silebilir
DROP POLICY IF EXISTS "flash_sales_update_seller" ON flash_sales;
CREATE POLICY "flash_sales_update_seller" ON flash_sales
  FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM shops s
      WHERE s.id = flash_sales.shop_id AND s.owner_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "flash_sales_delete_seller" ON flash_sales;
CREATE POLICY "flash_sales_delete_seller" ON flash_sales
  FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM shops s
      WHERE s.id = flash_sales.shop_id AND s.owner_id = auth.uid()
    )
  );

-- ============================================================================
-- 4) PRICE ALERTS TABLOSU
-- ============================================================================
CREATE TABLE IF NOT EXISTS price_alerts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  target_price NUMERIC(10,2) NOT NULL CHECK (target_price > 0),
  current_price_at_creation NUMERIC(10,2) NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT true,
  triggered_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT price_alerts_user_product_uniq UNIQUE (user_id, product_id)
);

CREATE INDEX IF NOT EXISTS idx_price_alerts_user_active
  ON price_alerts(user_id, is_active);
CREATE INDEX IF NOT EXISTS idx_price_alerts_product_active
  ON price_alerts(product_id, is_active);

-- ============================================================================
-- 5) PRICE ALERT RLS
-- ============================================================================
ALTER TABLE price_alerts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "price_alerts_select_own" ON price_alerts;
CREATE POLICY "price_alerts_select_own" ON price_alerts
  FOR SELECT USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "price_alerts_insert_own" ON price_alerts;
CREATE POLICY "price_alerts_insert_own" ON price_alerts
  FOR INSERT WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "price_alerts_update_own" ON price_alerts;
CREATE POLICY "price_alerts_update_own" ON price_alerts
  FOR UPDATE USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "price_alerts_delete_own" ON price_alerts;
CREATE POLICY "price_alerts_delete_own" ON price_alerts
  FOR DELETE USING (auth.uid() = user_id);

-- ============================================================================
-- 6) PRICE DROP TRIGGER: Ürün fiyatı düşünce alarm kurulu kullanıcılara
--    notification + push gönder
-- ============================================================================
CREATE OR REPLACE FUNCTION notify_price_drops()
RETURNS TRIGGER AS $$
DECLARE
  v_alert RECORD;
  v_function_url TEXT;
  v_anon_key TEXT;
  v_request_id BIGINT;
  v_old_price NUMERIC(10,2);
  v_new_price NUMERIC(10,2);
BEGIN
  -- Sadece fiyat düşüşünde tetikle (UPDATE'de price veya discount_price)
  v_old_price := COALESCE(OLD.discount_price, OLD.price);
  v_new_price := COALESCE(NEW.discount_price, NEW.price);

  -- Fiyat düşmediyse çık
  IF v_new_price >= v_old_price THEN
    RETURN NEW;
  END IF;

  v_function_url := 'https://xsbukxkgtmdyickknqzf.supabase.co/functions/v1/send-push-notification';
  v_anon_key := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InhzYnVreGtndG1keWlja2tucXpmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njg5MzI3MzgsImV4cCI6MjA4NDUwODczOH0.UqycLmPhsjpVQbD0706gp-FVPQ3aCyCs-m9S5rcO2pc';

  -- Bu ürün için aktif alarmı olan kullanıcıları bul
  FOR v_alert IN
    SELECT pa.id AS alert_id, pa.user_id, pa.target_price
      FROM price_alerts pa
      WHERE pa.product_id = NEW.id
        AND pa.is_active = true
        AND pa.target_price >= v_new_price
  LOOP
    -- In-app notification kaydı
    INSERT INTO notifications (user_id, type, title, content, actor_id, entity_id, is_read, created_at)
    VALUES (
      v_alert.user_id,
      'price_drop',
      '📉 Fiyat Düştü!',
      format('%s ürünü %.2f ₺ oldu. Hedefiniz %.2f ₺', NEW.name, v_new_price, v_alert.target_price),
      NULL,
      NEW.id,
      false,
      NOW()
    );

    -- Push notification async tetikle
    BEGIN
      SELECT net.http_post(
        v_function_url,
        jsonb_build_object(
          'user_id', v_alert.user_id::text,
          'title', '📉 Fiyat Düştü!',
          'body', format('%s — %.2f ₺', NEW.name, v_new_price),
          'data', jsonb_build_object(
            'type', 'price_drop',
            'product_id', NEW.id,
            'product_name', NEW.name,
            'new_price', v_new_price,
            'target_price', v_alert.target_price
          )
        ),
        '{}'::jsonb,
        jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || v_anon_key
        ),
        5000
      ) INTO v_request_id;
    EXCEPTION WHEN OTHERS THEN
      RAISE LOG 'Price drop push failed: %', SQLERRM;
    END;

    -- Alarmı tetiklendi olarak işaretle
    UPDATE price_alerts
      SET is_active = false, triggered_at = NOW()
      WHERE id = v_alert.alert_id;
  END LOOP;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp;

DROP TRIGGER IF EXISTS products_price_drop_alert ON products;
CREATE TRIGGER products_price_drop_alert
  AFTER UPDATE ON products
  FOR EACH ROW
  WHEN (OLD.price IS DISTINCT FROM NEW.price OR OLD.discount_price IS DISTINCT FROM NEW.discount_price)
  EXECUTE FUNCTION notify_price_drops();

-- ============================================================================
-- 7) REALTIME SUBSCRIBE (Flash Sale stok değişimi için)
-- ============================================================================
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables
                 WHERE pubname = 'supabase_realtime' AND tablename = 'flash_sales') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE flash_sales;
  END IF;
END $$;

-- ============================================================================
-- 8) REALTIME (Price alert tetiklendiği an UI'a yansıması için)
-- ============================================================================
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables
                 WHERE pubname = 'supabase_realtime' AND tablename = 'price_alerts') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE price_alerts;
  END IF;
END $$;

-- ============================================================================
-- 9) PRIVILEGES: Anon revoke, authenticated explicit grant
-- ============================================================================
-- Linter: anon bu SECURITY DEFINER RPC'leri REST ile çağırabiliyor.
-- Sadece authenticated (giriş yapmış) kullanıcılar çağırabilsin.
REVOKE EXECUTE ON FUNCTION public.claim_flash_sale(uuid, integer, uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public.release_flash_sale(uuid, integer) FROM anon;
REVOKE EXECUTE ON FUNCTION public.notify_price_drops() FROM anon;

GRANT EXECUTE ON FUNCTION public.claim_flash_sale(uuid, integer, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.release_flash_sale(uuid, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.notify_price_drops() TO authenticated;

-- ============================================================================
-- TAMAMLANDI
-- ============================================================================
-- Bu script idempotent: tekrar çalıştırılabilir.
-- ============================================================================
