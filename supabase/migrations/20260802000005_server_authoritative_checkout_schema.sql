-- ════════════════════════════════════════════════════════════════════════
-- SERVER-AUTHORITATIVE CHECKOUT ŞEMASI
-- Tarih: 2026-08-02
-- ════════════════════════════════════════════════════════════════════════
-- Bu migration, finansal checkout akışını client-authoritative'den
-- server-authoritative'e taşımak için gerekli yeni şema ve tabloları
-- oluşturur.
--
-- YENİ NESNELER:
--   - private şema (authenticated/anon GRANT yok, sadece service_role)
--   - private.server_checkout_sessions (immutable, server yazar)
--   - private.server_checkout_session_items (immutable, server yazar)
--   - private.flash_sale_reservations (rezervasyon, FOR UPDATE ile)
--   - private.server_checkout_audit (admin SELECT)
--   - public.orders, public.order_items, public.payment_transactions
--     kolon eklentileri (checkout_session_id, expected_amount, vb.)
-- ════════════════════════════════════════════════════════════════════════

-- ════════════════════════════════════════════════════════════════════════
-- 1) PRIVATE ŞEMA
-- ════════════════════════════════════════════════════════════════════════
-- Bu şemadaki tablolar PostgREST API'den hiçbir zaman EXPOSE EDILMEZ.
-- SECURITY DEFINER RPC'ler bu şemaya erişir; anon/authenticated
-- role'larinin GRANT'i yoktur.
CREATE SCHEMA IF NOT EXISTS private;
COMMENT ON SCHEMA private IS
  'Server-internal financial state. authenticated ve anon rollerine HIC BIR ZAMAN GRANT verilmez. service_role + SECURITY DEFINER RPC''ler uzerinden erisilir.';

-- authenticated ve anon'a tum tablolar uzerinde tum yetkileri kapat
-- (ileride yeni private.* tablolar eklendiginde de gecerli olmasi icin
-- tum tablolari REVOKE eden yardimci fonksiyon)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN
    EXECUTE 'REVOKE ALL ON SCHEMA private FROM authenticated';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='anon') THEN
    EXECUTE 'REVOKE ALL ON SCHEMA private FROM anon';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='public') THEN
    EXECUTE 'REVOKE ALL ON SCHEMA private FROM public';
  END IF;
END $$;

