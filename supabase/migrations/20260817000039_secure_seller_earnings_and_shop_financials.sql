-- =============================================================================
-- Satici kazanclarini sunucu-otoriteli hale getir
--
-- Bu migration uc ayri para deligini kapatir. Hepsi de saticinin kendi
-- bakiyesini istedigi gibi yazabilmesine izin veriyordu.
--
-- ACIK 1 — seller_earnings: herkese acik FOR ALL policy
--   20260621000007_CREATE_BALANCE_SYSTEM.sql:361-364
--     CREATE POLICY "Service can manage earnings"
--       ON seller_earnings FOR ALL USING (true);
--   TO yan tumcesi yok; PostgreSQL policy'yi 'public' role'e uygular, yani
--   authenticated dahil. FOR ALL + WITH CHECK yoklugu USING'i INSERT/UPDATE
--   icin de kullandirir. Sonuc: herhangi bir oturumlu kullanici
--     POST /rest/v1/seller_earnings {"seller_id": "...", "net_amount": 999999,
--                                    "status": "available"}
--   ile kendine kazanc uretebilir. Ayni hata user_balances icin
--   20260715000001_restrict_balance_rls_to_service_role.sql ile duzeltilmisti;
--   seller_earnings atlanmis.
--
-- ACIK 2 — shops: finansal sutunlar satici tarafindan yazilabilir
--   20260209000010_admin_crud_policies.sql:93-104 shops_update_policy yalnizca
--   SATIR duzeyinde kisitlar (owner_id = auth.uid()). Sutun kisiti yok:
--     PATCH /rest/v1/shops?id=eq.<kendi_magazam>
--     {"admin_credit": 999999, "commission_debt": 0, "commission_rate": 0}
--   Ardindan payout istegi hem Dart kontrolunden hem validate_payout_request
--   trigger'indan gecer, cunku ikisi de bu sutunlari okur.
--
-- ACIK 3 — seller_withdrawals: dogrulamasiz INSERT
--   20260621000007:400-403 saticiya serbest INSERT veriyor. request-withdrawal
--   Edge Function'i tamamen atlanabiliyor; tabloda dogrulayici trigger yok.
--
-- AYRICA — validate_payout_request sertlestirilir:
--   20260210000005_redesign_seller_payment_system.sql:150-205
--     a) SECURITY DEFINER degil -> shops SELECT'i cagiranin RLS'i altinda
--        calisir. Satir gorunmezse degiskenler NULL olur, NULL > NULL ve
--        NULL <= 0 karsilastirmalari NULL doner, hicbir EXCEPTION atilmaz
--        ve dogrulama sessizce ATLANIR.
--     b) NEW.amount dogrulanir ama bekleyen toplam SUM(total_amount) ile
--        hesaplanir; ikisi istemcinin bagimsiz doldurdugu iki ayri sutun.
--     c) payout_requests INSERT policy'si yalnizca seller_id = auth.uid()
--        kontrol eder; shop_id kisitlanmaz, yani satici BASKA bir magazanin
--        bakiyesine karsi talep olusturabilir.
-- =============================================================================

begin;

-- -----------------------------------------------------------------------------
-- 1) seller_earnings — yalnizca sunucu yazar
-- -----------------------------------------------------------------------------
drop policy if exists "Service can manage earnings" on public.seller_earnings;

revoke insert, update, delete, truncate
  on public.seller_earnings from anon, authenticated;
grant select on public.seller_earnings to authenticated;
grant all on public.seller_earnings to service_role;

-- Satici kendi kazancini GOREBILIR (mevcut SELECT policy'si korunur).
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'seller_earnings'
      and cmd = 'SELECT'
  ) then
    create policy "seller_earnings_select_own" on public.seller_earnings
      for select to authenticated
      using (
        seller_id = (select auth.uid())
        or public.auth_is_admin()
      );
  end if;
end $$;

-- -----------------------------------------------------------------------------
-- 2) seller_withdrawals — yalnizca Edge Function (service_role) yazar
-- -----------------------------------------------------------------------------
drop policy if exists "Sellers can create withdrawals" on public.seller_withdrawals;

revoke insert, update, delete, truncate
  on public.seller_withdrawals from anon, authenticated;
