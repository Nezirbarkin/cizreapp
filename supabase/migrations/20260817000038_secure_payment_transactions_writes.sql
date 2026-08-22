-- =============================================================================
-- payment_transactions: istemci yazma yetkisini kaldir
--
-- SORUN (canli guvenlik acigi):
--   20260212000007_online_payment_system.sql:77-86 iki policy tanimliyor:
--
--     CREATE POLICY "payment_transactions_insert" ... FOR INSERT TO authenticated
--       WITH CHECK (user_id = (SELECT auth.uid()));
--     CREATE POLICY "payment_transactions_update" ... FOR UPDATE TO authenticated
--       USING (user_id = (SELECT auth.uid()) OR public.auth_is_admin());
--
--   UPDATE policy'sinde WITH CHECK YOK. PostgreSQL bu durumda USING ifadesini
--   yeni satir icin de kullanir; yani kullanici KENDI satirinin her sutununu,
--   payment_status dahil, serbestce degistirebilir:
--
--     PATCH /rest/v1/payment_transactions?id=eq.<kendi_txn>
--     {"payment_status": "success", "paid_price": 0}
--
--   Tablo ayrica 20260621000007_CREATE_BALANCE_SYSTEM.sql:641'deki toplu
--   "GRANT ALL ON ALL TABLES IN SCHEMA public TO anon, authenticated" ile
--   grant seviyesinde de aciktir; RLS tek engeldi.
--
-- COZUM:
--   - INSERT/UPDATE policy'leri kaldirilir. Satirlari yalnizca
--     iyzico-payment-init / iyzico-payment-callback (service_role) yazar.
--   - Grant seviyesinde de INSERT/UPDATE/DELETE geri alinir.
--   - Istemcinin ihtiyac duydugu TEK yazma islemi (pending -> cancelled)
--     dar kapsamli bir RPC'ye tasinir.
--   - Ileride biri yanlislikla policy'yi geri eklerse diye trigger seviyesinde
--     ikinci bir savunma katmani eklenir.
-- =============================================================================

begin;

-- -----------------------------------------------------------------------------
-- 1) Genis policy'leri kaldir
-- -----------------------------------------------------------------------------
drop policy if exists "payment_transactions_insert" on public.payment_transactions;
drop policy if exists "payment_transactions_update" on public.payment_transactions;

-- SELECT policy'si korunur (kullanici kendi odemesini gorebilmeli).
-- 20260212000007:70-75 tanimli; burada yalnizca varligini garanti ediyoruz.
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'payment_transactions'
      and policyname = 'payment_transactions_select'
  ) then
    create policy "payment_transactions_select" on public.payment_transactions
      for select to authenticated
      using (
        user_id = (select auth.uid())
        or public.auth_is_admin()
      );
  end if;
end $$;

-- -----------------------------------------------------------------------------
-- 2) Grant seviyesinde yazmayi kapat
-- -----------------------------------------------------------------------------
revoke insert, update, delete, truncate
  on public.payment_transactions from anon, authenticated;

grant select on public.payment_transactions to authenticated;
grant all on public.payment_transactions to service_role;

-- -----------------------------------------------------------------------------
-- 3) Istemcinin tek mesru yazma ihtiyaci: pending -> cancelled
--
-- lib/core/services/payment_service.dart cancelPaymentTransaction() bunu
-- dogrudan UPDATE ile yapiyordu. Artik bu RPC uzerinden yapar.
-- -----------------------------------------------------------------------------
create or replace function public.cancel_my_payment_transaction(
  p_transaction_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_rows integer;
begin
  if v_uid is null then
    raise exception 'cancel_my_payment_transaction: authentication required'
      using errcode = '42501';
  end if;

  update public.payment_transactions
  set payment_status = 'cancelled',
      updated_at = now()
  where id = p_transaction_id
    and user_id = v_uid
    and payment_status = 'pending';

  get diagnostics v_rows = row_count;
  return v_rows > 0;
end;
$$;

revoke all on function public.cancel_my_payment_transaction(uuid)
  from public, anon;
grant execute on function public.cancel_my_payment_transaction(uuid)
  to authenticated, service_role;

comment on function public.cancel_my_payment_transaction(uuid) is
  'Kullanici kendi bekleyen odemesini iptal eder (pending -> cancelled). Baska hicbir gecise izin vermez. 2026-08-17.';

-- -----------------------------------------------------------------------------
-- 4) Savunma katmani: policy regresyonuna karsi trigger
--
-- SECURITY DEFINER fonksiyonlar tanimlayicinin (postgres) rolunde calisir,
-- bu yuzden RPC ve Edge Function yollari etkilenmez. Dogrudan PostgREST
-- uzerinden gelen authenticated/anon yazmalari ise burada durur.
-- -----------------------------------------------------------------------------
create or replace function public.guard_payment_transaction_client_writes()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if current_user in ('authenticated', 'anon') then
    raise exception
      'payment_transactions dogrudan istemciden yazilamaz (islem: %). public.cancel_my_payment_transaction kullanin.',
      tg_op
      using errcode = '42501';
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

drop trigger if exists guard_payment_transaction_client_writes
  on public.payment_transactions;
create trigger guard_payment_transaction_client_writes
  before insert or update or delete on public.payment_transactions
  for each row
  execute function public.guard_payment_transaction_client_writes();

comment on function public.guard_payment_transaction_client_writes() is
  'payment_transactions uzerinde dogrudan istemci yazmalarini engeller. RLS policy regresyonlarina karsi ikinci savunma katmani. 2026-08-17.';

commit;

notify pgrst, 'reload schema';
