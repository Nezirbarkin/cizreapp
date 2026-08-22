-- =============================================================================
-- Kurye finansal RPC'ler ve PII güvenlik testleri (pgTAP)
-- -----------------------------------------------------------------------------
-- Bu test veri yazmaz (yalnız katalog/RPC çağrılarında örnek veri gerektiren
-- testler pgTAP lives_ok/throws_ok üzerinden rollback yapar).
-- Çalıştırma: supabase test db
-- =============================================================================

begin;

create extension if not exists pgtap with schema extensions;

select plan(45);

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
select is(
  to_regprocedure('public.request_courier_payout(uuid)')::text,
  'request_courier_payout(uuid)',
  'request_courier_payout UUID istemci sozlesmesi mevcut');
select ok(
  to_regprocedure('public.request_courier_payout(text)') is null,
  'Belirsizlik yaratacak text payout overload mevcut degil');
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
select ok(pg_temp.has_policy('courier_payout_items', 'SELECT', 'authenticated'),
  'courier_payout_items SELECT policy (authenticated) mevcut');
select ok(pg_temp.rls_revoke_check('courier_payout_items', 'INSERT'),
  'authenticated courier_payout_items INSERT yapamaz');
select ok(pg_temp.rls_revoke_check('courier_payout_items', 'UPDATE'),
  'authenticated courier_payout_items UPDATE yapamaz');
select ok(pg_temp.rls_revoke_check('courier_payout_items', 'DELETE'),
  'authenticated courier_payout_items DELETE yapamaz');
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
-- 20260817000018: indeks KOSULLU hale getirildi. Kosulsuz haliyle,
-- admin_reject_courier_payout item satirlarini silmeyip yalnizca 'rejected'
-- isaretledigi icin kurye ayni kazanclarla bir daha ASLA odeme isteyemiyordu
-- (23505). Artik yalniz AKTIF kalemler tekil.
select ok(to_regclass('public.uq_courier_payout_items_earning_id_active') is not null,
  'courier_payout_items(earning_id) aktif-kalem UNIQUE mevcut');
select ok(to_regclass('public.uq_courier_payout_items_earning_id') is null,
  'kosulsuz eski earning_id UNIQUE indeksi kaldirildi');
select ok(exists (
  select 1 from pg_indexes
  where schemaname = 'public'
    and indexname = 'uq_courier_payout_items_earning_id_active'
    and indexdef ilike '%where%rejected%'
), 'aktif-kalem UNIQUE indeksi rejected kalemleri haric tutuyor');
select ok(to_regclass('public.uq_courier_payout_one_open_per_courier') is not null,
  'courier_payout_requests açık payout partial UNIQUE mevcut');
select ok(to_regclass('public.uq_courier_payout_courier_idempotency') is not null,
  'courier payout kurye + idempotency UNIQUE mevcut');
select ok(to_regclass('public.uq_courier_earnings_package_request') is not null,
  'courier_earnings(package_request_id) koşullu UNIQUE mevcut');

-- -----------------------------------------------------------------------------
-- 5) Bildirim tipi kisiti kurye zincirini kirmamali (20260817000018 regresyonu)
-- -----------------------------------------------------------------------------
-- notifications_type_check gecmiste sabit bir beyaz listeydi ve her yeni
-- ozellikte guncellenmedigi icin INSERT'leri 23514 ile dusuruyordu. En son
-- 20260801000003 listeden TUM kurye/paket tiplerini dusurmus, boylece
-- admin_approve_courier_payout'un son adimi ('courier_payout_approved'
-- bildirimi) patlayarak ODEME ONAYINI TAMAMEN ENGELLEMISTI.
select ok(not exists (
  select 1
  from pg_constraint con
  join pg_class rel on rel.oid = con.conrelid
  join pg_namespace nsp on nsp.oid = rel.relnamespace
  join pg_attribute att on att.attrelid = rel.oid and att.attnum = any (con.conkey)
  where nsp.nspname = 'public'
    and rel.relname = 'notifications'
    and con.contype = 'c'
    and att.attname = 'type'
    and pg_get_constraintdef(con.oid) ilike '%''like''%'
), 'notifications.type uzerinde sabit tip beyaz listesi kalmadi');

-- Kurye/paket zincirinin yazdigi her tip gercekten INSERT edilebilmeli.
select lives_ok($$
  insert into public.notifications (user_id, type, title, content, is_read)
  select u.id, t.tip, 'test', 'test', false
  from (select id from auth.users limit 1) u
  cross join (values
    ('courier_payout_approved'), ('courier_payout_rejected'),
    ('courier_payout_request'),  ('courier_delivered'),
    ('courier_assigned'),        ('new_package_request'),
    ('package_delivered'),       ('package_route'),
    ('package_dispute_rejected')
  ) as t(tip)
$$, 'kurye/paket bildirim tiplerinin tamami notifications''a yazilabiliyor');

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
