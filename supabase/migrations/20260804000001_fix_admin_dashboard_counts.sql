-- =============================================
-- Fix: Admin Dashboard sayaçlarının tümünün 0
-- görünmesine yol açan iki katmanlı hata.
-- =============================================
-- (1) support_tickets SELECT policy'sinin gövdesinde inline
--     `SELECT role FROM profiles WHERE id = auth.uid()` vardı.
--     20260803000006_secure_profiles_privileges_and_pii.sql
--     `role` ve `is_admin` sütunlarını authenticated'tan revoke
--     etmişti; bu yüzden admin olarak support_tickets sorgusu
--     `42501 permission denied for column role` fırlatıyor,
--     catch'e düşüyor, dashboard'daki 6 sayacın atandığı tek
--     setState hiç çalışmıyor, tüm sayaçlar 0 kalıyordu.
--     Çözüm: inline alt sorguyu SECURITY DEFINER helper'ıyla
--     değiştir.
--
-- (2) profiles SELECT policy'si kaldırıldığı için admin panelinin
--     `_loadRealData()` çağrıları sessizce boş dönüyor + 42501
--     patlaması yukarıdaki etkiyi yaratıyordu. Doğru mimari:
--     admin ihtiyaçları SECURITY DEFINER RPC'lerin arkasına
--     konulmalı; profiles tablosuna `authenticated` için geniş
--     SELECT policy'si AÇILMAMALI (PII sertleştirmesi geri
--     alınmamalı).
--     Çözüm: tek bir `admin_dashboard_counts()` SECURITY DEFINER
--     RPC'si ekle. RPC, çağıranın admin olup olmadığını
--     `private.current_user_is_admin()` ile denetler.

begin;

