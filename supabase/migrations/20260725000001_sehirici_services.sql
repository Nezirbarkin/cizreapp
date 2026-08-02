-- =============================================================================
-- ŞEHİRİÇİ SERVİS YÖNETİMİ MODÜLÜ
-- Tarih: 2026-07-25
-- Amaç: Şehir içi toplu taşıma servislerinin (belediye/minibüs/otobüs) hat,
-- durak, sefer, canlı konum, favori ve bildirim yönetimi.
-- =============================================================================

-- =============================================================================
-- 0) Ön Kontrol
-- =============================================================================
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pgcrypto') THEN
    CREATE EXTENSION IF NOT EXISTS pgcrypto;
  END IF;
END $$;

-- =============================================================================
-- 1) Enum Tipleri
-- =============================================================================

-- Servis aracı türü
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'sehirici_vehicle_type') THEN
    CREATE TYPE sehirici_vehicle_type AS ENUM (
      'minibus',  -- Minibüs
      'bus',      -- Otobüs
      'midibus',  -- Midibüs
      'dolmus',   -- Dolmuş
      'tram',     -- Tramvay
      'other'     -- Diğer
    );
  END IF;
END $$;

-- Sefer durumu
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'sehirici_trip_status') THEN
    CREATE TYPE sehirici_trip_status AS ENUM (
      'planned',    -- Planlandı (henüz başlamadı)
      'active',     -- Aktif (yolda, konum paylaşılıyor)
      'paused',     -- Duraklatıldı (molada vs.)
      'completed',  -- Tamamlandı
      'cancelled'   -- İptal
    );
  END IF;
END $$;

-- Bildirim türü (mevcut notification_type enum'una ek)
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_enum
    WHERE enumlabel = 'sehirici_trip_started'
      AND enumtypid = (SELECT oid FROM pg_type WHERE typname = 'notification_type')
  ) THEN
    ALTER TYPE notification_type ADD VALUE 'sehirici_trip_started';
  END IF;
EXCEPTION WHEN OTHERS THEN
  -- enum yoksa yoksay
  NULL;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_enum
    WHERE enumlabel = 'sehirici_trip_near_stop'
      AND enumtypid = (SELECT oid FROM pg_type WHERE typname = 'notification_type')
  ) THEN
    ALTER TYPE notification_type ADD VALUE 'sehirici_trip_near_stop';
  END IF;
EXCEPTION WHEN OTHERS THEN
  NULL;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_enum
    WHERE enumlabel = 'sehirici_trip_completed'
      AND enumtypid = (SELECT oid FROM pg_type WHERE typname = 'notification_type')
  ) THEN
    ALTER TYPE notification_type ADD VALUE 'sehirici_trip_completed';
  END IF;
EXCEPTION WHEN OTHERS THEN
  NULL;
END $$;

-- =============================================================================
-- 2) Tablolar
-- =============================================================================

-- 2.1) Şehirler
CREATE TABLE IF NOT EXISTS public.sehirici_cities (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name        TEXT NOT NULL UNIQUE,
  slug        TEXT NOT NULL UNIQUE,
  center_lat  DOUBLE PRECISION NOT NULL,
  center_lng  DOUBLE PRECISION NOT NULL,
  zoom_level  INTEGER NOT NULL DEFAULT 13,
  is_active   BOOLEAN NOT NULL DEFAULT TRUE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_sehirici_cities_active
  ON public.sehirici_cities(is_active) WHERE is_active = TRUE;

-- 2.2) Hatlar (Rotalar)
CREATE TABLE IF NOT EXISTS public.sehirici_lines (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  city_id         UUID NOT NULL REFERENCES public.sehirici_cities(id) ON DELETE CASCADE,
  code            TEXT NOT NULL, -- Örn: "1A", "M3", "22B"
  name            TEXT NOT NULL, -- Örn: "Hastane - Üniversite"
  color_hex       TEXT NOT NULL DEFAULT '#1976D2',
  vehicle_type    sehirici_vehicle_type NOT NULL DEFAULT 'bus',
  route_polyline  JSONB, -- Google encoded polyline (alternatif) + waypoint listesi
  estimated_minutes INTEGER, -- Tahmini tam tur süresi
  fare_amount     NUMERIC(10,2) DEFAULT 0, -- Ücret
  is_active       BOOLEAN NOT NULL DEFAULT TRUE,
  display_order   INTEGER NOT NULL DEFAULT 0,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(city_id, code)
);

