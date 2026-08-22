-- =============================================================================
-- posts_with_profiles view'ı: korumalı sütun erişim regresyon testi (pgTAP)
--
-- context: 20260812000001_fix_posts_with_profiles_protected_columns.sql
--   security_invoker=true view, anon/authenticated'ın profiles sütun-bazlı
--   SELECT yetkilerine bağlı. Eskiden view pr.role / pr.is_admin seçiyordu;
--   bu sütunların GRANT'ı yok → "permission denied for table profiles" (42501).
--   Bu test, fix sonrası anon/authenticated rollerinde view sorgusunun hata
--   fırlatMAdığını (izin engeli çıkmadığını) doğrular.
--
-- Çalıştırma: supabase test db supabase/tests/database
-- =============================================================================

begin;

create extension if not exists pgtap with schema extensions;

select plan(3);

-- -----------------------------------------------------------------------------
-- 1) authenticated rolüyle view sorgulanabilmeli (42501 regressyonu)
-- -----------------------------------------------------------------------------
set role authenticated;
select lives_ok(
  $$ select * from public.posts_with_profiles limit 1 $$,
  'authenticated posts_with_profiles sorgulayabilir (permission denied yok)'
);
reset role;

-- -----------------------------------------------------------------------------
-- 2) anon rolüyle de view sorgulanabilmeli (logout/önce-auth feed senaryosu)
-- -----------------------------------------------------------------------------
set role anon;
select lives_ok(
  $$ select * from public.posts_with_profiles limit 1 $$,
  'anon posts_with_profiles sorgulayabilir (permission denied yok)'
);
reset role;

-- -----------------------------------------------------------------------------
-- 3) View tanımı pr.role / pr.is_admin referansı içermemeli (regresyon guard)
--    Bu sütunların GRANT'ı yok; security_invoker view'da referans = 42501.
-- -----------------------------------------------------------------------------
select ok(
  position('pr.role' in pg_get_viewdef('public.posts_with_profiles'::regclass, true)) = 0
    and position('pr.is_admin' in pg_get_viewdef('public.posts_with_profiles'::regclass, true)) = 0,
  'view tanımında pr.role / pr.is_admin referansı yok (korumalı sütunlar)'
);

select * from finish();

rollback;
