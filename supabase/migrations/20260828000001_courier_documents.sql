-- =============================================================================
-- Kurye evrak/belge sistemi
--
-- Kurye panelinde kurye kendi kimlik/ehliyet/arac bilgilerini ve fotograflarini
-- (ad soyad, telefon, kimlik on/arka, ehliyet fotografi, motor fotografi, plaka)
-- girebilir. Admin panelinde "Kurye Yonetimi" bolumunden bu evraklar goruntulenip
-- onaylanabilir/reddedilebilir.
--
-- Yazma islemleri istemciden dogrudan tabloya degil, SECURITY DEFINER RPC'ler
-- uzerinden yapilir (courier_payout_items ile ayni desen): kurye kendi durumunu
-- ('approved' gibi) elle set edemesin diye submit RPC'si her zaman status'u
-- 'pending'e dondurur; onay/red yalniz admin RPC'sinden gecer.
--
-- Fotograflar 'courier-documents' adinda PRIVATE bir storage bucket'ta,
-- kuryenin kendi auth.uid()'i altindaki klasorde tutulur. Goruntuleme icin
-- istemci signed URL uretir (public URL yok - kimlik fotografi hassas veridir).
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '5s';

-- -----------------------------------------------------------------------------
-- 1) Tablo
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.courier_documents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  courier_id uuid NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name text,
  phone text,
  id_front_path text,
  id_back_path text,
  license_photo_path text,
  vehicle_photo_path text,
  plate_number text,
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'approved', 'rejected')),
  admin_note text,
  reviewed_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  reviewed_at timestamptz,
  submitted_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_courier_documents_status
  ON public.courier_documents (status);

ALTER TABLE public.courier_documents ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "courier_documents_select_own_or_admin"
  ON public.courier_documents;

CREATE POLICY "courier_documents_select_own_or_admin"
  ON public.courier_documents
  FOR SELECT
  TO authenticated
  USING (
    courier_id = (SELECT auth.uid())
    OR public.is_admin()
  );

-- Yazma yalniz SECURITY DEFINER RPC'ler uzerinden yapilir; kurye istemcisi
-- status/admin_note gibi alanlari dogrudan degistiremesin.
REVOKE ALL ON TABLE public.courier_documents FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.courier_documents TO authenticated;
GRANT ALL ON TABLE public.courier_documents TO service_role;

COMMENT ON TABLE public.courier_documents IS
  'Kurye kimlik/ehliyet/arac evraklari. Yazma yalniz submit_courier_documents '
  've admin_review_courier_document RPC''leri uzerinden yapilir.';

-- -----------------------------------------------------------------------------
-- 2) updated_at trigger
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.set_courier_documents_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  NEW.updated_at := pg_catalog.now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_courier_documents_updated_at
  ON public.courier_documents;

CREATE TRIGGER trg_courier_documents_updated_at
  BEFORE UPDATE ON public.courier_documents
  FOR EACH ROW
  EXECUTE FUNCTION public.set_courier_documents_updated_at();