CREATE INDEX IF NOT EXISTS idx_sehirici_lines_city
  ON public.sehirici_lines(city_id, is_active);

-- 2.3) Duraklar
CREATE TABLE IF NOT EXISTS public.sehirici_stops (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  city_id     UUID NOT NULL REFERENCES public.sehirici_cities(id) ON DELETE CASCADE,
  name        TEXT NOT NULL,
  code        TEXT, -- Opsiyonel durak kodu (örn: "D-001")
  lat         DOUBLE PRECISION NOT NULL,
  lng         DOUBLE PRECISION NOT NULL,
  address     TEXT,
  is_active   BOOLEAN NOT NULL DEFAULT TRUE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_sehirici_stops_city
  ON public.sehirici_stops(city_id, is_active);

-- 2.4) Hat-Durak İlişkisi (Durak sırası + tahmini varış süresi)
CREATE TABLE IF NOT EXISTS public.sehirici_line_stops (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  line_id           UUID NOT NULL REFERENCES public.sehirici_lines(id) ON DELETE CASCADE,
  stop_id           UUID NOT NULL REFERENCES public.sehirici_stops(id) ON DELETE CASCADE,
  stop_order        INTEGER NOT NULL, -- Sıra numarası (0'dan başlar)
  minutes_from_start INTEGER NOT NULL DEFAULT 0, -- Başlangıçtan itibaren tahmini dakika
  distance_km       NUMERIC(8,2) DEFAULT 0,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(line_id, stop_id),
  UNIQUE(line_id, stop_order)
);

CREATE INDEX IF NOT EXISTS idx_sehirici_line_stops_line
  ON public.sehirici_line_stops(line_id, stop_order);

-- 2.5) Şoförler (profiles tablosunda role kontrolü)
-- profiles.role zaten var; yeni bir tablo ile şoför detaylarını tutuyoruz
CREATE TABLE IF NOT EXISTS public.sehirici_drivers (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profile_id      UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  license_number  TEXT,
  phone           TEXT,
  assigned_line_id UUID REFERENCES public.sehirici_lines(id) ON DELETE SET NULL,
  is_on_duty      BOOLEAN NOT NULL DEFAULT FALSE,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(profile_id)
);

CREATE INDEX IF NOT EXISTS idx_sehirici_drivers_line
  ON public.sehirici_drivers(assigned_line_id) WHERE assigned_line_id IS NOT NULL;

-- 2.6) Aktif Seferler
CREATE TABLE IF NOT EXISTS public.sehirici_trips (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  line_id         UUID NOT NULL REFERENCES public.sehirici_lines(id) ON DELETE CASCADE,
  driver_id       UUID REFERENCES public.sehirici_drivers(id) ON DELETE SET NULL,
  status          sehirici_trip_status NOT NULL DEFAULT 'planned',
  started_at      TIMESTAMPTZ,
  ended_at        TIMESTAMPTZ,
  current_lat     DOUBLE PRECISION,
  current_lng     DOUBLE PRECISION,
  current_heading REAL, -- Yön (0-360)
  current_speed   REAL, -- m/s
  next_stop_id    UUID REFERENCES public.sehirici_stops(id) ON DELETE SET NULL,
  eta_minutes     INTEGER, -- Sıradaki durağa tahmini varış
  passenger_count INTEGER DEFAULT 0,
  notes           TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_sehirici_trips_active
  ON public.sehirici_trips(line_id, status) WHERE status IN ('active', 'paused');

CREATE INDEX IF NOT EXISTS idx_sehirici_trips_driver
  ON public.sehirici_trips(driver_id, status);

-- 2.7) Canlı Konum Geçmişi (kısa tutulur, son 1 saat)
CREATE TABLE IF NOT EXISTS public.sehirici_trip_locations (
  id          BIGSERIAL PRIMARY KEY,
  trip_id     UUID NOT NULL REFERENCES public.sehirici_trips(id) ON DELETE CASCADE,
  lat         DOUBLE PRECISION NOT NULL,
  lng         DOUBLE PRECISION NOT NULL,
  heading     REAL,
  speed       REAL,
  recorded_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_sehirici_trip_locations_trip
  ON public.sehirici_trip_locations(trip_id, recorded_at DESC);

-- Eski kayıtları temizlemek için
-- (1 saatten eski kayıtları cron veya trigger ile sil)

-- 2.8) Kullanıcı Favori Durakları
CREATE TABLE IF NOT EXISTS public.sehirici_favorite_stops (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  stop_id     UUID NOT NULL REFERENCES public.sehirici_stops(id) ON DELETE CASCADE,
  notify_minutes_before INTEGER NOT NULL DEFAULT 5, -- Kaç dk kala bildirim
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(user_id, stop_id)
);

