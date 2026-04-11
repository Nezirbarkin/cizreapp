-- Create optimized view for shops with product count and basic info
-- Bu view, shops tablosunu products ile birleştirerek N+1 query problemini önler
-- Frontend'den tek sorguda dükkan + ürün sayısı + kategori bilgisi çekilebilir

-- Önce view varsa sil
DROP VIEW IF EXISTS shops_with_products_stats;

-- View oluştur
CREATE VIEW shops_with_products_stats AS
SELECT 
  s.id,
  s.name,
  s.description,
  s.logo_url,
  s.banner_url,
  s.category_id,
  s.owner_id,
  s.address,
  s.phone,
  s.is_active,
  s.is_approved,
  s.is_verified,
  s.is_pinned,
  s.rating,
  s.review_count,
  s.delivery_fee,
  s.min_order_amount,
  s.free_delivery_min_amount,
  s.delivery_time,
  s.is_open,
  s.created_at,
  s.updated_at,
  -- Product count (products tablosunda hesaplanır)
  COALESCE(pc.product_count, 0) as products_count,
  -- Category info (kategori adı için join gerekirse separate query yapılabilir)
  -- RLS politikalarına uygun olarak
  CASE 
    WHEN s.is_active = true AND s.is_approved = true THEN true
    ELSE false
  END as is_listable
FROM shops s
LEFT JOIN (
  -- Subquery: Her dükkan için aktif ürün sayısı
  SELECT shop_id, COUNT(*) as product_count
  FROM products
  WHERE is_active = true
  GROUP BY shop_id
) pc ON s.id = pc.shop_id
WHERE s.is_active = true;

-- View için yorum
COMMENT ON VIEW shops_with_products_stats IS 'Optimized view for shops with product counts. Uses base table RLS policies.';

-- Kullanım örneği:
-- SELECT * FROM shops_with_products_stats 
-- WHERE is_listable = true 
-- ORDER BY is_pinned DESC, rating DESC 
-- LIMIT 20;

-- Performans notları:
-- 1. products tablosunda shop_id ve is_active indexleri mevcut olmalı
-- 2. GROUP BY subquery'i her dükkan için tek satır döndürür
-- 3. LEFT JOIN kullanarak ürünü olmayan dükkanlar da listelenir

-- Gerekli index'ler (varsa eklemeye gerek yok)
-- CREATE INDEX IF NOT EXISTS idx_products_shop_id_active ON products(shop_id, is_active) WHERE is_active = true;
