-- =============================================================================
-- ŞEHİRİÇİ — HARİTA İKON KÜTÜPHANESİ
-- Tarih: 2026-09-21
--
-- SORUN: Hattın araç türü `sehirici_vehicle_type` Postgres ENUM'uydu (minibus,
-- bus, midibus, dolmus, tram, other). Bu yüzden
--   • admin yeni bir araç türü (ör. "Taksi", "Servis") EKLEYEMİYORDU,
--   • haritadaki araç/durak görselini DEĞİŞTİREMİYORDU (görseller kodda gömülüydü).
--
-- ÇÖZÜM: Tür = kütüphane satırı. Her ikon bir "hazır çizim" (uygulamanın tepeden
-- görünüm çizimi) ve/veya admin'in yüklediği bir görsel taşır; hat, ikonu
-- `sehirici_marker_icons.key` ile seçer. Durak ikonları da aynı kütüphanededir
-- (kind = 'stop'); varsayılan olan (is_default) haritada kullanılır.
--
-- Geri uyum: eski uygulama sürümleri vehicle_type'ı metin olarak okur/yazar ve
-- eski enum değerlerinin hepsi katalogda anahtar olarak vardır — bozulmaz.
-- Bilinmeyen (yeni eklenmiş) bir anahtarı eski uygulama "diğer" gibi çizer.
--
-- İdempotent: tekrar çalıştırılabilir.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1) Tablo
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.sehirici_marker_icons (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kind                 text NOT NULL,
  key                  text NOT NULL,
  label                text NOT NULL,
  -- Uygulamanın kendi çizdiği hazır şekil. Görsel yüklenmiş olsa da yedek olarak
  -- kalır: görsel kaldırılınca bu şekle dönülür.
  builtin_shape        text,
  -- Admin'in yüklediği görsel (herkese açık bucket). Doluysa hazır çizimin yerine geçer.
  image_url            text,
  image_path           text,
  -- Görselin "burnu" hangi yöne bakıyorsa onu yukarıya çevirmek için (saat yönünde derece).
  image_rotation       smallint NOT NULL DEFAULT 0,
  -- true: hazır çizim hattın rengiyle boyanır. Yüklenen görseller boyanmaz.
  tint_with_line_color boolean NOT NULL DEFAULT true,
  scale                numeric(3,2) NOT NULL DEFAULT 1.00,
  -- Durak görselleri için: true → görselin alt-orta noktası koordinata oturur
  -- (iğne/levha), false → merkez.
  anchor_bottom        boolean NOT NULL DEFAULT false,
  is_builtin           boolean NOT NULL DEFAULT false,
  is_active            boolean NOT NULL DEFAULT true,
  is_default           boolean NOT NULL DEFAULT false,
  sort_order           integer NOT NULL DEFAULT 0,
  created_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT sehirici_marker_icons_kind_chk
    CHECK (kind IN ('vehicle', 'stop')),
  CONSTRAINT sehirici_marker_icons_key_chk
    CHECK (key ~ '^[a-z][a-z0-9_]{1,31}$'),
  -- Durak anahtarları "stop_" ile başlar; böylece tek bir global benzersiz
  -- anahtar alanı hem araç hem durak için yeter ve hat → ikon FK'si kurulabilir.
  CONSTRAINT sehirici_marker_icons_key_kind_chk
    CHECK ((kind = 'stop') = (key LIKE 'stop\_%')),
  CONSTRAINT sehirici_marker_icons_label_chk
    CHECK (char_length(btrim(label)) BETWEEN 1 AND 40),
  CONSTRAINT sehirici_marker_icons_rotation_chk
    CHECK (image_rotation IN (0, 90, 180, 270)),
  CONSTRAINT sehirici_marker_icons_scale_chk
    CHECK (scale BETWEEN 0.40 AND 2.50),
  CONSTRAINT sehirici_marker_icons_source_chk
    CHECK (builtin_shape IS NOT NULL OR image_url IS NOT NULL),
  CONSTRAINT sehirici_marker_icons_key_key UNIQUE (key)
);

-- Her türde (araç / durak) en fazla bir varsayılan.
CREATE UNIQUE INDEX IF NOT EXISTS sehirici_marker_icons_one_default_per_kind
  ON public.sehirici_marker_icons (kind)
  WHERE is_default;

CREATE INDEX IF NOT EXISTS idx_sehirici_marker_icons_kind_order
  ON public.sehirici_marker_icons (kind, sort_order, label);

DROP TRIGGER IF EXISTS trg_sehirici_marker_icons_updated_at
  ON public.sehirici_marker_icons;
