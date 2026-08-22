-- =============================================================================
-- Online odeme + satici kazanci degismezleri (pgTAP)
--
-- Calistirma:
--   supabase start
--   supabase test db supabase/tests/database
--
-- AMAC: 20260817000038/39/40 ile kapatilan para deliklerinin ileride bir kod
-- degisikligiyle sessizce geri acilmasini engellemek. Mevcut
-- 006_seller_panel_invariants.test.sql yalnizca "tablo var / RLS acik / sutun
-- var" dogruluyordu; bu testler o kontrolleri gecen ama yine de sizdiran
-- yapilandirmalari yakalar.
-- =============================================================================

begin;

create extension if not exists pgtap with schema extensions;

select plan(21);

-- -----------------------------------------------------------------------------
-- Yardimcilar
-- -----------------------------------------------------------------------------
create or replace function pg_temp.client_can_write(p_table text)
returns boolean language sql stable as $$
  select has_table_privilege('authenticated', 'public.' || quote_ident(p_table), 'INSERT')
      or has_table_privilege('authenticated', 'public.' || quote_ident(p_table), 'UPDATE')
      or has_table_privilege('authenticated', 'public.' || quote_ident(p_table), 'DELETE')
      or has_table_privilege('anon', 'public.' || quote_ident(p_table), 'INSERT')
      or has_table_privilege('anon', 'public.' || quote_ident(p_table), 'UPDATE')
      or has_table_privilege('anon', 'public.' || quote_ident(p_table), 'DELETE');
$$;

create or replace function pg_temp.has_write_policy(p_table text)
returns boolean language sql stable as $$
  select exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = p_table
      and cmd in ('INSERT', 'UPDATE', 'DELETE', 'ALL')
      and (roles @> array['authenticated']::name[]
           or roles @> array['public']::name[]
           or roles @> array['anon']::name[])
  );
$$;

create or replace function pg_temp.fn_is_service_role_only(p_name text)
returns boolean language sql stable as $$
  select exists (select 1 from pg_proc p
                 join pg_namespace n on n.oid = p.pronamespace
                 where n.nspname = 'public' and p.proname = p_name)
     and not exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = p_name
      and (has_function_privilege('public', p.oid, 'EXECUTE')
           or has_function_privilege('anon', p.oid, 'EXECUTE')
           or has_function_privilege('authenticated', p.oid, 'EXECUTE'))
  );
$$;

create or replace function pg_temp.trigger_exists(p_table text, p_trigger text)
returns boolean language sql stable as $$
  select exists (
    select 1 from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = p_table
      and t.tgname = p_trigger
      and not t.tgisinternal
  );
$$;

-- -----------------------------------------------------------------------------
-- 1) payment_transactions — istemci yazamaz
--
-- Regresyon: 20260212000007:81-86 UPDATE policy'sinde WITH CHECK yoktu;
-- kullanici kendi satirinda payment_status='success' yapabiliyordu.
-- -----------------------------------------------------------------------------
select ok(
  not pg_temp.client_can_write('payment_transactions'),
  'payment_transactions: authenticated/anon INSERT/UPDATE/DELETE yetkisi yok'
);

select ok(
  not pg_temp.has_write_policy('payment_transactions'),
  'payment_transactions: istemci rollerine acik yazma policy''si yok'
);

select ok(
  has_table_privilege('authenticated', 'public.payment_transactions', 'SELECT'),
  'payment_transactions: kullanici kendi odemesini okuyabilir'
);

select ok(
  pg_temp.trigger_exists('payment_transactions', 'guard_payment_transaction_client_writes'),
  'payment_transactions: istemci yazma koruma trigger''i kurulu'
);

-- Herhangi bir UPDATE policy'si eklenirse WITH CHECK'i olmali.
select ok(
  not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'payment_transactions'
      and cmd = 'UPDATE'
      and with_check is null
  ),
  'payment_transactions: WITH CHECK''siz UPDATE policy''si yok'
);

-- -----------------------------------------------------------------------------
-- 2) cancel_my_payment_transaction — dar kapsamli tek yazma yolu
-- -----------------------------------------------------------------------------
select has_function(
  'public', 'cancel_my_payment_transaction', array['uuid'],
  'cancel_my_payment_transaction(uuid) mevcut'
);

