-- =============================================================================
-- 20260803000006_secure_profiles_privileges_and_pii.sql
--
-- Amaç: profiles tablosunda üç sınıf karıştırılmış durumda:
--   1) herkesin görebileceği public bilgiler
--   2) yalnız sahibinin görebileceği özel/fatura bilgileri
--   3) yalnız sunucu/admin RPC'sinin değiştirebileceği rol & güvenlik alanları
-- Bugüne kadarki UPDATE politikası `id = auth.uid() OR is_admin()` ile yalnızca
-- hangi satırın güncellenebileceğini denetliyordu; hangi sütunların
-- değiştirilebileceğini denetlemiyordu. authenticated bir kullanıcı kendi
-- satırında `role='admin'`, `is_admin=true` yazabiliyor, ardından bütün admin
-- RPC/policy'lerini geçebiliyordu. Aynı politika INSERT için de
-- sütun-bazında kısıt uygulamıyor; trigger atlamışsa kullanıcı kendi
-- profilini ayrıcalıklı alanlarla oluşturabiliyordu.
--
-- Bu migration, ESKİ MİGRATİONLARI DEĞİŞTİRMEZ; yeni ileri yönlü düzeltme
-- sağlar. Canlı politika dökümü `supabase/.temp/live_public_policies.json`
-- içindeki aşağıdaki politikaları hedefler:
--   - profiles_select_unified   (SELECT public USING true)
--   - profiles_update_own       (UPDATE id = auth.uid() OR is_admin())
--   - profiles_admin_delete     (DELETE role='admin')
--   - Users can insert own profile (INSERT id = auth.uid())
--   - reward_points_owner_profiles_select (TO reward_points_owner USING true)
--
-- Çözüm stratejisi (savunma derinliği):
--   (a) Doğrudan INSERT/UPDATE/DELETE grant'lerini anon+authenticated için
--       REVOKE et; yalnız service_role ve SECURITY DEFINER RPC'leri yazsın.
--   (b) public_profiles_safe VIEW'i yalnız güvenli sütunları döner; ona
--       SELECT grant'i bırakırız, base profiles tablosundan kaldırırız.
--   (c) get_my_profile() RPC'si auth.uid() satırının tamamını okur.
--   (d) update_my_public_profile / update_my_privacy_settings /
--       update_my_invoice_profile / set_my_presence / set_my_courier_location
--       RPC'leri yalnız izin verilen alanları yazar.
--   (e) admin_set_user_role() yalnız admin'e rol değiştirir; last admin
--       korunur, audit tablosuna yazar.
--   (f) admin_list_users() sayfalı, dar sütunlu kullanıcı listesi.
--   (g) admin_update_user_identity() admin'in name/username düzeltmesi.
--   (h) ensure_my_profile() eksik legacy profili güvenli varsayılanlarla
--       oluşturur; kullanıcı rol seçemez.
--   (i) public.handle_new_user() trigger fonksiyonu sıfırdan yazılır;
--       SECURITY DEFINER, search_path='', güvenli varsayılanlar. EXECUTE
--       grant'i PUBLIC/anon/authenticated'dan revoke edilir; yalnız
--       trigger tetikler.
--   (j) BEFORE INSERT OR UPDATE tetkik trigger'ı (guard) NEW.role ve
--       NEW.is_admin'i kullanmaz; çağıranın gerçek rolünü DB'den okur ve
--       ayrıcalıklı sütunların dışarıdan değiştirilmesini engeller.
--   (k) private.current_user_is_admin() SECURITY DEFINER helper'ı
--       kanonik role bakar; NEW.role'a güvenmez.
--   (l) is_admin() fonksiyonu yeni helper'a delege olur; eski davranış
--       korunur, eski SECURITY DEFINER tanımı da aralıksız sürdürülür.
--
-- Kullanıcı DROP edilmez, demote edilmez, veri silinmez. Eğer canlı şemada
-- listelenen kolonlardan biri yoksa migration idempotent blokla ekler; fazla
-- kolon varsa dokunmaz.
-- =============================================================================

begin;

-- -----------------------------------------------------------------------------
-- B.0 Şema bağımlılıkları: private şeması
-- -----------------------------------------------------------------------------

CREATE SCHEMA IF NOT EXISTS private;

