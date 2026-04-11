-- ============================================================================
-- ONLINE ÖDEME SİSTEMİ - DATABASE SCHEMA
-- ============================================================================
-- iyzico entegrasyonu + Altbay pazaryeri çekim sistemi
-- Tarih: 2026-02-12

-- ============================================================================
-- 1. PAYMENT_TRANSACTIONS (Ödeme İşlemleri)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.payment_transactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID REFERENCES public.orders(id) ON DELETE SET NULL,
  user_id UUID REFERENCES public.profiles(id) NOT NULL,
  
  -- iyzico bilgileri
  payment_id VARCHAR(100) UNIQUE,
  conversation_id VARCHAR(100),
  token VARCHAR(500),
  payment_status VARCHAR(50) NOT NULL DEFAULT 'pending',
  -- pending, success, failure, refunded, cancelled
  
  -- Tutar bilgileri
  amount DECIMAL(10,2) NOT NULL,
  paid_price DECIMAL(10,2),
  currency VARCHAR(3) DEFAULT 'TRY',
  installment INTEGER DEFAULT 1,
  
  -- Kart bilgileri (maskeli)
  card_type VARCHAR(50),
  card_association VARCHAR(50),
  card_family VARCHAR(50),
  card_bank_name VARCHAR(100),
  last_four_digits VARCHAR(4),
  
  -- 3D Secure
  fraud_status INTEGER DEFAULT 0,
  three_d_secure INTEGER DEFAULT 1,
  
  -- Marketplace bilgileri
  marketplace_sub_merchant_key VARCHAR(200),
  sub_merchant_price DECIMAL(10,2),
  
  -- Callback bilgileri
  callback_received_at TIMESTAMPTZ,
  callback_data JSONB,
  
  -- Hata bilgileri
  error_code VARCHAR(50),
  error_message TEXT,
  error_group VARCHAR(50),
  
  -- Meta
  ip_address VARCHAR(45),
  
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_payment_transactions_order_id ON public.payment_transactions(order_id);
CREATE INDEX IF NOT EXISTS idx_payment_transactions_user_id ON public.payment_transactions(user_id);
CREATE INDEX IF NOT EXISTS idx_payment_transactions_payment_id ON public.payment_transactions(payment_id);
CREATE INDEX IF NOT EXISTS idx_payment_transactions_token ON public.payment_transactions(token);
CREATE INDEX IF NOT EXISTS idx_payment_transactions_status ON public.payment_transactions(payment_status);
CREATE INDEX IF NOT EXISTS idx_payment_transactions_created_at ON public.payment_transactions(created_at);

-- RLS
ALTER TABLE public.payment_transactions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "payment_transactions_select" ON public.payment_transactions
  FOR SELECT TO authenticated
  USING (
    user_id = (SELECT auth.uid())
    OR public.auth_is_admin()
  );

CREATE POLICY "payment_transactions_insert" ON public.payment_transactions
  FOR INSERT TO authenticated
  WITH CHECK (user_id = (SELECT auth.uid()));

CREATE POLICY "payment_transactions_update" ON public.payment_transactions
  FOR UPDATE TO authenticated
  USING (
    user_id = (SELECT auth.uid())
    OR public.auth_is_admin()
  );

COMMENT ON TABLE public.payment_transactions IS 'iyzico ödeme işlem kayıtları';

-- ============================================================================
-- 2. SELLER_BANK_ACCOUNTS (Satıcı Banka Hesapları)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.seller_bank_accounts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shop_id UUID REFERENCES public.shops(id) ON DELETE CASCADE NOT NULL,
  
  -- Banka bilgileri
  iban VARCHAR(34) NOT NULL,
  account_holder_name VARCHAR(200) NOT NULL,
  bank_name VARCHAR(100) NOT NULL,
  branch_name VARCHAR(100),
  
  -- Doğrulama
  is_verified BOOLEAN DEFAULT FALSE,
  verified_at TIMESTAMPTZ,
  verified_by UUID REFERENCES public.profiles(id),
  
  -- Durum
  is_active BOOLEAN DEFAULT TRUE,
  is_default BOOLEAN DEFAULT FALSE,
  
  -- iyzico sub-merchant bilgileri
  sub_merchant_key VARCHAR(200),
  sub_merchant_type VARCHAR(50),
  
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  
  UNIQUE(shop_id, iban)
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_seller_bank_accounts_shop_id ON public.seller_bank_accounts(shop_id);
CREATE INDEX IF NOT EXISTS idx_seller_bank_accounts_active ON public.seller_bank_accounts(is_active);

