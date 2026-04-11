-- ================================================================
-- Analytics RPC Functions for Seller Reports
-- ================================================================
-- Bu migration, satıcı rapor ekranında kullanılan RPC fonksiyonlarını oluşturur

-- Önce eski fonksiyonları sil (return type değişikliği için gerekli)
DROP FUNCTION IF EXISTS public.get_shop_total_views(UUID);
DROP FUNCTION IF EXISTS public.get_shop_today_views(UUID);
DROP FUNCTION IF EXISTS public.get_top_viewed_products(UUID, INTEGER);
DROP FUNCTION IF EXISTS public.get_top_customers(UUID, INTEGER);

-- 1. Mağaza toplam görüntüleme sayısı
CREATE OR REPLACE FUNCTION public.get_shop_total_views(p_shop_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN (
    SELECT COUNT(*)::INTEGER
    FROM shop_views
    WHERE shop_id = p_shop_id
  );
END;
$$;

-- 2. Bugünün görüntüleme sayısı
CREATE OR REPLACE FUNCTION public.get_shop_today_views(p_shop_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN (
    SELECT COUNT(*)::INTEGER
    FROM shop_views
    WHERE shop_id = p_shop_id
      AND DATE(viewed_at) = CURRENT_DATE
  );
END;
$$;

-- 3. En çok görüntülenen ürünler
CREATE OR REPLACE FUNCTION public.get_top_viewed_products(p_shop_id UUID, p_limit INTEGER DEFAULT 10)
RETURNS TABLE (
  product_id UUID,
  product_name TEXT,
  view_count BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    pv.product_id,
    p.name AS product_name,
    COUNT(*)::BIGINT AS view_count
  FROM product_views pv
  INNER JOIN products p ON p.id = pv.product_id
  WHERE pv.shop_id = p_shop_id
    AND p.shop_id = p_shop_id
  GROUP BY pv.product_id, p.name
  ORDER BY view_count DESC
  LIMIT p_limit;
END;
$$;

-- 4. En çok sipariş veren müşteriler
CREATE OR REPLACE FUNCTION public.get_top_customers(p_shop_id UUID, p_limit INTEGER DEFAULT 10)
RETURNS TABLE (
  user_id UUID,
  full_name TEXT,
  order_count BIGINT,
  total_spent NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    o.user_id,
    COALESCE(pr.full_name, 'Anonim') AS full_name,
    COUNT(o.id)::BIGINT AS order_count,
    SUM(o.subtotal)::NUMERIC AS total_spent
  FROM orders o
  LEFT JOIN profiles pr ON pr.id = o.user_id
  WHERE o.shop_id = p_shop_id
    AND o.status != 'cancelled'
  GROUP BY o.user_id, pr.full_name
  ORDER BY order_count DESC, total_spent DESC
  LIMIT p_limit;
END;
$$;

-- Yorum ekle
COMMENT ON FUNCTION public.get_shop_total_views(UUID) IS 'Mağazanın toplam görüntüleme sayısını döndürür';
COMMENT ON FUNCTION public.get_shop_today_views(UUID) IS 'Mağazanın bugünkü görüntüleme sayısını döndürür';
COMMENT ON FUNCTION public.get_top_viewed_products(UUID, INTEGER) IS 'En çok görüntülenen ürünleri döndürür';
COMMENT ON FUNCTION public.get_top_customers(UUID, INTEGER) IS 'En çok sipariş veren müşterileri döndürür';
