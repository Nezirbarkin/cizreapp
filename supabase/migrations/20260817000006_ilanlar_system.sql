-- =============================================================================
-- CizreApp profesyonel ilan sistemi
-- Kayıp, satılık, kiralık ve yönetilebilir özel kategoriler.
-- Güvenlik ilkesi: istemciye güvenilmez; yayın/moderasyon kuralları DB'de uygulanır.
-- =============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- RLS politikalarında profiles tablosunda özyineleme oluşturmadan admin kontrolü.
CREATE OR REPLACE FUNCTION public.ilan_is_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.profiles p
    WHERE p.id = (SELECT auth.uid())
      AND (p.role::text = 'admin' OR COALESCE(p.is_admin, false))
  );
$$;

REVOKE ALL ON FUNCTION public.ilan_is_admin() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ilan_is_admin() TO authenticated, service_role;

CREATE TABLE IF NOT EXISTS public.ilan_settings (
  id smallint PRIMARY KEY DEFAULT 1 CHECK (id = 1),
  is_enabled boolean NOT NULL DEFAULT true,
  allow_user_create boolean NOT NULL DEFAULT true,
  require_approval boolean NOT NULL DEFAULT true,
  allow_guest_view boolean NOT NULL DEFAULT true,
  max_active_per_user integer NOT NULL DEFAULT 10 CHECK (max_active_per_user BETWEEN 1 AND 100),
  max_images_per_ilan integer NOT NULL DEFAULT 8 CHECK (max_images_per_ilan BETWEEN 1 AND 12),
  default_expiry_days integer NOT NULL DEFAULT 30 CHECK (default_expiry_days BETWEEN 1 AND 365),
  home_category_limit integer NOT NULL DEFAULT 6 CHECK (home_category_limit BETWEEN 1 AND 12),
  home_ilan_limit integer NOT NULL DEFAULT 8 CHECK (home_ilan_limit BETWEEN 1 AND 20),
  show_prices_on_home boolean NOT NULL DEFAULT true,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL
);

