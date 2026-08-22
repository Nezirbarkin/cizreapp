-- =============================================================================
-- Odeme RPC'leri — DAVRANIS testleri (pgTAP)
--
-- NEDEN AYRI BIR DOSYA:
--   013_payment_and_seller_earnings_invariants.test.sql yalnizca ACL/policy
--   sekli dogruluyor. "column reference payment_status is ambiguous" (42702)
--   hatasini YAKALAYAMAZ, cunku:
--     - migration sorunsuz uygulanir (plpgsql govdesi tanim aninda
--       dogrulanmaz),
--     - ACL/policy kontrolleri gecer,
--     - hata ancak ilgili DEYIME ULASILDIGINDA, yani gercek bir odemede
--       ortaya cikar.
--
--   Bu dosya fonksiyonlari GERCEK VERIYLE CALISTIRIR, boylece ayni hata
--   bir daha canliya cikmadan once burada patlar.
--
-- Calistirma:
--   supabase start && supabase test db supabase/tests/database
-- =============================================================================

begin;

create extension if not exists pgtap with schema extensions;

select plan(10);

-- -----------------------------------------------------------------------------
-- FIXTURE
-- -----------------------------------------------------------------------------
create temporary table t_fix (
  user_id     uuid,
  txn_ok      uuid,   -- normal basarili odeme
  txn_legacy  uuid    -- eski akis: checkout_session_id NULL, fraud_status <> 1
);

do $$
declare
  v_user   uuid := gen_random_uuid();
  v_txn    uuid := gen_random_uuid();
  v_legacy uuid := gen_random_uuid();
begin
  insert into auth.users (
    id, instance_id, email, aud, role,
    created_at, updated_at, email_confirmed_at
  )
  values (
    v_user, '00000000-0000-0000-0000-000000000000',
    'pay_rpc_test_' || substring(v_user::text from 1 for 8) || '@example.com',
    'authenticated', 'authenticated', now(), now(), now()
  );

  -- on_auth_user_created trigger'i profili olusturur; olusturmadiysa yedek.
  if not exists (select 1 from public.profiles p where p.id = v_user) then
    begin
      insert into public.profiles (id) values (v_user);
    exception when others then
      null;
    end;
  end if;

  insert into public.payment_transactions
    (id, user_id, amount, payment_status, token, currency)
  values
    (v_txn, v_user, 100.00, 'pending', 'tok_' || v_txn::text, 'TRY');

  -- Eski akis kaydi: checkout_session_id NULL ve fraud_status = 0.
  -- Eski callback fraudStatus=1 sartini SADECE production'da uyguluyordu,
  -- bu yuzden bu kayit basariyla sonuclanmalidir.
  insert into public.payment_transactions
    (id, user_id, amount, payment_status, token, currency, fraud_status)
  values
    (v_legacy, v_user, 50.00, 'pending', 'tok_' || v_legacy::text, 'TRY', 0);

  insert into t_fix values (v_user, v_txn, v_legacy);
end $$;

-- -----------------------------------------------------------------------------
-- 1) atomic_finalize_payment_transaction — basarili sonuclandirma
--
-- BU TEST 42702 REGRESYONUNU YAKALAR: fonksiyondaki
--   "... where id = p_transaction_id and payment_status = 'pending'"
-- deyimi OUT sutunuyla cakisiyorsa bu cagri hata firlatir.
-- -----------------------------------------------------------------------------
select results_eq(
  $$ select updated, already_processed, payment_status
     from public.atomic_finalize_payment_transaction(
       (select txn_ok from t_fix),
       'PAY_TEST_1', 100.00,
       'CREDIT_CARD', 'MASTER_CARD', 'Bonus', 'Garanti', '1234',
       1, 'success'
     ) $$,
  $$ values (true, false, 'success'::text) $$,
  'atomic_finalize_payment_transaction: pending -> success (42702 regresyon korumasi)'
);

select results_eq(
  $$ select payment_status, paid_price
     from public.payment_transactions
     where id = (select txn_ok from t_fix) $$,
  $$ values ('success'::varchar, 100.00::numeric) $$,
  'atomic_finalize_payment_transaction: tablo durumu gercekten guncellendi'
);

