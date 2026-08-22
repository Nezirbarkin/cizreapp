-- =============================================================================
-- admin_user_list_with_stats RPC değişmezleri (pgTAP)
-- Çalıştırma: supabase test db supabase/tests/database
--
-- Bu paket 20260810000004_admin_user_list_with_stats.sql migration'ının
-- yüklediği RPC'nin sözleşmesini ve güvenlik özelliklerini doğrular:
--   * RPC mevcut ve doğru argüman imzasında,
--   * PII (email/phone) ve istatistik sütunları dönüşte var,
--   * yalnız authenticated + service_role EXECUTE edebilir (anon hariç),
--   * SECURITY DEFINER + SET search_path = '' (mevcut admin RPC'leriyle uyumlu).
--
-- Not: RPC, private.current_user_is_admin() ile gerçek-admin kapısını çalışma
-- zamanında uygular. pgTAP ortamında auth.uid() taklit edilmediğinden burada
-- davranışsal (non-admin reddi) testi değil, yapısal değişmezleri denetleriz;
-- davranışsal koruma 20260803000006 test paketinde current_user_is_admin ile
-- sabitlenmiştir.
-- =============================================================================

begin;

create extension if not exists pgtap with schema extensions;

select plan(12);

-- -----------------------------------------------------------------------------
-- Yardımcılar
-- -----------------------------------------------------------------------------

-- Bir fonksiyonun verilen rol tarafından EXECUTE yetkisi var mı?
create or replace function pg_temp.function_executable_by(
  p_schema text, p_name text, p_role text
)
returns boolean
language sql
stable
as $$
  select exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = p_schema
      and p.proname = p_name
      and has_function_privilege(p_role, p.oid, 'EXECUTE')
  );
$$;

-- Bir fonksiyonun dönüş türü metninde (pg_get_function_result) bir sütun
-- parçası var mı? Büyük/küçük harf duyarsız, joker/regex yoksuz (position).
create or replace function pg_temp.function_result_has_column(
  p_signature text, p_fragment text
)
returns boolean
language sql
stable
as $$
  select position(
    lower(p_fragment)
    in lower(pg_get_function_result(p_signature::regprocedure))
  ) > 0;
$$;

-- -----------------------------------------------------------------------------
-- 1) RPC mevcut, doğru imzada
-- -----------------------------------------------------------------------------

select has_function(
  'public', 'admin_user_list_with_stats',
  array['text', 'text', 'integer']::text[],
  'admin_user_list_with_stats mevcut (text,text,integer)'
);

-- -----------------------------------------------------------------------------
-- 2) EXECUTE yetkileri: authenticated + service_role EVET, anon HAYIR (PII)
-- -----------------------------------------------------------------------------

select ok(
  pg_temp.function_executable_by('public', 'admin_user_list_with_stats', 'authenticated'),
  'admin_user_list_with_stats authenticated EXECUTE var'
);

select ok(
  pg_temp.function_executable_by('public', 'admin_user_list_with_stats', 'service_role'),
  'admin_user_list_with_stats service_role EXECUTE var'
);

select ok(
  not pg_temp.function_executable_by('public', 'admin_user_list_with_stats', 'anon'),
  'admin_user_list_with_stats anon EXECUTE YOK (PII email/phone)'
);

-- -----------------------------------------------------------------------------
-- 3) Dönüş sütunları: email, phone (PII) + istatistikler
-- -----------------------------------------------------------------------------

select ok(
  pg_temp.function_result_has_column(
    'public.admin_user_list_with_stats(text,text,integer)', 'email text'),
  'dönüşte email sütunu var'
);

select ok(
  pg_temp.function_result_has_column(
    'public.admin_user_list_with_stats(text,text,integer)', 'phone text'),
  'dönüşte phone sütunu var'
);

select ok(
  pg_temp.function_result_has_column(
    'public.admin_user_list_with_stats(text,text,integer)', 'posts_count bigint'),
  'dönüşte posts_count bigint sütunu var'
);

select ok(
  pg_temp.function_result_has_column(
    'public.admin_user_list_with_stats(text,text,integer)', 'followers_count bigint'),
  'dönüşte followers_count bigint sütunu var'
);

select ok(
  pg_temp.function_result_has_column(
    'public.admin_user_list_with_stats(text,text,integer)', 'following_count bigint'),
  'dönüşte following_count bigint sütunu var'
);

select ok(
  pg_temp.function_result_has_column(
    'public.admin_user_list_with_stats(text,text,integer)', 'delivered_count integer'),
  'dönüşte delivered_count integer sütunu var'
);

-- -----------------------------------------------------------------------------
-- 4) Sertleştirme: SECURITY DEFINER + SET search_path = ''
-- -----------------------------------------------------------------------------

select ok(
  (
    select p.prosecdef
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'admin_user_list_with_stats'
  ),
  'admin_user_list_with_stats SECURITY DEFINER'
);

select ok(
  exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'admin_user_list_with_stats'
      and exists (
        select 1 from unnest(p.proconfig) as c where c like 'search_path=%'
      )
  ),
  'admin_user_list_with_stats search_path sabitlenmiş'
);

select * from finish();

rollback;
