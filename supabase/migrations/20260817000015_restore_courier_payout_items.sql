-- =============================================================================
-- Eksik courier_payout_items tablosunu geri yukle.
--
-- request_courier_payout(uuid) PL/pgSQL icinde bu tabloya basvurur. Fonksiyon
-- olusturulurken iliski varligi dogrulanmadigi icin RPC schema'da gorunebilse de
-- eksik tabloda calisma aninda 42P01 hatasi verir.
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '5s';

-- Ust tablolar yoksa eksik payout_items tablosunu tek basina olusturmak guvenli
-- degildir. Belirsiz bir FK hatasi yerine acik bir migration hatasi uret.
DO $$
BEGIN
  IF to_regclass('public.courier_payout_requests') IS NULL THEN
    RAISE EXCEPTION 'public.courier_payout_requests tablosu mevcut degil';
  END IF;

  IF to_regclass('public.courier_earnings') IS NULL THEN
    RAISE EXCEPTION 'public.courier_earnings tablosu mevcut degil';
  END IF;
END;
$$;

CREATE TABLE IF NOT EXISTS public.courier_payout_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  payout_id uuid NOT NULL
    REFERENCES public.courier_payout_requests(id) ON DELETE CASCADE,
  earning_id uuid NOT NULL
    REFERENCES public.courier_earnings(id) ON DELETE RESTRICT,
  amount_snapshot numeric(12, 2) NOT NULL
    CHECK (amount_snapshot >= 0),
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'paid', 'rejected')),
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Bir kazanc yalnizca bir payout istegine baglanabilir. Bu indeks hem tekrarli
-- odemeyi engeller hem de RPC'nin finansal idempotency garantisini tamamlar.
CREATE UNIQUE INDEX IF NOT EXISTS uq_courier_payout_items_earning_id
  ON public.courier_payout_items (earning_id);

CREATE INDEX IF NOT EXISTS idx_courier_payout_items_payout_id
  ON public.courier_payout_items (payout_id);

ALTER TABLE public.courier_payout_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "cpi_select_own_or_admin"
  ON public.courier_payout_items;

CREATE POLICY "cpi_select_own_or_admin"
  ON public.courier_payout_items
  FOR SELECT
  TO authenticated
  USING (
    public.is_admin()
    OR EXISTS (
      SELECT 1
      FROM public.courier_payout_requests AS cpr
      WHERE cpr.id = courier_payout_items.payout_id
        AND cpr.courier_id = (SELECT auth.uid())
    )
  );

-- Finansal satirlar istemciden degil, yalniz SECURITY DEFINER payout RPC'leri
-- tarafindan yazilir. Kurye ve admin istemcileri RLS kapsaminda okuyabilir.
REVOKE ALL ON TABLE public.courier_payout_items FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.courier_payout_items TO authenticated;
GRANT ALL ON TABLE public.courier_payout_items TO service_role;

COMMENT ON TABLE public.courier_payout_items IS
  'Kurye odeme istekleri ile kapsadiklari kazanc satirlari arasindaki degistirilemez bag.';

-- Yeni iliski ve yetkilerin PostgREST tarafindan hemen gorulmesini sagla.
NOTIFY pgrst, 'reload schema';

