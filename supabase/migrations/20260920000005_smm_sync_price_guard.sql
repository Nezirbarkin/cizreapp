-- =============================================================================
-- Dijital (SMM) ürünler: sağlayıcıda hizmet/ID/fiyat değişirse ürün otomatik
-- "tükendi" (is_available=false) olur.
--
-- smm-sync-products Edge Function'ı sağlayıcının `services` listesini çeker ve
-- her ürünü smm_product_baselines'taki taban değerlerle karşılaştırır:
--   provider_rate  sağlayıcının 1000 adet fiyatı (satıcı hizmeti seçtiği andaki ya da
--                  ilk senkronda alınan taban değer)
--   service_name   hizmetin sağlayıcıdaki adı (ID başka bir hizmete atanırsa ad değişir —
--                  "ID değişti" sinyali)
--
--   ID artık listede yok            -> kapat, smm_disabled_kind = 'missing'
--   ID var, ad değişmiş             -> kapat, smm_disabled_kind = 'service_changed'
--   ID var, fiyat değişmiş          -> kapat, smm_disabled_kind = 'price_changed'
--
-- Taban değerler BİLEREK products'ta DEĞİL, ayrı ve istemciye kapalı bir tabloda:
-- products herkesçe okunabiliyor; sağlayıcı fiyatı satıcının MALİYETİDİR ve
-- müşteriye sızmamalı. Aynı gerekçeyle smm_disabled_reason metni rakam içermez.
--
-- 'missing' düzelirse (hizmet geri gelirse ve ad/fiyat aynıysa) ürün otomatik açılır.
-- 'price_changed' / 'service_changed' OTOMATİK AÇILMAZ: satıcının/adminin yeni durumu
-- bilerek kabul etmesi gerekir. Kabul = ürünü elle tekrar açmak; alttaki tetikleyici bu
-- durumda tabanı siler, bir sonraki senkron mevcut değerleri yeni taban alır ve ürünü
-- tekrar kapatmaz.
-- =============================================================================

BEGIN;

ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS smm_disabled_kind text;

-- Bu tasarımın ilk taslağı taban değerleri products'a yazıyordu (müşteriye sızardı).
ALTER TABLE public.products
  DROP COLUMN IF EXISTS smm_provider_rate,
  DROP COLUMN IF EXISTS smm_service_name,
  DROP COLUMN IF EXISTS smm_last_synced_at;

ALTER TABLE public.products DROP CONSTRAINT IF EXISTS products_smm_disabled_kind_check;
ALTER TABLE public.products ADD CONSTRAINT products_smm_disabled_kind_check
  CHECK (smm_disabled_kind IS NULL OR smm_disabled_kind IN ('missing', 'service_changed', 'price_changed'));

-- Eski senkron yalnızca 'missing' biliyordu ve neden metnini yazıyordu.
UPDATE public.products
   SET smm_disabled_kind = 'missing'
 WHERE smm_disabled_reason IS NOT NULL AND smm_disabled_kind IS NULL;

CREATE TABLE IF NOT EXISTS public.smm_product_baselines (
  product_id    uuid PRIMARY KEY REFERENCES public.products(id) ON DELETE CASCADE,
  provider_rate numeric(12,4),
  service_name  text,
  updated_at    timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.smm_product_baselines ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.smm_product_baselines FROM PUBLIC, anon, authenticated;
GRANT ALL ON public.smm_product_baselines TO service_role;

COMMENT ON TABLE public.smm_product_baselines IS
  'SMM ürünlerinin sağlayıcı fiyat/ad tabanı. Satıcı maliyeti içerdiği için istemciye kapalı; yalnız service_role ve smm_set_product_baseline RPC''si.';

-- Satıcı/admin bir hizmeti seçtiğinde tabanı yazar (istemci tabloya doğrudan erişemez).
CREATE OR REPLACE FUNCTION public.smm_set_product_baseline(
  p_product_id uuid,
  p_rate       numeric,
  p_name       text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'smm_set_product_baseline: not authenticated' USING ERRCODE = '28000';
  END IF;

  IF NOT (
    private.current_user_is_admin()
    OR EXISTS (
      SELECT 1
      FROM public.products pr
      JOIN public.shops s ON s.id = pr.shop_id
      WHERE pr.id = p_product_id AND s.owner_id = auth.uid()
    )
  ) THEN
    RAISE EXCEPTION 'smm_set_product_baseline: forbidden' USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.smm_product_baselines AS b (product_id, provider_rate, service_name, updated_at)
  VALUES (p_product_id, p_rate, NULLIF(btrim(COALESCE(p_name, '')), ''), now())
  ON CONFLICT (product_id) DO UPDATE
    SET provider_rate = EXCLUDED.provider_rate,
        service_name = EXCLUDED.service_name,
        updated_at = now();
END;
$$;

REVOKE ALL ON FUNCTION public.smm_set_product_baseline(uuid, numeric, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.smm_set_product_baseline(uuid, numeric, text) TO authenticated, service_role;

-- Elle yeniden açma = yeni durumu kabul etme (yukarıdaki açıklama).
-- service_role (Edge Function) bu tetikleyiciyi atlar: kendi kararını kendisi yazar.
CREATE OR REPLACE FUNCTION public.products_smm_accept_on_reenable()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF COALESCE(auth.role(), '') <> 'service_role'
     AND OLD.is_available = false
     AND NEW.is_available = true
     AND OLD.smm_disabled_kind IN ('price_changed', 'service_changed') THEN
    DELETE FROM public.smm_product_baselines WHERE product_id = NEW.id;
    NEW.smm_disabled_kind := NULL;
    NEW.smm_disabled_reason := NULL;
  END IF;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.products_smm_accept_on_reenable() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_products_smm_accept_on_reenable ON public.products;
CREATE TRIGGER trg_products_smm_accept_on_reenable
  BEFORE UPDATE OF is_available ON public.products
  FOR EACH ROW EXECUTE FUNCTION public.products_smm_accept_on_reenable();

-- Otomatik senkron: 10 dakikada bir. Kimlik bilgileri vault'ta (smm-order-status-check
-- cron'uyla aynı kaynak); komut, mevcut işin komutunun URL'si değiştirilerek üretilir.
DO $$
DECLARE
  v_cmd text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    RETURN;
  END IF;
  SELECT command INTO v_cmd FROM cron.job WHERE jobname = 'smm-order-status-check-5min';
  IF v_cmd IS NULL THEN
    RAISE NOTICE 'smm-order-status-check-5min bulunamadı; smm-sync-products cron''u kurulmadı';
    RETURN;
  END IF;

  PERFORM cron.unschedule('smm-sync-products-10min')
  WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'smm-sync-products-10min');
  PERFORM cron.schedule(
    'smm-sync-products-10min',
    '*/10 * * * *',
    replace(v_cmd, 'smm-order-status-check', 'smm-sync-products')
  );
END;
$$;

COMMIT;

NOTIFY pgrst, 'reload schema';