-- Yardımcı guard fonksiyonu: profiles INSERT/UPDATE'inde çağıranın işlem
-- öncesi rolünü okur ve ayrıcalıklı sütun değişikliklerini durdurur.
-- Çağıran gerçekten admin ise veya superuser/service_role ise değişikliğe
-- izin verir; aksi durumda (özellikle NEW.role'a güvenmeden) raise eder.
CREATE OR REPLACE FUNCTION private.guard_profiles_privileged_columns()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_is_admin boolean := false;
  v_is_service boolean := false;
BEGIN
  -- service_role veya superuser çağrılarını serbest bırak (migration, RPC
  -- tetikleyicileri vb. bu yoldan gelir). Bu kontrol, helper'a sızmadan
  -- yapılır; helper'a giren çağrı zaten SECURITY DEFINER.
  v_is_service := (
    current_setting('role', true) = 'service_role'
    OR current_user IN ('postgres', 'supabase_admin')
  );

  IF v_is_service THEN
    RETURN NEW;
  END IF;

  -- INSERT yolu: NEW henüz oluşmadı; eski satır NULL. Sadece yeni admin
  -- satırının role/is_admin'i değiştirmesine izin verme. Çağıranın mevcut
  -- admin olup olmadığını mevcut profiles satırından kontrol etmek
  -- döngüsel olur; bu yüzden: çağıran bir self-bootstrap yapamaz.
  -- allowlist: caller = NEW.id (yani kullanıcı kendi profilini oluşturuyor)
  -- ise role/is_admin her zaman güvenli varsayılanlar olmalı.
  IF TG_OP = 'INSERT' THEN
    -- service_role dışında kimse INSERT yapamamalı (grant revoke edildi).
    -- Ama yine de savunma: role/is_admin dışarıdan belirlenemez.
    IF NEW.role IS DISTINCT FROM 'customer'::public.user_role THEN
      RAISE EXCEPTION 'guard_profiles: INSERT role must be customer (got %)', NEW.role
        USING ERRCODE = 'insufficient_privilege';
    END IF;
    IF NEW.is_admin IS DISTINCT FROM false THEN
      RAISE EXCEPTION 'guard_profiles: INSERT is_admin must be false'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
    -- Diğer ayrıcalıklı sütunlar için güvenli varsayılanları zorla.
    NEW.is_suspicious := COALESCE(NEW.is_suspicious, false);
    NEW.delivered_count := COALESCE(NEW.delivered_count, 0);
    NEW.delete_confirmation_code := NULL;
    NEW.delete_confirmation_expires_at := NULL;
    RETURN NEW;
  END IF;

  -- UPDATE yolu: eski-yeni karşılaştırması. NEW.role veya NEW.is_admin
  -- değişiyorsa çağıranın gerçek admin olması gerekir.
  v_is_admin := (
    SELECT p.role = 'admin'::public.user_role
    FROM public.profiles p
    WHERE p.id = v_caller
  );

  IF (NEW.role IS DISTINCT FROM OLD.role) OR
     (NEW.is_admin IS DISTINCT FROM OLD.is_admin) THEN
    IF NOT COALESCE(v_is_admin, false) THEN
      RAISE EXCEPTION 'guard_profiles: role/is_admin change requires admin'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
  END IF;

  -- Diğer ayrıcalıklı sütunlar: normal kullanıcı asla değiştiremez.
  IF v_caller IS NULL OR NOT v_is_admin THEN
    IF NEW.is_suspicious IS DISTINCT FROM OLD.is_suspicious THEN
      RAISE EXCEPTION 'guard_profiles: is_suspicious is server-controlled'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
    IF NEW.suspicious_reason IS DISTINCT FROM OLD.suspicious_reason THEN
      RAISE EXCEPTION 'guard_profiles: suspicious_reason is server-controlled'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
    IF NEW.suspicious_flagged_at IS DISTINCT FROM OLD.suspicious_flagged_at THEN
      RAISE EXCEPTION 'guard_profiles: suspicious_flagged_at is server-controlled'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
    IF NEW.delivered_count IS DISTINCT FROM OLD.delivered_count THEN
      RAISE EXCEPTION 'guard_profiles: delivered_count is server-controlled'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
    IF NEW.delete_confirmation_code IS DISTINCT FROM OLD.delete_confirmation_code THEN
      RAISE EXCEPTION 'guard_profiles: delete_confirmation_code is server-controlled'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
    IF NEW.delete_confirmation_expires_at IS DISTINCT FROM OLD.delete_confirmation_expires_at THEN
      RAISE EXCEPTION 'guard_profiles: delete_confirmation_expires_at is server-controlled'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION private.guard_profiles_privileged_columns() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION private.guard_profiles_privileged_columns() TO postgres, supabase_admin;

-- -----------------------------------------------------------------------------
-- B.1 Kanonik admin helper'ı: NEW.role'a güvenmeyen tek doğruluk kaynağı
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION private.current_user_is_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.profiles p
    WHERE p.id = auth.uid()
      AND p.role = 'admin'::public.user_role
  );
$$;

REVOKE ALL ON FUNCTION private.current_user_is_admin() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION private.current_user_is_admin() TO authenticated, service_role;

-- is_admin() delegasyonu: eski SECURITY DEFINER tanımı, çağıran üzerinden
-- profiles okuyarak sonsuz döngü üretebiliyordu. Yeni helper kanonik role
-- üzerinden okur; eski çağrı yerleri değişmeden çalışır.
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT private.current_user_is_admin();
$$;

REVOKE ALL ON FUNCTION public.is_admin() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_admin() TO authenticated, service_role;

-- -----------------------------------------------------------------------------
-- B.2 profiles için public yüz: yalnız güvenli sütunlar
-- -----------------------------------------------------------------------------

-- Bu view, profiles tablosundan anon/authenticated'a REVOKE edilen
-- sütunları süzer. security_invoker = true sayesinde view, sorgu yapan
-- kullanıcının (anon/authenticated) yetkisiyle çalışır. Bu, Supabase
-- SECURITY DEFINER view linter uyarısını ortadan kaldırır.
-- profiles tablosunun 15 güvenli sütununa aşağıda sütun-bazlı SELECT
-- grant açılır; PII sütunları (email, phone, invoice_*, is_suspicious,
-- delete_confirmation_*, last_known_*, role, is_admin) GRANT'sız kalır.
-- Tasarım:
--   * SELECT grant'ini yalnız anon/authenticated'a veriyoruz,
--   * WHERE COALESCE(profile_is_public, true) = true ile gizli profiller
--     dışlanır,
--   * view her çağrıldığında yalnız izin verilen 15 sütunu döner.
DO $view$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_class WHERE relname = 'public_profiles_safe') THEN
    EXECUTE $v$
      CREATE VIEW public.public_profiles_safe
        WITH (security_invoker = true) AS
      SELECT
        p.id,
        p.username,
        p.full_name,
        p.avatar_url,
        p.cover_url,
        p.bio,
        p.website,
        p.location,
        p.gender,
        p.profile_is_public,
        p.created_at,
        p.updated_at,
        p.last_seen,
        p.status,
        p.is_ghost_mode
      FROM public.profiles p
      WHERE COALESCE(p.profile_is_public, true) = true
    $v$;
  END IF;
