-- Her satıcının sadece bir dükkanı olmasını sağla
-- + shop_reviews trigger'ını düzelt
-- 1. Önce ilişkili verileri temizle
-- 2. Fazla dükkanları sil (en eski dükkanı tut)
-- 3. UNIQUE constraint ekle

-- 0. Önce shop_reviews trigger'ını düzelt (is_deleted sütunu yok hatası)
CREATE OR REPLACE FUNCTION update_shop_rating()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE shops SET
    review_count = (
      SELECT COUNT(*)
      FROM shop_reviews
      WHERE shop_id = COALESCE(NEW.shop_id, OLD.shop_id)
    ),
    rating = COALESCE((
      SELECT AVG(rating)
      FROM shop_reviews
      WHERE shop_id = COALESCE(NEW.shop_id, OLD.shop_id)
    ), 0)
  WHERE id = COALESCE(NEW.shop_id, OLD.shop_id);
  
  RETURN COALESCE(NEW, OLD);
END;
$$;

-- 1. Order items'ları temizle (silinecek dükkanlardan)
DELETE FROM order_items
WHERE shop_id NOT IN (
  SELECT DISTINCT ON (owner_id) id
  FROM shops
  ORDER BY owner_id, created_at ASC
);

-- 2. Ürünleri temizle (silinecek dükkanlardan)
DELETE FROM products
WHERE shop_id NOT IN (
  SELECT DISTINCT ON (owner_id) id
  FROM shops
  ORDER BY owner_id, created_at ASC
);

-- 3. Shop reviews temizle (silinecek dükkanlardan)
DELETE FROM shop_reviews
WHERE shop_id NOT IN (
  SELECT DISTINCT ON (owner_id) id
  FROM shops
  ORDER BY owner_id, created_at ASC
);

-- 4. Fazla dükkanları sil (her owner_id için sadece ilk dükkanı tut)
DELETE FROM shops
WHERE id NOT IN (
  SELECT DISTINCT ON (owner_id) id
  FROM shops
  ORDER BY owner_id, created_at ASC
);

-- 5. owner_id için UNIQUE constraint ekle (eğer yoksa)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'shops_owner_id_unique'
    ) THEN
        ALTER TABLE shops ADD CONSTRAINT shops_owner_id_unique UNIQUE (owner_id);
    END IF;
END $$;

-- Bilgi mesajı
COMMENT ON CONSTRAINT shops_owner_id_unique ON shops IS 'Her satıcının sadece bir dükkanı olabilir';
