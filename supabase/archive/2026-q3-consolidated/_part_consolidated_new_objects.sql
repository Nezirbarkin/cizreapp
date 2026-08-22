-- -----------------------------------------------------------------------------
-- BOLUM 9: api_keys tablosu (hicbir migration olusturmuyordu; admin paneli
-- CRUD yapiyor). RLS: yalniz admin.
-- Kolonlar Flutter kullanimina göre: _part_api_settings.dart ve
-- _part_data_loaders.dart (.select(), .order('created_at'), insert/update/delete)
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.api_keys (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL CHECK (length(name) BETWEEN 1 AND 200),
  key text NOT NULL,
  description text,
  is_active boolean NOT NULL DEFAULT true,
  last_used_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_api_keys_created_at
  ON public.api_keys (created_at DESC);

-- updated_at otomatik guncelleme
CREATE OR REPLACE FUNCTION public.trg_api_keys_set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS api_keys_set_updated_at ON public.api_keys;
CREATE TRIGGER api_keys_set_updated_at
  BEFORE UPDATE ON public.api_keys
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_api_keys_set_updated_at();

ALTER TABLE public.api_keys ENABLE ROW LEVEL SECURITY;

-- Yalniz admin okuyup yönetebilir; API anahtarlari hassastir.
DROP POLICY IF EXISTS "api_keys_admin_all" ON public.api_keys;
CREATE POLICY "api_keys_admin_all"
  ON public.api_keys
  FOR ALL
  TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid() AND p.role = 'admin'::public.user_role
  ))
  WITH CHECK (EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid() AND p.role = 'admin'::public.user_role
  ));

DROP POLICY IF EXISTS "api_keys_service_all" ON public.api_keys;
CREATE POLICY "api_keys_service_all"
  ON public.api_keys
  FOR ALL
  TO service_role
  USING (true) WITH CHECK (true);

GRANT ALL ON public.api_keys TO authenticated, service_role;


-- -----------------------------------------------------------------------------
-- BOLUM 10: news_views RLS SELECT policy
-- Kaynak: news_system.sql sadece INSERT policy tanimlamisti; SELECT policy
-- yoktu -> sorgular her zaman bos donerdi. Uygulama news_views'a yalniz
-- INSERT yapsa da, admin analytics icin admin-only guvenli SELECT policy
-- eklenir (hassas goruntuleme verisini herkese acmaz).
-- -----------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policy
    WHERE polrelid = 'public.news_views'::regclass
      AND polcmd IN ('r','*') AND polpermissive
  ) THEN
    CREATE POLICY "news_views_admin_select"
      ON public.news_views
      FOR SELECT
      TO authenticated
      USING (EXISTS (
        SELECT 1 FROM public.profiles p
        WHERE p.id = auth.uid() AND p.role = 'admin'::public.user_role
      ));
    RAISE NOTICE 'news_views icin admin SELECT policy olusturuldu';
  END IF;
END $$;


-- -----------------------------------------------------------------------------
-- BOLUM 11: smm_providers kolon-bazli SELECT grant (yeniden uygula)
-- Kaynak: 20260710000003_smm_integration.sql, ama uygulanmamis olabilir.
-- smm_service.dart yalniz su kolonlari select ediyor:
--   id, owner_type, owner_id, name, api_url, is_active, created_at, updated_at
-- ONEM: Tablo-bazli SELECT grant ACILMADI -> api_key kolonu sizmaz.
-- -----------------------------------------------------------------------------
GRANT SELECT (id, owner_type, owner_id, name, api_url, is_active, created_at, updated_at)
  ON public.smm_providers TO authenticated;
GRANT INSERT (owner_type, owner_id, name, api_url, api_key, is_active)
  ON public.smm_providers TO authenticated;
GRANT UPDATE (name, api_url, api_key, is_active)
  ON public.smm_providers TO authenticated;
GRANT DELETE ON public.smm_providers TO authenticated;
GRANT ALL ON public.smm_providers TO service_role;


DO $$
BEGIN
  RAISE NOTICE '==================================================';
  RAISE NOTICE 'Konsolide uygulama kontrati duzeltmesi tamamlandi.';
  RAISE NOTICE 'Eksik RPC, tablo, view, RLS ve yetkiler olusturuldu.';
  RAISE NOTICE 'Dogrulama icin CIZREAPP_TESHIS.sql i tekrar calistirin.';
  RAISE NOTICE '==================================================';
END $$;