CREATE INDEX IF NOT EXISTS idx_sehirici_favorite_stops_user
  ON public.sehirici_favorite_stops(user_id);

-- 2.9) Sistem Ayarları (Açma/Kapama)
-- Mevcut app_settings tablosuna satır olarak ekliyoruz (anahtar/değer).
-- Burada dokümante ediyoruz; gerçek anahtarlar:
--   'sehirici_module_enabled'      -> BOOL (modül açık mı?)
--   'sehirici_default_city_id'     -> UUID (varsayılan şehir)
--   'sehirici_location_update_interval_sec' -> INT (varsayılan 10 sn)
--   'sehirici_eta_refresh_seconds' -> INT (varsayılan 30 sn)
--   'sehirici_max_history_minutes' -> INT (varsayılan 60)
--   'sehirici_allow_user_favorites' -> BOOL (varsayılan TRUE)

-- =============================================================================
-- 3) RLS Politikaları
-- =============================================================================

-- Yardımcı: auth.uid() ile admin kontrolü (mevcut auth_is_admin kullanılır)
-- is_admin SECURITY DEFINER olduğu için burada da kullanılabilir.

ALTER TABLE public.sehirici_cities ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sehirici_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sehirici_stops ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sehirici_line_stops ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sehirici_drivers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sehirici_trips ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sehirici_trip_locations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sehirici_favorite_stops ENABLE ROW LEVEL SECURITY;

-- Cities: herkes aktif olanları görebilir, admin CRUD
DROP POLICY IF EXISTS sehirici_cities_select_all ON public.sehirici_cities;
CREATE POLICY sehirici_cities_select_all
  ON public.sehirici_cities FOR SELECT
  USING (is_active = TRUE OR public.auth_is_admin());

DROP POLICY IF EXISTS sehirici_cities_admin_all ON public.sehirici_cities;
CREATE POLICY sehirici_cities_admin_all
  ON public.sehirici_cities FOR ALL
  USING (public.auth_is_admin())
  WITH CHECK (public.auth_is_admin());

-- Lines
DROP POLICY IF EXISTS sehirici_lines_select_all ON public.sehirici_lines;
CREATE POLICY sehirici_lines_select_all
  ON public.sehirici_lines FOR SELECT
  USING (is_active = TRUE OR public.auth_is_admin());

DROP POLICY IF EXISTS sehirici_lines_admin_all ON public.sehirici_lines;
CREATE POLICY sehirici_lines_admin_all
  ON public.sehirici_lines FOR ALL
  USING (public.auth_is_admin())
  WITH CHECK (public.auth_is_admin());

-- Stops
DROP POLICY IF EXISTS sehirici_stops_select_all ON public.sehirici_stops;
CREATE POLICY sehirici_stops_select_all
  ON public.sehirici_stops FOR SELECT
  USING (is_active = TRUE OR public.auth_is_admin());

DROP POLICY IF EXISTS sehirici_stops_admin_all ON public.sehirici_stops;
CREATE POLICY sehirici_stops_admin_all
  ON public.sehirici_stops FOR ALL
  USING (public.auth_is_admin())
  WITH CHECK (public.auth_is_admin());

-- Line Stops
DROP POLICY IF EXISTS sehirici_line_stops_select_all ON public.sehirici_line_stops;
CREATE POLICY sehirici_line_stops_select_all
  ON public.sehirici_line_stops FOR SELECT
  USING (TRUE);

DROP POLICY IF EXISTS sehirici_line_stops_admin_all ON public.sehirici_line_stops;
CREATE POLICY sehirici_line_stops_admin_all
  ON public.sehirici_line_stops FOR ALL
  USING (public.auth_is_admin())
  WITH CHECK (public.auth_is_admin());

-- Drivers: sadece admin veya kendisi
DROP POLICY IF EXISTS sehirici_drivers_select_admin ON public.sehirici_drivers;
CREATE POLICY sehirici_drivers_select_admin
  ON public.sehirici_drivers FOR SELECT
  USING (public.auth_is_admin() OR profile_id = auth.uid());

