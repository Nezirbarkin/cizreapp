-- =============================================================================
-- Kurye finansal RPC'ler ve PII güvenlik testleri (pgTAP)
-- -----------------------------------------------------------------------------
-- Bu test veri yazmaz (yalnız katalog/RPC çağrılarında örnek veri gerektiren
-- testler pgTAP lives_ok/throws_ok üzerinden rollback yapar).
-- Çalıştırma: supabase test db
-- =============================================================================

begin;

create extension if not exists pgtap with schema extensions;

select plan(28);

-- -----------------------------------------------------------------------------
-- Yardımcı fonksiyonlar
-- -----------------------------------------------------------------------------
create or replace function pg_temp.has_policy(p_table text, p_cmd text, p_role text)
returns boolean
language sql stable
as $$
  select exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = p_table
      and cmd = p_cmd
      and (roles @> array[p_role]::name[] or roles @> array['public']::name[])
  );
$$;

create or replace function pg_temp.has_function(p_name text)
returns boolean
language sql stable
as $$
  select exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = p_name
  );
$$;

create or replace function pg_temp.rls_revoke_check(
  p_table text,
  p_privilege text
)
returns boolean
language sql stable
as $$
  select not exists (
    select 1
    from information_schema.role_table_grants rtg
    where rtg.table_schema = 'public'
      and rtg.table_name = p_table
      and rtg.privilege_type = p_privilege
      and rtg.grantee = 'authenticated'
  );
$$;

-- -----------------------------------------------------------------------------
-- 1) Yeni RPC'ler mevcut mu?
-- -----------------------------------------------------------------------------
select ok(pg_temp.has_function('create_package_request'),
  'create_package_request RPC mevcut');
select ok(pg_temp.has_function('list_available_package_requests'),
  'list_available_package_requests RPC mevcut');
select ok(pg_temp.has_function('accept_package_request'),
  'accept_package_request RPC mevcut');
select ok(pg_temp.has_function('reject_package_request'),
  'reject_package_request RPC mevcut');
select ok(pg_temp.has_function('request_package_delivery_confirmation'),
  'request_package_delivery_confirmation RPC mevcut');
select ok(pg_temp.has_function('confirm_package_delivery'),
  'confirm_package_delivery RPC mevcut');
select ok(pg_temp.has_function('admin_resolve_package_dispute'),
  'admin_resolve_package_dispute RPC mevcut');
select ok(pg_temp.has_function('request_courier_payout'),
  'request_courier_payout RPC mevcut');
select ok(pg_temp.has_function('admin_approve_courier_payout'),
  'admin_approve_courier_payout RPC mevcut');
select ok(pg_temp.has_function('admin_reject_courier_payout'),
  'admin_reject_courier_payout RPC mevcut');
select ok(pg_temp.has_function('get_assigned_package_details'),
  'get_assigned_package_details RPC mevcut');
select ok(pg_temp.has_function('get_available_orders_for_courier'),
  'get_available_orders_for_courier RPC mevcut');
select ok(pg_temp.has_function('get_courier_active_orders'),
  'get_courier_active_orders RPC mevcut');

-- -----------------------------------------------------------------------------
-- 2) RLS politikaları temizlenmiş mi + doğru mu?
-- -----------------------------------------------------------------------------
-- Eski politikalar artık mevcut olmamalı
select ok(not exists (
  select 1 from pg_policies
  where schemaname = 'public' and tablename = 'courier_requests'
    and policyname in (
      'courier_requests_authenticated',
      'Users can view own courier requests',
      'Couriers can update assigned requests',
      'courier_requests_select_scoped',
      'courier_requests_insert_sender',
      'courier_requests_update_courier_or_admin',
      'courier_requests_delete_sender_or_admin'
    )
), 'Eski courier_requests politikaları tamamen kaldırıldı');

select ok(not exists (
  select 1 from pg_policies
  where schemaname = 'public' and tablename = 'courier_earnings'
    and policyname in (
      'Admins update earnings', 'Admins view all earnings',
      'Couriers insert own earnings', 'Couriers view own earnings'
    )
), 'Eski courier_earnings politikaları kaldırıldı');