-- service_role tam erişim (gerekirse SECURITY DEFINER RPC'ler için)
GRANT USAGE ON SCHEMA private TO service_role;

-- ════════════════════════════════════════════════════════════════════════
-- 2) server_checkout_sessions
-- ════════════════════════════════════════════════════════════════════════
-- Client-authoritative alanlar (user_id, total, vb.) YOKTUR.
-- user_id her zaman auth.uid()'den veya SECURITY DEFINER baglamindan set edilir.
CREATE TABLE IF NOT EXISTS private.server_checkout_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- user_id: auth.uid() ile set edilir, client INSERT ile set edilemez
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

  -- Idempotency: ayni user + key ile iki kez prepare = tek session
  idempotency_key TEXT NOT NULL,
  payment_method TEXT NOT NULL CHECK (payment_method IN
    ('cash','card_on_delivery','balance','online')),
  currency CHAR(3) NOT NULL DEFAULT 'TRY' CHECK (currency = 'TRY'),

  -- Address: kullanicinin kendi adresi (private.server tarafindan dogrulanir)
  address_id UUID REFERENCES public.addresses(id) ON DELETE SET NULL,

  -- Coupon: shop_coupons'tan (yine server dogrulamali)
  coupon_id UUID REFERENCES public.shop_coupons(id) ON DELETE SET NULL,

  -- Order group: multi-shop siparisler icin birden fazla session'i baglar
  order_group_id UUID,

  -- ═════════════════════════════════════════════════════════════════
  -- SERVER-AUTHORITATIVE FINANSAL ALANLAR
  -- Bu degerler client tarafindan ASLA set edilmez. prepare_checkout_session
  -- veya commit_*_order RPC'leri tarafindan hesaplanir.
  -- ═════════════════════════════════════════════════════════════════
  server_subtotal NUMERIC(12,2) NOT NULL CHECK (server_subtotal >= 0),
  server_delivery_fee NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (server_delivery_fee >= 0),
  server_discount NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (server_discount >= 0),
  server_coupon_discount NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (server_coupon_discount >= 0),
  server_commission_amount NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (server_commission_amount >= 0),
  server_total NUMERIC(12,2) NOT NULL CHECK (server_total >= 0),

  -- Multi-shop icin: alt-siparis tutarlari (yoksa NULL)
  sub_order_subtotals JSONB,            -- {shop_id: subtotal}
  sub_order_delivery_fees JSONB,        -- {shop_id: delivery_fee}
  sub_order_coupon_discounts JSONB,     -- {shop_id: coupon_discount}

  -- Snapshot (fatura/raporlama): client tarafindan degil, server tarafindan
  -- products ve shops tablolarindan cekilip yazildi
  items_snapshot JSONB NOT NULL,         -- [{product_id, name, shop_id, shop_name, image_url, quantity, unit_price, subtotal, variant_data, flash_sale_id, flash_price}]
  delivery_address_snapshot JSONB,       -- {id, full_address, district, city, phone}

  -- ═════════════════════════════════════════════════════════════════
  -- ONLINE ODEME ICIN BEKLENEN TUTAR (iyzico init sirasinda set)
  -- Callback'te iyzico retrieve response'u ile karsilastirilir.
  -- ═════════════════════════════════════════════════════════════════
  expected_currency CHAR(3),
  expected_paid_price NUMERIC(12,2),
  expected_conversation_id TEXT,
  expected_basket_id TEXT,
  iyzico_environment TEXT CHECK (iyzico_environment IN ('sandbox','production') OR iyzico_environment IS NULL),

  -- Lifecycle
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','committed','expired','cancelled','failed')),
  expires_at TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '15 minutes'),
  committed_at TIMESTAMPTZ,
  cancelled_at TIMESTAMPTZ,
  cancellation_reason TEXT,

  -- Link'ler (commit sonrasi)
  payment_transaction_id UUID REFERENCES public.payment_transactions(id) ON DELETE SET NULL,
  order_id UUID,
  order_group_order_id UUID,

  -- Notes / invoice (server validate eder; uzunluk sinirli)
  notes TEXT CHECK (notes IS NULL OR length(notes) <= 500),
  invoice_data JSONB,

  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT scs_total_arithmetic CHECK (
    server_total = server_subtotal + server_delivery_fee - server_discount - server_coupon_discount
  ),
  CONSTRAINT scs_unique_user_idempotency UNIQUE (user_id, idempotency_key)
);

COMMENT ON TABLE private.server_checkout_sessions IS
  'Server-authoritative checkout session. Client INSERT/UPDATE/DELETE YAPAMAZ. Tum finansal alanlar server tarafindan hesaplanir.';

-- Indexes
CREATE INDEX IF NOT EXISTS idx_scs_user_status
  ON private.server_checkout_sessions(user_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_scs_expires_at
  ON private.server_checkout_sessions(expires_at) WHERE status = 'pending';
CREATE INDEX IF NOT EXISTS idx_scs_order_id
  ON private.server_checkout_sessions(order_id) WHERE order_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_scs_payment_txn
  ON private.server_checkout_sessions(payment_transaction_id)
  WHERE payment_transaction_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_scs_order_group
  ON private.server_checkout_sessions(order_group_id)
  WHERE order_group_id IS NOT NULL;

-- updated_at trigger
CREATE OR REPLACE FUNCTION private.trg_scs_set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS scs_set_updated_at ON private.server_checkout_sessions;
CREATE TRIGGER scs_set_updated_at
  BEFORE UPDATE ON private.server_checkout_sessions
  FOR EACH ROW
  EXECUTE FUNCTION private.trg_scs_set_updated_at();

-- ════════════════════════════════════════════════════════════════════════
-- 3) flash_sale_reservations
-- ════════════════════════════════════════════════════════════════════════
-- Stok rezervasyonu add-to-cart'ta DEGIL, prepare_checkout_session sirasinda
-- yapilir. Commit_*_order basarili olunca status='committed' + sold_count++.
-- Session iptal/expired olunca status='released' (client tetiklemez).
CREATE TABLE IF NOT EXISTS private.flash_sale_reservations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  sale_id UUID NOT NULL REFERENCES public.flash_sales(id) ON DELETE CASCADE,
  session_id UUID NOT NULL REFERENCES private.server_checkout_sessions(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
  shop_id UUID NOT NULL REFERENCES public.shops(id) ON DELETE CASCADE,

  quantity INTEGER NOT NULL CHECK (quantity > 0 AND quantity <= 100),

  -- Snapshot (commit sirasinda orders.flash_sale_id/flash_price icin kullanilir)
  unit_price NUMERIC(12,2) NOT NULL CHECK (unit_price > 0),
  original_price NUMERIC(12,2) NOT NULL CHECK (original_price > 0),

  status TEXT NOT NULL DEFAULT 'active'
    CHECK (status IN ('active','committed','released','expired')),
  expires_at TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '15 minutes'),
  committed_at TIMESTAMPTZ,
  released_at TIMESTAMPTZ,
  release_reason TEXT,

  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- Ayni session'da ayni sale iki kez rezerve edilemez (idempotency)
  CONSTRAINT fsr_session_sale_unique UNIQUE (session_id, sale_id)
);

