-- =============================================================================
-- Kurye evrak sistemine selfie video ekleniyor
--
-- Kurye, motorunu/plakasini kendi yuzuyle birlikte gosteren kisa bir video
-- yukler (kimlik dogrulama amacli - salt fotograftan daha guvenilir).
-- Video da diger evraklar gibi 'courier-documents' private bucket'ta
-- kuryenin auth.uid() klasorunde tutulur ve admin onayina tabidir.
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '5s';

-- -----------------------------------------------------------------------------
-- 1) Tabloya kolon ekle
-- -----------------------------------------------------------------------------
ALTER TABLE public.courier_documents
  ADD COLUMN IF NOT EXISTS selfie_video_path text;

-- -----------------------------------------------------------------------------
-- 2) submit_courier_documents: p_selfie_video_path parametresi eklendi
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.submit_courier_documents(
  text, text, text, text, text, text, text
);

CREATE OR REPLACE FUNCTION public.submit_courier_documents(
  p_full_name text,
  p_phone text,
  p_id_front_path text,
  p_id_back_path text,
  p_license_photo_path text,
  p_vehicle_photo_path text,
  p_plate_number text,
  p_selfie_video_path text DEFAULT NULL
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
    plate_number, selfie_video_path, status, admin_note, reviewed_by, reviewed_at, submitted_at
  ) VALUES (
    v_uid, pg_catalog.btrim(p_full_name), pg_catalog.btrim(p_phone),
    p_id_front_path, p_id_back_path, p_license_photo_path, p_vehicle_photo_path,
    pg_catalog.btrim(p_plate_number), p_selfie_video_path, 'pending', NULL, NULL, NULL, pg_catalog.now()
  )
  ON CONFLICT (courier_id) DO UPDATE SET
    full_name = EXCLUDED.full_name,
    phone = EXCLUDED.phone,
    id_front_path = COALESCE(EXCLUDED.id_front_path, public.courier_documents.id_front_path),
    id_back_path = COALESCE(EXCLUDED.id_back_path, public.courier_documents.id_back_path),
    license_photo_path = COALESCE(EXCLUDED.license_photo_path, public.courier_documents.license_photo_path),
    vehicle_photo_path = COALESCE(EXCLUDED.vehicle_photo_path, public.courier_documents.vehicle_photo_path),
    plate_number = EXCLUDED.plate_number,
    selfie_video_path = COALESCE(EXCLUDED.selfie_video_path, public.courier_documents.selfie_video_path),
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
  text, text, text, text, text, text, text, text
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_courier_documents(
  text, text, text, text, text, text, text, text
) TO authenticated;

-- -----------------------------------------------------------------------------
-- 3) Storage bucket: video mime tiplerine izin ver, boyut limitini yukselt
--    (selfie videosu icin - 8MB fotograf limiti video icin yetersiz)
-- -----------------------------------------------------------------------------
UPDATE storage.buckets
SET
  file_size_limit = 52428800, -- 50MB
  allowed_mime_types = ARRAY[
    'image/jpeg', 'image/jpg', 'image/png', 'image/webp',
    'video/mp4', 'video/quicktime', 'video/webm', 'video/3gpp'
  ]::text[]
WHERE id = 'courier-documents';

NOTIFY pgrst, 'reload schema';
