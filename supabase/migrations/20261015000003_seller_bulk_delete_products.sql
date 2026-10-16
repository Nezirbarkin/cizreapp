-- ============================================================================
-- Satıcı toplu ürün silme (2026-10-15)
--
--   public.seller_bulk_delete_products(p_product_ids uuid[], p_dry_run boolean)
--
-- Kural: geçmişi olan ürün SİLİNMEZ, satışa kapatılır (is_available = false);
-- geçmişi olmayan kalıcı silinir. "Geçmiş":
--   - order_items      (FK ON DELETE SET NULL — silme engellenmiyordu: ürün
--                       siliniyor, sipariş kalemi ürünsüz kalıyordu),
--   - digital_orders   (FK NO ACTION — silme 23503 ile düşer),
--   - shop_sponsorships (FK CASCADE — ücretli öne çıkarma kaydı, yani para
--                       hareketi, ürünle birlikte siliniyordu).
--
-- Tekli silme (ProductService.deleteProduct) da bu fonksiyonu tek kimlikle
-- çağırır; eskiden 23503'e güvendiği için yalnız dijital üründe kapatıyordu.
--
-- p_dry_run = true hiçbir şeyi değiştirmez, aynı sayıları döner (onay
-- penceresi "N silinecek, M kapatılacak" gösterir).
--
-- Dönüş: { deleted, deactivated, not_found, dry_run,
--          deleted_ids: [..], deactivated_ids: [..] }
-- not_found: çağıranın mağazasına ait olmayan ya da bulunamayan kimlikler.
-- Storage'daki ürün görselleri silinmez (bkz. ürün görsel kütüphanesi notu:
-- görsel adresi başka ürünlere kopyalanmış olabilir).
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.seller_bulk_delete_products(
  p_product_ids UUID[],
  p_dry_run     BOOLEAN DEFAULT false
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $fn$
DECLARE
  v_uid         UUID := auth.uid();
  v_ids         UUID[];
  v_owned       UUID[];
  v_keep        UUID[];
  v_delete      UUID[];
  v_deleted     UUID[] := '{}';
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'seller_bulk_delete_products: oturum bulunamadi'
      USING ERRCODE = '28000';
  END IF;

  SELECT COALESCE(array_agg(DISTINCT x), '{}') INTO v_ids
    FROM unnest(COALESCE(p_product_ids, '{}')) AS x
   WHERE x IS NOT NULL;

  IF array_length(v_ids, 1) IS NULL THEN
    RAISE EXCEPTION 'En az bir ürün seçmelisiniz' USING ERRCODE = '22023';
  END IF;
  IF array_length(v_ids, 1) > 500 THEN
    RAISE EXCEPTION 'Tek seferde en fazla 500 ürün silinebilir' USING ERRCODE = '22023';
  END IF;

  -- Satırlar kilitlenir: kontrol ile silme arasında yeni sipariş kalemi
  -- eklenemesin (sipariş eklemenin FK denetimi bu kilidi bekler).
  SELECT COALESCE(array_agg(p.id), '{}') INTO v_owned
    FROM (
      SELECT p.id
        FROM public.products p
        JOIN public.shops s ON s.id = p.shop_id
       WHERE p.id = ANY (v_ids)
         AND s.owner_id = v_uid
       ORDER BY p.id
       FOR UPDATE OF p
    ) p;

  -- (Takma ad u.pid: alt sorgulardaki tabloların da "id" sütunu var.)
  SELECT COALESCE(array_agg(u.pid), '{}') INTO v_keep
    FROM unnest(v_owned) AS u(pid)
   WHERE EXISTS (SELECT 1 FROM public.order_items oi WHERE oi.product_id = u.pid)
      OR EXISTS (SELECT 1 FROM public.digital_orders dg WHERE dg.product_id = u.pid)
      OR EXISTS (SELECT 1 FROM public.shop_sponsorships sp WHERE sp.product_id = u.pid);

  SELECT COALESCE(array_agg(u.pid), '{}') INTO v_delete
    FROM unnest(v_owned) AS u(pid)
   WHERE NOT (u.pid = ANY (v_keep));

  IF NOT COALESCE(p_dry_run, false) THEN
    IF array_length(v_keep, 1) IS NOT NULL THEN
      UPDATE public.products p
         SET is_available = false
       WHERE p.id = ANY (v_keep)
         AND p.is_available IS DISTINCT FROM false;
    END IF;

    IF array_length(v_delete, 1) IS NOT NULL THEN
      WITH d AS (
        DELETE FROM public.products p WHERE p.id = ANY (v_delete) RETURNING p.id
      )
      SELECT COALESCE(array_agg(id), '{}') INTO v_deleted FROM d;
    END IF;
  ELSE
    v_deleted := v_delete;
  END IF;

  RETURN jsonb_build_object(
    'deleted', COALESCE(array_length(v_deleted, 1), 0),
    'deactivated', COALESCE(array_length(v_keep, 1), 0),
    'not_found', COALESCE(array_length(v_ids, 1), 0) - COALESCE(array_length(v_owned, 1), 0),
    'dry_run', COALESCE(p_dry_run, false),
    'deleted_ids', to_jsonb(v_deleted),
    'deactivated_ids', to_jsonb(v_keep)
  );
END;
$fn$;

COMMENT ON FUNCTION public.seller_bulk_delete_products(UUID[], BOOLEAN) IS
  'Satıcı toplu/tekli ürün silme: sipariş, dijital sipariş ya da öne çıkarma geçmişi olan ürün '
  'silinmez, satışa kapatılır. Ayrıntı: 20261015000003_seller_bulk_delete_products.sql';

REVOKE ALL ON FUNCTION public.seller_bulk_delete_products(UUID[], BOOLEAN) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.seller_bulk_delete_products(UUID[], BOOLEAN) FROM anon;
GRANT EXECUTE ON FUNCTION public.seller_bulk_delete_products(UUID[], BOOLEAN) TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';
