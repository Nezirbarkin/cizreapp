-- =============================================================================
-- Şehiriçi düzeltmeleri: eksik sehirici_routes tablosu + app_settings admin yazma izni
-- Tarih: 2026-07-25
-- Sebep: "rota oluşturulmuyor" — SehiriciRouteService.createLineRoute()
-- sehirici_routes tablosuna insert yapıyordu ama bu tablo hiç oluşturulmamıştı.
-- Sebep: "ayarlar çalışmıyor" — app_settings üzerinde admin için UPDATE policy
-- yoksa RLS satırı sessizce 0 satır güncelleyip hata fırlatmaz; updateSetting()
-- false döner ama UI eskiden bunu göstermiyordu (ayrıca burada RLS de garantiye alınıyor).
-- =============================================================================

-- =============================================================================
-- 1) sehirici_routes tablosu
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.sehirici_routes (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  line_id      UUID NOT NULL REFERENCES public.sehirici_lines(id) ON DELETE CASCADE,
  trip_id      UUID REFERENCES public.sehirici_trips(id) ON DELETE SET NULL,
  driver_id    UUID REFERENCES public.sehirici_drivers(id) ON DELETE SET NULL,
  points       JSONB NOT NULL DEFAULT '[]'::jsonb,
  status       TEXT NOT NULL DEFAULT 'draft'
               CHECK (status IN ('draft', 'active', 'completed', 'cancelled')),
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  started_at   TIMESTAMPTZ,
  completed_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_sehirici_routes_line
  ON public.sehirici_routes(line_id, status);

ALTER TABLE public.sehirici_routes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS sehirici_routes_select_all ON public.sehirici_routes;
CREATE POLICY sehirici_routes_select_all
  ON public.sehirici_routes FOR SELECT
  USING (
    TRUE = TRUE -- herkes rota bilgisini görebilir (hat rengine/duruş bilgisine benzer)
  );

DROP POLICY IF EXISTS sehirici_routes_admin_all ON public.sehirici_routes;
CREATE POLICY sehirici_routes_admin_all
  ON public.sehirici_routes FOR ALL
  USING (public.auth_is_admin())
  WITH CHECK (public.auth_is_admin());

DROP POLICY IF EXISTS sehirici_routes_driver_update ON public.sehirici_routes;
CREATE POLICY sehirici_routes_driver_update
  ON public.sehirici_routes FOR UPDATE
  USING (
    driver_id IN (SELECT id FROM public.sehirici_drivers WHERE profile_id = auth.uid())
  )
  WITH CHECK (
    driver_id IN (SELECT id FROM public.sehirici_drivers WHERE profile_id = auth.uid())
  );

COMMENT ON TABLE public.sehirici_routes IS 'Hat rotaları (taslak/aktif/tamamlanmış) - konum noktaları';

-- =============================================================================
-- 2) app_settings üzerinde admin UPDATE izni garantiye alınıyor
-- =============================================================================
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_tables WHERE schemaname = 'public' AND tablename = 'app_settings') THEN
    EXECUTE 'DROP POLICY IF EXISTS sehirici_app_settings_admin_update ON public.app_settings';
    EXECUTE $pol$
      CREATE POLICY sehirici_app_settings_admin_update
        ON public.app_settings FOR UPDATE
        TO authenticated
        USING (public.auth_is_admin())
        WITH CHECK (public.auth_is_admin())
    $pol$;
  END IF;
END $$;
