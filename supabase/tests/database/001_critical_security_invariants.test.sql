-- =============================================================================
-- CizreApp kritik veritabanı güvenlik değişmezleri
--
-- Çalıştırma:
--   supabase start
--   supabase test db
--
-- Bu testler veri yazmaz. Katalog üzerinden şema, RLS, GRANT ve SECURITY
-- DEFINER ACL yapılandırmasını doğrular. Bir ihlal bulunduğunda pgTAP testi
-- başarısız olur ve CI/deploy süreci durdurulabilir.
-- =============================================================================

begin;

create extension if not exists pgtap with schema extensions;

select plan(38);

-- -----------------------------------------------------------------------------
-- Yardımcı test fonksiyonları
-- -----------------------------------------------------------------------------

create or replace function pg_temp.table_exists(p_table text)
returns boolean
language sql
stable
as $$
  select to_regclass(format('public.%I', p_table)) is not null;
$$;

create or replace function pg_temp.rls_enabled(p_table text)
returns boolean
language sql
stable
as $$
  select coalesce((
    select c.relrowsecurity
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relname = p_table
  ), false);
$$;

create or replace function pg_temp.has_write_policy_for_role(
  p_table text,
  p_role text
)
returns boolean
language sql
stable
as $$
  select exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = p_table
      and cmd in ('INSERT', 'UPDATE', 'DELETE', 'ALL')
      and (roles @> array[p_role]::name[] or roles @> array['public']::name[])
  );
$$;

-- -----------------------------------------------------------------------------
-- 1) Kritik tablolar var olmalı ve RLS açık olmalı
-- -----------------------------------------------------------------------------

select ok(pg_temp.table_exists('user_balances'), 'user_balances tablosu var');
select ok(pg_temp.rls_enabled('user_balances'), 'user_balances RLS açık');

select ok(pg_temp.table_exists('balance_transactions'), 'balance_transactions tablosu var');
select ok(pg_temp.rls_enabled('balance_transactions'), 'balance_transactions RLS açık');

select ok(pg_temp.table_exists('payment_transactions'), 'payment_transactions tablosu var');
select ok(pg_temp.rls_enabled('payment_transactions'), 'payment_transactions RLS açık');

select ok(pg_temp.table_exists('seller_withdrawals'), 'seller_withdrawals tablosu var');
select ok(pg_temp.rls_enabled('seller_withdrawals'), 'seller_withdrawals RLS açık');

select ok(pg_temp.table_exists('digital_orders'), 'digital_orders tablosu var');
select ok(pg_temp.rls_enabled('digital_orders'), 'digital_orders RLS açık');

select ok(pg_temp.table_exists('ad_reward_views'), 'ad_reward_views tablosu var');
select ok(pg_temp.rls_enabled('ad_reward_views'), 'ad_reward_views RLS açık');

select ok(pg_temp.table_exists('task_submissions'), 'task_submissions tablosu var');
select ok(pg_temp.rls_enabled('task_submissions'), 'task_submissions RLS açık');

select ok(pg_temp.table_exists('courier_requests'), 'courier_requests tablosu var');
select ok(pg_temp.rls_enabled('courier_requests'), 'courier_requests RLS açık');

-- -----------------------------------------------------------------------------
-- 2) Anon rolü kritik finans tablolarında hiçbir RLS policy ile eşleşmemeli.
-- Supabase public şemada rol bazında geniş tablo GRANT'leri kullanabildiği için
-- gerçek erişim sınırı RLS policy katmanıdır.
-- -----------------------------------------------------------------------------

select ok(
  not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'user_balances'
      and (roles @> array['anon']::name[] or roles @> array['public']::name[])
  ),
  'anon/public user_balances RLS policy bulunmuyor'
);

select ok(
  not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'balance_transactions'
      and (roles @> array['anon']::name[] or roles @> array['public']::name[])
  ),
  'anon/public balance_transactions RLS policy bulunmuyor'
);

select ok(
  not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'payment_transactions'
      and (roles @> array['anon']::name[] or roles @> array['public']::name[])
  ),
  'anon/public payment_transactions RLS policy bulunmuyor'
);

-- -----------------------------------------------------------------------------
-- 3) Authenticated rolü sunucuya özel tablolara doğrudan yazamamalı
-- RLS policy katmanı kontrol edilir.
-- -----------------------------------------------------------------------------

select ok(
  not pg_temp.has_write_policy_for_role('user_balances', 'authenticated'),
  'user_balances için authenticated/public yazma policy bulunmuyor'
);

select ok(
  not pg_temp.has_write_policy_for_role('balance_transactions', 'authenticated'),
  'balance_transactions için authenticated/public yazma policy bulunmuyor'
);

select ok(
  not pg_temp.has_write_policy_for_role('digital_orders', 'authenticated'),
  'digital_orders için authenticated/public yazma policy bulunmuyor'
);

select ok(
  not pg_temp.has_write_policy_for_role('ad_reward_views', 'authenticated'),
  'ad_reward_views için authenticated/public yazma policy bulunmuyor'
);

-- -----------------------------------------------------------------------------
-- 4) Iyzico secret kolonları istemci tarafından okunabilen tabloda bulunmamalı
-- -----------------------------------------------------------------------------

select ok(
  not exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'app_about_settings'
      and column_name = 'iyzico_api_key'
  ),
  'app_about_settings.iyzico_api_key kaldırılmış'
);

select ok(
  not exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'app_about_settings'
      and column_name = 'iyzico_secret_key'
  ),
  'app_about_settings.iyzico_secret_key kaldırılmış'
);