grant select on public.seller_withdrawals to authenticated;
grant all on public.seller_withdrawals to service_role;

-- -----------------------------------------------------------------------------
-- 3) shops — finansal sutunlari kilitle
--
-- RLS sutun bazli kisitlama yapamaz, bu yuzden trigger kullaniyoruz.
-- Admin (auth_is_admin) ve sunucu baglami (service_role / SECURITY DEFINER
-- fonksiyonlar, ki bunlar tanimlayici rolunde calisir) degistirebilir.
-- Magaza sahibi degistiremez.
-- -----------------------------------------------------------------------------
create or replace function public.guard_shop_financial_columns()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  -- Korunan sutunlar. to_jsonb uzerinden karsilastiriliyor ki sutunlardan
  -- biri bir ortamda mevcut olmasa bile fonksiyon calisma zamaninda
  -- patlamasin (sema surumleri arasinda fark var).
  c_protected constant text[] := array[
    'admin_credit',
    'commission_debt',
    'commission_rate',
    'digital_commission_rate',
    'total_paid',
    'pending_payout',
    'cash_payment_revenue',
    'online_payment_revenue',
    'total_collected_cash'
  ];
  v_old_row jsonb;
  v_new_row jsonb;
  v_col     text;
  v_changed text[] := '{}';
begin
  -- Sunucu baglami: SECURITY DEFINER fonksiyonlar ve service_role serbest.
  if current_user not in ('authenticated', 'anon') then
    return new;
  end if;

  -- Admin serbest (admin paneli bu sutunlari dogrudan duzenliyor).
  if public.auth_is_admin() then
    return new;
  end if;

  v_old_row := to_jsonb(old);
  v_new_row := to_jsonb(new);

  foreach v_col in array c_protected loop
    if v_new_row ? v_col
       and (v_new_row -> v_col) is distinct from (v_old_row -> v_col) then
      v_changed := v_changed || v_col;
    end if;
  end loop;

  if array_length(v_changed, 1) > 0 then
    raise exception
      'Magaza finansal alanlari satici tarafindan degistirilemez: %',
      array_to_string(v_changed, ', ')
      using errcode = '42501';
  end if;

  return new;
end;
$$;

drop trigger if exists guard_shop_financial_columns on public.shops;
create trigger guard_shop_financial_columns
  before update on public.shops
  for each row
  execute function public.guard_shop_financial_columns();

comment on function public.guard_shop_financial_columns() is
  'shops uzerindeki bakiye/komisyon sutunlarini magaza sahibinin degistirmesini engeller. Admin ve sunucu baglami muaftir. 2026-08-17.';

-- Yeni magazada komisyon oranini satici belirleyemesin:
-- seller_dashboard_screen.dart:2136 insert sirasinda commission_rate: 10.0
-- gonderiyor. Admin olmayan INSERT'lerde sistem varsayilanina zorla.
create or replace function public.force_default_shop_commission_on_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_default numeric;
begin
  if current_user not in ('authenticated', 'anon') then
    return new;
  end if;
  if public.auth_is_admin() then
    return new;
  end if;

  select nullif(value, '')::numeric
    into v_default
  from public.system_settings
  where key = 'admin_commission_rate';

  new.commission_rate         := coalesce(v_default, 10);
  new.digital_commission_rate := null;
  new.admin_credit            := 0;
  new.commission_debt         := 0;
  new.total_paid              := 0;
  new.pending_payout          := 0;
  new.cash_payment_revenue    := 0;
  new.online_payment_revenue  := 0;
  new.total_collected_cash    := 0;

  return new;
end;
$$;

drop trigger if exists force_default_shop_commission_on_insert on public.shops;
create trigger force_default_shop_commission_on_insert
  before insert on public.shops
  for each row
  execute function public.force_default_shop_commission_on_insert();

comment on function public.force_default_shop_commission_on_insert() is
  'Yeni magaza olustururken komisyon oranini ve tum bakiye alanlarini sunucu varsayilanina zorlar. 2026-08-17.';

