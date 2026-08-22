-- ============================================================================
-- İPTAL + İADE ADMIN ONAYLI AKIŞI — Tablo altyapısı
-- ----------------------------------------------------------------------------
-- Müşteri iptal TALEBİ açar (sebep ile). Admin onaylar → aynı anda:
--   1) orders.status = 'cancelled', payment_status = 'refunded' (iade varsa)
--   2) refund_method='balance' ise add_to_balance RPC ile CizreApp bakiyesine
--      atomik iade (balance_transactions type='refund')
--   3) restore_product_stock trigger'ı stokları geri yükler (confirmed->cancelled)
--   4) Müşteriye notification
-- Admin reddederse sadece notification gider; sipariş olduğu gibi kalır.
--
-- İade kuralları (snapshot, talep anında kilitlenir):
--   payment_method IN ('balance','online') -> refund_method='balance', refund_amount=total
--   payment_method IN ('cash','card_on_delivery') -> refund_method='none', refund_amount=0
--
-- Bağımlılıklar:
--   - public.orders (payment_method text, payment_status enum('pending','paid','refunded'))
--   - public.profiles (role text, 'admin')
--   - public.is_admin() SECURITY DEFINER fonksiyonu (20260209000005_security_fixes.sql)
--   - public.add_to_balance(...) RETURNS UUID (20260621000007_CREATE_BALANCE_SYSTEM.sql)
--   - public.restore_product_stock trigger (20260211000001_stock_management_trigger.sql)
--   - public.notifications (type text, entity_id text)
--   - public.update_updated_at_column() (20260207000007_create_chat_system.sql)
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1) TABLO
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.cancellation_requests (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id        UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
    user_id         UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    shop_id         UUID REFERENCES public.shops(id) ON DELETE SET NULL,

    -- Müşteri talebi
    reason          TEXT NOT NULL,

    -- Durum: pending -> approved | rejected | cancelled
    status          TEXT NOT NULL DEFAULT 'pending'
                    CHECK (status IN ('pending','approved','rejected','cancelled')),

    -- İADE SNAPSHOT (talep anında kilitlenir; onayda değişmez)
    order_total     NUMERIC(12,2) NOT NULL DEFAULT 0,
    payment_method  TEXT NOT NULL,                       -- siparişin anlık payment_method
    refund_method   TEXT NOT NULL DEFAULT 'none'
                    CHECK (refund_method IN ('balance','none')),
    refund_amount   NUMERIC(12,2) NOT NULL DEFAULT 0,

    -- İnceleme (admin)
    reviewed_by     UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    reviewed_at     TIMESTAMPTZ,
    admin_response  TEXT,
    -- approve sırasında add_to_balance'nin oluşturduğu refund transaction (varsa)
    balance_transaction_id UUID,

    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ---------------------------------------------------------------------------
-- 2) INDEX'LER
-- ---------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_cancellation_requests_user_id
    ON public.cancellation_requests(user_id);

CREATE INDEX IF NOT EXISTS idx_cancellation_requests_status
    ON public.cancellation_requests(status);

CREATE INDEX IF NOT EXISTS idx_cancellation_requests_created_at
    ON public.cancellation_requests(created_at DESC);

-- Her sipariş için tek AKTİF (pending) talep — partial unique index
-- (onay/reddedilmiş talepler geçmiş için tutulur, yenisi açılabilir)
CREATE UNIQUE INDEX IF NOT EXISTS idx_cancellation_requests_active_order
    ON public.cancellation_requests(order_id)
    WHERE status = 'pending';

-- ---------------------------------------------------------------------------
-- 3) updated_at TRIGGER
-- ---------------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_cancellation_requests_updated_at
    ON public.cancellation_requests;

CREATE TRIGGER trg_cancellation_requests_updated_at
    BEFORE UPDATE ON public.cancellation_requests
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_at_column();

-- ---------------------------------------------------------------------------
-- 4) RLS
-- ---------------------------------------------------------------------------
ALTER TABLE public.cancellation_requests ENABLE ROW LEVEL SECURITY;

-- Eski politikalari temizle (idempotent)
DROP POLICY IF EXISTS "cr_select_own"        ON public.cancellation_requests;
DROP POLICY IF EXISTS "cr_select_admin"      ON public.cancellation_requests;
DROP POLICY IF EXISTS "cr_select_shop"       ON public.cancellation_requests;
DROP POLICY IF EXISTS "cr_insert_own"        ON public.cancellation_requests;
DROP POLICY IF EXISTS "cr_update_admin"      ON public.cancellation_requests;
DROP POLICY IF EXISTS "cr_delete_admin"      ON public.cancellation_requests;

-- SELECT: müşteri kendi talepleri
CREATE POLICY "cr_select_own"
    ON public.cancellation_requests FOR SELECT TO authenticated
    USING (user_id = auth.uid());

-- SELECT: admin tüm talepler
CREATE POLICY "cr_select_admin"
    ON public.cancellation_requests FOR SELECT TO authenticated
    USING (public.is_admin());

-- SELECT: mağaza sahibi kendi mağazasının talepleri
CREATE POLICY "cr_select_shop"
    ON public.cancellation_requests FOR SELECT TO authenticated
    USING (
        shop_id IS NOT NULL
        AND shop_id IN (SELECT id FROM public.shops WHERE owner_id = auth.uid())
    );

-- INSERT: sadece authenticated kullanıcı kendi user_id'si ile
-- (RPC SECURITY DEFINER ile insert ediliyor; burada yine de sınır koyuyoruz)
CREATE POLICY "cr_insert_own"
    ON public.cancellation_requests FOR INSERT TO authenticated
    WITH CHECK (user_id = auth.uid());

-- UPDATE: sadece admin (approve/reject RPC'leri SECURITY DEFINER)
CREATE POLICY "cr_update_admin"
    ON public.cancellation_requests FOR UPDATE TO authenticated
    USING (public.is_admin())
    WITH CHECK (public.is_admin());

-- DELETE: sadece admin (geçmiş temizliği için opsiyonel)
CREATE POLICY "cr_delete_admin"
    ON public.cancellation_requests FOR DELETE TO authenticated
    USING (public.is_admin());

-- ---------------------------------------------------------------------------
-- 5) YORUMLAR
-- ---------------------------------------------------------------------------
COMMENT ON TABLE public.cancellation_requests IS
'İptal+İade admin onaylı talepler. Müşteri açar, admin onaylar -> sipariş cancelled + bakiye iade.';
COMMENT ON COLUMN public.cancellation_requests.refund_method IS
'balance: CizreApp bakiyesine iade | none: cash/card_on_delivery (iade yok)';
COMMENT ON COLUMN public.cancellation_requests.refund_amount IS
'Onay anında add_to_balance ile eklenecek tutar (snapshot). 0 ise iade yok.';
COMMENT ON COLUMN public.cancellation_requests.balance_transaction_id IS
'approve RPCsinin add_to_balance ile oluşturduğu refund transaction id (refund_amount>0 ise).';