-- RLS
ALTER TABLE public.seller_bank_accounts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "seller_bank_accounts_select" ON public.seller_bank_accounts
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.shops s
      WHERE s.id = seller_bank_accounts.shop_id
      AND s.owner_id = (SELECT auth.uid())
    )
    OR public.auth_is_admin()
  );

CREATE POLICY "seller_bank_accounts_insert" ON public.seller_bank_accounts
  FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.shops s
      WHERE s.id = seller_bank_accounts.shop_id
      AND s.owner_id = (SELECT auth.uid())
    )
  );

CREATE POLICY "seller_bank_accounts_update" ON public.seller_bank_accounts
  FOR UPDATE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.shops s
      WHERE s.id = seller_bank_accounts.shop_id
      AND s.owner_id = (SELECT auth.uid())
    )
    OR public.auth_is_admin()
  );

CREATE POLICY "seller_bank_accounts_delete" ON public.seller_bank_accounts
  FOR DELETE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.shops s
      WHERE s.id = seller_bank_accounts.shop_id
      AND s.owner_id = (SELECT auth.uid())
    )
  );

COMMENT ON TABLE public.seller_bank_accounts IS 'Satıcı banka hesapları (çekim için)';

-- ============================================================================
-- 3. PAYOUT_TRANSACTIONS (Satıcı Çekim İşlemleri)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.payout_transactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  payout_request_id UUID REFERENCES public.payout_requests(id) ON DELETE SET NULL,
  shop_id UUID REFERENCES public.shops(id) NOT NULL,
  bank_account_id UUID REFERENCES public.seller_bank_accounts(id),
  
  -- İşlem bilgileri
  transaction_ref VARCHAR(100) UNIQUE,
  payout_status VARCHAR(50) NOT NULL DEFAULT 'pending',
  -- pending, processing, completed, failed, cancelled
  
  -- Tutar bilgileri
  amount DECIMAL(10,2) NOT NULL,
  commission DECIMAL(10,2) DEFAULT 0,
  net_amount DECIMAL(10,2) NOT NULL,
  currency VARCHAR(3) DEFAULT 'TRY',
  
  -- Banka bilgileri (snapshot)
  bank_name VARCHAR(100),
  iban_last_4 VARCHAR(4),
  account_holder_name VARCHAR(200),
  
  -- Admin onayı
  approved_by UUID REFERENCES public.profiles(id),
  approved_at TIMESTAMPTZ,
  approval_notes TEXT,
  
  -- İşlem sonucu
  completed_at TIMESTAMPTZ,
  
  -- Hata bilgileri
  error_code VARCHAR(50),
  error_message TEXT,
  
  -- Meta
  metadata JSONB,
  
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_payout_transactions_shop_id ON public.payout_transactions(shop_id);
CREATE INDEX IF NOT EXISTS idx_payout_transactions_status ON public.payout_transactions(payout_status);
CREATE INDEX IF NOT EXISTS idx_payout_transactions_request_id ON public.payout_transactions(payout_request_id);
CREATE INDEX IF NOT EXISTS idx_payout_transactions_created_at ON public.payout_transactions(created_at);

-- RLS
ALTER TABLE public.payout_transactions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "payout_transactions_select" ON public.payout_transactions
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.shops s
      WHERE s.id = payout_transactions.shop_id
      AND s.owner_id = (SELECT auth.uid())
    )
    OR public.auth_is_admin()
  );

CREATE POLICY "payout_transactions_insert" ON public.payout_transactions
  FOR INSERT TO authenticated
  WITH CHECK (
    public.auth_is_admin()
  );

CREATE POLICY "payout_transactions_update" ON public.payout_transactions
  FOR UPDATE TO authenticated
  USING (
    public.auth_is_admin()
  );

COMMENT ON TABLE public.payout_transactions IS 'Satıcı bakiye çekim işlem kayıtları';