-- -----------------------------------------------------------------------------
-- 4) validate_payout_request — SECURITY DEFINER + magaza sahipligi + tutar
-- -----------------------------------------------------------------------------
create or replace function public.validate_payout_request()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin_credit          numeric;
  v_commission_debt       numeric;
  v_has_own_courier       boolean;
  v_owner_id              uuid;
  v_pending_total         numeric;
  v_net_receivable        numeric;
  v_requested             numeric;
begin
  -- Magaza kaydi SECURITY DEFINER sayesinde RLS'ten bagimsiz okunur;
  -- eskiden gorunmezse degiskenler NULL kalip dogrulama atlaniyordu.
  select s.admin_credit, s.commission_debt, s.has_own_courier, s.owner_id
    into v_admin_credit, v_commission_debt, v_has_own_courier, v_owner_id
  from public.shops s
  where s.id = new.shop_id;

  if not found then
    raise exception 'Magaza bulunamadi' using errcode = 'P0002';
  end if;

  -- Satici yalnizca KENDI magazasi icin talep olusturabilir.
  -- payout_requests INSERT policy'si shop_id'yi kisitlamiyor.
  if new.seller_id is distinct from v_owner_id then
    raise exception 'Bu magaza icin odeme istegi olusturamazsiniz'
      using errcode = '42501';
  end if;

  -- Istemci seller_id'yi kendi disinda bir degere set edemesin.
  if auth.uid() is not null and new.seller_id is distinct from auth.uid() then
    raise exception 'Baskasi adina odeme istegi olusturamazsiniz'
      using errcode = '42501';
  end if;

  v_admin_credit    := coalesce(v_admin_credit, 0);
  v_commission_debt := coalesce(v_commission_debt, 0);

  select coalesce(sum(pr.total_amount), 0)
    into v_pending_total
  from public.payout_requests pr
  where pr.shop_id = new.shop_id
    and pr.status = 'pending';

  if coalesce(v_has_own_courier, false) then
    v_net_receivable := v_admin_credit - v_commission_debt - v_pending_total;
    new.commission_debt := v_commission_debt;
  else
    v_net_receivable := v_admin_credit - v_pending_total;
    new.commission_debt := 0;
  end if;

  new.net_receivable := v_net_receivable;
  new.admin_credit   := v_admin_credit;

  if v_net_receivable <= 0 then
    raise exception
      'Odeme istegi olusturulamaz. Alacak: %, komisyon borcu: %, bekleyen istekler: %',
      v_admin_credit, v_commission_debt, v_pending_total
      using errcode = 'P0001';
  end if;

  -- Eski surum NEW.amount'u dogruluyor ama bekleyen toplami
  -- SUM(total_amount) ile hesapliyordu; ikisi istemcinin bagimsiz doldurdugu
  -- iki ayri sutun. Artik IKISININ DE BUYUGU dogrulanir, boylece hangisi
  -- asagi akista kullanilirsa kullanilsin limit asilamaz.
  --
  -- NOT: 'amount' sutunu icin to_jsonb kullaniliyor. Sutunu ekleyen bir
  -- migration repoda bulunmuyor (yalnizca total_amount CREATE TABLE'da
  -- tanimli), dolayisiyla dogrudan new.amount referansi sutunun olmadigi
  -- bir ortamda calisma zamaninda patlardi.
  v_requested := greatest(
    coalesce(new.total_amount, 0),
    coalesce((to_jsonb(new)->>'amount')::numeric, 0)
  );

  if v_requested <= 0 then
    raise exception 'Odeme istegi tutari sifirdan buyuk olmali'
      using errcode = 'P0001';
  end if;

  if v_requested > v_net_receivable then
    raise exception
      'Istediginiz tutar (%) net odenebilir tutardan (%) fazla.',
      v_requested, v_net_receivable
      using errcode = 'P0001';
  end if;

  -- Dogrulanan degeri kanonik sutuna sabitle.
  new.total_amount := v_requested;

  return new;
end;
$$;

comment on function public.validate_payout_request() is
  'payout_requests INSERT dogrulamasi. SECURITY DEFINER: magaza satiri RLS''ten bagimsiz okunur, boylece NULL-degrade ile dogrulama atlanamaz. Magaza sahipligi ve tutar tutarliligi da kontrol edilir. 2026-08-17.';

commit;

notify pgrst, 'reload schema';
