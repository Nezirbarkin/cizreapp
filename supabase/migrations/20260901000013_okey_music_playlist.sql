-- =============================================================================
-- 101 Okey Plus — ÇOKLU ŞARKI (çalma listesi)
-- -----------------------------------------------------------------------------
-- Arka plan müziği tek bir dosyaydı (`background_music` anahtarı). Artık
-- admin birden çok şarkı yükleyebilir; oyun bunları sırayla/karışık çalar.
--
-- TASARIM: Şarkılar ses efektleriyle AYNI tabloda tutulur ama anahtarları
-- `music:<uuid>` biçimindedir. Böylece mevcut yükleme/silme altyapısı ve
-- depo politikaları aynen kullanılır; ayrı bir tablo ve ayrı RLS gerekmez.
-- Eski tek şarkı (`background_music`) da geçerli kalır — geriye dönük uyumlu.
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '10s';

-- -----------------------------------------------------------------------------
-- Şarkıya insan-okunur bir ad verebilmek için
-- -----------------------------------------------------------------------------
ALTER TABLE public.okey_sound_assets
  ADD COLUMN IF NOT EXISTS display_name text;

COMMENT ON COLUMN public.okey_sound_assets.display_name IS
  'Çalma listesindeki şarkının görünen adı (yalnızca müzik anahtarları için).';

-- -----------------------------------------------------------------------------
-- admin_okey_add_music: çalma listesine YENİ şarkı ekler
--
-- Her çağrı yeni bir anahtar üretir; şarkılar birbirinin üzerine yazmaz.
-- -----------------------------------------------------------------------------
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
    NULLIF(trim(COALESCE(p_display_name, '')), '')
  );

  RETURN v_key;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_okey_add_music(text, text, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_okey_add_music(text, text, text)
  TO authenticated;

-- -----------------------------------------------------------------------------
-- okey_list_music: oyuncunun çalacağı şarkılar
--
-- Herkes okuyabilir (müzik gizli bilgi değil). Eski tek şarkı da listeye
-- dahil edilir, böylece daha önce yüklenmiş müzik çalmaya devam eder.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.okey_list_music()
RETURNS TABLE(sound_key text, public_url text, display_name text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT a.sound_key, a.public_url, a.display_name
  FROM public.okey_sound_assets AS a
  WHERE a.sound_key LIKE 'music:%'
     OR a.sound_key = 'background_music'
  ORDER BY a.display_name NULLS LAST, a.sound_key;
$$;
REVOKE ALL ON FUNCTION public.okey_list_music() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_list_music() TO authenticated;

NOTIFY pgrst, 'reload schema';