DROP POLICY IF EXISTS sehirici_drivers_admin_all ON public.sehirici_drivers;
CREATE POLICY sehirici_drivers_admin_all
  ON public.sehirici_drivers FOR ALL
  USING (public.auth_is_admin())
  WITH CHECK (public.auth_is_admin());

DROP POLICY IF EXISTS sehirici_drivers_update_self ON public.sehirici_drivers;
CREATE POLICY sehirici_drivers_update_self
  ON public.sehirici_drivers FOR UPDATE
  USING (profile_id = auth.uid())
  WITH CHECK (profile_id = auth.uid());

-- Trips: herkes aktif seferleri görebilir
DROP POLICY IF EXISTS sehirici_trips_select_all ON public.sehirici_trips;
CREATE POLICY sehirici_trips_select_all
  ON public.sehirici_trips FOR SELECT
  USING (
    status IN ('active', 'paused', 'completed') OR
    public.auth_is_admin() OR
    driver_id IN (SELECT id FROM public.sehirici_drivers WHERE profile_id = auth.uid())
  );

DROP POLICY IF EXISTS sehirici_trips_driver_insert ON public.sehirici_trips;
CREATE POLICY sehirici_trips_driver_insert
  ON public.sehirici_trips FOR INSERT
  WITH CHECK (
    driver_id IN (SELECT id FROM public.sehirici_drivers WHERE profile_id = auth.uid())
    OR public.auth_is_admin()
  );

DROP POLICY IF EXISTS sehirici_trips_driver_update ON public.sehirici_trips;
CREATE POLICY sehirici_trips_driver_update
  ON public.sehirici_trips FOR UPDATE
  USING (
    driver_id IN (SELECT id FROM public.sehirici_drivers WHERE profile_id = auth.uid())
    OR public.auth_is_admin()
  );

DROP POLICY IF EXISTS sehirici_trips_admin_delete ON public.sehirici_trips;
CREATE POLICY sehirici_trips_admin_delete
  ON public.sehirici_trips FOR DELETE
  USING (public.auth_is_admin());

-- Trip Locations: sadece ilgili sefer sahibi şoför veya admin yazabilir
DROP POLICY IF EXISTS sehirici_trip_locations_select_all ON public.sehirici_trip_locations;
CREATE POLICY sehirici_trip_locations_select_all
  ON public.sehirici_trip_locations FOR SELECT
  USING (TRUE);

DROP POLICY IF EXISTS sehirici_trip_locations_driver_insert ON public.sehirici_trip_locations;
CREATE POLICY sehirici_trip_locations_driver_insert
  ON public.sehirici_trip_locations FOR INSERT
  WITH CHECK (
    trip_id IN (
      SELECT t.id FROM public.sehirici_trips t
      JOIN public.sehirici_drivers d ON t.driver_id = d.id
      WHERE d.profile_id = auth.uid()
    )
    OR public.auth_is_admin()
  );

-- Favorite Stops: sadece sahibi
DROP POLICY IF EXISTS sehirici_favorite_stops_own ON public.sehirici_favorite_stops;
CREATE POLICY sehirici_favorite_stops_own
  ON public.sehirici_favorite_stops FOR ALL
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS sehirici_favorite_stops_admin ON public.sehirici_favorite_stops;
CREATE POLICY sehirici_favorite_stops_admin
  ON public.sehirici_favorite_stops FOR SELECT
  USING (public.auth_is_admin());

-- =============================================================================
-- 4) Realtime Publication
-- =============================================================================
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'sehirici_trips'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.sehirici_trips;
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'sehirici_trip_locations'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.sehirici_trip_locations;
  END IF;
END $$;

-- =============================================================================
-- 5) RPC Fonksiyonları
-- =============================================================================