COMMENT ON TABLE private.flash_sale_reservations IS
  'Flash sale stok rezervasyonu. add-to-cart degil, prepare_checkout_session sirasinda olusturulur. Client INSERT/UPDATE/DELETE YAPAMAZ.';

CREATE INDEX IF NOT EXISTS idx_fsr_session
  ON private.flash_sale_reservations(session_id);
CREATE INDEX IF NOT EXISTS idx_fsr_user_status
  ON private.flash_sale_reservations(user_id, status);
CREATE INDEX IF NOT EXISTS idx_fsr_sale_status
  ON private.flash_sale_reservations(sale_id, status);
CREATE INDEX IF NOT EXISTS idx_fsr_expires_at
  ON private.flash_sale_reservations(expires_at) WHERE status = 'active';

DROP TRIGGER IF EXISTS fsr_set_updated_at ON private.flash_sale_reservations;
CREATE TRIGGER fsr_set_updated_at
  BEFORE UPDATE ON private.flash_sale_reservations
  FOR EACH ROW
  EXECUTE FUNCTION private.trg_scs_set_updated_at();

-- ════════════════════════════════════════════════════════════════════════
-- 4) server_checkout_audit
-- ════════════════════════════════════════════════════════════════════════
-- Iyzico signature_invalid / amount_mismatch gibi guvenlik olaylarini
-- admin'in inceleyebilecegi append-only tablo.
CREATE TABLE IF NOT EXISTS private.server_checkout_audit (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  session_id UUID REFERENCES private.server_checkout_sessions(id) ON DELETE SET NULL,
  payment_transaction_id UUID REFERENCES public.payment_transactions(id) ON DELETE SET NULL,
  user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,

  event_type TEXT NOT NULL CHECK (event_type IN (
    'session_prepared',
    'session_committed',
    'session_expired',
    'session_cancelled',
    'amount_mismatch',
    'signature_invalid',
    'currency_mismatch',
    'env_mismatch',
    'product_unavailable',
    'coupon_invalid',
    'balance_insufficient',
    'flash_stock_exhausted',
    'oversell_blocked',
    'duplicate_callback',
    'manual_reconciliation_required'
  )),

  -- Olay detaylari (PII icermez; sadece transaction_id ve tutar bilgisi)
  detail JSONB NOT NULL DEFAULT '{}'::JSONB,

  -- Cozum durumu (admin isaretleyebilir)
  resolved_at TIMESTAMPTZ,
  resolved_by UUID REFERENCES auth.users(id),
  resolution_note TEXT,

  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE private.server_checkout_audit IS
  'Guvenlik/reconciliation olaylari. Sadece admin SELECT yapabilir (public.server_checkout_audit_admin view ile).';

CREATE INDEX IF NOT EXISTS idx_sca_session
  ON private.server_checkout_audit(session_id) WHERE session_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_sca_event_type
  ON private.server_checkout_audit(event_type, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_sca_unresolved
  ON private.server_checkout_audit(created_at DESC) WHERE resolved_at IS NULL;

-- Audit tablosu INSERT-only (UPDATE/DELETE yok)
CREATE OR REPLACE FUNCTION private.server_checkout_audit_no_modify()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  RAISE EXCEPTION 'server_checkout_audit tablosu append-only: UPDATE/DELETE yasak';
END;
$$;

DROP TRIGGER IF EXISTS sca_no_update ON private.server_checkout_audit;
CREATE TRIGGER sca_no_update
  BEFORE UPDATE ON private.server_checkout_audit
  FOR EACH ROW EXECUTE FUNCTION private.server_checkout_audit_no_modify();

DROP TRIGGER IF EXISTS sca_no_delete ON private.server_checkout_audit;
CREATE TRIGGER sca_no_delete
  BEFORE DELETE ON private.server_checkout_audit
  FOR EACH ROW EXECUTE FUNCTION private.server_checkout_audit_no_modify();

-- ════════════════════════════════════════════════════════════════════════
-- 5) MEVCUT TABLOLARA YENI KOLONLAR
-- ════════════════════════════════════════════════════════════════════════

-- orders: checkout_session_id link
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS checkout_session_id UUID,
  ADD COLUMN IF NOT EXISTS committed_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS price_mismatch BOOLEAN NOT NULL DEFAULT false;

CREATE INDEX IF NOT EXISTS idx_orders_checkout_session_id
  ON public.orders(checkout_session_id) WHERE checkout_session_id IS NOT NULL;

-- payment_transactions: server-authoritative alanlar
ALTER TABLE public.payment_transactions
  ADD COLUMN IF NOT EXISTS checkout_session_id UUID,
  ADD COLUMN IF NOT EXISTS expected_amount NUMERIC(12,2),
  ADD COLUMN IF NOT EXISTS expected_currency CHAR(3),
  ADD COLUMN IF NOT EXISTS expected_conversation_id TEXT,
  ADD COLUMN IF NOT EXISTS expected_basket_id TEXT,
  ADD COLUMN IF NOT EXISTS iyzico_environment TEXT CHECK (iyzico_environment IN ('sandbox','production') OR iyzico_environment IS NULL),
  ADD COLUMN IF NOT EXISTS idempotency_key TEXT,
  ADD COLUMN IF NOT EXISTS reconciliation_status TEXT,
  ADD COLUMN IF NOT EXISTS reconciliation_note TEXT;

CREATE INDEX IF NOT EXISTS idx_pt_checkout_session
  ON public.payment_transactions(checkout_session_id) WHERE checkout_session_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_pt_idempotency
  ON public.payment_transactions(idempotency_key) WHERE idempotency_key IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_pt_reconciliation
  ON public.payment_transactions(reconciliation_status) WHERE reconciliation_status IS NOT NULL;

-- ════════════════════════════════════════════════════════════════════════
-- 6) service_role TAM ERISIM
-- ════════════════════════════════════════════════════════════════════════
GRANT ALL ON private.server_checkout_sessions TO service_role;
GRANT ALL ON private.server_checkout_session_items TO service_role;
GRANT ALL ON private.flash_sale_reservations TO service_role;
GRANT ALL ON private.server_checkout_audit TO service_role;
GRANT ALL ON private.trg_scs_set_updated_at TO service_role;
GRANT ALL ON private.server_checkout_audit_no_modify TO service_role;

-- ════════════════════════════════════════════════════════════════════════
-- 7) NOTIFY
-- ════════════════════════════════════════════════════════════════════════
DO $$
BEGIN
    RAISE NOTICE '════════════════════════════════════════════════════════════';
    RAISE NOTICE '✅ Server-Authoritative Checkout şeması oluşturuldu';
    RAISE NOTICE '   - private.server_checkout_sessions (immutable)';
    RAISE NOTICE '   - private.flash_sale_reservations (immutable)';
    RAISE NOTICE '   - private.server_checkout_audit (append-only)';
    RAISE NOTICE '   - orders.checkout_session_id, committed_at, price_mismatch';
    RAISE NOTICE '   - payment_transactions.checkout_session_id, expected_*';
    RAISE NOTICE '';
    RAISE NOTICE '   Sonraki adım: 20260802000006_prepare_checkout_session_rpc.sql';
    RAISE NOTICE '════════════════════════════════════════════════════════════';
END $$;
