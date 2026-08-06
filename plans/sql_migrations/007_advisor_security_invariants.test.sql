-- =============================================================================
-- CizreApp Supabase Security Advisor değişmezleri
--
-- Çalıştırma:
--   supabase start
--   supabase db reset
--   supabase test db
--
-- [`20260804000002_fix_advisor_security_lints.sql`](../migrations/20260804000002_fix_advisor_security_lints.sql:1)
-- ile kapatılan Security Advisor lint'lerinin geri gelmediğini doğrular:
--   * function_search_path_mutable       (0011)
--   * extension_in_public                (0014)
--   * public_bucket_allows_listing       (0025)
--   * anon SECURITY DEFINER — verify_password_reset_otp (0028)
--
-- Ayrıca, düzeltmenin bilerek KORUDUĞU erişimleri de doğrular. Bunlar
-- regresyon açısından en az lint'ler kadar önemlidir: geçmişte toplu REVOKE
-- uygulamak kayıt akışını, misafir ulaşım haritasını ve RLS değerlendirmesini
-- kıracaktı.
-- =============================================================================

begin;

create extension if not exists pgtap with schema extensions;

select plan(10);

-- -----------------------------------------------------------------------------
-- 1) function_search_path_mutable
--    Extension'a ait fonksiyonlar hariç tutulur: cube/earthdistance kendi
--    fonksiyonlarını getirir, onların proconfig'ini değiştirmek extension
--    sahipliğini bozar ve Advisor da onları hedeflemez.
-- -----------------------------------------------------------------------------
select is(
  (
    select coalesce(string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text), '')
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prokind in ('f', 'p')
      and not exists (
        select 1 from pg_depend d
        where d.classid = 'pg_proc'::regclass and d.objid = p.oid and d.deptype = 'e'
      )
      and not exists (
        select 1 from unnest(coalesce(p.proconfig, array[]::text[])) as cfg
        where cfg like 'search\_path=%'
      )
  )::text,
  ''::text,
  'search_path sabitlenmemiş proje fonksiyonu yok'
);

-- -----------------------------------------------------------------------------
-- 2) extension_in_public
-- -----------------------------------------------------------------------------
select is(
  (
    select coalesce(string_agg(e.extname, ', ' order by e.extname), '')
    from pg_extension e
    join pg_namespace n on n.oid = e.extnamespace
    where n.nspname = 'public'
      and e.extname not in ('plpgsql')
  )::text,
  ''::text,
  'public şemasında extension yok'
);

-- Taşımanın yan etkisi: earth fonksiyonlarını şemasız çağıran fonksiyonların
-- search_path'inde extensions bulunmalı, yoksa çalışma anında patlarlar.
select is(
  (
    select coalesce(string_agg(p.proname, ', ' order by p.proname), '')
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prosrc ~* '\m(ll_to_earth|earth_distance|earth_box|geo_distance)\s*\('
      and not exists (
        select 1 from pg_depend d
        where d.classid = 'pg_proc'::regclass and d.objid = p.oid and d.deptype = 'e'
      )
      and not exists (
        select 1 from unnest(coalesce(p.proconfig, array[]::text[])) as cfg
        where cfg like 'search\_path=%' and cfg ~ '(^|=|,\s*)extensions(\s*,|$)'
      )
  )::text,
  ''::text,
  'earth_distance/ll_to_earth kullanan fonksiyonların search_path''inde extensions var'
);

-- -----------------------------------------------------------------------------
-- 3) public_bucket_allows_listing — news-images
-- -----------------------------------------------------------------------------
select is(
  (
    select count(*)
    from pg_policies
    where schemaname = 'storage'
      and tablename  = 'objects'
      and cmd in ('SELECT', 'ALL')
      and coalesce(qual, '') like '%news-images%'
  )::bigint,
  0::bigint,
  'news-images public bucket''ında geniş SELECT (listeleme) policy''si yok'
);

-- -----------------------------------------------------------------------------
-- 4) anon SECURITY DEFINER — kaldırılan güvensiz OTP RPC'si
-- -----------------------------------------------------------------------------
select is(
  (
    select count(*)
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'verify_password_reset_otp'
  )::bigint,
  0::bigint,
  'güvensiz verify_password_reset_otp RPC''si veritabanında yok'
);

-- -----------------------------------------------------------------------------
-- 5) BİLEREK KORUNAN erişimler — bunları kaybetmek üretimde kırılma demektir
-- -----------------------------------------------------------------------------

-- Kayıt akışı: anon çağıramazsa kimse kayıt olamaz.
select ok(
  has_function_privilege('anon', 'public.verify_registration_otp(text, text)', 'EXECUTE'),
  'anon verify_registration_otp çağırabiliyor (kayıt akışı)'
);

-- Misafir ulaşım haritası: uygulamada guest modu var, bu RPC'ler anon'a açık.
select ok(
  has_function_privilege('anon', 'public.get_sehirici_lines_with_stops(uuid)', 'EXECUTE'),
  'anon get_sehirici_lines_with_stops çağırabiliyor (misafir ulaşım haritası)'
);

-- RLS yardımcısı: policy ifadeleri sorguyu yapan rolün yetkisiyle değerlendirilir.
-- Bu EXECUTE kaybolursa authenticated için tüm RLS değerlendirmesi hata verir.
select ok(
  has_function_privilege('authenticated', 'public.is_admin(uuid)', 'EXECUTE'),
  'authenticated is_admin çağırabiliyor (RLS policy yardımcısı)'
);

-- -----------------------------------------------------------------------------
-- 6) EXECUTE sertleştirmesinin değişmezleri
--    ([`20260804000003`](../migrations/20260804000003_revoke_client_unreachable_rpc_execute.sql:1))
-- -----------------------------------------------------------------------------

-- RLS policy / CHECK / DEFAULT / index / trigger tarafından kullanılan hiçbir
-- fonksiyon istemci rollerine kapatılmamış olmalı. Kapanırsa ilgili tablolarda
-- SELECT veya INSERT çalışma anında yetki hatası verir.
select is(
  (
    select coalesce(string_agg(distinct p.oid::regprocedure::text, ', '), '')
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and exists (
        select 1 from pg_depend d
        where d.refclassid = 'pg_proc'::regclass
          and d.refobjid   = p.oid
          and d.classid in (
            'pg_policy'::regclass, 'pg_constraint'::regclass,
            'pg_attrdef'::regclass, 'pg_class'::regclass, 'pg_trigger'::regclass
          )
      )
      and not has_function_privilege('authenticated', p.oid, 'EXECUTE')
  )::text,
  ''::text,
  'policy/CHECK/DEFAULT tarafından kullanılan fonksiyonların EXECUTE yetkisi korunmuş'
);

-- Sertleştirilen her fonksiyonda service_role yolu açık kalmalı; aksi halde
-- Edge Function''lar (28 tanesi service_role kullanıyor) kırılır.
select is(
  (
    select coalesce(string_agg(r.function_signature, ', ' order by r.function_signature), '')
    from (select distinct function_signature from private.client_execute_revocations) r
    where to_regprocedure(r.function_signature) is not null
      and not has_function_privilege('service_role', to_regprocedure(r.function_signature), 'EXECUTE')
  )::text,
  ''::text,
  'EXECUTE kaldırılan fonksiyonlarda service_role yolu açık (Edge Function''lar çalışır)'
);

-- Sonuç
select * from finish();

rollback;