-- ============================================================================
-- 4. ORDERS TABLOSUNA YENİ ALANLAR EKLE
-- ============================================================================
ALTER TABLE public.orders 
  ADD COLUMN IF NOT EXISTS payment_transaction_id UUID REFERENCES public.payment_transactions(id),
  ADD COLUMN IF NOT EXISTS iyzico_payment_id VARCHAR(100),
  ADD COLUMN IF NOT EXISTS iyzico_conversation_id VARCHAR(100);

CREATE INDEX IF NOT EXISTS idx_orders_payment_transaction_id ON public.orders(payment_transaction_id);
CREATE INDEX IF NOT EXISTS idx_orders_iyzico_payment_id ON public.orders(iyzico_payment_id);

-- ============================================================================
-- 5. PAYOUT_REQUESTS TABLOSUNA YENİ ALANLAR EKLE
-- ============================================================================
ALTER TABLE public.payout_requests
  ADD COLUMN IF NOT EXISTS payout_transaction_id UUID REFERENCES public.payout_transactions(id),
  ADD COLUMN IF NOT EXISTS bank_account_id UUID REFERENCES public.seller_bank_accounts(id);

CREATE INDEX IF NOT EXISTS idx_payout_requests_transaction_id ON public.payout_requests(payout_transaction_id);
CREATE INDEX IF NOT EXISTS idx_payout_requests_bank_account_id ON public.payout_requests(bank_account_id);

-- ============================================================================
-- 6. UPDATED_AT TRİGGER FONKSİYONLARI
-- ============================================================================
CREATE OR REPLACE FUNCTION public.update_payment_transactions_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

CREATE TRIGGER update_payment_transactions_updated_at
  BEFORE UPDATE ON public.payment_transactions
  FOR EACH ROW
  EXECUTE FUNCTION public.update_payment_transactions_updated_at();

CREATE OR REPLACE FUNCTION public.update_seller_bank_accounts_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

CREATE TRIGGER update_seller_bank_accounts_updated_at
  BEFORE UPDATE ON public.seller_bank_accounts
  FOR EACH ROW
  EXECUTE FUNCTION public.update_seller_bank_accounts_updated_at();

CREATE OR REPLACE FUNCTION public.update_payout_transactions_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

CREATE TRIGGER update_payout_transactions_updated_at
  BEFORE UPDATE ON public.payout_transactions
  FOR EACH ROW
  EXECUTE FUNCTION public.update_payout_transactions_updated_at();

-- ============================================================================
-- 7. ÖDEME SONRASI SİPARİŞ OLUŞTURMA FONKSİYONU
-- ============================================================================
-- Bu fonksiyon iyzico callback Edge Function tarafından çağrılır
CREATE OR REPLACE FUNCTION public.complete_online_payment(
  p_payment_transaction_id UUID,
  p_iyzico_payment_id VARCHAR,
  p_order_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Payment transaction'ı güncelle
  UPDATE public.payment_transactions
  SET payment_status = 'success',
      payment_id = p_iyzico_payment_id,
      callback_received_at = NOW(),
      updated_at = NOW()
  WHERE id = p_payment_transaction_id;
  
  -- Siparişi güncelle
  UPDATE public.orders
  SET payment_status = 'paid',
      payment_transaction_id = p_payment_transaction_id,
      iyzico_payment_id = p_iyzico_payment_id,
      updated_at = NOW()
  WHERE id = p_order_id;
END;
$$;

COMMENT ON FUNCTION public.complete_online_payment IS 'iyzico ödeme başarılı callback sonrası çağrılır';

DO $$
BEGIN
    RAISE NOTICE '✅ Online ödeme sistemi tabloları oluşturuldu:';
    RAISE NOTICE '   - payment_transactions (iyzico ödemeleri)';
    RAISE NOTICE '   - seller_bank_accounts (satıcı banka hesapları)';
    RAISE NOTICE '   - payout_transactions (satıcı çekim işlemleri)';
    RAISE NOTICE '   - orders tablosuna payment alanları eklendi';
    RAISE NOTICE '   - payout_requests tablosuna bank_account alanı eklendi';
    RAISE NOTICE '   - RLS policy''leri ve trigger''lar oluşturuldu';
END $$;
