-- Ürün Görsel Kütüphanesi: admin tarafından önceden yüklenen, satıcıların
-- kendi fotoğraf yüklemek yerine ürün eklerken seçebileceği hazır görseller.
-- categories tablosunun "admin önceden yükler, herkes görür" desenini taklit
-- eder (bkz. 20260129000001_fix_rls_performance.sql categories policy'leri).

CREATE TABLE IF NOT EXISTS public.product_image_presets (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  description TEXT,
  image_url TEXT NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT true,
  display_order INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.product_image_presets ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "product_image_presets_select_policy" ON public.product_image_presets;
CREATE POLICY "product_image_presets_select_policy"
ON public.product_image_presets FOR SELECT
TO authenticated
USING (is_active OR public.auth_is_admin());

DROP POLICY IF EXISTS "product_image_presets_admin_insert_policy" ON public.product_image_presets;
CREATE POLICY "product_image_presets_admin_insert_policy"
ON public.product_image_presets FOR INSERT
TO authenticated
WITH CHECK (public.auth_is_admin());

DROP POLICY IF EXISTS "product_image_presets_admin_update_policy" ON public.product_image_presets;
CREATE POLICY "product_image_presets_admin_update_policy"
ON public.product_image_presets FOR UPDATE
TO authenticated
USING (public.auth_is_admin())
WITH CHECK (public.auth_is_admin());

DROP POLICY IF EXISTS "product_image_presets_admin_delete_policy" ON public.product_image_presets;
CREATE POLICY "product_image_presets_admin_delete_policy"
ON public.product_image_presets FOR DELETE
TO authenticated
USING (public.auth_is_admin());

GRANT ALL ON public.product_image_presets TO authenticated;

CREATE INDEX IF NOT EXISTS idx_product_image_presets_name_trgm
  ON public.product_image_presets USING gin (name extensions.gin_trgm_ops);

CREATE INDEX IF NOT EXISTS idx_product_image_presets_active_order
  ON public.product_image_presets (is_active, display_order);

COMMENT ON TABLE public.product_image_presets IS
  'Admin tarafından yüklenen hazır ürün görselleri; satıcılar ürün eklerken kendi fotoğrafı yerine buradan seçebilir.';
