-- Function search_path güvenlik açığını düzelt
-- Tüm fonksiyonları SET search_path = public ile güvenli hale getir

-- ============================================
-- 1. update_payout_requests_updated_at
-- ============================================
CREATE OR REPLACE FUNCTION update_payout_requests_updated_at()
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

-- ============================================
-- 2. set_default_working_hours
-- ============================================
CREATE OR REPLACE FUNCTION set_default_working_hours()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.working_hours IS NULL THEN
    NEW.working_hours = '{"monday":{"open":"09:00","close":"18:00","active":true},"tuesday":{"open":"09:00","close":"18:00","active":true},"wednesday":{"open":"09:00","close":"18:00","active":true},"thursday":{"open":"09:00","close":"18:00","active":true},"friday":{"open":"09:00","close":"18:00","active":true},"saturday":{"open":"09:00","close":null,"active":true},"sunday":{"open":null,"close":null,"active":false}}'::jsonb;
  END IF;
  RETURN NEW;
END;
$$;

-- ============================================
-- 3. update_shop_rating
-- ============================================
CREATE OR REPLACE FUNCTION update_shop_rating()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Mağaza yorum sayısı ve ortalama puanını güncelle
  UPDATE shops
  SET 
    review_count = (
      SELECT COUNT(*) 
      FROM shop_reviews 
      WHERE shop_id = NEW.shop_id AND is_deleted = false
    ),
    rating = COALESCE((
      SELECT AVG(rating) 
      FROM shop_reviews 
      WHERE shop_id = NEW.shop_id AND is_deleted = false
    ), 0)
  WHERE id = NEW.shop_id;
  
  RETURN NEW;
END;
$$;

-- ============================================
-- 4. handle_new_user
-- ============================================
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (id, email, full_name, username)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'full_name', ''),
    COALESCE(NEW.raw_user_meta_data->>'username', '')
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;

-- ============================================
-- 5. get_categories_with_shop_count
-- ============================================
CREATE OR REPLACE FUNCTION get_categories_with_shop_count()
RETURNS TABLE (
  id uuid,
  name text,
  description text,
  display_order integer,
  is_active boolean,
  image_url text,
  shop_count bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    c.id,
    c.name,
    c.description,
    c.display_order,
    c.is_active,
    c.image_url,
    COALESCE(COUNT(s.id), 0) as shop_count
  FROM public.categories c
  LEFT JOIN public.shops s ON s.category_id = c.id
  GROUP BY c.id, c.name, c.description, c.display_order, c.is_active, c.image_url
  ORDER BY c.display_order ASC;
END;
$$;

-- ============================================
-- Yorumlar
-- ============================================
COMMENT ON FUNCTION update_payout_requests_updated_at() IS 'Ödeme istekleri güncellendiğinde updated_at''i günceller - search_path güvenli';
COMMENT ON FUNCTION set_default_working_hours() IS 'Yeni mağaza oluşturulduğunda varsayılan çalışma saatlerini ayarlar - search_path güvenli';
COMMENT ON FUNCTION update_shop_rating() IS 'Yorum eklendiğinde/güncellendiğinde mağaza puanını günceller - search_path güvenli';
COMMENT ON FUNCTION public.handle_new_user() IS 'Yeni kullanıcı kayıt olduğunda otomatik profil oluşturur - search_path güvenli';
COMMENT ON FUNCTION get_categories_with_shop_count() IS 'Kategorileri mağaza sayılarıyla birlikte getirir - search_path güvenli';
