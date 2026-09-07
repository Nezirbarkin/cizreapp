-- =============================================================================
-- 101 Okey Plus — MASA ARKA PLANI (admin fotoğraf yükleme)
-- -----------------------------------------------------------------------------
-- Masanın arkasındaki "oda" şu ana kadar tamamen VEKTÖRELDİ (sıcak bir
-- gradyan + iki ışık lekesi), çünkü elimizde görsel varlık yoktu. Kullanıcı
-- gerçek bir 3D/fotoğraf ortam istedi ve fotoğrafı admin panelinden
-- yükleyebilmeyi önerdi — bu migration o altyapıyı kurar.
--
-- Desen okey-sounds ile BİREBİR AYNI (bkz. 20260831000003):
--   * herkese açık okunabilen bir storage bucket
--   * hangi görselin nereye bağlı olduğunu tutan küçük bir tablo
--   * yalnız adminin yazabildiği SECURITY DEFINER RPC'ler
--
-- asset_key şimdilik tek değer taşır ('room_backdrop') ama tablo anahtar
-- bazlı: ileride masa keçesi dokusu, ıstaka ahşabı gibi başka görseller de
-- şema değişikliği olmadan eklenebilir.
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '5s';

-- -----------------------------------------------------------------------------
-- 1) Storage bucket
-- -----------------------------------------------------------------------------
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'okey-backgrounds',
  'okey-backgrounds',
  true,
  5242880, -- 5 MB: tam ekran bir oda fotoğrafı için fazlasıyla yeterli
  ARRAY['image/jpeg', 'image/png', 'image/webp']::text[]
)
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "okey_backgrounds_public_read" ON storage.objects;
CREATE POLICY "okey_backgrounds_public_read" ON storage.objects
  FOR SELECT TO public USING (bucket_id = 'okey-backgrounds');

DROP POLICY IF EXISTS "okey_backgrounds_admin_write" ON storage.objects;
CREATE POLICY "okey_backgrounds_admin_write" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'okey-backgrounds' AND public.is_admin());

DROP POLICY IF EXISTS "okey_backgrounds_admin_update" ON storage.objects;
CREATE POLICY "okey_backgrounds_admin_update" ON storage.objects
  FOR UPDATE TO authenticated
  USING (bucket_id = 'okey-backgrounds' AND public.is_admin());

DROP POLICY IF EXISTS "okey_backgrounds_admin_delete" ON storage.objects;
CREATE POLICY "okey_backgrounds_admin_delete" ON storage.objects
  FOR DELETE TO authenticated
  USING (bucket_id = 'okey-backgrounds' AND public.is_admin());

-- -----------------------------------------------------------------------------
-- 2) Hangi görsel nereye bağlı
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.okey_table_assets (
  asset_key text PRIMARY KEY,
  storage_path text NOT NULL,
  public_url text NOT NULL,
  updated_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.okey_table_assets IS
  'Okey masasının admin tarafından yüklenmiş görselleri (asset_key: room_backdrop). Tüm oyuncular okuyabilir; yalnız admin yazabilir.';

ALTER TABLE public.okey_table_assets ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS okey_table_assets_select ON public.okey_table_assets;
CREATE POLICY okey_table_assets_select ON public.okey_table_assets
  FOR SELECT TO authenticated USING (true);

REVOKE INSERT, UPDATE, DELETE ON public.okey_table_assets FROM authenticated;

-- -----------------------------------------------------------------------------
-- 3) RPC'ler
-- -----------------------------------------------------------------------------
-- Yeni dosya yazılmadan ÖNCE eskisinin yolu okunur ki, kayıt güncellendikten
-- SONRA eski dosya silinebilsin (ses akışıyla aynı sıra — silme başarısız
-- olsa bile yeni görsel geçerli kalır).
CREATE OR REPLACE FUNCTION public.admin_okey_previous_table_asset_path(
  p_asset_key text
)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT a.storage_path FROM public.okey_table_assets AS a
  WHERE a.asset_key = p_asset_key AND public.is_admin();
$$;
REVOKE ALL ON FUNCTION public.admin_okey_previous_table_asset_path(text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_okey_previous_table_asset_path(text)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_okey_set_table_asset(
  p_asset_key text,
  p_storage_path text,
  p_public_url text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'APP:forbidden' USING ERRCODE = '42501';
  END IF;
  IF p_asset_key IS NULL OR btrim(p_asset_key) = '' THEN
    RAISE EXCEPTION 'APP:invalid_value' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.okey_table_assets
    (asset_key, storage_path, public_url, updated_by, updated_at)
  VALUES (p_asset_key, p_storage_path, p_public_url, (SELECT auth.uid()), now())
  ON CONFLICT (asset_key) DO UPDATE SET
    storage_path = EXCLUDED.storage_path,
    public_url = EXCLUDED.public_url,
    updated_by = EXCLUDED.updated_by,
    updated_at = now();
END;
$$;
REVOKE ALL ON FUNCTION public.admin_okey_set_table_asset(text, text, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_okey_set_table_asset(text, text, text)
  TO authenticated;

-- Görseli kaldırmak: kayıt silinir, oyun VEKTÖREL arka plana geri döner.
CREATE OR REPLACE FUNCTION public.admin_okey_clear_table_asset(p_asset_key text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_path text;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'APP:forbidden' USING ERRCODE = '42501';
  END IF;

  DELETE FROM public.okey_table_assets WHERE asset_key = p_asset_key
  RETURNING storage_path INTO v_path;

  RETURN v_path; -- çağıran, dosyayı storage'dan silmek için kullanır
END;
$$;
REVOKE ALL ON FUNCTION public.admin_okey_clear_table_asset(text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_okey_clear_table_asset(text)
  TO authenticated;

NOTIFY pgrst, 'reload schema';