CREATE TRIGGER trg_sehirici_marker_icons_updated_at
  BEFORE UPDATE ON public.sehirici_marker_icons
  FOR EACH ROW EXECUTE FUNCTION public.sehirici_set_updated_at();

-- -----------------------------------------------------------------------------
-- 2) Yerleşik (seed) ikonlar — eski enum değerlerinin birebir karşılığı
-- -----------------------------------------------------------------------------
INSERT INTO public.sehirici_marker_icons
  (kind, key, label, builtin_shape, is_builtin, is_default, sort_order)
VALUES
  ('vehicle', 'minibus', 'Minibüs',  'minibus', true, false, 10),
  ('vehicle', 'dolmus',  'Dolmuş',   'dolmus',  true, false, 20),
  ('vehicle', 'midibus', 'Midibüs',  'midibus', true, false, 30),
  ('vehicle', 'bus',     'Otobüs',   'bus',     true, false, 40),
  ('vehicle', 'tram',    'Tramvay',  'tram',    true, false, 50),
  ('vehicle', 'other',   'Diğer',    'car',     true, true,  90),
  ('stop', 'stop_sign',  'Durak Levhası', 'sign', true, true,  10),
  ('stop', 'stop_pin',   'Modern İğne',   'pin',  true, false, 20),
  ('stop', 'stop_dot',   'Sade Nokta',    'dot',  true, false, 30)
ON CONFLICT (key) DO NOTHING;

-- -----------------------------------------------------------------------------
-- 3) RLS — katalog herkese açık okunur; yazma yalnız admin RPC'leriyle
-- -----------------------------------------------------------------------------
ALTER TABLE public.sehirici_marker_icons ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS sehirici_marker_icons_read ON public.sehirici_marker_icons;
CREATE POLICY sehirici_marker_icons_read
  ON public.sehirici_marker_icons
  FOR SELECT
  TO anon, authenticated
  USING (true);

REVOKE INSERT, UPDATE, DELETE, TRUNCATE
  ON public.sehirici_marker_icons FROM anon, authenticated;

-- -----------------------------------------------------------------------------
-- 4) Hattın araç türü: enum → katalog anahtarı (metin + FK)
-- -----------------------------------------------------------------------------
ALTER TABLE public.sehirici_lines ALTER COLUMN vehicle_type DROP DEFAULT;
ALTER TABLE public.sehirici_lines
  ALTER COLUMN vehicle_type TYPE text USING vehicle_type::text;
ALTER TABLE public.sehirici_lines ALTER COLUMN vehicle_type SET DEFAULT 'bus';

ALTER TABLE public.sehirici_lines
  DROP CONSTRAINT IF EXISTS sehirici_lines_vehicle_type_fkey;
ALTER TABLE public.sehirici_lines
  ADD CONSTRAINT sehirici_lines_vehicle_type_fkey
  FOREIGN KEY (vehicle_type)
  REFERENCES public.sehirici_marker_icons (key)
  ON UPDATE CASCADE
  ON DELETE RESTRICT;