-- -----------------------------------------------------------------------------
-- 3) submit_courier_documents: kurye kendi evragini gonderir/gunceller
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.submit_courier_documents(
  p_full_name text,
  p_phone text,
  p_id_front_path text,
  p_id_back_path text,
  p_license_photo_path text,
  p_vehicle_photo_path text,
  p_plate_number text
)
RETURNS public.courier_documents
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid CONSTANT uuid := (SELECT auth.uid());
  v_row public.courier_documents%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'APP:auth_required' USING ERRCODE = '42501';
  END IF;

  IF NOT public.is_courier_role() THEN
    RAISE EXCEPTION 'APP:forbidden' USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.courier_documents (
    courier_id, full_name, phone,
    id_front_path, id_back_path, license_photo_path, vehicle_photo_path,
    plate_number, status, admin_note, reviewed_by, reviewed_at, submitted_at
  ) VALUES (
    v_uid, pg_catalog.btrim(p_full_name), pg_catalog.btrim(p_phone),
    p_id_front_path, p_id_back_path, p_license_photo_path, p_vehicle_photo_path,
    pg_catalog.btrim(p_plate_number), 'pending', NULL, NULL, NULL, pg_catalog.now()
  )
  ON CONFLICT (courier_id) DO UPDATE SET
    full_name = EXCLUDED.full_name,
    phone = EXCLUDED.phone,
    id_front_path = COALESCE(EXCLUDED.id_front_path, public.courier_documents.id_front_path),
    id_back_path = COALESCE(EXCLUDED.id_back_path, public.courier_documents.id_back_path),
    license_photo_path = COALESCE(EXCLUDED.license_photo_path, public.courier_documents.license_photo_path),
    vehicle_photo_path = COALESCE(EXCLUDED.vehicle_photo_path, public.courier_documents.vehicle_photo_path),
    plate_number = EXCLUDED.plate_number,
    -- Her yeniden gonderim, onceki onay/red durumunu sifirlar; admin yeniden
    -- degerlendirmelidir.
    status = 'pending',
    admin_note = NULL,
    reviewed_by = NULL,
    reviewed_at = NULL,
    submitted_at = pg_catalog.now()
  RETURNING * INTO v_row;

  INSERT INTO public.notifications (
    user_id, type, title, content, metadata, is_read
  )
  SELECT
    p.id,
    'courier_document_submitted',
    'Kurye evragi incelemede',
    'Bir kurye kimlik/ehliyet evraklarini gonderdi, incelemeniz gerekiyor.',
    pg_catalog.jsonb_build_object('courier_id', v_uid),
    false
  FROM public.profiles AS p
  WHERE p.role::text = 'admin';

  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION public.submit_courier_documents(
  text, text, text, text, text, text, text
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_courier_documents(
  text, text, text, text, text, text, text
) TO authenticated;

-- -----------------------------------------------------------------------------
-- 4) admin_review_courier_document: admin onaylar/reddeder
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_review_courier_document(
  p_courier_id uuid,
  p_status text,
  p_note text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_admin CONSTANT uuid := (SELECT auth.uid());
  v_title text;
  v_content text;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'APP:forbidden | admin gerekli' USING ERRCODE = '42501';
  END IF;

  IF p_status NOT IN ('approved', 'rejected') THEN
    RAISE EXCEPTION 'APP:invalid_status' USING ERRCODE = '22023';
  END IF;

  UPDATE public.courier_documents AS cd
     SET status = p_status,
         admin_note = p_note,
         reviewed_by = v_admin,
         reviewed_at = pg_catalog.now()
   WHERE cd.courier_id = p_courier_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'APP:not_found' USING ERRCODE = 'P0001';
  END IF;

  IF p_status = 'approved' THEN
    v_title := 'Evraklarınız onaylandı';
    v_content := 'Kimlik/ehliyet evraklarınız admin tarafından onaylandı.';
  ELSE
    v_title := 'Evraklarınız reddedildi';
    v_content := 'Gerekçe: ' || COALESCE(p_note, '-');
  END IF;

  INSERT INTO public.notifications (
    user_id, type, title, content, metadata, is_read
  )
  VALUES (
    p_courier_id,
    'courier_document_' || p_status,
    v_title,
    v_content,
    pg_catalog.jsonb_build_object('status', p_status, 'note', p_note),
    false
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_review_courier_document(uuid, text, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_review_courier_document(uuid, text, text)
  TO authenticated;

-- -----------------------------------------------------------------------------
-- 5) Storage bucket: courier-documents (PRIVATE - kimlik fotografi hassas veri)
-- -----------------------------------------------------------------------------
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'courier-documents',
  'courier-documents',
  false,
  8388608, -- 8MB
  ARRAY['image/jpeg', 'image/jpg', 'image/png', 'image/webp']::text[]
)
ON CONFLICT (id) DO UPDATE SET
  public = false,
  file_size_limit = 8388608,
  allowed_mime_types = ARRAY['image/jpeg', 'image/jpg', 'image/png', 'image/webp']::text[];

DROP POLICY IF EXISTS "courier_documents_storage_select" ON storage.objects;
DROP POLICY IF EXISTS "courier_documents_storage_insert" ON storage.objects;
DROP POLICY IF EXISTS "courier_documents_storage_update" ON storage.objects;
DROP POLICY IF EXISTS "courier_documents_storage_delete" ON storage.objects;

-- Kurye kendi klasorunu (courier-documents/<auth.uid()>/...) okuyabilir; admin
-- tum klasorleri okuyabilir (inceleme icin).
CREATE POLICY "courier_documents_storage_select"
ON storage.objects FOR SELECT
TO authenticated
USING (
  bucket_id = 'courier-documents'
  AND (
    (storage.foldername(name))[1] = (SELECT auth.uid())::text
    OR public.is_admin()
  )
);

CREATE POLICY "courier_documents_storage_insert"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'courier-documents'
  AND (storage.foldername(name))[1] = (SELECT auth.uid())::text
);

CREATE POLICY "courier_documents_storage_update"
ON storage.objects FOR UPDATE
TO authenticated
USING (
  bucket_id = 'courier-documents'
  AND (storage.foldername(name))[1] = (SELECT auth.uid())::text
);

CREATE POLICY "courier_documents_storage_delete"
ON storage.objects FOR DELETE
TO authenticated
USING (
  bucket_id = 'courier-documents'
  AND (storage.foldername(name))[1] = (SELECT auth.uid())::text
);

NOTIFY pgrst, 'reload schema';