-- -----------------------------------------------------------------------------
-- 4b) AI sağlayıcı secret kolonları world-readable ai_settings tablosundan
-- kaldırılmış olmalı (vault.secrets'e taşındı).
-- -----------------------------------------------------------------------------

select ok(
  not exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'ai_settings'
      and column_name = 'gemini_api_key'
  ),
  'ai_settings.gemini_api_key kaldırılmış'
);

select ok(
  not exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'ai_settings'
      and column_name = 'groq_api_key'
  ),
  'ai_settings.groq_api_key kaldırılmış'
);

select ok(
  not exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'ai_settings'
      and column_name = 'openrouter_api_key'
  ),
  'ai_settings.openrouter_api_key kaldırılmış'
);

select ok(
  not exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'ai_settings'
      and column_name = 'openai_api_key'
  ),
  'ai_settings.openai_api_key kaldırılmış'
);

-- -----------------------------------------------------------------------------
-- 5) Para mutasyonu yapan SECURITY DEFINER fonksiyonları istemci rollerine
-- açık olmamalı. Authenticated kullanıma açık diğer SECURITY DEFINER RPC'ler
-- kendi sahiplik/admin kontrollerini yaptıkları için bu listeye dahil değildir.
-- -----------------------------------------------------------------------------

select ok(
  not exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prosecdef
      and p.proname = any(array[
        'add_to_balance',
        'atomic_add_balance_topup',
        'atomic_add_balance_topup_secure',
        'atomic_finalize_payment_transaction',
        'grant_ad_reward'
      ])
      and (
        has_function_privilege('public', p.oid, 'EXECUTE')
        or has_function_privilege('anon', p.oid, 'EXECUTE')
        or has_function_privilege('authenticated', p.oid, 'EXECUTE')
      )
  ),
  'Sunucuya özel para mutasyon RPC fonksiyonları istemci rollerine kapalı'
);

select ok(
  not exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'deduct_from_balance'
      and (
        has_function_privilege('public', p.oid, 'EXECUTE')
        or has_function_privilege('anon', p.oid, 'EXECUTE')
      )
  ),
  'deduct_from_balance PUBLIC/anon rollerine kapalı'
);

-- -----------------------------------------------------------------------------
-- 6) add_to_balance tüm overload'ları PUBLIC/anon/authenticated'a kapalı,
-- yalnız service_role'a açık olmalı (2026-08-02 kritik hardening).
-- -----------------------------------------------------------------------------

select ok(
  not exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'add_to_balance'
      and (
        has_function_privilege('public', p.oid, 'EXECUTE')
        or has_function_privilege('anon', p.oid, 'EXECUTE')
        or has_function_privilege('authenticated', p.oid, 'EXECUTE')
      )
  ),
  'add_to_balance tüm overloadları PUBLIC/anon/authenticated rollerine kapalı'
);

select ok(
  not exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'add_to_balance'
      and not has_function_privilege('service_role', p.oid, 'EXECUTE')
  ),
  'add_to_balance tüm overloadları service_role tarafından çalıştırılabilir'
);

-- -----------------------------------------------------------------------------
-- 7) admin_cancel_courier_request_with_refund RPC'si PUBLIC/anon'a kapalı,
-- authenticated ve service_role'a açık olmalı.
-- -----------------------------------------------------------------------------

select ok(
  exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'admin_cancel_courier_request_with_refund'
      and p.prosecdef
  ),
  'admin_cancel_courier_request_with_refund SECURITY DEFINER olarak tanımlı'
);

select ok(
  not exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'admin_cancel_courier_request_with_refund'
      and (
        has_function_privilege('public', p.oid, 'EXECUTE')
        or has_function_privilege('anon', p.oid, 'EXECUTE')
      )
  ),
  'admin_cancel_courier_request_with_refund PUBLIC/anon rollerine kapalı'
);

select ok(
  exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'admin_cancel_courier_request_with_refund'
      and has_function_privilege('authenticated', p.oid, 'EXECUTE')
      and has_function_privilege('service_role', p.oid, 'EXECUTE')
  ),
  'admin_cancel_courier_request_with_refund authenticated ve service_role için erişilebilir'
);

-- RPC gövdesi search_path güvenliği (sabit değer) kullanmalı
select ok(
  (
    select coalesce(
      array_position(p.proconfig, 'search_path=public, pg_temp') is not null
      or array_position(p.proconfig, 'search_path=public') is not null,
      false
    )
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'admin_cancel_courier_request_with_refund'
    limit 1
  ),
  'admin_cancel_courier_request_with_refund sabit search_path kullanıyor'
);

-- -----------------------------------------------------------------------------
-- 8) Güvensiz özel password reset OTP sistemi kaldırıldı (2026-08-02).
-- verify_password_reset_otp RPC'si ve password_reset_otps tablosu artık
-- şemada bulunmamalı. registration_otps ve verify_registration_otp
-- bilinçli olarak korunur.
-- -----------------------------------------------------------------------------

select ok(
  not exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'verify_password_reset_otp'
  ),
  'verify_password_reset_otp fonksiyonu şemadan kaldırıldı'
);

select ok(
  to_regclass('public.password_reset_otps') is null,
  'password_reset_otps tablosu kaldırıldı'
);

-- registration_otps bilinçli korunuyor
select ok(
  to_regclass('public.registration_otps') is not null,
  'registration_otps tablosu korunuyor (bu migration kapsamı dışı)'
);

-- verify_registration_otp bilinçli korunuyor
select ok(
  exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'verify_registration_otp'
  ),
  'verify_registration_otp fonksiyonu korunuyor (bu migration kapsamı dışı)'
);

select * from finish();

rollback;