select ok(not exists (
  select 1 from pg_policies
  where schemaname = 'public' and tablename = 'courier_payout_requests'
    and policyname in (
      'Admins update payouts', 'Admins view all payouts',
      'Couriers create payouts', 'Couriers view own payouts'
    )
), 'Eski courier_payout_requests politikaları kaldırıldı');

-- Yeni politikalar var
select ok(pg_temp.has_policy('courier_requests', 'SELECT', 'authenticated'),
  'courier_requests SELECT policy (authenticated) mevcut');
select ok(pg_temp.has_policy('courier_earnings', 'SELECT', 'authenticated'),
  'courier_earnings SELECT policy (authenticated) mevcut');
select ok(pg_temp.has_policy('courier_payout_requests', 'SELECT', 'authenticated'),
  'courier_payout_requests SELECT policy (authenticated) mevcut');

-- authenticated'ın INSERT/UPDATE/DELETE grant'i kaldırılmış mı?
select ok(pg_temp.rls_revoke_check('courier_earnings', 'INSERT'),
  'authenticated courier_earnings INSERT yapamaz');
select ok(pg_temp.rls_revoke_check('courier_earnings', 'UPDATE'),
  'authenticated courier_earnings UPDATE yapamaz');
select ok(pg_temp.rls_revoke_check('courier_earnings', 'DELETE'),
  'authenticated courier_earnings DELETE yapamaz');
select ok(pg_temp.rls_revoke_check('courier_payout_requests', 'INSERT'),
  'authenticated courier_payout_requests INSERT yapamaz');
select ok(pg_temp.rls_revoke_check('courier_payout_requests', 'UPDATE'),
  'authenticated courier_payout_requests UPDATE yapamaz');
select ok(pg_temp.rls_revoke_check('courier_payout_requests', 'DELETE'),
  'authenticated courier_payout_requests DELETE yapamaz');
select ok(pg_temp.rls_revoke_check('courier_requests', 'UPDATE'),
  'authenticated courier_requests UPDATE yapamaz');
select ok(pg_temp.rls_revoke_check('courier_requests', 'DELETE'),
  'authenticated courier_requests DELETE yapamaz');

-- -----------------------------------------------------------------------------
-- 3) RPC'lerin anon/authenticated grant durumu
-- -----------------------------------------------------------------------------
select ok(not exists (
  select 1 from information_schema.routine_privileges rp
  join information_schema.routines r on r.specific_name = rp.specific_name
  where r.routine_schema = 'public'
    and r.routine_name in (
      'create_package_request', 'list_available_package_requests',
      'accept_package_request', 'reject_package_request',
      'request_package_delivery_confirmation', 'confirm_package_delivery',
      'admin_resolve_package_dispute', 'request_courier_payout',
      'admin_approve_courier_payout', 'admin_reject_courier_payout',
      'get_assigned_package_details', 'get_available_orders_for_courier',
      'get_courier_active_orders'
    )
    and rp.grantee = 'anon'
), 'Hiçbir yeni kurye RPC''si anon''a açık değil');

-- -----------------------------------------------------------------------------
-- 4) Yeni yardımcı tablolar
-- -----------------------------------------------------------------------------
select ok(to_regclass('public.courier_payout_items') is not null,
  'courier_payout_items tablosu mevcut');
select ok(to_regclass('public.courier_request_rejections') is not null,
  'courier_request_rejections tablosu mevcut');

-- Unique indexler
select ok(to_regclass('public.uq_courier_payout_items_earning_id') is not null,
  'courier_payout_items(earning_id) UNIQUE mevcut');
select ok(to_regclass('public.uq_courier_payout_one_open_per_courier') is not null,
  'courier_payout_requests açık payout partial UNIQUE mevcut');
select ok(to_regclass('public.uq_courier_earnings_package_request') is not null,
  'courier_earnings(package_request_id) koşullu UNIQUE mevcut');

-- deduct_from_balance authenticated EXECUTE revoke
select ok(not exists (
  select 1 from information_schema.routine_privileges rp
  join information_schema.routines r on r.specific_name = rp.specific_name
  where r.routine_schema = 'public'
    and r.routine_name = 'deduct_from_balance'
    and rp.grantee = 'authenticated'
), 'deduct_from_balance authenticated EXECUTE yetkisi kaldırıldı');

select * from finish();
rollback;