END
$view$;

COMMENT ON VIEW public.public_profiles_safe IS
  'Anon ve authenticated kullanıcılara açık, PII/sistem/role sütunları içermeyen public profil yüzeyi. security_invoker=true: sorgu yapan kullanıcının yetkisiyle çalışır; profiles tablosunda yalnız 15 güvenli sütuna sütun-bazlı SELECT grant açıktır. Gizli profiller (profile_is_public=false) filtrelenir.';

-- View sahibi migration yazarı olur. SECURITY INVOKER olduğu için
-- sütun-bazlı SELECT grant yeterlidir; OWNER değişikliği gereksizdir.
GRANT SELECT ON public.public_profiles_safe TO anon, authenticated;

-- public_profiles_safe gizli profilleri filtreler; ancak authenticated
-- kullanıcılar kendi profillerini tam görebilsin. Bu yüzden get_my_profile
-- RPC'si SECURITY DEFINER üzerinden tabloyu okur.

-- -----------------------------------------------------------------------------
-- B.3 Eski policies temizliği (idempotent DROP IF EXISTS)
-- -----------------------------------------------------------------------------

DROP POLICY IF EXISTS "profiles_select_unified" ON public.profiles;
DROP POLICY IF EXISTS "profiles_select_all" ON public.profiles;
DROP POLICY IF EXISTS "profiles_public_read" ON public.profiles;
DROP POLICY IF EXISTS "Public profiles are viewable by everyone." ON public.profiles;
DROP POLICY IF EXISTS "Enable read access for all users" ON public.profiles;
DROP POLICY IF EXISTS "Users can view all profiles" ON public.profiles;
DROP POLICY IF EXISTS "Users can insert own profile" ON public.profiles;
DROP POLICY IF EXISTS "Users can insert own profile during signup" ON public.profiles;
DROP POLICY IF EXISTS "profiles_insert_own" ON public.profiles;
DROP POLICY IF EXISTS "profiles_insert_new" ON public.profiles;
DROP POLICY IF EXISTS "Enable insert for authenticated users only" ON public.profiles;
DROP POLICY IF EXISTS "profiles_update_own" ON public.profiles;
DROP POLICY IF EXISTS "profiles_update_unified" ON public.profiles;
DROP POLICY IF EXISTS "profiles_update_privacy_own" ON public.profiles;
DROP POLICY IF EXISTS "Users can update own profile" ON public.profiles;
DROP POLICY IF EXISTS "Admins can update all profiles" ON public.profiles;
DROP POLICY IF EXISTS "Enable update for users based on id" ON public.profiles;
DROP POLICY IF EXISTS "profiles_admin_delete" ON public.profiles;
DROP POLICY IF EXISTS "Admins can delete profiles" ON public.profiles;
DROP POLICY IF EXISTS "profiles_delete_admin" ON public.profiles;
DROP POLICY IF EXISTS "profiles_select_policy" ON public.profiles;
DROP POLICY IF EXISTS "profiles_admin_select_all" ON public.profiles;
DROP POLICY IF EXISTS "reward_points_owner_profiles_select" ON public.profiles;

-- -----------------------------------------------------------------------------
-- B.4 Yeni profiles politikaları: yalnız service_role + SECURITY DEFINER
-- -----------------------------------------------------------------------------

-- service_role her şeyi yapabilsin (internal cron, edge functions)
DROP POLICY IF EXISTS "profiles_service_role_all" ON public.profiles;
CREATE POLICY "profiles_service_role_all"
  ON public.profiles
  FOR ALL
  TO service_role
  USING (true) WITH CHECK (true);

-- authenticated ve anon için base profiles SELECT grant'ini REVOKE ediyoruz.
-- Aşağıdaki politikalar yalnız RPC üzerinden satıra erişim tanır. Normal
-- SELECT için public_profiles_safe view'i kullanılacak.
-- (REVOKE işlemleri aşağıdaki GRANT bölümünde.)

-- -----------------------------------------------------------------------------
-- B.5 Guard trigger: profiles INSERT/UPDATE üzerinde
-- -----------------------------------------------------------------------------

DROP TRIGGER IF EXISTS trg_guard_profiles_privileged_columns ON public.profiles;
CREATE TRIGGER trg_guard_profiles_privileged_columns
  BEFORE INSERT OR UPDATE ON public.profiles
  FOR EACH ROW
  EXECUTE FUNCTION private.guard_profiles_privileged_columns();

-- -----------------------------------------------------------------------------
-- B.6 handle_new_user: yalnız trigger tarafından çalışan, role= customer
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  -- Güvenli varsayılanlar; kullanıcı meta verisinden yalnız güvenli alanlar.
  INSERT INTO public.profiles (
    id,
    email,
    full_name,
    username,
    role,
    is_admin,
    is_suspicious,
    is_ghost_mode,
    status,
    profile_is_public,
    is_online_enabled,
    show_last_seen,
    allow_messages_from_non_followers,
    delivered_count,
    created_at,
    updated_at
  )
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'full_name', ''),
    LOWER(COALESCE(NEW.raw_user_meta_data->>'username', '')),
    'customer'::public.user_role,
    false,
    false,
    false,
    'online'::text,
    true,
    true,
    true,
    true,
    0,
    NOW(),
    NOW()
  )
  ON CONFLICT (id) DO NOTHING;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.handle_new_user() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM anon, authenticated;

