-- =============================================================================
-- 20260803000006_profile_security_audit.sql
-- Salt okunur audit raporu. T.C. kimlik numarası, e-posta, telefon, adres,
-- fatura bilgisi veya silme kodu gibi PII verileri döndürmez. Yalnız:
--   * sayım
--   * null/non-null durumu
--   * id, created_at, updated_at, role, is_admin
--   * sütun adı, politika adı, fonksiyon adı, grant yapısı
-- gibi audit için gerekli minimum bilgiyi verir.
--
-- Çalıştırma:
--   psql "$DATABASE_URL" -f supabase/tests/20260803000006_profile_security_audit.sql
-- veya
--   supabase db remote execute --file supabase/tests/20260803000006_profile_security_audit.sql
--   ya da Supabase SQL Editor'a yapıştır ve çalıştır
--
-- Bu dosya veri yazmaz; hiçbir UPDATE/INSERT/DELETE/DROP içermez.
-- =============================================================================

-- 1) role='admin' olan hesapların id, oluşturulma ve son güncelleme tarihi
--    (PII yok; yalnız id + tarih).
SELECT '=== 1) role=admin hesapları ===' AS "===";
SELECT
  p.id,
  p.role,
  p.is_admin,
  p.created_at,
  p.updated_at,
  (p.email IS NOT NULL) AS has_email,
  (p.phone IS NOT NULL) AS has_phone
FROM public.profiles p
WHERE p.role = 'admin'::public.user_role
ORDER BY p.created_at DESC;

-- 2) role/is_admin uyuşmazlığı: is_admin=true ama role<>admin veya tersi
SELECT '=== 2) role/is_admin uyuşmazlıkları ===' AS "===";
SELECT
  p.id,
  p.role,
  p.is_admin,
  p.created_at
FROM public.profiles p
WHERE (p.is_admin = true AND p.role <> 'admin'::public.user_role)
   OR (p.is_admin = false AND p.role = 'admin'::public.user_role)
ORDER BY p.created_at DESC;

-- 3) auth.users'ta olup profiles'ta olmayan kullanıcılar
SELECT '=== 3) auth.users olup profiles''ta olmayanlar ===' AS "===";
SELECT
  u.id,
  u.created_at,
  (u.email IS NOT NULL) AS has_email
FROM auth.users u
LEFT JOIN public.profiles p ON p.id = u.id
WHERE p.id IS NULL
ORDER BY u.created_at DESC;

-- 4) role dağılımı
SELECT '=== 4) role dağılımı ===' AS "===";
SELECT
  COALESCE(p.role::text, 'NULL') AS role_value,
  count(*) AS row_count
FROM public.profiles p
GROUP BY p.role
ORDER BY row_count DESC;

-- 5) profiles.role CHECK constraint
SELECT '=== 5) profiles.role CHECK constraint ===' AS "===";
SELECT
  con.conname AS constraint_name,
  pg_get_constraintdef(con.oid) AS definition
FROM pg_constraint con
JOIN pg_class rel ON rel.oid = con.conrelid
WHERE rel.relname = 'profiles'
  AND con.contype = 'c'
  AND pg_get_constraintdef(con.oid) ILIKE '%role%';

-- 6) profiles trigger'ları
SELECT '=== 6) profiles trigger listesi ===' AS "===";
SELECT
  t.tgname AS trigger_name,
  p.proname AS function_name,
  CASE t.tgtype::int & 2 WHEN 2 THEN 'BEFORE' ELSE 'AFTER' END AS timing,
  CASE t.tgtype::int & 28
    WHEN 4 THEN 'INSERT'
    WHEN 8 THEN 'DELETE'
    WHEN 16 THEN 'UPDATE'
    WHEN 20 THEN 'INSERT OR UPDATE'
    WHEN 28 THEN 'INSERT OR UPDATE OR DELETE'
    ELSE 'OTHER'
  END AS event
FROM pg_trigger t
JOIN pg_proc p ON p.oid = t.tgfoid
JOIN pg_class rel ON rel.oid = t.tgrelid
WHERE rel.relname = 'profiles'
  AND NOT t.tgisinternal
ORDER BY t.tgname;

-- 7) profiles RLS politikaları
SELECT '=== 7) profiles RLS politikaları ===' AS "===";
SELECT
  p.policyname,
  p.cmd,
  p.roles,
  p.qual,
  p.with_check
FROM pg_policies p
WHERE p.schemaname = 'public' AND p.tablename = 'profiles'
ORDER BY p.policyname;

-- 8) role/is_admin/is_suspicious kullanan fonksiyonlar
SELECT '=== 8) role/is_admin/is_suspicious kullanan fonksiyonlar ===' AS "===";
SELECT
  p.proname AS function_name,
  pg_get_functiondef(p.oid) LIKE '%is_admin%' AS uses_is_admin,
  pg_get_functiondef(p.oid) LIKE '%is_suspicious%' AS uses_is_suspicious,
  p.prosecdef AS is_security_definer,
  CASE WHEN p.proacl::text LIKE '%anon%' THEN 'anon' END AS grant_to_anon,
  CASE WHEN p.proacl::text LIKE '%authenticated%' THEN 'authenticated' END AS grant_to_authenticated
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public'
  AND (
    pg_get_functiondef(p.oid) LIKE '%is_admin%'
    OR pg_get_functiondef(p.oid) LIKE '%is_suspicious%'
    OR pg_get_functiondef(p.oid) LIKE '%public.user_role%'
  )
