-- =============================================================================
-- İlanlar: gerçek misafir (anon) erişim düzeltmesi
--
-- Kök neden:
-- ilan_categories ve ilan_images politikaları anon + authenticated için ortak
-- tanımlanmış ve policy içinde ilan_is_admin() çağırıyordu. Güvenlik gereği bu
-- fonksiyon anon'a kapalı olduğundan PostgreSQL, aktif/public satırlarda bile
-- anon sorgusunu "permission denied for function ilan_is_admin" ile kesiyordu.
--
-- Çözüm: anon ve authenticated politikalarını ayır. Anon politikası hiçbir
-- ayrıcalıklı fonksiyon çağırmaz; sadece public ilan kurallarını değerlendirir.
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- Kategoriler
-- -----------------------------------------------------------------------------
DROP POLICY IF EXISTS ilan_categories_public_read ON public.ilan_categories;
DROP POLICY IF EXISTS ilan_categories_anon_read ON public.ilan_categories;
DROP POLICY IF EXISTS ilan_categories_authenticated_read ON public.ilan_categories;

CREATE POLICY ilan_categories_anon_read
ON public.ilan_categories
FOR SELECT TO anon
USING (
  is_active
  AND EXISTS (
    SELECT 1
    FROM public.ilan_settings s
    WHERE s.id = 1
      AND s.is_enabled
      AND s.allow_guest_view
  )
);

CREATE POLICY ilan_categories_authenticated_read
ON public.ilan_categories
FOR SELECT TO authenticated
USING (is_active OR (SELECT public.ilan_is_admin()));

-- -----------------------------------------------------------------------------
-- İlanlar
-- -----------------------------------------------------------------------------
DROP POLICY IF EXISTS ilanlar_public_read ON public.ilanlar;
DROP POLICY IF EXISTS ilanlar_anon_read ON public.ilanlar;
DROP POLICY IF EXISTS ilanlar_authenticated_public_read ON public.ilanlar;

CREATE POLICY ilanlar_anon_read
ON public.ilanlar
FOR SELECT TO anon
USING (
  status = 'published'
  AND (expires_at IS NULL OR expires_at > now())
  AND EXISTS (
    SELECT 1
    FROM public.ilan_settings s
    WHERE s.id = 1
      AND s.is_enabled
      AND s.allow_guest_view
  )
);

CREATE POLICY ilanlar_authenticated_public_read
ON public.ilanlar
FOR SELECT TO authenticated
USING (
  status = 'published'
  AND (expires_at IS NULL OR expires_at > now())
  AND EXISTS (
    SELECT 1 FROM public.ilan_settings s
    WHERE s.id = 1 AND s.is_enabled
  )
);

-- -----------------------------------------------------------------------------
-- İlan görselleri
-- -----------------------------------------------------------------------------
DROP POLICY IF EXISTS ilan_images_public_read ON public.ilan_images;
DROP POLICY IF EXISTS ilan_images_anon_read ON public.ilan_images;
DROP POLICY IF EXISTS ilan_images_authenticated_read ON public.ilan_images;

CREATE POLICY ilan_images_anon_read
ON public.ilan_images
FOR SELECT TO anon
USING (
  EXISTS (
    SELECT 1
    FROM public.ilanlar i
    JOIN public.ilan_settings s ON s.id = 1
    WHERE i.id = ilan_id
      AND i.status = 'published'
      AND (i.expires_at IS NULL OR i.expires_at > now())
      AND s.is_enabled
      AND s.allow_guest_view
  )
);

CREATE POLICY ilan_images_authenticated_read
ON public.ilan_images
FOR SELECT TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.ilanlar i
    WHERE i.id = ilan_id
      AND (
        (i.status = 'published' AND (i.expires_at IS NULL OR i.expires_at > now()))
        OR i.owner_id = (SELECT auth.uid())
        OR (SELECT public.ilan_is_admin())
      )
  )
);

-- Tablo izinlerini son kez açıkça garanti et.
GRANT SELECT ON public.ilan_settings TO anon;
GRANT SELECT ON public.ilan_categories TO anon;
GRANT SELECT ON public.ilanlar TO anon;
GRANT SELECT ON public.ilan_images TO anon;

COMMIT;

