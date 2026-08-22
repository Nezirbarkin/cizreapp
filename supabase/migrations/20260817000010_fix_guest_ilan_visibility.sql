-- =============================================================================
-- Misafir ilan görünürlüğü: anon GRANT + açık ve deterministik RLS politikaları
-- Admin panelindeki allow_guest_view anahtarı kapatılırsa anon erişim yine kapanır.
-- =============================================================================

BEGIN;

GRANT SELECT ON public.ilan_settings TO anon;
GRANT SELECT ON public.ilan_categories TO anon;
GRANT SELECT ON public.ilanlar TO anon;
GRANT SELECT ON public.ilan_images TO anon;

DROP POLICY IF EXISTS ilan_settings_read ON public.ilan_settings;
CREATE POLICY ilan_settings_read ON public.ilan_settings
FOR SELECT TO anon, authenticated
USING (true);

DROP POLICY IF EXISTS ilan_categories_public_read ON public.ilan_categories;
CREATE POLICY ilan_categories_public_read ON public.ilan_categories
FOR SELECT TO anon, authenticated
USING (is_active OR (SELECT public.ilan_is_admin()));

DROP POLICY IF EXISTS ilanlar_public_read ON public.ilanlar;
CREATE POLICY ilanlar_public_read ON public.ilanlar
FOR SELECT TO anon, authenticated
USING (
  status = 'published'
  AND (expires_at IS NULL OR expires_at > now())
  AND EXISTS (
    SELECT 1
    FROM public.ilan_settings s
    WHERE s.id = 1
      AND s.is_enabled
      AND (
        (SELECT auth.uid()) IS NOT NULL
        OR s.allow_guest_view
      )
  )
);

DROP POLICY IF EXISTS ilan_images_public_read ON public.ilan_images;
CREATE POLICY ilan_images_public_read ON public.ilan_images
FOR SELECT TO anon, authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.ilanlar i
    WHERE i.id = ilan_id
      AND (
        (
          i.status = 'published'
          AND (i.expires_at IS NULL OR i.expires_at > now())
          AND EXISTS (
            SELECT 1 FROM public.ilan_settings s
            WHERE s.id = 1
              AND s.is_enabled
              AND ((SELECT auth.uid()) IS NOT NULL OR s.allow_guest_view)
          )
        )
        OR i.owner_id = (SELECT auth.uid())
        OR (SELECT public.ilan_is_admin())
      )
  )
);

COMMIT;