select ok(
  exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'cancel_my_payment_transaction'
      and p.prosecdef
      and has_function_privilege('authenticated', p.oid, 'EXECUTE')
  ),
  'cancel_my_payment_transaction SECURITY DEFINER ve authenticated''a acik'
);

-- -----------------------------------------------------------------------------
-- 3) seller_earnings — satici kendi kazancini uretemez
--
-- Regresyon: 20260621000007:361-364
--   CREATE POLICY "Service can manage earnings" FOR ALL USING (true);
-- TO yan tumcesi olmadigi icin authenticated dahil herkese uyguluyordu.
-- -----------------------------------------------------------------------------
select ok(
  not pg_temp.client_can_write('seller_earnings'),
  'seller_earnings: authenticated/anon yazma yetkisi yok'
);

select ok(
  not pg_temp.has_write_policy('seller_earnings'),
  'seller_earnings: istemci rollerine acik yazma policy''si yok'
);

select ok(
  not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'seller_earnings'
      and qual = 'true'
      and cmd = 'ALL'
  ),
  'seller_earnings: "FOR ALL USING (true)" policy''si yok'
);

-- -----------------------------------------------------------------------------
-- 4) seller_withdrawals — yalnizca Edge Function yazar
-- -----------------------------------------------------------------------------
select ok(
  not pg_temp.client_can_write('seller_withdrawals'),
  'seller_withdrawals: authenticated/anon yazma yetkisi yok'
);

select ok(
  not pg_temp.has_write_policy('seller_withdrawals'),
  'seller_withdrawals: istemci rollerine acik yazma policy''si yok'
);

-- -----------------------------------------------------------------------------
-- 5) shops — finansal sutunlar satici tarafindan degistirilemez
--
-- shops UPDATE policy'si satir duzeyinde kalmak zorunda (satici magazasinin
-- adini/adresini duzenleyebilmeli), bu yuzden koruma trigger seviyesinde.
-- -----------------------------------------------------------------------------
select ok(
  pg_temp.trigger_exists('shops', 'guard_shop_financial_columns'),
  'shops: finansal sutun koruma trigger''i kurulu'
);

select ok(
  pg_temp.trigger_exists('shops', 'force_default_shop_commission_on_insert'),
  'shops: yeni magazada komisyon orani sunucu varsayilanina zorlaniyor'
);

select ok(
  exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'guard_shop_financial_columns'
      and p.prosecdef
  ),
  'guard_shop_financial_columns SECURITY DEFINER'
);

-- -----------------------------------------------------------------------------
-- 6) validate_payout_request — SECURITY DEFINER olmali
--
-- Regresyon: invoker rights ile calisirken shops satiri RLS nedeniyle
-- gorunmezse degiskenler NULL kaliyor, NULL karsilastirmalari EXCEPTION
-- atmiyor ve tutar dogrulamasi tamamen atlaniyordu.
-- -----------------------------------------------------------------------------
select ok(
  exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'validate_payout_request'
      and p.prosecdef
  ),
  'validate_payout_request SECURITY DEFINER (NULL-degrade ile atlanamaz)'
);

select ok(
  pg_temp.trigger_exists('payout_requests', 'validate_payout_request'),
  'payout_requests: validate_payout_request trigger''i kurulu'
);

-- -----------------------------------------------------------------------------
-- 7) Odeme finalizer'lari — public semada, yalnizca service_role
--
-- Bunlar public semada OLMAK ZORUNDA: PostgREST private semayi expose
-- etmiyor, dolayisiyla Edge Function private.* cagiramaz. Guvenlik
-- semadan degil GRANT'tan geliyor.
-- -----------------------------------------------------------------------------
select ok(
  pg_temp.fn_is_service_role_only('atomic_finalize_payment_transaction'),
  'atomic_finalize_payment_transaction mevcut ve yalnizca service_role''e acik'
);

select ok(
  pg_temp.fn_is_service_role_only('commit_online_order'),
  'commit_online_order mevcut ve yalnizca service_role''e acik'
);

select ok(
  pg_temp.fn_is_service_role_only('link_checkout_session_payment'),
  'link_checkout_session_payment mevcut ve yalnizca service_role''e acik'
);

-- Eski client-authoritative finalizer geri gelmemeli.
select ok(
  not exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'complete_online_payment'
  ),
  'complete_online_payment (callback_data''dan fiyat okuyan surum) kaldirilmis'
);

select * from finish();

rollback;
