-- Categories tablosuna admin kullanıcıları için RLS politikaları ekle
-- Bu script'i Supabase SQL Editor'de çalıştırın

-- ============================================
-- RPC FONKSİYONU: Kategorileri dükkan sayılarıyla getir
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

-- Herkesin bu RPC fonksiyonunu kullanmasına izin ver
GRANT EXECUTE ON FUNCTION get_categories_with_shop_count() TO authenticated;
GRANT EXECUTE ON FUNCTION get_categories_with_shop_count() TO anon;

-- ============================================
-- RLS POLİTİKALARI
-- ============================================

-- Önce eski politikaları kontrol et
SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual 
FROM pg_policies 
WHERE tablename = 'categories';

-- Önce eski politikaları varsa kaldır
DROP POLICY IF EXISTS "categories_admin_insert_policy" ON public.categories;
DROP POLICY IF EXISTS "categories_admin_update_policy" ON public.categories;
DROP POLICY IF EXISTS "categories_admin_delete_policy" ON public.categories;

-- Admin kullanıcıları için INSERT politikası
CREATE POLICY "categories_admin_insert_policy"
ON public.categories FOR INSERT
TO authenticated
WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.profiles
    WHERE profiles.id = auth.uid()
    AND profiles.role = 'admin'
  )
);

-- Admin kullanıcıları için UPDATE politikası
CREATE POLICY "categories_admin_update_policy"
ON public.categories FOR UPDATE
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.profiles
    WHERE profiles.id = auth.uid()
    AND profiles.role = 'admin'
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.profiles
    WHERE profiles.id = auth.uid()
    AND profiles.role = 'admin'
  )
);

-- Admin kullanıcıları için DELETE politikası
CREATE POLICY "categories_admin_delete_policy"
ON public.categories FOR DELETE
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.profiles
    WHERE profiles.id = auth.uid()
    AND profiles.role = 'admin'
  )
);

-- Politikaları kontrol et
SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual 
FROM pg_policies 
WHERE tablename = 'categories';

-- ============================================
-- KULLANIM TALİMATLARI
-- ============================================
-- 1. Supabase Dashboard > SQL Editor'e gidin
-- 2. Bu SQL dosyasının tüm içeriğini kopyalayıp yapıştırın
-- 3. "Run" butonuna tıklayın
-- 4. İşlem başarılı olursa kategoriler artık doğru çalışacaktır
-- 5. Eğer hata alırsanız, hata mesajını kontrol edin
-- 6. Profile tablonuzda role='admin' olan kullanıcı olduğundan emin olun