-- 5.1) Şehir ID'sine göre hatları ve durakları getir
CREATE OR REPLACE FUNCTION public.get_sehirici_lines_with_stops(p_city_id UUID)
RETURNS TABLE (
  line_id UUID,
  code TEXT,
  name TEXT,
  color_hex TEXT,
  vehicle_type sehirici_vehicle_type,
  estimated_minutes INTEGER,
  fare_amount NUMERIC,
  stops JSONB
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT
    l.id AS line_id,
    l.code,
    l.name,
    l.color_hex,
    l.vehicle_type,
    l.estimated_minutes,
    l.fare_amount,
    COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'stop_id', ls.stop_id,
            'stop_order', ls.stop_order,
            'minutes_from_start', ls.minutes_from_start,
            'distance_km', ls.distance_km,
            'name', s.name,
            'lat', s.lat,
            'lng', s.lng
          ) ORDER BY ls.stop_order
        )
        FROM public.sehirici_line_stops ls
        JOIN public.sehirici_stops s ON ls.stop_id = s.id
        WHERE ls.line_id = l.id
      ),
      '[]'::jsonb
    ) AS stops
  FROM public.sehirici_lines l
  WHERE l.city_id = p_city_id AND l.is_active = TRUE
  ORDER BY l.display_order, l.code;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_sehirici_lines_with_stops(UUID) TO authenticated, anon;
