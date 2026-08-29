-- lib/features/courier/screens/courier_panel_screen.dart içindeki "Ayarlar"
-- diyalogu (Ad Soyad + Telefon düzenleme) doğrudan `profiles` tablosuna
-- raw .update({'full_name':..., 'phone':...}) çağrısı yapıyordu. 20260803000006
-- migration'ı authenticated rolünden profiles tablosu üzerindeki UPDATE
-- yetkisini tamamen kaldırdığı için bu yazım her zaman 42501 (permission
-- denied) ile sessizce başarısız oluyordu.
--
-- update_my_public_profile RPC'si full_name'i zaten destekliyor ama phone
-- eksik. Fonksiyon arity'si değiştiği için (8 -> 9 parametre) önce eski
-- imzayı DROP ediyoruz; aksi halde CREATE OR REPLACE aynı isimde ayrı bir
-- overload yaratır ve PostgREST var olan çağrılarda (yalnız bir kısım p_*
-- isimlendirilmiş parametre gönderen) "birden fazla aday fonksiyon" hatası
-- (PGRST203) verir.
begin;

DROP FUNCTION IF EXISTS public.update_my_public_profile(
  text, text, text, text, text, text, text, text
);

CREATE FUNCTION public.update_my_public_profile(
  p_full_name text DEFAULT NULL,
  p_username text DEFAULT NULL,
  p_bio text DEFAULT NULL,
  p_website text DEFAULT NULL,
  p_location text DEFAULT NULL,
  p_gender text DEFAULT NULL,
  p_avatar_url text DEFAULT NULL,
  p_cover_url text DEFAULT NULL,
  p_phone text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'update_my_public_profile: not authenticated'
      USING ERRCODE = '28000';
  END IF;

  -- username uzunluk / karakter doğrulaması (sadece 3-32, a-z0-9_.)
  IF p_username IS NOT NULL AND p_username <> '' THEN
    IF p_username !~ '^[a-z0-9_.]{3,32}$' THEN
      RAISE EXCEPTION 'update_my_public_profile: invalid username'
        USING ERRCODE = '22023';
    END IF;
  END IF;

  -- updated_at hariç server kontrollü sütunlara dokunmadan UPDATE.
  UPDATE public.profiles
    SET
      full_name = COALESCE(p_full_name, full_name),
      username  = CASE WHEN p_username IS NULL OR p_username = '' THEN username
                       ELSE LOWER(p_username) END,
      bio       = COALESCE(p_bio, bio),
      website   = COALESCE(p_website, website),
      location  = COALESCE(p_location, location),
      gender    = COALESCE(p_gender, gender),
      avatar_url = COALESCE(p_avatar_url, avatar_url),
      cover_url  = COALESCE(p_cover_url, cover_url),
      phone      = COALESCE(p_phone, phone),
      updated_at = NOW()
  WHERE id = v_uid;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'update_my_public_profile: profile not found'
      USING ERRCODE = 'P0002';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.update_my_public_profile(
  text, text, text, text, text, text, text, text, text
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.update_my_public_profile(
  text, text, text, text, text, text, text, text, text
) TO authenticated, service_role;

commit;
