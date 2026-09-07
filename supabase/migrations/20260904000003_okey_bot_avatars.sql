-- =============================================================================
-- 101 Okey — BOT PROFİLİ FOTOĞRAF YÜKLEME
-- -----------------------------------------------------------------------------
-- Bot profillerinin avatarı şimdiye kadar yalnızca elle yapıştırılan bir URL
-- olarak tutulabiliyordu. Pratikte bu, adminin görseli başka bir yere yükleyip
-- bağlantısını kopyalaması demekti; kimse yapmadığı için bütün botlar masada
-- ikonla görünüyordu — yani "bu bir bot" diye kendini ilan ediyordu.
--
-- Burada masa arka planı (20260903000008) ve ses (20260831000003) akışlarıyla
-- BİREBİR AYNI desen kurulur:
--   * herkese açık okunabilen, yalnız adminin yazabildiği bir storage bucket
--   * profilde dosyanın YOLUNU tutan bir sütun (eski dosyayı silebilmek için)
--   * yalnız adminin çağırabildiği SECURITY DEFINER RPC'ler
--
-- avatar_url ZATEN VARDI ve KORUNUR: dışarıdan bir bağlantı yapıştırmak hâlâ
-- mümkün. Yeni avatar_path yalnızca "bu dosyayı biz yükledik, değişince
-- eskisini silelim" bilgisini taşır.
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '5s';

-- -----------------------------------------------------------------------------
-- 1) Storage bucket
-- -----------------------------------------------------------------------------
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'okey-bot-avatars',
  'okey-bot-avatars',
  true,
  -- 2 MB: avatar masada en fazla ~90px çizilir, daha büyüğü boşuna trafik.
  2097152,
  ARRAY['image/jpeg', 'image/png', 'image/webp']::text[]
)
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "okey_bot_avatars_public_read" ON storage.objects;
CREATE POLICY "okey_bot_avatars_public_read" ON storage.objects
  FOR SELECT TO public USING (bucket_id = 'okey-bot-avatars');

DROP POLICY IF EXISTS "okey_bot_avatars_admin_write" ON storage.objects;
CREATE POLICY "okey_bot_avatars_admin_write" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'okey-bot-avatars' AND public.is_admin());

DROP POLICY IF EXISTS "okey_bot_avatars_admin_update" ON storage.objects;
CREATE POLICY "okey_bot_avatars_admin_update" ON storage.objects
  FOR UPDATE TO authenticated
  USING (bucket_id = 'okey-bot-avatars' AND public.is_admin());

DROP POLICY IF EXISTS "okey_bot_avatars_admin_delete" ON storage.objects;
CREATE POLICY "okey_bot_avatars_admin_delete" ON storage.objects
  FOR DELETE TO authenticated
  USING (bucket_id = 'okey-bot-avatars' AND public.is_admin());

-- -----------------------------------------------------------------------------
-- 2) Yüklenen dosyanın yolu
-- -----------------------------------------------------------------------------
ALTER TABLE public.okey_bot_profiles
  ADD COLUMN IF NOT EXISTS avatar_path text;

COMMENT ON COLUMN public.okey_bot_profiles.avatar_path IS
  'okey-bot-avatars bucket''ındaki dosya yolu. NULL ise avatar_url dışarıdan yapıştırılmış bir bağlantıdır (ya da avatar yoktur) ve değişince silinecek bir dosyamız yoktur.';

-- -----------------------------------------------------------------------------
-- 3) RPC'ler
-- -----------------------------------------------------------------------------
--
-- İkisi de ESKİ YOLU döndürür: istemci kaydı güncelledikten SONRA eski dosyayı
-- siler. Sıra bilerek böyle — önce silip sonra kaydı güncelleseydik, arada
-- kalan bir hata profili var olmayan bir dosyaya bağlı bırakırdı.
CREATE OR REPLACE FUNCTION public.admin_okey_set_bot_avatar(
  p_id uuid,
  p_storage_path text,
  p_public_url text
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_previous text;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'APP:forbidden' USING ERRCODE = '42501';
  END IF;
  IF NULLIF(trim(COALESCE(p_storage_path, '')), '') IS NULL
     OR NULLIF(trim(COALESCE(p_public_url, '')), '') IS NULL THEN
    RAISE EXCEPTION 'APP:path_required' USING ERRCODE = '22023';
  END IF;

  SELECT b.avatar_path INTO v_previous
  FROM public.okey_bot_profiles AS b WHERE b.id = p_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'APP:not_found' USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.okey_bot_profiles
  SET avatar_path = p_storage_path,
      avatar_url = p_public_url
  WHERE id = p_id;

  RETURN v_previous;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_okey_set_bot_avatar(uuid, text, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_okey_set_bot_avatar(uuid, text, text)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_okey_clear_bot_avatar(p_id uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_previous text;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'APP:forbidden' USING ERRCODE = '42501';
  END IF;

  SELECT b.avatar_path INTO v_previous
  FROM public.okey_bot_profiles AS b WHERE b.id = p_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'APP:not_found' USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.okey_bot_profiles
  SET avatar_path = NULL, avatar_url = NULL
  WHERE id = p_id;

  RETURN v_previous;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_okey_clear_bot_avatar(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_okey_clear_bot_avatar(uuid) TO authenticated;

-- -----------------------------------------------------------------------------
-- 4) upsert: avatar_path'i EZMESİN
-- -----------------------------------------------------------------------------
--
-- Eski upsert yalnızca avatar_url yazıyordu. Admin yüklenmiş bir avatarı olan
-- profilin ADINI değiştirdiğinde, formdaki (dolu) URL alanı aynen geri
-- yazılıyor ama yol bilgisi ilgisiz kalıyordu. Artık URL gerçekten
-- değiştiğinde yol da temizlenir: dosya artık o URL'e ait değildir.
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

  RETURN v_row;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_okey_upsert_bot_profile(uuid, text, text, boolean)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_okey_upsert_bot_profile(uuid, text, text, boolean)
  TO authenticated;

NOTIFY pgrst, 'reload schema';