ORDER BY p.proname;

-- 9) profiles tablo ve sütun grant'leri
SELECT '=== 9) profiles tablo grant''leri ===' AS "===";
SELECT
  grantee,
  string_agg(DISTINCT privilege_type, ', ' ORDER BY privilege_type) AS privileges
FROM information_schema.role_table_grants
WHERE table_schema = 'public' AND table_name = 'profiles'
  AND grantee IN ('anon', 'authenticated', 'service_role')
GROUP BY grantee
ORDER BY grantee;

SELECT '=== 9.b) profiles sütun grant''leri (anon/authenticated) ===' AS "===";
SELECT
  grantee,
  count(*) AS granted_columns
FROM information_schema.column_privileges
WHERE table_schema = 'public' AND table_name = 'profiles'
  AND grantee IN ('anon', 'authenticated')
GROUP BY grantee
ORDER BY grantee;

-- 10) public_profiles_safe view sütunları
SELECT '=== 10) public_profiles_safe view sütunları ===' AS "===";
SELECT
  a.attname AS column_name,
  format_type(a.atttypid, a.atttypmod) AS data_type
FROM pg_attribute a
JOIN pg_class c ON c.oid = a.attrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relname = 'public_profiles_safe'
  AND a.attnum > 0
  AND NOT a.attisdropped
ORDER BY a.attnum;

-- 11) public_profiles_safe'de sızıntı taraması
SELECT '=== 11) public_profiles_safe sızıntı taraması ===' AS "===";
SELECT
  'public_profiles_safe' AS view_name,
  count(*) AS sensitive_column_count
FROM pg_attribute a
JOIN pg_class c ON c.oid = a.attrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relname = 'public_profiles_safe'
  AND a.attname IN (
    'email','phone','invoice_tc_no','invoice_tax_number','invoice_tax_office',
    'invoice_address','invoice_email','invoice_full_name','invoice_type',
    'invoice_saved_at',
    'is_suspicious','suspicious_reason','suspicious_flagged_at',
    'delete_confirmation_code','delete_confirmation_expires_at',
    'last_known_lat','last_known_lng','last_location_update',
    'is_admin','role'
  );

-- 12) realtime publication durumu
SELECT '=== 12) profiles realtime publication durumu ===' AS "===";
SELECT
  pub.pubname,
  EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = pub.pubname AND tablename = 'profiles'
  ) AS profiles_in_publication
FROM pg_publication pub
WHERE pub.pubname = 'supabase_realtime';

-- 13) profile_role_change_audit toplam kayıt
SELECT '=== 13) profile_role_change_audit toplam kayıt ===' AS "===";
SELECT count(*) AS total_audit_records
FROM public.profile_role_change_audit;

-- 14) handle_new_user imzası ve EXECUTE grant'leri
SELECT '=== 14) handle_new_user signature/EXECUTE ===' AS "===";
SELECT
  p.proname,
  pg_get_function_identity_arguments(p.oid) AS arguments,
  p.prosecdef AS is_security_definer,
  CASE WHEN p.proacl::text LIKE '%anon%' THEN 'anon' END AS grant_to_anon,
  CASE WHEN p.proacl::text LIKE '%authenticated%' THEN 'authenticated' END AS grant_to_authenticated,
  CASE WHEN p.proacl::text LIKE '%service_role%' THEN 'service_role' END AS grant_to_service_role
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public' AND p.proname = 'handle_new_user';

-- 15) private.current_user_is_admin imzası
SELECT '=== 15) private.current_user_is_admin ===' AS "===";
SELECT
  p.proname,
  pg_get_function_identity_arguments(p.oid) AS arguments,
  p.prosecdef AS is_security_definer,
  CASE WHEN p.proacl::text LIKE '%authenticated%' THEN 'authenticated' END AS grant_to_authenticated,
  CASE WHEN p.proacl::text LIKE '%service_role%' THEN 'service_role' END AS grant_to_service_role
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'private' AND p.proname = 'current_user_is_admin';

-- 16) public.is_admin() delegasyonu
SELECT '=== 16) public.is_admin() imzası ===' AS "===";
SELECT
  p.proname,
  pg_get_function_identity_arguments(p.oid) AS arguments,
  p.prosecdef AS is_security_definer,
  p.proconfig AS config_settings,
  CASE WHEN p.proacl::text LIKE '%authenticated%' THEN 'authenticated' END AS grant_to_authenticated,
  CASE WHEN p.proacl::text LIKE '%service_role%' THEN 'service_role' END AS grant_to_service_role
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public' AND p.proname = 'is_admin';

-- Audit sonu
SELECT '=== AUDIT TAMAMLANDI ===' AS "===";