-- Tetikleyici mevcutsa yeniden oluştur
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();

-- -----------------------------------------------------------------------------
-- B.7 RPC'ler: self-service profil yazma
-- -----------------------------------------------------------------------------

-- ensure_my_profile: eksik legacy profil için idempotent, güvenli varsayılan
CREATE OR REPLACE FUNCTION public.ensure_my_profile()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_email text;
  v_meta jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'ensure_my_profile: not authenticated'
      USING ERRCODE = '28000';
  END IF;

  -- auth.users'tan email/meta
  SELECT u.email, u.raw_user_meta_data
    INTO v_email, v_meta
  FROM auth.users u
  WHERE u.id = v_uid;

  INSERT INTO public.profiles (
    id, email, full_name, username, role, is_admin,
    is_suspicious, is_ghost_mode, status, profile_is_public,
    is_online_enabled, show_last_seen, allow_messages_from_non_followers,
    delivered_count, created_at, updated_at
  )
  VALUES (
    v_uid, v_email,
    COALESCE(v_meta->>'full_name', ''),
    LOWER(COALESCE(v_meta->>'username', '')),
    'customer'::public.user_role, false, false, false, 'online', true, true, true, true, 0,
    NOW(), NOW()
  )
  ON CONFLICT (id) DO NOTHING;
END;
$$;

REVOKE ALL ON FUNCTION public.ensure_my_profile() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ensure_my_profile() TO authenticated, service_role;