-- SECURITY DEFINER: anon çağrısında da yetki kontrolü RLS + içeride yapılıyor.
-- Public erişim için PUBLIC'ten EXECUTE açık kalmalı; ilave koruma yok.
-- (Linter uyarısı kabul edilebilir; başka şehiriçi SECURITY DEFINER fonksiyonları
-- sadece authenticated'a verildiği için anon burada amaçlı.)

-- 5.2) Aktif seferleri özet bilgi ile getir
CREATE OR REPLACE FUNCTION public.get_sehirici_active_trips(p_city_id UUID DEFAULT NULL)
RETURNS TABLE (
  trip_id UUID,
  line_id UUID,
  line_code TEXT,
  line_name TEXT,
  line_color TEXT,
  driver_name TEXT,
  current_lat DOUBLE PRECISION,
  current_lng DOUBLE PRECISION,
  current_heading REAL,
  current_speed REAL,
  started_at TIMESTAMPTZ,
  next_stop_id UUID,
  next_stop_name TEXT,
  next_stop_lat DOUBLE PRECISION,
  next_stop_lng DOUBLE PRECISION,
  eta_minutes INTEGER,
  status sehirici_trip_status
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT
    t.id AS trip_id,
    t.line_id,
    l.code AS line_code,
    l.name AS line_name,
    l.color_hex AS line_color,
    COALESCE(p.full_name, 'Şoför') AS driver_name,
    t.current_lat,
    t.current_lng,
    t.current_heading,
    t.current_speed,
    t.started_at,
    t.next_stop_id,
    ns.name AS next_stop_name,
    ns.lat AS next_stop_lat,
    ns.lng AS next_stop_lng,
    t.eta_minutes,
    t.status
  FROM public.sehirici_trips t
  JOIN public.sehirici_lines l ON t.line_id = l.id
  LEFT JOIN public.sehirici_drivers d ON t.driver_id = d.id
  LEFT JOIN public.profiles p ON d.profile_id = p.id
  LEFT JOIN public.sehirici_stops ns ON t.next_stop_id = ns.id
  WHERE t.status IN ('active', 'paused')
    AND (p_city_id IS NULL OR l.city_id = p_city_id)
  ORDER BY t.started_at DESC NULLS LAST;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_sehirici_active_trips(UUID) TO authenticated, anon;

-- 5.3) Duraktan geçen aktif seferler (kullanıcı durak seçtiğinde)
CREATE OR REPLACE FUNCTION public.get_sehirici_trips_for_stop(p_stop_id UUID)
RETURNS TABLE (
  trip_id UUID,
  line_id UUID,
  line_code TEXT,
  line_name TEXT,
  line_color TEXT,
  current_lat DOUBLE PRECISION,
  current_lng DOUBLE PRECISION,
  stop_order INTEGER,
  minutes_from_start INTEGER,
  eta_minutes INTEGER
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT
    t.id AS trip_id,
    l.id AS line_id,
    l.code AS line_code,
    l.name AS line_name,
    l.color_hex AS line_color,
    t.current_lat,
    t.current_lng,
    ls.stop_order,
    ls.minutes_from_start,
    t.eta_minutes
  FROM public.sehirici_trips t
  JOIN public.sehirici_lines l ON t.line_id = l.id
  JOIN public.sehirici_line_stops ls ON ls.line_id = l.id AND ls.stop_id = p_stop_id
  WHERE t.status IN ('active', 'paused')
  ORDER BY t.eta_minutes NULLS LAST;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_sehirici_trips_for_stop(UUID) TO authenticated, anon;

-- 5.4) Şoför için sefer başlat
CREATE OR REPLACE FUNCTION public.start_sehirici_trip(
  p_driver_id UUID,
  p_line_id UUID,
  p_initial_lat DOUBLE PRECISION,
  p_initial_lng DOUBLE PRECISION
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_trip_id UUID;
  v_driver_profile UUID;
  v_existing_active UUID;
BEGIN
  -- Şoför doğrulama
  SELECT profile_id INTO v_driver_profile
  FROM public.sehirici_drivers WHERE id = p_driver_id;

  IF v_driver_profile IS NULL OR v_driver_profile != auth.uid() THEN
    RAISE EXCEPTION 'Bu sürücü için yetkiniz yok';
  END IF;

  -- Zaten aktif sefer varsa kapat
  SELECT id INTO v_existing_active
  FROM public.sehirici_trips
  WHERE driver_id = p_driver_id AND status IN ('active', 'paused')
  LIMIT 1;

  IF v_existing_active IS NOT NULL THEN
    UPDATE public.sehirici_trips
    SET status = 'completed', ended_at = now()
    WHERE id = v_existing_active;
  END IF;

  -- Yeni sefer oluştur
  INSERT INTO public.sehirici_trips (
    line_id, driver_id, status, started_at, current_lat, current_lng
  ) VALUES (
    p_line_id, p_driver_id, 'active', now(), p_initial_lat, p_initial_lng
  )
  RETURNING id INTO v_trip_id;

  -- İlk konum kaydı
  INSERT INTO public.sehirici_trip_locations (trip_id, lat, lng)
  VALUES (v_trip_id, p_initial_lat, p_initial_lng);

  -- Şoförü göreve al
  UPDATE public.sehirici_drivers SET is_on_duty = TRUE WHERE id = p_driver_id;

  RETURN v_trip_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.start_sehirici_trip(UUID, UUID, DOUBLE PRECISION, DOUBLE PRECISION) TO authenticated;

-- 5.5) Şoför için konum güncelle (toplu: trip + location + ETA hesabı)
CREATE OR REPLACE FUNCTION public.update_sehirici_trip_location(
  p_trip_id UUID,
  p_lat DOUBLE PRECISION,
  p_lng DOUBLE PRECISION,
  p_heading REAL DEFAULT NULL,
  p_speed REAL DEFAULT NULL,
  p_passenger_count INTEGER DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_driver_profile UUID;
BEGIN
  -- Yetki kontrolü
  SELECT d.profile_id INTO v_driver_profile
  FROM public.sehirici_trips t
  JOIN public.sehirici_drivers d ON t.driver_id = d.id
  WHERE t.id = p_trip_id;

  IF v_driver_profile IS NULL OR v_driver_profile != auth.uid() THEN
    RAISE EXCEPTION 'Bu sefer için yetkiniz yok';
  END IF;

  -- Trip güncelle
  UPDATE public.sehirici_trips
  SET current_lat = p_lat,
      current_lng = p_lng,
      current_heading = COALESCE(p_heading, current_heading),
      current_speed = COALESCE(p_speed, current_speed),
      passenger_count = COALESCE(p_passenger_count, passenger_count),
      updated_at = now()
  WHERE id = p_trip_id AND status = 'active';

  -- Konum geçmişi
  INSERT INTO public.sehirici_trip_locations (trip_id, lat, lng, heading, speed)
  VALUES (p_trip_id, p_lat, p_lng, p_heading, p_speed);
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_sehirici_trip_location(UUID, DOUBLE PRECISION, DOUBLE PRECISION, REAL, REAL, INTEGER) TO authenticated;

-- 5.6) Sefer durumunu güncelle (pause/resume/complete)
CREATE OR REPLACE FUNCTION public.set_sehirici_trip_status(
  p_trip_id UUID,
  p_new_status sehirici_trip_status
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_driver_profile UUID;
BEGIN
  SELECT d.profile_id INTO v_driver_profile
  FROM public.sehirici_trips t
  JOIN public.sehirici_drivers d ON t.driver_id = d.id
  WHERE t.id = p_trip_id;

  IF v_driver_profile IS NULL OR v_driver_profile != auth.uid() THEN
    RAISE EXCEPTION 'Bu sefer için yetkiniz yok';
  END IF;

  UPDATE public.sehirici_trips
  SET status = p_new_status,
      ended_at = CASE WHEN p_new_status IN ('completed', 'cancelled') THEN now() ELSE ended_at END,
      updated_at = now()
  WHERE id = p_trip_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.set_sehirici_trip_status(UUID, sehirici_trip_status) TO authenticated;

-- 5.7) Sıradaki durağı ve ETA'yı hesapla (basit mesafe-bazlı)
CREATE OR REPLACE FUNCTION public.compute_sehirici_next_stop(p_trip_id UUID)
RETURNS TABLE (
  next_stop_id UUID,
  next_stop_name TEXT,
  eta_minutes INTEGER
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_line_id UUID;
  v_lat DOUBLE PRECISION;
  v_lng DOUBLE PRECISION;
  v_speed REAL;
BEGIN
  SELECT line_id, current_lat, current_lng, COALESCE(current_speed, 8.0)
    INTO v_line_id, v_lat, v_lng, v_speed
  FROM public.sehirici_trips WHERE id = p_trip_id;

  IF v_line_id IS NULL OR v_lat IS NULL OR v_lng IS NULL THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    s.id,
    s.name,
    GREATEST(1, CEIL(
      (earth_distance(
        ll_to_earth(v_lat, v_lng),
        ll_to_earth(s.lat, s.lng)
      ) / 1000.0) / NULLIF(v_speed * 3.6, 0) * 60)::INTEGER
    )::INTEGER AS eta_minutes
  FROM public.sehirici_line_stops ls
  JOIN public.sehirici_stops s ON ls.stop_id = s.id
  WHERE ls.line_id = v_line_id
  ORDER BY
    -- En yakın durak
    earth_distance(ll_to_earth(v_lat, v_lng), ll_to_earth(s.lat, s.lng)) ASC
  LIMIT 1;
END;
$$;

GRANT EXECUTE ON FUNCTION public.compute_sehirici_next_stop(UUID) TO authenticated, anon;

-- earth_distance için gerekli olabilir (extensions şemasında — public'i kirletmez)
CREATE EXTENSION IF NOT EXISTS cube WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS earthdistance WITH SCHEMA extensions;

-- Eğer public şemasında yanlışlıkla kurulmuşsa, şema ile çağıralım.
-- compute_sehirici_next_stop içinde extensions.earth_distance / extensions.ll_to_earth kullanırız.

-- 5.8) Eski konum kayıtlarını temizle (cron çağırır)
CREATE OR REPLACE FUNCTION public.cleanup_sehirici_old_locations(p_keep_minutes INTEGER DEFAULT 60)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_deleted INTEGER;
BEGIN
  DELETE FROM public.sehirici_trip_locations
  WHERE recorded_at < now() - (p_keep_minutes || ' minutes')::INTERVAL;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  RETURN v_deleted;
END;
$$;

GRANT EXECUTE ON FUNCTION public.cleanup_sehirici_old_locations(INTEGER) TO service_role;

-- =============================================================================
-- 6) Default Sistem Ayarları
-- =============================================================================
-- value kolonu jsonb ve NOT NULL: tüm değerler JSON string olarak saklanır.
-- Dart tarafı (SehiriciSettings.fromSettingsMap) string bekler.
INSERT INTO public.app_settings (key, value, description)
VALUES
  ('sehirici_module_enabled', '"true"', 'Şehiriçi servis modülü açık mı?'),
  ('sehirici_default_city_id', '""', 'Varsayılan şehir UUID (boş = ilk şehir)'),
  ('sehirici_location_update_interval_sec', '"10"', 'Şoför konum güncelleme aralığı (sn)'),
  ('sehirici_eta_refresh_seconds', '"30"', 'Kullanıcı tarafı ETA yenileme (sn)'),
  ('sehirici_max_history_minutes', '"60"', 'Konum geçmişi saklama süresi (dk)'),
  ('sehirici_allow_user_favorites', '"true"', 'Kullanıcı favori durağı ekleyebilir mi?')