INSERT INTO public.ilan_settings (id) VALUES (1)
ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.ilan_categories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL CHECK (char_length(btrim(name)) BETWEEN 2 AND 60),
  slug text NOT NULL UNIQUE CHECK (slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'),
  description text,
  icon_name text NOT NULL DEFAULT 'category',
  color_hex text NOT NULL DEFAULT '#6D28D9' CHECK (color_hex ~ '^#[0-9A-Fa-f]{6}$'),
  category_type text NOT NULL DEFAULT 'other'
    CHECK (category_type IN ('lost', 'sale', 'rent', 'service', 'other')),
  pricing_mode text NOT NULL DEFAULT 'optional'
    CHECK (pricing_mode IN ('forbidden', 'optional', 'required')),
  allowed_conditions text[] NOT NULL DEFAULT ARRAY[]::text[],
  is_active boolean NOT NULL DEFAULT true,
  sort_order integer NOT NULL DEFAULT 0 CHECK (sort_order BETWEEN 0 AND 10000),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.ilanlar (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  category_id uuid NOT NULL REFERENCES public.ilan_categories(id) ON DELETE RESTRICT,
  title text NOT NULL CHECK (char_length(btrim(title)) BETWEEN 5 AND 120),
  description text NOT NULL CHECK (char_length(btrim(description)) BETWEEN 20 AND 5000),
  price numeric(14,2) CHECK (price IS NULL OR price >= 0),
  currency text CHECK (currency IS NULL OR currency IN ('TRY', 'USD', 'EUR')),
  is_negotiable boolean NOT NULL DEFAULT false,
  item_condition text,
  city text NOT NULL DEFAULT 'Şırnak' CHECK (char_length(btrim(city)) BETWEEN 2 AND 80),
  district text NOT NULL DEFAULT 'Cizre' CHECK (char_length(btrim(district)) BETWEEN 2 AND 80),
  neighborhood text CHECK (neighborhood IS NULL OR char_length(btrim(neighborhood)) BETWEEN 2 AND 120),
  latitude double precision CHECK (latitude IS NULL OR latitude BETWEEN -90 AND 90),
  longitude double precision CHECK (longitude IS NULL OR longitude BETWEEN -180 AND 180),
  contact_phone text CHECK (contact_phone IS NULL OR contact_phone ~ '^\+?[0-9 ()-]{10,20}$'),
  contact_preference text NOT NULL DEFAULT 'app'
    CHECK (contact_preference IN ('app', 'phone', 'both')),
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('draft', 'pending', 'published', 'rejected', 'sold', 'rented', 'found', 'expired', 'archived')),
  rejection_reason text,
  cover_image_url text,
  attributes jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(attributes) = 'object'),
  view_count bigint NOT NULL DEFAULT 0 CHECK (view_count >= 0),
  favorite_count bigint NOT NULL DEFAULT 0 CHECK (favorite_count >= 0),
  published_at timestamptz,
  expires_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  moderated_at timestamptz,
  moderated_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS public.ilan_images (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ilan_id uuid NOT NULL REFERENCES public.ilanlar(id) ON DELETE CASCADE,
  owner_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  image_url text NOT NULL,
  storage_path text NOT NULL UNIQUE,
  sort_order integer NOT NULL DEFAULT 0 CHECK (sort_order BETWEEN 0 AND 100),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.ilan_favorites (
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  ilan_id uuid NOT NULL REFERENCES public.ilanlar(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, ilan_id)
);

CREATE INDEX IF NOT EXISTS ilan_categories_active_sort_idx
  ON public.ilan_categories (is_active, sort_order, name);
CREATE INDEX IF NOT EXISTS ilanlar_public_feed_idx
  ON public.ilanlar (published_at DESC, created_at DESC)
  WHERE status = 'published';
CREATE INDEX IF NOT EXISTS ilanlar_category_feed_idx
  ON public.ilanlar (category_id, published_at DESC)
  WHERE status = 'published';
CREATE INDEX IF NOT EXISTS ilanlar_owner_status_idx
  ON public.ilanlar (owner_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS ilanlar_admin_status_idx
  ON public.ilanlar (status, created_at DESC);
CREATE INDEX IF NOT EXISTS ilan_images_ilan_sort_idx
  ON public.ilan_images (ilan_id, sort_order);

-- Kategoriye göre fiyat kuralı ve yönetim ayarlarını sunucu tarafında uygular.
CREATE OR REPLACE FUNCTION public.validate_ilan_write()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_settings public.ilan_settings%ROWTYPE;
  v_pricing_mode text;
  v_allowed_conditions text[];
  v_is_admin boolean := public.ilan_is_admin();
  v_active_count integer;
BEGIN
  SELECT * INTO v_settings FROM public.ilan_settings WHERE id = 1;

  IF NOT v_is_admin THEN
    IF NOT v_settings.is_enabled THEN
      RAISE EXCEPTION 'İlan sistemi şu anda kapalı' USING ERRCODE = 'P0001';
    END IF;
    IF TG_OP = 'INSERT' AND NOT v_settings.allow_user_create THEN
      RAISE EXCEPTION 'Kullanıcı ilan paylaşımı şu anda kapalı' USING ERRCODE = '42501';
    END IF;
    IF NEW.owner_id IS DISTINCT FROM (SELECT auth.uid()) THEN
      RAISE EXCEPTION 'Başka bir kullanıcı adına ilan oluşturulamaz' USING ERRCODE = '42501';
    END IF;
  END IF;

  SELECT c.pricing_mode, c.allowed_conditions
    INTO v_pricing_mode, v_allowed_conditions
  FROM public.ilan_categories c
  WHERE c.id = NEW.category_id
    AND (c.is_active OR v_is_admin);

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Geçersiz veya pasif ilan kategorisi' USING ERRCODE = '23514';
  END IF;

  IF v_pricing_mode = 'forbidden' THEN
    NEW.price := NULL;
    NEW.currency := NULL;
    NEW.is_negotiable := false;
  ELSIF v_pricing_mode = 'required' AND (NEW.price IS NULL OR NEW.price <= 0) THEN
    RAISE EXCEPTION 'Bu kategori için sıfırdan büyük fiyat zorunludur' USING ERRCODE = '23514';
  ELSIF NEW.price IS NOT NULL THEN
    NEW.currency := COALESCE(NEW.currency, 'TRY');
  ELSE
    NEW.currency := NULL;
    NEW.is_negotiable := false;
  END IF;

  IF cardinality(v_allowed_conditions) > 0
     AND (NEW.item_condition IS NULL OR NOT (NEW.item_condition = ANY(v_allowed_conditions))) THEN
    RAISE EXCEPTION 'Bu kategori için geçersiz ürün durumu' USING ERRCODE = '23514';
  END IF;

  NEW.title := btrim(NEW.title);
  NEW.description := btrim(NEW.description);
  NEW.updated_at := now();

  IF TG_OP = 'INSERT' THEN
    IF NOT v_is_admin THEN
      SELECT count(*) INTO v_active_count
      FROM public.ilanlar i
      WHERE i.owner_id = NEW.owner_id
        AND i.status IN ('draft', 'pending', 'published');
      IF v_active_count >= v_settings.max_active_per_user THEN
        RAISE EXCEPTION 'Aktif ilan limitine ulaştınız' USING ERRCODE = 'P0001';
      END IF;
      NEW.status := CASE WHEN v_settings.require_approval THEN 'pending' ELSE 'published' END;
    END IF;
    IF NEW.status = 'published' THEN
      NEW.published_at := COALESCE(NEW.published_at, now());
      NEW.expires_at := COALESCE(NEW.expires_at, now() + make_interval(days => v_settings.default_expiry_days));
    END IF;
  ELSE
    IF NOT v_is_admin THEN
      NEW.moderated_by := OLD.moderated_by;
      NEW.moderated_at := OLD.moderated_at;
      NEW.rejection_reason := OLD.rejection_reason;
      -- Kullanıcı içerik/kategori/fiyat değiştirdiyse tekrar moderasyona gönder.
      IF ROW(NEW.category_id, NEW.title, NEW.description, NEW.price, NEW.attributes)
         IS DISTINCT FROM ROW(OLD.category_id, OLD.title, OLD.description, OLD.price, OLD.attributes) THEN
        NEW.status := CASE WHEN v_settings.require_approval THEN 'pending' ELSE 'published' END;
      ELSIF NEW.status NOT IN ('sold', 'rented', 'found', 'archived', OLD.status) THEN
        NEW.status := OLD.status;
      END IF;
    END IF;
    IF NEW.status = 'published' AND OLD.status IS DISTINCT FROM 'published' THEN
      NEW.published_at := now();
      NEW.expires_at := COALESCE(NEW.expires_at, now() + make_interval(days => v_settings.default_expiry_days));
      IF v_is_admin THEN
        NEW.moderated_by := (SELECT auth.uid());
        NEW.moderated_at := now();
      END IF;
    ELSIF v_is_admin AND NEW.status IN ('rejected', 'archived') AND NEW.status IS DISTINCT FROM OLD.status THEN
      NEW.moderated_by := (SELECT auth.uid());
      NEW.moderated_at := now();
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_ilan_write ON public.ilanlar;
CREATE TRIGGER trg_validate_ilan_write
BEFORE INSERT OR UPDATE ON public.ilanlar
FOR EACH ROW EXECUTE FUNCTION public.validate_ilan_write();

CREATE OR REPLACE FUNCTION public.validate_ilan_image_write()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_owner uuid;
  v_limit integer;
  v_count integer;
BEGIN
  SELECT owner_id INTO v_owner FROM public.ilanlar WHERE id = NEW.ilan_id;
  IF v_owner IS NULL OR (NOT public.ilan_is_admin() AND v_owner IS DISTINCT FROM (SELECT auth.uid())) THEN
    RAISE EXCEPTION 'Bu ilana görsel ekleme yetkiniz yok' USING ERRCODE = '42501';
  END IF;
  NEW.owner_id := v_owner;
  SELECT max_images_per_ilan INTO v_limit FROM public.ilan_settings WHERE id = 1;
  SELECT count(*) INTO v_count FROM public.ilan_images WHERE ilan_id = NEW.ilan_id AND id IS DISTINCT FROM NEW.id;
  IF v_count >= v_limit THEN
    RAISE EXCEPTION 'İlan görsel limitine ulaşıldı' USING ERRCODE = 'P0001';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_ilan_image_write ON public.ilan_images;
CREATE TRIGGER trg_validate_ilan_image_write
BEFORE INSERT OR UPDATE ON public.ilan_images
FOR EACH ROW EXECUTE FUNCTION public.validate_ilan_image_write();

CREATE OR REPLACE FUNCTION public.sync_ilan_favorite_count()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_ilan_id uuid;
BEGIN
  v_ilan_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.ilan_id ELSE NEW.ilan_id END;
  UPDATE public.ilanlar
  SET favorite_count = (
    SELECT count(*) FROM public.ilan_favorites f
    WHERE f.ilan_id = v_ilan_id
  )
  WHERE id = v_ilan_id;
  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_ilan_favorite_count ON public.ilan_favorites;
CREATE TRIGGER trg_sync_ilan_favorite_count
AFTER INSERT OR DELETE ON public.ilan_favorites
FOR EACH ROW EXECUTE FUNCTION public.sync_ilan_favorite_count();

CREATE OR REPLACE FUNCTION public.increment_ilan_view(p_ilan_id uuid)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  UPDATE public.ilanlar
  SET view_count = view_count + 1
  WHERE id = p_ilan_id
    AND status = 'published'
    AND (expires_at IS NULL OR expires_at > now());
$$;

REVOKE ALL ON FUNCTION public.increment_ilan_view(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.increment_ilan_view(uuid) TO anon, authenticated;

ALTER TABLE public.ilan_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ilan_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ilanlar ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ilan_images ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ilan_favorites ENABLE ROW LEVEL SECURITY;

CREATE POLICY ilan_settings_read ON public.ilan_settings
FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY ilan_settings_admin_write ON public.ilan_settings
FOR ALL TO authenticated USING ((SELECT public.ilan_is_admin()))
WITH CHECK ((SELECT public.ilan_is_admin()));

CREATE POLICY ilan_categories_public_read ON public.ilan_categories
FOR SELECT TO anon, authenticated
USING (is_active OR (SELECT public.ilan_is_admin()));
CREATE POLICY ilan_categories_admin_write ON public.ilan_categories
FOR ALL TO authenticated USING ((SELECT public.ilan_is_admin()))
WITH CHECK ((SELECT public.ilan_is_admin()));

CREATE POLICY ilanlar_public_read ON public.ilanlar
FOR SELECT TO anon, authenticated
USING (
  status = 'published'
  AND (expires_at IS NULL OR expires_at > now())
  AND EXISTS (
    SELECT 1 FROM public.ilan_settings s
    WHERE s.id = 1 AND s.is_enabled AND (s.allow_guest_view OR (SELECT auth.uid()) IS NOT NULL)
  )
);
CREATE POLICY ilanlar_owner_admin_read ON public.ilanlar
FOR SELECT TO authenticated
USING (owner_id = (SELECT auth.uid()) OR (SELECT public.ilan_is_admin()));
CREATE POLICY ilanlar_owner_admin_insert ON public.ilanlar
FOR INSERT TO authenticated
WITH CHECK (owner_id = (SELECT auth.uid()) OR (SELECT public.ilan_is_admin()));
CREATE POLICY ilanlar_owner_admin_update ON public.ilanlar
FOR UPDATE TO authenticated
USING (owner_id = (SELECT auth.uid()) OR (SELECT public.ilan_is_admin()))
WITH CHECK (owner_id = (SELECT auth.uid()) OR (SELECT public.ilan_is_admin()));
CREATE POLICY ilanlar_owner_admin_delete ON public.ilanlar
FOR DELETE TO authenticated
USING (owner_id = (SELECT auth.uid()) OR (SELECT public.ilan_is_admin()));

CREATE POLICY ilan_images_public_read ON public.ilan_images
FOR SELECT TO anon, authenticated
USING (EXISTS (
  SELECT 1 FROM public.ilanlar i
  WHERE i.id = ilan_id
    AND (i.status = 'published' OR i.owner_id = (SELECT auth.uid()) OR (SELECT public.ilan_is_admin()))
));
CREATE POLICY ilan_images_owner_admin_insert ON public.ilan_images
FOR INSERT TO authenticated
WITH CHECK (owner_id = (SELECT auth.uid()) OR (SELECT public.ilan_is_admin()));
CREATE POLICY ilan_images_owner_admin_update ON public.ilan_images
FOR UPDATE TO authenticated
USING (owner_id = (SELECT auth.uid()) OR (SELECT public.ilan_is_admin()))
WITH CHECK (owner_id = (SELECT auth.uid()) OR (SELECT public.ilan_is_admin()));
CREATE POLICY ilan_images_owner_admin_delete ON public.ilan_images
FOR DELETE TO authenticated
USING (owner_id = (SELECT auth.uid()) OR (SELECT public.ilan_is_admin()));

CREATE POLICY ilan_favorites_own_read ON public.ilan_favorites
FOR SELECT TO authenticated USING (user_id = (SELECT auth.uid()));
CREATE POLICY ilan_favorites_own_insert ON public.ilan_favorites
FOR INSERT TO authenticated WITH CHECK (user_id = (SELECT auth.uid()));
CREATE POLICY ilan_favorites_own_delete ON public.ilan_favorites
FOR DELETE TO authenticated USING (user_id = (SELECT auth.uid()));

-- Seed: kayıp ilanlarında fiyat DB seviyesinde her zaman temizlenir.
INSERT INTO public.ilan_categories
  (name, slug, description, icon_name, color_hex, category_type, pricing_mode, allowed_conditions, sort_order)
VALUES
  ('Kayıp İlanları', 'kayip-ilanlari', 'Kayıp eşya, evcil hayvan ve bulunan eşyalar', 'travel_explore', '#DC2626', 'lost', 'forbidden', ARRAY[]::text[], 10),
  ('Satılık İlanlar', 'satilik-ilanlar', 'İkinci el ve sıfır satılık ürünler', 'sell', '#059669', 'sale', 'required', ARRAY['Sıfır', 'Yeni Gibi', 'İyi', 'Kullanılmış']::text[], 20),
  ('Kiralık İlanlar', 'kiralik-ilanlar', 'Ev, iş yeri, araç ve eşya kiralama ilanları', 'key', '#2563EB', 'rent', 'required', ARRAY['Sıfır', 'Yeni Gibi', 'İyi', 'Kullanılmış']::text[], 30),
  ('Hizmet İlanları', 'hizmet-ilanlari', 'Yerel hizmet ve usta ilanları', 'handyman', '#7C3AED', 'service', 'optional', ARRAY[]::text[], 40)
ON CONFLICT (slug) DO NOTHING;

-- Herkese açık görseller; yazma işlemleri yalnız kullanıcının kendi UUID klasöründe.
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'ilan-images',
  'ilan-images',
  true,
  10485760,
  ARRAY['image/jpeg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO UPDATE SET
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

DROP POLICY IF EXISTS ilan_storage_public_read ON storage.objects;
CREATE POLICY ilan_storage_public_read ON storage.objects
FOR SELECT TO public USING (bucket_id = 'ilan-images');
DROP POLICY IF EXISTS ilan_storage_owner_insert ON storage.objects;
CREATE POLICY ilan_storage_owner_insert ON storage.objects
FOR INSERT TO authenticated WITH CHECK (
  bucket_id = 'ilan-images'
  AND (storage.foldername(name))[1] = (SELECT auth.uid())::text
);
DROP POLICY IF EXISTS ilan_storage_owner_update ON storage.objects;
CREATE POLICY ilan_storage_owner_update ON storage.objects
FOR UPDATE TO authenticated
USING (
  bucket_id = 'ilan-images'
  AND ((storage.foldername(name))[1] = (SELECT auth.uid())::text OR (SELECT public.ilan_is_admin()))
)
WITH CHECK (
  bucket_id = 'ilan-images'
  AND ((storage.foldername(name))[1] = (SELECT auth.uid())::text OR (SELECT public.ilan_is_admin()))
);
DROP POLICY IF EXISTS ilan_storage_owner_delete ON storage.objects;
CREATE POLICY ilan_storage_owner_delete ON storage.objects
FOR DELETE TO authenticated USING (
  bucket_id = 'ilan-images'
  AND ((storage.foldername(name))[1] = (SELECT auth.uid())::text OR (SELECT public.ilan_is_admin()))
);

GRANT SELECT ON public.ilan_settings, public.ilan_categories, public.ilanlar, public.ilan_images TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.ilanlar, public.ilan_images, public.ilan_favorites TO authenticated;
GRANT SELECT ON public.ilan_favorites TO authenticated;
GRANT INSERT, UPDATE, DELETE ON public.ilan_settings, public.ilan_categories TO authenticated;

COMMENT ON TABLE public.ilanlar IS 'Kayıp, satılık, kiralık ve hizmet ilanlarının ana tablosu.';
COMMENT ON COLUMN public.ilan_categories.pricing_mode IS 'forbidden: fiyat silinir, optional: isteğe bağlı, required: pozitif fiyat zorunlu.';
COMMENT ON TABLE public.ilan_settings IS 'Tek satırlı (id=1) ilan modülü çalışma ve paylaşım ayarları.';

COMMIT;
