-- ============================================================================
-- 2026-08-25 | Satici paneli: coklu urunlerde "2 Al Biri Bakiye" kampanyasi
-- ============================================================================
-- "2 Al Biri Bakiye" kampanyasi (products.campaign_type = 'buy2_get1_balance')
-- su ana kadar yalnizca tek urun duzenleme formundan acilip kapatilabiliyordu.
-- Bu migration, satici panelindeki coklu (toplu) secim akisina ayni islemi
-- ekleyen bir RPC tanimlar; seller_bulk_set_discount ile ayni guvenlik
-- desenini izler (caller'in gercekten magaza sahibi oldugu dogrulanir).
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.seller_bulk_set_campaign_type(
  p_product_ids UUID[],
  p_campaign_type TEXT DEFAULT NULL
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $fn$
DECLARE
  v_user_id UUID := auth.uid();
  v_updated INTEGER := 0;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'seller_bulk_set_campaign_type: oturum bulunamadi'
      USING ERRCODE = '28000';
  END IF;

  IF p_product_ids IS NULL OR array_length(p_product_ids, 1) IS NULL THEN
    RAISE EXCEPTION 'En az bir urun secmelisiniz' USING ERRCODE = '22023';
  END IF;

  IF array_length(p_product_ids, 1) > 500 THEN
    RAISE EXCEPTION 'Tek seferde en fazla 500 urun guncellenebilir'
      USING ERRCODE = '22023';
  END IF;

  IF p_campaign_type IS NOT NULL AND p_campaign_type <> 'buy2_get1_balance' THEN
    RAISE EXCEPTION 'Gecersiz kampanya tipi: %', p_campaign_type USING ERRCODE = '22023';
  END IF;

  -- Kampanya dijital urunlere uygulanmaz (tek urun formuyla ayni kural).
  UPDATE public.products p
     SET campaign_type = p_campaign_type,
         updated_at    = NOW()
   WHERE p.id = ANY(p_product_ids)
     AND COALESCE(p.product_type, 'normal') <> 'digital'
     AND p.campaign_type IS DISTINCT FROM p_campaign_type
     AND EXISTS (
       SELECT 1 FROM public.shops s
        WHERE s.id = p.shop_id AND s.owner_id = v_user_id
     );

  GET DIAGNOSTICS v_updated = ROW_COUNT;
  RETURN v_updated;
END;
$fn$;

REVOKE ALL ON FUNCTION public.seller_bulk_set_campaign_type(UUID[], TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.seller_bulk_set_campaign_type(UUID[], TEXT) TO authenticated;

COMMIT;