ON CONFLICT (key) DO NOTHING;

-- =============================================================================
-- 7) updated_at trigger
-- =============================================================================
CREATE OR REPLACE FUNCTION public.sehirici_set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_sehirici_cities_updated_at') THEN
    CREATE TRIGGER trg_sehirici_cities_updated_at
      BEFORE UPDATE ON public.sehirici_cities
      FOR EACH ROW EXECUTE FUNCTION public.sehirici_set_updated_at();
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_sehirici_lines_updated_at') THEN
    CREATE TRIGGER trg_sehirici_lines_updated_at
      BEFORE UPDATE ON public.sehirici_lines
      FOR EACH ROW EXECUTE FUNCTION public.sehirici_set_updated_at();
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_sehirici_stops_updated_at') THEN
    CREATE TRIGGER trg_sehirici_stops_updated_at
      BEFORE UPDATE ON public.sehirici_stops
      FOR EACH ROW EXECUTE FUNCTION public.sehirici_set_updated_at();
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_sehirici_drivers_updated_at') THEN
    CREATE TRIGGER trg_sehirici_drivers_updated_at
      BEFORE UPDATE ON public.sehirici_drivers
      FOR EACH ROW EXECUTE FUNCTION public.sehirici_set_updated_at();
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_sehirici_trips_updated_at') THEN
    CREATE TRIGGER trg_sehirici_trips_updated_at
      BEFORE UPDATE ON public.sehirici_trips
      FOR EACH ROW EXECUTE FUNCTION public.sehirici_set_updated_at();
  END IF;
