-- =============================================================================
-- Satıcı paneli: ürün bazlı görüntülenme + beğeni istatistikleri
--
-- Ürünler ekranındaki her satırda 👁 görüntülenme ve ❤ beğeni sayısını N+1
-- sorgu yapmadan göstermek için tek seferlik toplu (batch) RPC. Ayrıca Raporlar
-- ekranının Genel/Ürünler sekmelerine beğeni bazlı bölümler eklenecek
-- (get_top_viewed_products / get_shop_total_views'ın beğeni karşılıkları).
--
-- get_product_favorite_count (20240124000010, sertleştirmesi 20260727000004
-- ile 20240124000013_fix_function_search_path.sql) zaten SECURITY DEFINER +
-- search_path='' ile RLS'i güvenli biçimde bypass ediyor; ManageProductScreen
-- tekil ürün özeti onu kullanır, burada tekrar edilmez.
-- =============================================================================

BEGIN;

-- 1) Mağazanın TÜM ürünleri için tek çağrıda view+favori sayısı (N+1 önler).
CREATE OR REPLACE FUNCTION public.get_shop_product_stats(p_shop_id uuid)
RETURNS TABLE (
  product_id     uuid,
  view_count     bigint,
  favorite_count bigint
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.shops WHERE id = p_shop_id AND owner_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'get_shop_product_stats: not shop owner' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT
    p.id AS product_id,
    COALESCE(v.view_count, 0)::bigint AS view_count,
    COALESCE(f.favorite_count, 0)::bigint AS favorite_count
  FROM public.products p
  LEFT JOIN (
    SELECT pv.product_id, COUNT(*) AS view_count
    FROM public.product_views pv
    WHERE pv.shop_id = p_shop_id
    GROUP BY pv.product_id
  ) v ON v.product_id = p.id
  LEFT JOIN (
    SELECT pf.product_id, COUNT(*) AS favorite_count
    FROM public.product_favorites pf
    INNER JOIN public.products p2 ON p2.id = pf.product_id
    WHERE p2.shop_id = p_shop_id
    GROUP BY pf.product_id
  ) f ON f.product_id = p.id
  WHERE p.shop_id = p_shop_id;
END;
$$;

-- 2) En çok beğenilen ürünler (get_top_viewed_products'ın beğeni karşılığı).
CREATE OR REPLACE FUNCTION public.get_top_favorited_products(p_shop_id uuid, p_limit integer DEFAULT 10)
RETURNS TABLE (
  product_id     uuid,
  product_name   text,
  favorite_count bigint
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.shops WHERE id = p_shop_id AND owner_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'get_top_favorited_products: not shop owner' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT p.id AS product_id, p.name AS product_name, COUNT(*)::bigint AS favorite_count
  FROM public.product_favorites pf
  INNER JOIN public.products p ON p.id = pf.product_id
  WHERE p.shop_id = p_shop_id
  GROUP BY p.id, p.name
  ORDER BY favorite_count DESC
  LIMIT p_limit;
END;
$$;

-- 3) Mağazanın toplam beğeni sayısı (get_shop_total_views'ın beğeni karşılığı).
CREATE OR REPLACE FUNCTION public.get_shop_total_favorites(p_shop_id uuid)
RETURNS bigint
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.shops WHERE id = p_shop_id AND owner_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'get_shop_total_favorites: not shop owner' USING ERRCODE = '42501';
  END IF;

  RETURN (
    SELECT COUNT(*)
    FROM public.product_favorites pf
    INNER JOIN public.products p ON p.id = pf.product_id
    WHERE p.shop_id = p_shop_id
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_shop_product_stats(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_top_favorited_products(uuid, integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_shop_total_favorites(uuid) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.get_shop_product_stats(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_top_favorited_products(uuid, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_shop_total_favorites(uuid) TO authenticated;

COMMENT ON FUNCTION public.get_shop_product_stats(uuid) IS 'Mağazanın tüm ürünleri için görüntülenme+favori sayısı (satıcı paneli Ürünler ekranı, N+1 önler)';
COMMENT ON FUNCTION public.get_top_favorited_products(uuid, integer) IS 'En çok favorilenen ürünler (get_top_viewed_products beğeni karşılığı)';
COMMENT ON FUNCTION public.get_shop_total_favorites(uuid) IS 'Mağazanın toplam favori sayısı (get_shop_total_views beğeni karşılığı)';

COMMIT;

NOTIFY pgrst, 'reload schema';