-- -----------------------------------------------------------------------------
-- 5) Hat kaydı: doğrulama + sıra korunur
--    (imza aynı → eski istemciler bozulmaz)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_upsert_sehirici_line(
  p_id uuid,
  p_city_id uuid,
  p_code text,
  p_name text,
  p_color_hex text,
  p_vehicle_type text,
  p_estimated_minutes integer,
  p_fare_amount numeric,
  p_is_active boolean,
  p_display_order integer
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_id uuid;
  v_code text := btrim(coalesce(p_code, ''));
  v_name text := btrim(coalesce(p_name, ''));
  v_type text := COALESCE(NULLIF(btrim(coalesce(p_vehicle_type, '')), ''), 'bus');
  v_color text := COALESCE(NULLIF(btrim(coalesce(p_color_hex, '')), ''), '#1976D2');
BEGIN
  IF NOT public.auth_sehirici_is_admin() THEN
    RAISE EXCEPTION 'Bu işlem için admin yetkisi gerekir';
  END IF;

  IF v_code = '' THEN
    RAISE EXCEPTION 'Hat kodu boş olamaz';
  END IF;
  IF v_name = '' THEN
    RAISE EXCEPTION 'Hat adı boş olamaz';
  END IF;
  IF v_color !~ '^#[0-9A-Fa-f]{6}$' THEN
    RAISE EXCEPTION 'Renk #RRGGBB biçiminde olmalı';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.sehirici_marker_icons
    WHERE key = v_type AND kind = 'vehicle'
  ) THEN
    RAISE EXCEPTION 'Geçersiz araç türü: %', v_type;
  END IF;
  IF p_estimated_minutes IS NOT NULL AND p_estimated_minutes < 0 THEN
    RAISE EXCEPTION 'Süre eksi olamaz';
  END IF;
  IF COALESCE(p_fare_amount, 0) < 0 THEN
    RAISE EXCEPTION 'Ücret eksi olamaz';
  END IF;

  INSERT INTO public.sehirici_lines (
    id, city_id, code, name, color_hex, vehicle_type,
    estimated_minutes, fare_amount, is_active, display_order
  )
  VALUES (
    COALESCE(p_id, gen_random_uuid()),
    p_city_id,
    v_code,
    v_name,
    upper(v_color),
    v_type,
    p_estimated_minutes,
    COALESCE(p_fare_amount, 0),
    COALESCE(p_is_active, TRUE),
    -- Sıra verilmediyse yeni hat listenin sonuna eklenir.
    COALESCE(
      p_display_order,
      (SELECT COALESCE(MAX(l.display_order), 0) + 1
         FROM public.sehirici_lines l WHERE l.city_id = p_city_id)
    )
  )
  ON CONFLICT (id) DO UPDATE SET
    city_id = EXCLUDED.city_id,
    code = EXCLUDED.code,
    name = EXCLUDED.name,
    color_hex = EXCLUDED.color_hex,
    vehicle_type = EXCLUDED.vehicle_type,
    estimated_minutes = EXCLUDED.estimated_minutes,
    fare_amount = EXCLUDED.fare_amount,
    is_active = EXCLUDED.is_active,
    -- Sıra verilmediyse (NULL) mevcut sıra korunur; eskiden her düzenleme 0'a
    -- sıfırlıyordu.
    display_order = COALESCE(p_display_order, public.sehirici_lines.display_order),
    updated_at = now()
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_upsert_sehirici_line(
  uuid, uuid, text, text, text, text, integer, numeric, boolean, integer
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_upsert_sehirici_line(
  uuid, uuid, text, text, text, text, integer, numeric, boolean, integer
) TO authenticated;

-- -----------------------------------------------------------------------------
-- 6) Kullanıcıya dönen hat listesi: araç türü artık metin; durak kodu + adresi eklendi
--    (dönüş tipi değiştiği için DROP + CREATE)
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.get_sehirici_lines_with_stops(uuid);

CREATE FUNCTION public.get_sehirici_lines_with_stops(p_city_id uuid)
RETURNS TABLE (
  line_id uuid,
  code text,
  name text,
  color_hex text,
  vehicle_type text,
  estimated_minutes integer,
  fare_amount numeric,
  stops jsonb,
  route_polyline jsonb
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
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
            'lng', s.lng,
            'code', s.code,
            'address', s.address
          ) ORDER BY ls.stop_order
        )
        FROM public.sehirici_line_stops ls
        JOIN public.sehirici_stops s ON ls.stop_id = s.id
        WHERE ls.line_id = l.id
      ),
      '[]'::jsonb
    ) AS stops,
    l.route_polyline
  FROM public.sehirici_lines l
  WHERE l.city_id = p_city_id AND l.is_active = TRUE
  ORDER BY l.display_order, l.code;
END;
$$;

