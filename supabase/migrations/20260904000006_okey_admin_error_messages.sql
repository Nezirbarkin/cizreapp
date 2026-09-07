-- =============================================================================
-- 101 Okey — ADMIN PANELİ HATA MESAJLARI VE ŞARKI ADLARI
-- -----------------------------------------------------------------------------
-- İki ayrı sorun, ikisi de adminin panelde gördüğü metinle ilgili.
--
-- 1) BOT ADI ÇAKIŞMASI HAM POSTGRES HATASI OLARAK ÇIKIYORDU
--    `uq_okey_bot_profiles_name` (lower(trim(display_name)) üzerinde UNIQUE)
--    zaten vardı ama upsert onu yakalamıyordu. Aynı adı ikinci kez kaydeden
--    admin ekranda şunu görüyordu:
--      PostgrestException(message: duplicate key value violates unique
--      constraint "uq_okey_bot_profiles_name", code: 23505, ...)
--    Panel bu metni olduğu gibi basıyor; admin ne yapacağını anlayamıyordu.
--    Diğer hatalar gibi `APP:name_taken` verilir, istemci Türkçeye çevirir.
--
--    Bu senaryo pratikte SANILDIĞINDAN SIK: profil kaydedilip fotoğraf
--    yüklemesi başarısız olduğunda liste tazelenmiyordu, admin kaydın
--    oluşmadığını sanıp aynı adla tekrar deniyor ve bu hatayı alıyordu.
--
-- 2) ŞARKI ADLARINDA DOSYA UZANTISI KALIYORDU
--    `display_name` yüklenen dosyanın adının ta kendisiydi; oyuncunun
--    bildirim panelinde gördüğü metin
--      "Rojda - Ezim Ezim _Official Music_(_9dIWJhizr4o_).m4a"
--    şeklindeydi. Uzantı sunucuda kırpılır — hem yeni yüklemelerde hem de
--    hâlihazırdaki kayıtlarda.
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '5s';

-- -----------------------------------------------------------------------------
-- 1) Bot profili upsert — ad çakışmasını anlaşılır koda çevir
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_okey_upsert_bot_profile(
  p_id uuid,
  p_display_name text,
  p_avatar_url text DEFAULT NULL,
  p_is_active boolean DEFAULT true
)
RETURNS public.okey_bot_profiles
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_row public.okey_bot_profiles%ROWTYPE;
  v_url text := NULLIF(trim(COALESCE(p_avatar_url, '')), '');
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'APP:forbidden' USING ERRCODE = '42501';
  END IF;
  IF NULLIF(trim(COALESCE(p_display_name, '')), '') IS NULL THEN
    RAISE EXCEPTION 'APP:name_required' USING ERRCODE = '22023';
  END IF;

  BEGIN
    IF p_id IS NULL THEN
      INSERT INTO public.okey_bot_profiles (display_name, avatar_url, is_active)
      VALUES (trim(p_display_name), v_url, COALESCE(p_is_active, true))
      RETURNING * INTO v_row;
    ELSE
      UPDATE public.okey_bot_profiles AS b
      SET display_name = trim(p_display_name),
          avatar_url = v_url,
          -- URL değiştiyse (ya da silindiyse) elimizdeki dosya yolu artık
          -- geçersizdir; yükleme akışı yolu kendi RPC'siyle yeniden yazar.
          avatar_path = CASE
            WHEN v_url IS DISTINCT FROM b.avatar_url THEN NULL
            ELSE b.avatar_path
          END,
          is_active = COALESCE(p_is_active, true)
      WHERE b.id = p_id
      RETURNING * INTO v_row;

      IF v_row.id IS NULL THEN
        RAISE EXCEPTION 'APP:not_found' USING ERRCODE = 'P0001';
      END IF;
    END IF;
  EXCEPTION
    WHEN unique_violation THEN
      -- Tek benzersizlik kuralı ad üzerinde; başka bir çakışma olamaz.
      RAISE EXCEPTION 'APP:name_taken' USING ERRCODE = '23505';
  END;

  RETURN v_row;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_okey_upsert_bot_profile(uuid, text, text, boolean)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_okey_upsert_bot_profile(uuid, text, text, boolean)
  TO authenticated;

-- -----------------------------------------------------------------------------
-- 2) Şarkı adından dosya uzantısını kırp
-- -----------------------------------------------------------------------------
--
-- IMMUTABLE değil çünkü yalnız metin işliyor ama şart da değil; tek
-- kullanıcısı aşağıdaki iki yer.
CREATE OR REPLACE FUNCTION public.okey_internal_strip_extension(p_name text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$
  SELECT NULLIF(
    trim(regexp_replace(COALESCE(p_name, ''),
                        '\.(mp3|m4a|wav|ogg|aac|mp4|webm)$', '', 'i')),
    '');
$$;
REVOKE ALL ON FUNCTION public.okey_internal_strip_extension(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_internal_strip_extension(text) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_okey_add_music(
  p_storage_path text,
  p_public_url text,
  p_display_name text
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_key text;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'APP:forbidden' USING ERRCODE = '42501';
  END IF;
  IF NULLIF(trim(COALESCE(p_public_url, '')), '') IS NULL THEN
    RAISE EXCEPTION 'APP:invalid_value' USING ERRCODE = '22023';
  END IF;

  v_key := 'music:' || gen_random_uuid()::text;

  INSERT INTO public.okey_sound_assets
    (sound_key, storage_path, public_url, display_name)
  VALUES (
    v_key, p_storage_path, p_public_url,
    public.okey_internal_strip_extension(p_display_name)
  );

  RETURN v_key;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_okey_add_music(text, text, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_okey_add_music(text, text, text)
  TO authenticated;

-- Hâlihazırdaki kayıtlar: yalnızca sondaki uzantı kırpılır, adın geri
-- kalanına dokunulmaz.
UPDATE public.okey_sound_assets
SET display_name = public.okey_internal_strip_extension(display_name)
WHERE sound_key LIKE 'music:%'
  AND display_name IS NOT NULL
  AND display_name ~* '\.(mp3|m4a|wav|ogg|aac|mp4|webm)$';

NOTIFY pgrst, 'reload schema';