END $$;

-- =============================================================================
-- 8) Bildirim: Kullanıcının favori durağına yaklaşan sefer
-- (uygulama tarafında polling ile tetiklenir; burada sadece fonksiyon)
-- =============================================================================
CREATE OR REPLACE FUNCTION public.notify_sehirici_favorite_approaching(
  p_trip_id UUID,
  p_stop_id UUID,
  p_eta_minutes INTEGER
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INTEGER := 0;
BEGIN
  -- Her favori durak sahibine bildirim gönder
  WITH inserted AS (
    INSERT INTO public.notifications (user_id, type, title, content, data)
    SELECT
      fs.user_id,
      'sehirici_trip_near_stop',
      'Servis Yaklaşıyor!',
      format('Favori durağınıza %s dakika kaldı', p_eta_minutes),
      jsonb_build_object(
        'trip_id', p_trip_id,
        'stop_id', p_stop_id,
        'eta_minutes', p_eta_minutes
      )
    FROM public.sehirici_favorite_stops fs
    WHERE fs.stop_id = p_stop_id
      AND p_eta_minutes <= fs.notify_minutes_before
    RETURNING 1
  )
  SELECT count(*) INTO v_count FROM inserted;

  RETURN v_count;
END;
$$;

GRANT EXECUTE ON FUNCTION public.notify_sehirici_favorite_approaching(UUID, UUID, INTEGER) TO authenticated, service_role;

-- =============================================================================
-- 9) Realtime: trips tablosunda INSERT/UPDATE abone olunabilir
-- =============================================================================

-- =============================================================================
-- 9b) Güvenlik: SECURITY DEFINER fonksiyonlarından PUBLIC (anon) EXECUTE
-- yetkisini kaldır — yalnızca yukarıda GRANT edilen roller çağırabilsin.
-- (Supabase linter: anon_security_definer_function_executable uyarısını giderir)
-- =============================================================================
REVOKE EXECUTE ON FUNCTION public.start_sehirici_trip(UUID, UUID, DOUBLE PRECISION, DOUBLE PRECISION) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.update_sehirici_trip_location(UUID, DOUBLE PRECISION, DOUBLE PRECISION, REAL, REAL, INTEGER) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.set_sehirici_trip_status(UUID, public.sehirici_trip_status) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.cleanup_sehirici_old_locations(INTEGER) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.notify_sehirici_favorite_approaching(UUID, UUID, INTEGER) FROM PUBLIC;

COMMENT ON TABLE public.sehirici_cities IS 'Şehir içi servis sistemi - Şehirler';
COMMENT ON TABLE public.sehirici_lines IS 'Şehir içi servis sistemi - Hatlar';
COMMENT ON TABLE public.sehirici_stops IS 'Şehir içi servis sistemi - Duraklar';
COMMENT ON TABLE public.sehirici_line_stops IS 'Hat-Durak ilişkisi ve sırası';
COMMENT ON TABLE public.sehirici_drivers IS 'Şoför profilleri ve hat atamaları';
COMMENT ON TABLE public.sehirici_trips IS 'Aktif ve geçmiş seferler';
COMMENT ON TABLE public.sehirici_trip_locations IS 'Sefer canlı konum geçmişi (max 1 saat)';
COMMENT ON TABLE public.sehirici_favorite_stops IS 'Kullanıcı favori durakları';

-- =============================================================================
-- SON
-- =============================================================================