REVOKE ALL ON FUNCTION public.get_sehirici_lines_with_stops(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_sehirici_lines_with_stops(uuid)
  TO anon, authenticated;

-- -----------------------------------------------------------------------------
-- 7) Admin RPC'leri — ikon kütüphanesi
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_upsert_sehirici_marker_icon(
  p_id uuid,
  p_kind text,
  p_key text,
  p_label text,
  p_builtin_shape text,
  p_image_url text,
  p_image_path text,
  p_image_rotation integer,
  p_tint_with_line_color boolean,
  p_scale numeric,
  p_anchor_bottom boolean,
  p_is_active boolean,
  p_sort_order integer
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_existing public.sehirici_marker_icons%ROWTYPE;
  v_kind text;
  v_key text;
  v_label text := btrim(coalesce(p_label, ''));
  v_shape text := NULLIF(btrim(coalesce(p_builtin_shape, '')), '');
  v_url text := NULLIF(btrim(coalesce(p_image_url, '')), '');
  v_path text := NULLIF(btrim(coalesce(p_image_path, '')), '');
  v_rotation integer := COALESCE(p_image_rotation, 0);
  v_scale numeric := COALESCE(p_scale, 1.0);
  v_id uuid;
BEGIN
  IF NOT public.auth_sehirici_is_admin() THEN
    RAISE EXCEPTION 'Bu işlem için admin yetkisi gerekir';
  END IF;

  IF v_label = '' THEN
    RAISE EXCEPTION 'İkon adı boş olamaz';
  END IF;
  IF char_length(v_label) > 40 THEN
    RAISE EXCEPTION 'İkon adı en fazla 40 karakter olabilir';
  END IF;

  IF p_id IS NOT NULL THEN
    SELECT * INTO v_existing
    FROM public.sehirici_marker_icons WHERE id = p_id;
  END IF;

  IF v_existing.id IS NOT NULL THEN
    -- Tür ve anahtar hatların referansı olduğundan değiştirilemez.
    v_kind := v_existing.kind;
    v_key := v_existing.key;
  ELSE
    v_kind := lower(btrim(coalesce(p_kind, '')));
    v_key := lower(btrim(coalesce(p_key, '')));
    IF v_kind NOT IN ('vehicle', 'stop') THEN
      RAISE EXCEPTION 'İkon türü araç veya durak olmalı';
    END IF;
    IF v_kind = 'stop' AND v_key NOT LIKE 'stop\_%' THEN
      v_key := 'stop_' || v_key;
    END IF;
    IF v_key !~ '^[a-z][a-z0-9_]{1,31}$' THEN
      RAISE EXCEPTION
        'Anahtar 2-32 karakter olmalı; harf ile başlamalı, yalnız küçük harf, rakam ve alt çizgi içermeli';
    END IF;
    IF v_kind = 'vehicle' AND v_key LIKE 'stop\_%' THEN
      RAISE EXCEPTION 'Araç anahtarı "stop_" ile başlayamaz';
    END IF;
    IF EXISTS (SELECT 1 FROM public.sehirici_marker_icons WHERE key = v_key) THEN
      RAISE EXCEPTION 'Bu anahtar zaten kullanılıyor: %', v_key;
    END IF;
  END IF;

  IF v_shape IS NOT NULL AND NOT (
       (v_kind = 'vehicle' AND v_shape IN
         ('minibus', 'midibus', 'bus', 'dolmus', 'tram', 'car', 'taxi', 'motorcycle'))
    OR (v_kind = 'stop' AND v_shape IN ('sign', 'pin', 'dot'))
  ) THEN
    RAISE EXCEPTION 'Geçersiz hazır çizim: %', v_shape;
  END IF;
  IF v_shape IS NULL AND v_url IS NULL THEN
    RAISE EXCEPTION 'Hazır bir çizim seçin veya görsel yükleyin';
  END IF;
  IF v_rotation NOT IN (0, 90, 180, 270) THEN
    RAISE EXCEPTION 'Görsel yönü 0, 90, 180 veya 270 olmalı';
  END IF;
  IF v_scale < 0.4 OR v_scale > 2.5 THEN
    RAISE EXCEPTION 'Ölçek 0,4 ile 2,5 arasında olmalı';
  END IF;

  IF v_existing.id IS NULL THEN
    INSERT INTO public.sehirici_marker_icons (
      kind, key, label, builtin_shape, image_url, image_path, image_rotation,
      tint_with_line_color, scale, anchor_bottom, is_active, sort_order
    )
    VALUES (
      v_kind, v_key, v_label, v_shape, v_url,
      CASE WHEN v_url IS NULL THEN NULL ELSE v_path END,
      v_rotation,
      COALESCE(p_tint_with_line_color, TRUE),
      v_scale,
      COALESCE(p_anchor_bottom, FALSE),
      COALESCE(p_is_active, TRUE),
      COALESCE(p_sort_order, 100)
    )
    RETURNING id INTO v_id;
  ELSE
    UPDATE public.sehirici_marker_icons SET
      label = v_label,
      builtin_shape = v_shape,
      image_url = v_url,
      image_path = CASE WHEN v_url IS NULL THEN NULL ELSE v_path END,
      image_rotation = v_rotation,
      tint_with_line_color = COALESCE(p_tint_with_line_color, tint_with_line_color),
      scale = v_scale,
      anchor_bottom = COALESCE(p_anchor_bottom, anchor_bottom),
      -- Varsayılan ikon pasife alınamaz (haritada kullanılan o).
      is_active = CASE WHEN is_default THEN TRUE
                       ELSE COALESCE(p_is_active, is_active) END,
      sort_order = COALESCE(p_sort_order, sort_order)
    WHERE id = v_existing.id
    RETURNING id INTO v_id;
  END IF;

  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_delete_sehirici_marker_icon(p_id uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_row public.sehirici_marker_icons%ROWTYPE;
  v_used integer;
BEGIN
  IF NOT public.auth_sehirici_is_admin() THEN
    RAISE EXCEPTION 'Bu işlem için admin yetkisi gerekir';
  END IF;

  SELECT * INTO v_row FROM public.sehirici_marker_icons WHERE id = p_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'İkon bulunamadı';
  END IF;
  IF v_row.is_builtin THEN
    RAISE EXCEPTION
      'Yerleşik ikonlar silinemez; yüklediğiniz görseli kaldırıp hazır çizime dönebilirsiniz';
  END IF;
  IF v_row.is_default THEN
    RAISE EXCEPTION
      'Varsayılan ikon silinemez; önce başka bir ikonu varsayılan yapın';
  END IF;
  IF v_row.kind = 'vehicle' THEN
    SELECT count(*) INTO v_used
    FROM public.sehirici_lines WHERE vehicle_type = v_row.key;
    IF v_used > 0 THEN
      RAISE EXCEPTION
        '% hat bu ikonu kullanıyor; önce o hatların araç türünü değiştirin', v_used;
    END IF;
  END IF;

  DELETE FROM public.sehirici_marker_icons WHERE id = p_id;
  -- İstemci, dönen yolu bucket'tan siler.
  RETURN v_row.image_path;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_set_default_sehirici_marker_icon(p_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_kind text;
BEGIN
  IF NOT public.auth_sehirici_is_admin() THEN
    RAISE EXCEPTION 'Bu işlem için admin yetkisi gerekir';
  END IF;

  SELECT kind INTO v_kind FROM public.sehirici_marker_icons WHERE id = p_id;
  IF v_kind IS NULL THEN
    RAISE EXCEPTION 'İkon bulunamadı';
  END IF;

  -- Benzersiz kısmi indeks yüzünden önce eski varsayılan kaldırılır.
  UPDATE public.sehirici_marker_icons
     SET is_default = FALSE
   WHERE kind = v_kind AND is_default AND id <> p_id;
  UPDATE public.sehirici_marker_icons
     SET is_default = TRUE, is_active = TRUE
   WHERE id = p_id;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_upsert_sehirici_marker_icon(
  uuid, text, text, text, text, text, text, integer, boolean, numeric, boolean, boolean, integer
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_upsert_sehirici_marker_icon(
  uuid, text, text, text, text, text, text, integer, boolean, numeric, boolean, boolean, integer
) TO authenticated;

REVOKE ALL ON FUNCTION public.admin_delete_sehirici_marker_icon(uuid)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_delete_sehirici_marker_icon(uuid)
  TO authenticated;

REVOKE ALL ON FUNCTION public.admin_set_default_sehirici_marker_icon(uuid)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_set_default_sehirici_marker_icon(uuid)
  TO authenticated;

-- -----------------------------------------------------------------------------
-- 8) Görsel deposu (herkese açık okuma, yazma yalnız admin)
--    product-image-presets ile aynı desen.
-- -----------------------------------------------------------------------------
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'sehirici-icons',
  'sehirici-icons',
  true,
  1048576, -- 1 MB: harita ikonları küçüktür
  ARRAY['image/png', 'image/webp', 'image/jpeg']
) ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "Şehiriçi ikonları herkese açık" ON storage.objects;
DROP POLICY IF EXISTS "Sadece adminler şehiriçi ikonu yükleyebilir" ON storage.objects;
DROP POLICY IF EXISTS "Sadece adminler şehiriçi ikonunu güncelleyebilir" ON storage.objects;
DROP POLICY IF EXISTS "Sadece adminler şehiriçi ikonunu silebilir" ON storage.objects;

CREATE POLICY "Şehiriçi ikonları herkese açık"
ON storage.objects FOR SELECT
TO public
USING (bucket_id = 'sehirici-icons');

CREATE POLICY "Sadece adminler şehiriçi ikonu yükleyebilir"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (bucket_id = 'sehirici-icons' AND public.auth_is_admin());

CREATE POLICY "Sadece adminler şehiriçi ikonunu güncelleyebilir"
ON storage.objects FOR UPDATE
TO authenticated
USING (bucket_id = 'sehirici-icons' AND public.auth_is_admin())
WITH CHECK (bucket_id = 'sehirici-icons' AND public.auth_is_admin());

CREATE POLICY "Sadece adminler şehiriçi ikonunu silebilir"
ON storage.objects FOR DELETE
TO authenticated
USING (bucket_id = 'sehirici-icons' AND public.auth_is_admin());

NOTIFY pgrst, 'reload schema';