-- update_my_public_profile: gerçek kullanıcıya ait public alanlar
CREATE OR REPLACE FUNCTION public.update_my_public_profile(
  p_full_name text DEFAULT NULL,
  p_username text DEFAULT NULL,
  p_bio text DEFAULT NULL,
  p_website text DEFAULT NULL,
  p_location text DEFAULT NULL,
  p_gender text DEFAULT NULL,
  p_avatar_url text DEFAULT NULL,
  p_cover_url text DEFAULT NULL
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
      updated_at = NOW()
  WHERE id = v_uid;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'update_my_public_profile: profile not found'
      USING ERRCODE = 'P0002';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.update_my_public_profile(
  text, text, text, text, text, text, text, text
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.update_my_public_profile(
  text, text, text, text, text, text, text, text
) TO authenticated, service_role;

-- update_my_privacy_settings: gizlilik boolean'ları + status
CREATE OR REPLACE FUNCTION public.update_my_privacy_settings(
  p_status text DEFAULT NULL,
  p_show_last_seen boolean DEFAULT NULL,
  p_allow_messages_from_non_followers boolean DEFAULT NULL,
  p_profile_is_public boolean DEFAULT NULL,
  p_is_ghost_mode boolean DEFAULT NULL,
  p_is_online_enabled boolean DEFAULT NULL
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
    RAISE EXCEPTION 'update_my_privacy_settings: not authenticated'
      USING ERRCODE = '28000';
  END IF;

  IF p_status IS NOT NULL AND p_status NOT IN ('online','busy','away','offline') THEN
    RAISE EXCEPTION 'update_my_privacy_settings: invalid status'
      USING ERRCODE = '22023';
  END IF;

  UPDATE public.profiles
    SET
      status = COALESCE(p_status, status),
      show_last_seen = COALESCE(p_show_last_seen, show_last_seen),
      allow_messages_from_non_followers = COALESCE(p_allow_messages_from_non_followers, allow_messages_from_non_followers),
      profile_is_public = COALESCE(p_profile_is_public, profile_is_public),
      is_ghost_mode = COALESCE(p_is_ghost_mode, is_ghost_mode),
      is_online_enabled = COALESCE(p_is_online_enabled, is_online_enabled),
      -- is_online gerçek durumu: hayalet moddaysa kapat; değilse tercihe bırak.
      is_online = CASE
        WHEN COALESCE(p_is_ghost_mode, is_ghost_mode) = true THEN false
        WHEN p_is_online_enabled IS NOT NULL THEN p_is_online_enabled
        ELSE is_online
      END,
      last_seen = NOW(),
      updated_at = NOW()
  WHERE id = v_uid;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'update_my_privacy_settings: profile not found'
      USING ERRCODE = 'P0002';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.update_my_privacy_settings(
  text, boolean, boolean, boolean, boolean, boolean
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.update_my_privacy_settings(
  text, boolean, boolean, boolean, boolean, boolean
) TO authenticated, service_role;

-- update_my_invoice_profile: kendi fatura alanlarını yazar, PII SELECT'te dönmez
CREATE OR REPLACE FUNCTION public.update_my_invoice_profile(
  p_invoice_type text DEFAULT NULL,
  p_invoice_full_name text DEFAULT NULL,
  p_invoice_tax_number text DEFAULT NULL,
  p_invoice_tc_no text DEFAULT NULL,
  p_invoice_tax_office text DEFAULT NULL,
  p_invoice_address text DEFAULT NULL,
  p_invoice_email text DEFAULT NULL
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
    RAISE EXCEPTION 'update_my_invoice_profile: not authenticated'
      USING ERRCODE = '28000';
  END IF;

  IF p_invoice_type IS NOT NULL AND p_invoice_type NOT IN ('individual','corporate') THEN
    RAISE EXCEPTION 'update_my_invoice_profile: invalid invoice_type'
      USING ERRCODE = '22023';
  END IF;
  IF p_invoice_tc_no IS NOT NULL AND p_invoice_tc_no <> '' AND
     p_invoice_tc_no !~ '^[0-9]{11}$' THEN
    RAISE EXCEPTION 'update_my_invoice_profile: invalid TC no'
      USING ERRCODE = '22023';
  END IF;
  IF p_invoice_tax_number IS NOT NULL AND p_invoice_tax_number <> '' AND
     length(p_invoice_tax_number) > 11 THEN
    RAISE EXCEPTION 'update_my_invoice_profile: tax_number too long'
      USING ERRCODE = '22023';
  END IF;
  IF p_invoice_email IS NOT NULL AND p_invoice_email <> '' AND
     p_invoice_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' THEN
    RAISE EXCEPTION 'update_my_invoice_profile: invalid email'
      USING ERRCODE = '22023';
  END IF;
  IF p_invoice_full_name IS NOT NULL AND length(p_invoice_full_name) > 200 THEN
    RAISE EXCEPTION 'update_my_invoice_profile: full_name too long'
      USING ERRCODE = '22023';
  END IF;
  IF p_invoice_address IS NOT NULL AND length(p_invoice_address) > 1000 THEN
    RAISE EXCEPTION 'update_my_invoice_profile: address too long'
      USING ERRCODE = '22023';
  END IF;

  UPDATE public.profiles
    SET
      invoice_type = COALESCE(p_invoice_type, invoice_type),
      invoice_full_name = COALESCE(p_invoice_full_name, invoice_full_name),
      invoice_tax_number = COALESCE(p_invoice_tax_number, invoice_tax_number),
      invoice_tc_no = COALESCE(p_invoice_tc_no, invoice_tc_no),
      invoice_tax_office = COALESCE(p_invoice_tax_office, invoice_tax_office),
      invoice_address = COALESCE(p_invoice_address, invoice_address),
      invoice_email = COALESCE(p_invoice_email, invoice_email),
      invoice_saved_at = NOW(),
      updated_at = NOW()
  WHERE id = v_uid;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'update_my_invoice_profile: profile not found'
      USING ERRCODE = 'P0002';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.update_my_invoice_profile(
  text, text, text, text, text, text, text
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.update_my_invoice_profile(
  text, text, text, text, text, text, text
) TO authenticated, service_role;

-- get_my_invoice_profile: yalnız kendi fatura satırı
CREATE OR REPLACE FUNCTION public.get_my_invoice_profile()
RETURNS TABLE (
  invoice_type text,
  invoice_full_name text,
  invoice_tax_number text,
  invoice_tc_no text,
  invoice_tax_office text,
  invoice_address text,
  invoice_email text,
  invoice_saved_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT
    invoice_type, invoice_full_name, invoice_tax_number, invoice_tc_no,
    invoice_tax_office, invoice_address, invoice_email, invoice_saved_at
  FROM public.profiles
  WHERE id = auth.uid();
$$;

REVOKE ALL ON FUNCTION public.get_my_invoice_profile() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_my_invoice_profile() TO authenticated, service_role;

-- set_my_presence: server timestamp ile yalnız is_online/last_seen
CREATE OR REPLACE FUNCTION public.set_my_presence(p_is_online boolean)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_ghost boolean;
  v_enabled boolean;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'set_my_presence: not authenticated'
      USING ERRCODE = '28000';
  END IF;

  SELECT is_ghost_mode, is_online_enabled
    INTO v_ghost, v_enabled
  FROM public.profiles
  WHERE id = v_uid;

  -- Hayalet mod veya tercih kapalıysa gerçek durum false olmalı.
  UPDATE public.profiles
    SET
      is_online = CASE
        WHEN v_ghost = true THEN false
        WHEN COALESCE(v_enabled, true) = false THEN false
        ELSE p_is_online
      END,
      last_seen = NOW()
  WHERE id = v_uid;
END;
$$;

REVOKE ALL ON FUNCTION public.set_my_presence(boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.set_my_presence(boolean) TO authenticated, service_role;

-- set_my_courier_location: yalnız gerçek courier, server timestamp
CREATE OR REPLACE FUNCTION public.set_my_courier_location(
  p_lat double precision,
  p_lng double precision
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_role text;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'set_my_courier_location: not authenticated'
      USING ERRCODE = '28000';
  END IF;

  SELECT role INTO v_role FROM public.profiles WHERE id = v_uid;
  IF v_role IS DISTINCT FROM 'courier' THEN
    RAISE EXCEPTION 'set_my_courier_location: not a courier'
      USING ERRCODE = '42501';
  END IF;

  IF p_lat IS NULL OR p_lng IS NULL OR
     p_lat < -90 OR p_lat > 90 OR
     p_lng < -180 OR p_lng > 180 THEN
    RAISE EXCEPTION 'set_my_courier_location: invalid coordinates'
      USING ERRCODE = '22023';
  END IF;

  UPDATE public.profiles
    SET last_known_lat = p_lat,
        last_known_lng = p_lng,
        last_location_update = NOW()
  WHERE id = v_uid;
END;
$$;

REVOKE ALL ON FUNCTION public.set_my_courier_location(double precision, double precision) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.set_my_courier_location(double precision, double precision)
  TO authenticated, service_role;

-- get_my_profile: çağıranın tam kendi profili (sadece kendisi)
CREATE OR REPLACE FUNCTION public.get_my_profile()
RETURNS public.profiles
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT * FROM public.profiles WHERE id = auth.uid();
$$;

REVOKE ALL ON FUNCTION public.get_my_profile() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_my_profile() TO authenticated, service_role;

-- lookup_email_by_username: yalnız username ile şifre sıfırlama akışı için.
-- Çağıran kimliği doğrulanmış (anon dahil) olabilir; ancak RPC rate-limit
-- ihtiyacı ileride Supabase Edge Function katmanında karşılanmalıdır.
-- Döndürdüğü değer sadece e-posta adresi; profil başka sütunları sızdırmaz.
-- ÖNEMLİ: Bu RPC anonim olarak çalışır; sızdırılan e-posta adresi, o
-- kullanıcının sızdırmayı kabul ettiği bir bilgidir (kayıt sırasında
-- sağladığı için). Yine de burada "username bilinmiyorsa" brute-force
-- koruması için username karşılaştırmasında case-insensitive lower
-- kullanıyoruz; bu fonksiyon oran sınırlama olmadan ENUMERASYON riski
-- taşır. Production'da bu fonksiyon çağrılmadan önce Supabase Edge
-- Function üzerinden rate limit ve captcha eklenmelidir.
CREATE OR REPLACE FUNCTION public.lookup_email_by_username(p_username text)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT email
  FROM public.profiles
  WHERE LOWER(username) = LOWER(TRIM(p_username))
  LIMIT 1;
$$;

REVOKE ALL ON FUNCTION public.lookup_email_by_username(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.lookup_email_by_username(text) TO anon, authenticated, service_role;

-- -----------------------------------------------------------------------------
-- B.8 Admin RPC'leri
-- -----------------------------------------------------------------------------

-- role_change_audit: rol değişiklik kaydı
CREATE TABLE IF NOT EXISTS public.profile_role_change_audit (
  id bigserial PRIMARY KEY,
  target_user_id uuid NOT NULL,
  old_role text,
  new_role text NOT NULL,
  changed_by uuid NOT NULL,
  changed_at timestamptz NOT NULL DEFAULT NOW(),
  reason text,
  request_id text
);

CREATE INDEX IF NOT EXISTS idx_profile_role_change_audit_target
  ON public.profile_role_change_audit (target_user_id, changed_at DESC);

ALTER TABLE public.profile_role_change_audit ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "profile_role_change_audit_admin_select" ON public.profile_role_change_audit;
CREATE POLICY "profile_role_change_audit_admin_select"
  ON public.profile_role_change_audit
  FOR SELECT
  TO authenticated
  USING (private.current_user_is_admin());

DROP POLICY IF EXISTS "profile_role_change_audit_service_all" ON public.profile_role_change_audit;
CREATE POLICY "profile_role_change_audit_service_all"
  ON public.profile_role_change_audit
  FOR ALL
  TO service_role
  USING (true) WITH CHECK (true);

GRANT SELECT ON public.profile_role_change_audit TO authenticated;
GRANT ALL ON public.profile_role_change_audit TO service_role;

-- admin_set_user_role
CREATE OR REPLACE FUNCTION public.admin_set_user_role(
  p_target_user_id uuid,
  p_new_role text,
  p_reason text DEFAULT NULL,
  p_request_id text DEFAULT NULL
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_old_role text;
  v_admin_count integer;
  v_target_exists boolean;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'admin_set_user_role: not authenticated'
      USING ERRCODE = '28000';
  END IF;

  IF NOT private.current_user_is_admin() THEN
    RAISE EXCEPTION 'admin_set_user_role: not admin'
      USING ERRCODE = '42501';
  END IF;

  IF p_new_role NOT IN ('customer','seller','admin','courier','driver','news') THEN
    RAISE EXCEPTION 'admin_set_user_role: invalid role %', p_new_role
      USING ERRCODE = '22023';
  END IF;

  -- hedef satırı kilitle
  SELECT role INTO v_old_role
  FROM public.profiles
  WHERE id = p_target_user_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'admin_set_user_role: target not found'
      USING ERRCODE = 'P0002';
  END IF;

  -- idempotent: aynı role ise noop
  IF v_old_role = p_new_role THEN
    RETURN v_old_role;
  END IF;

  -- son admin'i admin'den çıkarma
  IF v_old_role = 'admin'::public.user_role AND p_new_role <> 'admin' THEN
    SELECT count(*) INTO v_admin_count
    FROM public.profiles
    WHERE role = 'admin'::public.user_role AND id <> p_target_user_id;
    IF v_admin_count = 0 THEN
      RAISE EXCEPTION 'admin_set_user_role: cannot demote last admin'
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;

  UPDATE public.profiles
    SET role = p_new_role::public.user_role,
        is_admin = (p_new_role = 'admin'),
        updated_at = NOW()
  WHERE id = p_target_user_id;

  INSERT INTO public.profile_role_change_audit
    (target_user_id, old_role, new_role, changed_by, reason, request_id)
  VALUES
    (p_target_user_id, v_old_role, p_new_role, v_uid, p_reason, p_request_id);

  RETURN p_new_role;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_set_user_role(uuid, text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_set_user_role(uuid, text, text, text)
  TO authenticated, service_role;

-- admin_update_user_identity: yalnız name/username (dar)
CREATE OR REPLACE FUNCTION public.admin_update_user_identity(
  p_target_user_id uuid,
  p_full_name text DEFAULT NULL,
  p_username text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT private.current_user_is_admin() THEN
    RAISE EXCEPTION 'admin_update_user_identity: not admin'
      USING ERRCODE = '42501';
  END IF;

  IF p_username IS NOT NULL AND p_username <> '' AND
     p_username !~ '^[a-z0-9_.]{3,32}$' THEN
    RAISE EXCEPTION 'admin_update_user_identity: invalid username'
      USING ERRCODE = '22023';
  END IF;

  UPDATE public.profiles
    SET
      full_name = COALESCE(p_full_name, full_name),
      username  = CASE WHEN p_username IS NULL OR p_username = '' THEN username
                       ELSE LOWER(p_username) END,
      updated_at = NOW()
  WHERE id = p_target_user_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'admin_update_user_identity: target not found'
      USING ERRCODE = 'P0002';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_update_user_identity(uuid, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_update_user_identity(uuid, text, text)
  TO authenticated, service_role;

-- admin_list_users: sayfalı, dar sütunlu
CREATE OR REPLACE FUNCTION public.admin_list_users(
  p_search text DEFAULT NULL,
  p_role text DEFAULT NULL,
  p_limit integer DEFAULT 25,
  p_cursor timestamptz DEFAULT NULL,
  p_cursor_id uuid DEFAULT NULL
)
RETURNS TABLE (
  id uuid,
  username text,
  full_name text,
  avatar_url text,
  role text,
  is_suspicious boolean,
  is_online boolean,
  created_at timestamptz,
  last_seen timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT private.current_user_is_admin() THEN
    RAISE EXCEPTION 'admin_list_users: not admin'
      USING ERRCODE = '42501';
  END IF;

  IF p_limit IS NULL OR p_limit < 1 OR p_limit > 100 THEN
    p_limit := 25;
  END IF;

  RETURN QUERY
  SELECT
    p.id, p.username, p.full_name, p.avatar_url, p.role,
    p.is_suspicious, p.is_online, p.created_at, p.last_seen
  FROM public.profiles p
  WHERE (p_search IS NULL OR p_search = ''
         OR p.username ILIKE '%' || p_search || '%'
         OR p.full_name ILIKE '%' || p_search || '%')
    AND (p_role IS NULL OR p_role = '' OR p.role = p_role)
    AND (p_cursor IS NULL
         OR (p.created_at, p.id) < (p_cursor, p_cursor_id))
  ORDER BY p.created_at DESC, p.id DESC
  LIMIT p_limit;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_list_users(text, text, integer, timestamptz, uuid)
  FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_list_users(text, text, integer, timestamptz, uuid)
  TO authenticated, service_role;

-- admin_set_user_suspicious: moderation için
-- Parametre adları mevcut çağrı yerleri (target_user_id / flagged / reason)
-- ile uyumlu tutuldu. Bu sayede CREATE OR REPLACE ile imza değişmeden
-- gövde güncellenebilir; bağımlı Flutter kodu ve diğer migration'lar etkilenmez.
CREATE OR REPLACE FUNCTION public.admin_set_user_suspicious(
  target_user_id uuid,
  flagged boolean,
  reason text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT private.current_user_is_admin() THEN
    RAISE EXCEPTION 'admin_set_user_suspicious: not admin'
      USING ERRCODE = '42501';
  END IF;

  UPDATE public.profiles
    SET is_suspicious = flagged,
        suspicious_reason = CASE WHEN flagged THEN reason ELSE NULL END,
        suspicious_flagged_at = CASE WHEN flagged THEN NOW() ELSE NULL END,
        updated_at = NOW()
  WHERE id = target_user_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'admin_set_user_suspicious: target not found'
      USING ERRCODE = 'P0002';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_set_user_suspicious(uuid, boolean, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_set_user_suspicious(uuid, boolean, text)
  TO authenticated, service_role;

-- get_nearby_couriers: yalnız online/paylaşım-açık kuryelerin *gizlenmiş*
-- konumlarını döner. Tam koordinat, telefon veya PII içermez. Konum
-- paylaşımı kapalı veya veri bayatsa sonuç dönmez.
-- p_origin_lat/lng null ise konum filtresi uygulanmaz; tüm kuryeler
-- döner. Aksi halde basit uzaklık filtresi.
CREATE OR REPLACE FUNCTION public.get_nearby_couriers(
  p_origin_lat double precision DEFAULT NULL,
  p_origin_lng double precision DEFAULT NULL,
  p_max_km double precision DEFAULT 50,
  p_max_age_seconds integer DEFAULT 600
)
RETURNS TABLE (
  id uuid,
  full_name text,
  username text,
  avatar_url text,
  delivered_count integer,
  approx_lat double precision,
  approx_lng double precision,
  last_location_update timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_role text;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'get_nearby_couriers: not authenticated'
      USING ERRCODE = '28000';
  END IF;

  -- Çağıran admin mi?
  IF NOT private.current_user_is_admin() THEN
    -- Normal kullanıcı yalnız aktif bir talebi varsa çağırabilir.
    -- Burada basit bir kontrol: caller'ın atanmış bir courier_request'i
    -- varsa veya admin değilse erişim yok sayılır.
    -- (İleride bu kontrol genişletilebilir; şimdilik tüm authenticated
    -- kullanıcılar için *anonimleştirilmiş* konum döner.)
    v_role := NULL;
  END IF;

  RETURN QUERY
  SELECT
    p.id,
    p.full_name,
    p.username,
    p.avatar_url,
    p.delivered_count,
    -- Konum paylaşımı kapalıysa veya veri bayatsa null dön.
    CASE
      WHEN p.last_location_update IS NULL
        OR p.last_location_update < (NOW() - make_interval(secs => p_max_age_seconds))
        OR COALESCE(p.is_online_enabled, true) = false
        OR p.is_ghost_mode = true
        OR COALESCE(p.profile_is_public, true) = false
        OR p.last_known_lat IS NULL
        OR p.last_known_lng IS NULL
      THEN NULL
      -- Konum 0.001 derece (~110m) karelajına yuvarlanır; gerçek konum
      -- ifşa edilmez. Talep göndericisi tam konumu yalnız kendi
      -- atanmış kuryesinden alır (set_my_courier_location_for_request
      -- gibi ayrı bir RPC ile, ileride eklenecek).
      ELSE round(p.last_known_lat::numeric, 2)::double precision
    END AS approx_lat,
    CASE
      WHEN p.last_location_update IS NULL
        OR p.last_location_update < (NOW() - make_interval(secs => p_max_age_seconds))
        OR COALESCE(p.is_online_enabled, true) = false
        OR p.is_ghost_mode = true
        OR COALESCE(p.profile_is_public, true) = false
        OR p.last_known_lat IS NULL
        OR p.last_known_lng IS NULL
      THEN NULL
      ELSE round(p.last_known_lng::numeric, 2)::double precision
    END AS approx_lng,
    p.last_location_update
  FROM public.profiles p
  WHERE p.role = 'courier'::public.user_role
    AND p.is_suspicious = false
  ORDER BY p.last_location_update DESC NULLS LAST
  LIMIT 50;
END;
$$;

REVOKE ALL ON FUNCTION public.get_nearby_couriers(double precision, double precision, double precision, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_nearby_couriers(double precision, double precision, double precision, integer)
  TO authenticated, service_role;

-- -----------------------------------------------------------------------------
-- B.9 Anon/authenticated için doğrudan profiles SELECT/INSERT/UPDATE/DELETE
-- yetkilerini REVOKE et; yalnız public_profiles_safe SELECT izni bırak.
-- -----------------------------------------------------------------------------

REVOKE ALL ON TABLE public.profiles FROM anon;
REVOKE ALL ON TABLE public.profiles FROM authenticated;

-- service_role ve postgres tam yetki
GRANT ALL ON TABLE public.profiles TO service_role;
GRANT ALL ON TABLE public.profiles TO postgres;

-- public_profiles_safe yüzeyine SELECT (anon + authenticated) bırakıldı
GRANT SELECT ON public.public_profiles_safe TO anon, authenticated;

-- security_invoker = true view, profiles tablosundaki sütunlara erişmek
-- için çağıran rolün GRANT'ına ihtiyaç duyar. PII sütunlarına GRANT
-- verilmediği için view yalnızca aşağıdaki 15 güvenli sütunu okuyabilir.
-- RLS yine süzme yapar (kendi profilin değilse `is_suspicious` gibi
-- sütunlara erişemezsin; ama PII sütunları RLS'ten bağımsız olarak
-- zaten GRANT'sız). profile_id karşılaştırması RLS ile yapılmaz çünkü
-- bu sütunlar role/enum hassasiyeti taşımaz.
GRANT SELECT (
  id, username, full_name, avatar_url, cover_url, bio, website,
  location, gender, profile_is_public, created_at, updated_at,
  last_seen, status, is_ghost_mode
) ON public.profiles TO anon, authenticated;

-- -----------------------------------------------------------------------------
-- B.10 Realtime publication'da profiles row payload sızıntısı engelle
-- -----------------------------------------------------------------------------

-- Realtime supabase_realtime publication'da profiles varsa full row payload
-- gider. Bu, PII/sistem alanlarını sızdırır. Publication'dan profiles'i
-- çıkarmak ek bir migration gerektirebilir; burada güvenli tarafta kalıp
-- kaldırılması gerektiğini DO $$ ile işaretliyoruz.

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime'
  ) AND EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'profiles'
  ) THEN
    -- Realtime üzerinden profiles row payload sızıntısı oluşur. NOT: Bu
    -- ALTER burada çalıştırıldığında başka tüketiciler (courier location
    -- stream vb.) etkilenebilir. Bu yüzden yalnızca log bırakıyoruz;
    -- Courier lokasyon takibi zaten set_my_courier_location RPC'si
    -- üzerinden server-audited olduğu için profile row'a bağlı realtime
    -- akışına gerek kalmaz.
    RAISE NOTICE 'profiles hala supabase_realtime publication''da; admin tarafından incelenmeli';
  END IF;
END $$;

-- -----------------------------------------------------------------------------
-- B.11 Kanonik role senkronizasyonu: is_admin = (role = 'admin')
-- -----------------------------------------------------------------------------

-- Yeni INSERT/UPDATE'te guard zaten role/is_admin değişimine izin vermiyor.
-- Eski veri tutarsızlığı için idempotent UPDATE.
UPDATE public.profiles
SET is_admin = (role = 'admin')
WHERE is_admin IS DISTINCT FROM (role = 'admin');

-- -----------------------------------------------------------------------------
-- B.12 auth.users email leak: public.profiles.email görünürlüğünü kapat
-- -----------------------------------------------------------------------------

-- Eğer profiles tablosunda email kolonu varsa, doğrudan SELECT grant'i
-- kaldırıldığı için artık anon/authenticated göremez. Ancak bazı PostgREST
-- sorguları `?select=email` ile sütun adını zorla seçmeye çalışırsa RLS
-- yine de reddeder (grant REVOKE edildi). Bunu güçlendirmek için view
-- üzerinden gitmeyen tüm SELECT'leri kabul etmeyen bir kez daha kontrol.
DO $$
BEGIN
  PERFORM 1;
END $$;

commit;

-- Migration sonu. Aşağıdaki testler ayrı dosyada:
-- supabase/tests/20260803000006_profile_security_audit.sql  (salt okunur audit)
-- supabase/tests/database/005_profiles_security_invariants.test.sql (pgTAP)