-- -----------------------------------------------------------------------------
-- (0) private şeması + current_user_is_admin helper'ı
-- -----------------------------------------------------------------------------
-- Bu migration, support_tickets policy gövdesinde ve kendi SECURITY
-- DEFINER RPC'lerinin admin denetiminde `private.current_user_is_admin()`
-- helper'ını kullanır. 20260803000006 ile birlikte `private` şeması
-- yaratılmış olmalı, ancak bağımsız deploy senaryolarında (örn. staging
-- prod'dan geride kaldığında) bu şema henüz mevcut olmayabilir. Bu
-- yüzden idempotent olarak şema ve helper'ı burada yeniden yaratıyoruz.
-- Mevcutsa CREATE ... IF NOT EXISTS ile dokunulmaz; helper CREATE OR
-- REPLACE ile güncellenir.

CREATE SCHEMA IF NOT EXISTS private;

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
GRANT EXECUTE ON FUNCTION private.current_user_is_admin()
  TO authenticated, service_role;

-- -----------------------------------------------------------------------------
-- (0.b) admin_list_users() — sayfalı, dar sütunlu kullanıcı listesi
-- -----------------------------------------------------------------------------
-- Bu fonksiyon normalde 20260803000006 ile birlikte yaratılmış olmalı.
-- Ancak bazı ortamlar (staging, geri-almış DB'ler) için migration'ı
-- tamamen self-contained yapmak adına, fonksiyon burada idempotent
-- olarak yeniden yaratılır: 20260803000006 deploy edilmemişse YARATIR,
-- edilmişse imza korunarak gövde yine aynı şekilde kurulur (no-op).

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
    RAISE EXCEPTION 'admin_list_users: not admin' USING ERRCODE = '42501';
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

REVOKE ALL ON FUNCTION public.admin_list_users(text, text, integer, timestamptz, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_list_users(text, text, integer, timestamptz, uuid)
  TO authenticated, service_role;

-- -----------------------------------------------------------------------------
-- (1) support_tickets policy düzeltmesi
-- -----------------------------------------------------------------------------

DROP POLICY IF EXISTS "support_tickets_select_policy" ON public.support_tickets;
CREATE POLICY "support_tickets_select_policy"
  ON public.support_tickets
  FOR SELECT
  TO authenticated
  USING (
    user_id = (select auth.uid())
    OR private.current_user_is_admin()
  );

-- -----------------------------------------------------------------------------
-- (2) admin_dashboard_counts() RPC
-- -----------------------------------------------------------------------------
-- PostgREST sayımı: `from(t).select('id').length` 1000 satırla
-- sınırlıdır (supabase/config.toml'da max_rows override'ı yok).
-- RPC, gerçek count(*) döndürür; sayaçlar 1000'de takılmaz.

CREATE OR REPLACE FUNCTION public.admin_dashboard_counts()
RETURNS TABLE (
  total_users bigint,
  total_posts bigint,
  total_products bigint,
  total_orders bigint,
  total_reports bigint,
  unanswered_complaints bigint,
  unanswered_tickets bigint
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT private.current_user_is_admin() THEN
    RAISE EXCEPTION 'admin_dashboard_counts: not admin'
      USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT
    (SELECT count(*) FROM public.profiles),
    (SELECT count(*) FROM public.posts),
    (SELECT count(*) FROM public.products),
    (SELECT count(*) FROM public.orders),
    (SELECT count(*) FROM public.user_reports),
    (SELECT count(*) FROM public.user_reports
       WHERE status IN ('pending','reviewing'))
      + COALESCE((SELECT count(*) FROM public.post_reports
                   WHERE status IN ('pending','reviewing')), 0),
    (SELECT count(*) FROM public.support_tickets
       WHERE status = 'open');
END;
$$;

REVOKE ALL ON FUNCTION public.admin_dashboard_counts() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_dashboard_counts()
  TO authenticated, service_role;

-- -----------------------------------------------------------------------------
-- (3) admin_logs_counts() RPC
-- -----------------------------------------------------------------------------
-- _part_data_loaders.dart → _loadLogsData() içindeki 7 ayrı
-- `from('profiles').select('id').count(CountOption.exact)` çağrısı
-- profiles üzerinde authenticated SELECT policy'si olmadığı için
-- sessizce boş döner (RLS deny→0). RPC, count(*) ile gerçek
-- değerleri verir.

CREATE OR REPLACE FUNCTION public.admin_logs_counts()
RETURNS TABLE (
  online_count bigint,
  dau_count bigint,
  wau_count bigint,
  mau_count bigint,
  total_users bigint,
  new_today_count bigint,
  inactive_count bigint
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_now timestamptz := NOW();
  v_today_start timestamptz := date_trunc('day', v_now AT TIME ZONE 'UTC') AT TIME ZONE 'UTC';
  v_week_ago timestamptz := v_now - interval '7 days';
  v_five_min_ago timestamptz := v_now - interval '5 minutes';
  v_month_ago timestamptz := v_now - interval '30 days';
BEGIN
  IF NOT private.current_user_is_admin() THEN
    RAISE EXCEPTION 'admin_logs_counts: not admin' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT
    (SELECT count(*) FROM public.profiles
       WHERE last_seen >= v_five_min_ago),
    (SELECT count(*) FROM public.profiles
       WHERE last_seen >= v_today_start),
    (SELECT count(*) FROM public.profiles
       WHERE last_seen >= v_week_ago),
    (SELECT count(*) FROM public.profiles
       WHERE last_seen >= v_month_ago),
    (SELECT count(*) FROM public.profiles),
    (SELECT count(*) FROM public.profiles
       WHERE created_at >= v_today_start),
    (SELECT count(*) FROM public.profiles
       WHERE last_seen < v_month_ago);
END;
$$;

REVOKE ALL ON FUNCTION public.admin_logs_counts() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_logs_counts()
  TO authenticated, service_role;

-- -----------------------------------------------------------------------------
-- (4) admin_list_couriers() RPC
-- -----------------------------------------------------------------------------
-- _part_data_loaders.dart → _loadCouriers() içindeki
-- `from('profiles').select('id, username, full_name, email, ...).eq('role','courier')`
-- çağrısı `email` ve `role` sütunları revoke edildiği için 42501
-- fırlatırdı. Courier listesi admin_list_users ile çekilemez çünkü
-- `delivered_count` döndürmez. Bu RPC ihtiyaç duyulan dar sütunlu
-- listeyi verir.

CREATE OR REPLACE FUNCTION public.admin_list_couriers()
RETURNS TABLE (
  id uuid,
  username text,
  full_name text,
  avatar_url text,
  is_online boolean,
  delivered_count integer,
  created_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT private.current_user_is_admin() THEN
    RAISE EXCEPTION 'admin_list_couriers: not admin' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT
    p.id,
    p.username,
    p.full_name,
    p.avatar_url,
    p.is_online,
    p.delivered_count,
    p.created_at
  FROM public.profiles p
  WHERE p.role = 'courier'::public.user_role
  ORDER BY p.created_at DESC;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_list_couriers() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_list_couriers()
  TO authenticated, service_role;

-- -----------------------------------------------------------------------------
-- (5) admin_profiles_minimal() RPC
-- -----------------------------------------------------------------------------
-- Çeşitli admin ekranlarında "yalnız id ve username/full_name/avatar_url"
-- gereken durumlar için ortak helper. profiles.role/is_admin/email
-- sütunlarına dokunmaz; PII sızdırmaz.

CREATE OR REPLACE FUNCTION public.admin_profiles_minimal(
  p_user_ids uuid[] DEFAULT NULL
)
RETURNS TABLE (
  id uuid,
  username text,
  full_name text,
  avatar_url text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT private.current_user_is_admin() THEN
    RAISE EXCEPTION 'admin_profiles_minimal: not admin' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT
    p.id,
    p.username,
    p.full_name,
    p.avatar_url
  FROM public.profiles p
  WHERE (p_user_ids IS NULL OR p.id = ANY(p_user_ids));
END;
$$;

REVOKE ALL ON FUNCTION public.admin_profiles_minimal(uuid[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_profiles_minimal(uuid[])
  TO authenticated, service_role;

-- -----------------------------------------------------------------------------
-- (6) admin_recent_active_users() RPC
-- -----------------------------------------------------------------------------
-- _part_data_loaders.dart → _loadLogsData() içindeki "recent users"
-- listesi admin_logs dashboard'unda "Son Aktif Kullanıcılar" altında
-- gösterilir. is_online + last_seen + full_name + username sütunlarını
-- last_seen DESC sırasıyla döner.

CREATE OR REPLACE FUNCTION public.admin_recent_active_users(
  p_limit integer DEFAULT 20
)
RETURNS TABLE (
  id uuid,
  username text,
  full_name text,
  avatar_url text,
  is_online boolean,
  last_seen timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT private.current_user_is_admin() THEN
    RAISE EXCEPTION 'admin_recent_active_users: not admin' USING ERRCODE = '42501';
  END IF;

  IF p_limit IS NULL OR p_limit < 1 OR p_limit > 200 THEN
    p_limit := 20;
  END IF;

  RETURN QUERY
  SELECT
    p.id,
    p.username,
    p.full_name,
    p.avatar_url,
    p.is_online,
    p.last_seen
  FROM public.profiles p
  WHERE p.last_seen IS NOT NULL
  ORDER BY p.last_seen DESC
  LIMIT p_limit;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_recent_active_users(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_recent_active_users(integer)
  TO authenticated, service_role;

-- -----------------------------------------------------------------------------
-- (7) admin_get_profile_email() RPC
-- -----------------------------------------------------------------------------
-- _part_shops.dart içindeki dükkan kartı `owner_email` gösterir.
-- `email` sütunu profiles'tan revoke edildiği için doğrudan select
-- mümkün değil. Bu RPC admin'in istediği tek bir profilde email
-- okumasına izin verir; sadece admin erişebilir.

CREATE OR REPLACE FUNCTION public.admin_get_profile_email(p_user_id uuid)
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_email text;
BEGIN
  IF NOT private.current_user_is_admin() THEN
    RAISE EXCEPTION 'admin_get_profile_email: not admin' USING ERRCODE = '42501';
  END IF;

  SELECT email INTO v_email FROM public.profiles WHERE id = p_user_id;
  RETURN v_email;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_get_profile_email(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_get_profile_email(uuid)
  TO authenticated, service_role;

-- -----------------------------------------------------------------------------
-- (8) admin_search_users() RPC
-- -----------------------------------------------------------------------------
-- Bakiye yükleme ve cüzdan yönetimi ekranlarında admin kullanıcıyı
-- full_name / phone / email / username alanlarında arar. Bu sütunların
-- tümü PII olduğu için doğrudan SELECT yapılamaz. RPC admin için
-- güvenli ILIKE araması yapar.

CREATE OR REPLACE FUNCTION public.admin_search_users(
  p_query text,
  p_limit integer DEFAULT 10
)
RETURNS TABLE (
  id uuid,
  username text,
  full_name text,
  avatar_url text,
  phone text,
  email text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_q text := trim(coalesce(p_query, ''));
BEGIN
  IF NOT private.current_user_is_admin() THEN
    RAISE EXCEPTION 'admin_search_users: not admin' USING ERRCODE = '42501';
  END IF;

  IF v_q = '' OR p_limit IS NULL OR p_limit < 1 OR p_limit > 50 THEN
    p_limit := 10;
  END IF;

  RETURN QUERY
  SELECT
    p.id,
    p.username,
    p.full_name,
    p.avatar_url,
    p.phone,
    p.email
  FROM public.profiles p
  WHERE p.full_name ILIKE '%' || v_q || '%'
     OR p.phone     ILIKE '%' || v_q || '%'
     OR p.email     ILIKE '%' || v_q || '%'
     OR p.username  ILIKE '%' || v_q || '%'
  ORDER BY p.created_at DESC NULLS LAST
  LIMIT p_limit;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_search_users(text, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_search_users(text, integer)
  TO authenticated, service_role;

-- -----------------------------------------------------------------------------
-- (9) admin_get_courier_profiles() RPC
-- -----------------------------------------------------------------------------
-- admin_package_requests_tab.dart içindeki "Atanan Kurye" satırı
-- full_name + phone gösterir. `phone` sütunu profiles'tan revoke
-- edildi; SECURITY DEFINER admin_search_users yerine toplu ID listesi
-- ile daha hızlı bir RPC tanımlıyoruz.

CREATE OR REPLACE FUNCTION public.admin_get_courier_profiles(
  p_user_ids uuid[]
)
RETURNS TABLE (
  id uuid,
  full_name text,
  phone text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT private.current_user_is_admin() THEN
    RAISE EXCEPTION 'admin_get_courier_profiles: not admin' USING ERRCODE = '42501';
  END IF;

  IF p_user_ids IS NULL OR array_length(p_user_ids, 1) = 0 THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    p.id,
    p.full_name,
    p.phone
  FROM public.profiles p
  WHERE p.id = ANY(p_user_ids);
END;
$$;

REVOKE ALL ON FUNCTION public.admin_get_courier_profiles(uuid[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_get_courier_profiles(uuid[])
  TO authenticated, service_role;

-- -----------------------------------------------------------------------------
-- (10) admin_get_owner_profile() RPC
-- -----------------------------------------------------------------------------
-- shop_detail_admin_screen.dart içindeki dükkan detay sayfası sahip
-- için full_name + email + phone gösterir. Bu üç sütun PII olduğu
-- için SECURITY DEFINER RPC üzerinden alınmalı.

CREATE OR REPLACE FUNCTION public.admin_get_owner_profile(p_user_id uuid)
RETURNS TABLE (
  id uuid,
  full_name text,
  email text,
  phone text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT private.current_user_is_admin() THEN
    RAISE EXCEPTION 'admin_get_owner_profile: not admin' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT
    p.id,
    p.full_name,
    p.email,
    p.phone
  FROM public.profiles p
  WHERE p.id = p_user_id;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_get_owner_profile(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_get_owner_profile(uuid)
  TO authenticated, service_role;

-- -----------------------------------------------------------------------------
-- Doğrulama: policy ve RPC'ler canlı mı?
-- -----------------------------------------------------------------------------

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_namespace WHERE nspname = 'private'
  ) THEN
    RAISE EXCEPTION 'private schema bulunamadı';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'private' AND p.proname = 'current_user_is_admin'
  ) THEN
    RAISE EXCEPTION 'private.current_user_is_admin helper bulunamadı';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'support_tickets'
      AND policyname = 'support_tickets_select_policy'
  ) THEN
    RAISE EXCEPTION 'support_tickets_select_policy bulunamadı';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'admin_dashboard_counts'
  ) THEN
    RAISE EXCEPTION 'admin_dashboard_counts RPC bulunamadı';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'admin_list_users'
  ) THEN
    RAISE EXCEPTION 'admin_list_users RPC bulunamadı';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'admin_logs_counts'
  ) THEN
    RAISE EXCEPTION 'admin_logs_counts RPC bulunamadı';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'admin_list_couriers'
  ) THEN
    RAISE EXCEPTION 'admin_list_couriers RPC bulunamadı';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'admin_profiles_minimal'
  ) THEN
    RAISE EXCEPTION 'admin_profiles_minimal RPC bulunamadı';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'admin_recent_active_users'
  ) THEN
    RAISE EXCEPTION 'admin_recent_active_users RPC bulunamadı';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'admin_get_profile_email'
  ) THEN
    RAISE EXCEPTION 'admin_get_profile_email RPC bulunamadı';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'admin_search_users'
  ) THEN
    RAISE EXCEPTION 'admin_search_users RPC bulunamadı';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'admin_get_courier_profiles'
  ) THEN
    RAISE EXCEPTION 'admin_get_courier_profiles RPC bulunamadı';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'admin_get_owner_profile'
  ) THEN
    RAISE EXCEPTION 'admin_get_owner_profile RPC bulunamadı';
  END IF;

  RAISE NOTICE 'admin_dashboard_counts migration başarıyla uygulandı';
END $$;

-- -----------------------------------------------------------------------------
-- PostgREST schema cache'i hemen yenile
-- -----------------------------------------------------------------------------
-- Yeni eklenen/altered SECURITY DEFINER RPC'ler PostgREST'in pg_proc
-- snapshot'unda hemen görünmüyor; ilk istek PGRST202 döndürüyor.
-- NOTIFY ile PostgREST'i bilgilendirip bir reload tetikliyoruz. Bu, yeni
-- migration'lar için Supabase'in önerdiği "reload schema" kalıbıdır.
NOTIFY pgrst, 'reload schema';

commit;