-- -----------------------------------------------------------------------------
-- 2) Idempotency — ikinci cagri hicbir sey degistirmemeli
-- -----------------------------------------------------------------------------
select results_eq(
  $$ select updated, already_processed, payment_status
     from public.atomic_finalize_payment_transaction(
       (select txn_ok from t_fix),
       'PAY_TEST_1', 100.00,
       'CREDIT_CARD', 'MASTER_CARD', 'Bonus', 'Garanti', '1234',
       1, 'success'
     ) $$,
  $$ values (false, true, 'success'::text) $$,
  'atomic_finalize_payment_transaction: tekrar cagri idempotent (already_processed)'
);

-- -----------------------------------------------------------------------------
-- 3) Eski akis uyumlulugu — session NULL + fraud_status <> 1 basarili olmali
--
-- Mutabakat kontrolleri yalnizca checkout_session_id dolu kayitlarda
-- calismali. Kosulsuz calisirsa yayindaki eski uygulama surumunun mesru
-- odemeleri 'failure' isaretlenir ve siparis olusmaz.
-- -----------------------------------------------------------------------------
select results_eq(
  $$ select updated, payment_status, reconciliation_status
     from public.atomic_finalize_payment_transaction(
       (select txn_legacy from t_fix),
       'PAY_TEST_2', 50.00,
       'CREDIT_CARD', 'VISA', 'Bonus', 'Ziraat', '5678',
       0, 'success'
     ) $$,
  $$ values (true, 'success'::text, null::text) $$,
  'Eski akis (session NULL, fraud_status=0) mutabakata takilmadan basarili olur'
);

-- -----------------------------------------------------------------------------
-- 4) Olmayan transaction P0002 firlatmali
-- -----------------------------------------------------------------------------
select throws_ok(
  $$ select * from public.atomic_finalize_payment_transaction(
       '00000000-0000-0000-0000-000000000000'::uuid,
       'X', 1.00, 'a', 'b', 'c', 'd', '0000', 1, 'success'
     ) $$,
  'P0002',
  null,
  'Olmayan payment transaction icin P0002'
);

-- -----------------------------------------------------------------------------
-- 5) STATIK KONTROL — RETURNS TABLE sutun adlarina nitelenmemis atif
--
-- plpgsql'de RETURNS TABLE sutunlari govdede degisken olarak kapsamdadir.
-- Ayni adli tablo sutununa "and <ad> =" gibi nitelenmemis atif 42702 verir.
-- commit_online_order'in tam happy-path'i icin fixture kurmak agir oldugundan
-- (shops + products + addresses + session + flash sales), o fonksiyon bu
-- statik kontrolle korunuyor.
--
-- Desen: bir anahtar kelimeden (and/where/or) sonra DOGRUDAN sutun adi
-- geliyorsa nitelenmemistir. "and pt.payment_status = ..." eslesmez.
-- -----------------------------------------------------------------------------
create or replace function pg_temp.has_unqualified_out_ref(p_fn text, p_col text)
returns boolean language sql stable as $$
  select exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = p_fn
      and p.prolang = (select oid from pg_language where lanname = 'plpgsql')
      and p.prosrc ~* ('(and|where|or)[[:space:]]+'
                       || p_col
                       || '[[:space:]]*(=|is[[:space:]])')
  );
$$;

select ok(
  not pg_temp.has_unqualified_out_ref('atomic_finalize_payment_transaction', 'payment_status'),
  'atomic_finalize: "payment_status" atiflari nitelenmis (42702 korumasi)'
);

select ok(
  not pg_temp.has_unqualified_out_ref('atomic_finalize_payment_transaction', 'reconciliation_status'),
  'atomic_finalize: "reconciliation_status" atiflari nitelenmis'
);

select ok(
  not pg_temp.has_unqualified_out_ref('commit_online_order', 'order_id'),
  'commit_online_order: "order_id" atiflari nitelenmis (42702 korumasi)'
);

select ok(
  not pg_temp.has_unqualified_out_ref('commit_online_order', 'status'),
  'commit_online_order: "status" atiflari nitelenmis (42702 korumasi)'
);

select ok(
  not pg_temp.has_unqualified_out_ref('commit_online_order', 'order_group_id'),
  'commit_online_order: "order_group_id" atiflari nitelenmis'
);

select * from finish();

rollback;
