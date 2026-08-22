-- =============================================================================
-- Online odeme finalizer'ini onar (20260802000009'un yerine gecer)
--
-- NEDEN YENI BIR MIGRATION:
--   20260802000009_lock_payment_finalizer_to_backend.sql HICBIR ZAMAN
--   UYGULANAMADI. Dosyanin 40-42. satirlarinda:
--
--     p_md_status INTEGER DEFAULT NULL,
--     p_status TEXT,                 -- varsayilani yok
--
--   PostgreSQL varsayilan degerli bir parametreden SONRA varsayilansiz
--   parametre kabul etmez (42P13: "input parameters after one with a default
--   value must also have defaults"). CREATE FUNCTION patlar, migration
--   komple geri alinir, dolayisiyla ayni dosyadaki private.commit_online_order
--   da hicbir zaman olusmaz.
--
--   Bunun uzerine iyzico-payment-callback Edge Function'i
--     supabase.rpc("private.atomic_finalize_payment_transaction", ...)
--   bicimini kullaniyor. supabase-js .rpc() ciplak fonksiyon adi bekler;
--   nokta iceren ad PostgREST'te public."private.foo" olarak aranir ve
--   PGRST202 doner. Dogru sozdizimi (.schema('private')) kullanilsa bile
--   private semasi PostgREST'e expose edilmemis durumda (canlida yalnizca
--   20260802000006:46'daki "GRANT USAGE ON SCHEMA private TO service_role"
--   var, db_schemas ayari yok) ve PGRST106 donerdi.
--
-- BU MIGRATION NE YAPAR:
--   Iki fonksiyonu da PUBLIC semada olusturur (PostgREST erisebilsin diye),
--   ama EXECUTE yetkisini yalnizca service_role'e verir. Boylece Edge
--   Function service-role anahtariyla cagirabilir, mobil istemci cagiramaz.
--   Bu, projede zaten kullanilan desendir (bkz. 20260810000008).
--
-- 20260802000009'a GORE DUZELTILEN HATALAR:
--   1) Parametre sirasi: varsayilansizlar once, varsayilanlilar sonra (42P13).
--   2) nextval('order_number_seq') -> nextval('public.order_number_seq').
--      search_path = '' altinda niteliksiz ad cozulemez. Ayni hata
--      commit_cod_order/commit_balance_order icin 20260804000002:2749'da
--      zaten duzeltilmisti; online yol atlanmisti.
--   3) Kupon cift harcamasi: eski kod once gen_random_uuid() sahte order_id
--      ile private.use_coupon cagiriyor, sonra gercek order_id ile tekrar
--      cagiriyordu. Ilk cagri idempotency kontrolunun goremedigi bir kullanim
--      satiri birakiyordu. Artik commit_cod_order ile ayni satir ici desen
--      kullaniliyor (tek INSERT + usage_count++), private.use_coupon'a
--      bagimlilik da ortadan kalkiyor (o fonksiyon yalnizca deferred/
--      altindaki uygulanmamis bir migration'da tanimli).
-- =============================================================================

begin;

-- -----------------------------------------------------------------------------
-- 1) atomic_finalize_payment_transaction
-- -----------------------------------------------------------------------------
-- Eski (2026-06-30) 15 parametreli surumu kaldir; imzasi farkli oldugu icin
-- CREATE OR REPLACE onu guncelleyemez, yan yana iki overload kalirdi.
drop function if exists public.atomic_finalize_payment_transaction(
  uuid, text, numeric, text, text, text, text, text, integer,
  text, text, text, text, timestamptz, jsonb
);

create or replace function public.atomic_finalize_payment_transaction(
  p_transaction_id        uuid,
  p_payment_id            text,
  p_paid_price            numeric,
  p_card_type             text,
  p_card_association      text,
  p_card_family           text,
  p_card_bank_name        text,
  p_last_four_digits      text,
  p_fraud_status          integer,
  p_status                text,                            -- 'success' | 'failure'
  p_md_status             integer     default null,
  p_error_code            text        default null,
  p_error_message         text        default null,
  p_error_group           text        default null,
  p_callback_received_at  timestamptz default now(),
  p_merged_callback_data  jsonb       default '{}'::jsonb
)
returns table (
  updated               boolean,
  already_processed     boolean,
  payment_status        text,
  reconciliation_status text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_current_status    text;
  v_expected_amount   numeric;
  v_expected_currency char(3);
  v_expected_env      text;
  v_session_id        uuid;
  v_reconciliation    text := null;
  v_rows              integer;
begin
  select pt.payment_status, pt.expected_amount, pt.expected_currency,
         pt.iyzico_environment, pt.checkout_session_id
    into v_current_status, v_expected_amount, v_expected_currency,
         v_expected_env, v_session_id
  from public.payment_transactions pt
  where pt.id = p_transaction_id
  for update;

  if not found then
    raise exception 'Payment transaction bulunamadi' using errcode = 'P0002';
  end if;

  -- Idempotent: pending degilse onceki sonucu don.
  if v_current_status is distinct from 'pending' then
    return query select false, true, v_current_status, null::text;
    return;
  end if;

  -- ---------------------------------------------------------------------------
  -- Mutabakat kontrolleri
  --
  -- YALNIZCA sunucu-otoriteli akista (checkout_session_id dolu) uygulanir.
  --
  -- Neden: bu kontroller sunucunun onceden yazdigi beklentilere karsi
  -- karsilastirma yapar (expected_amount, expected_currency,
  -- iyzico_environment) ve bunlar yalnizca yeni akista doldurulur. Eski
  -- akisla olusmus kayitlarda checkout_session_id NULL'dur.
  --
  -- Ozellikle fraud kontrolu kritik: eski callback fraudStatus=1 sartini
  -- SADECE production'da uyguluyordu ("sandbox'ta fraudStatus 0 olabiliyor").
  -- Bu blok kosulsuz calissaydi, migration yeni Edge Function deploy
  -- edilmeden once uygulandiginda mesru odemeler failure isaretlenir ve
  -- siparis olusmazdi. Bu kapi sayesinde migration hangi sirada
  -- uygulanirsa uygulansin eski akisin davranisi degismez.
  -- ---------------------------------------------------------------------------
  if p_status = 'success' and v_session_id is not null then
    if v_expected_amount is not null and p_paid_price is not null
       and abs(p_paid_price - v_expected_amount) > 0.005 then
      v_reconciliation := 'amount_mismatch';

    elsif v_expected_currency is not null
          and p_merged_callback_data->>'currency' is not null
          and v_expected_currency <> (p_merged_callback_data->>'currency') then
      v_reconciliation := 'currency_mismatch';

    elsif v_expected_env = 'production'
          and (p_merged_callback_data->>'environment') = 'sandbox' then
      v_reconciliation := 'env_mismatch';

    elsif p_fraud_status is not null and p_fraud_status <> 1 then
      v_reconciliation := 'signature_invalid';
    end if;

    if v_reconciliation is not null then
      insert into private.server_checkout_audit
        (session_id, payment_transaction_id, event_type, detail)
      values (v_session_id, p_transaction_id, v_reconciliation, jsonb_build_object(
        'expected_amount',   v_expected_amount,
        'actual_paid_price', p_paid_price,
        'expected_currency', v_expected_currency,
        'expected_env',      v_expected_env,
        'fraud_status',      p_fraud_status,
        'payment_id',        p_payment_id
      ));

      update public.payment_transactions
      set payment_status        = 'failure',
          reconciliation_status = v_reconciliation,
          error_code            = p_error_code,
          error_message         = coalesce(p_error_message,
                                           'Reconciliation gerekli: ' || v_reconciliation),
          error_group           = p_error_group,
          callback_received_at  = p_callback_received_at,
          callback_data         = coalesce(callback_data, '{}'::jsonb) || p_merged_callback_data,
          updated_at            = now()
      where id = p_transaction_id;

      return query select true, false, 'failure'::text, v_reconciliation;
      return;
    end if;
  end if;

  -- ---------------------------------------------------------------------------
  -- Atomik guncelleme
  -- ---------------------------------------------------------------------------
  update public.payment_transactions
  set payment_status       = p_status,
      payment_id           = p_payment_id,
      paid_price           = p_paid_price,
      card_type            = p_card_type,
      card_association     = p_card_association,
      card_family          = p_card_family,
      card_bank_name       = p_card_bank_name,
      last_four_digits     = p_last_four_digits,
      fraud_status         = p_fraud_status,
      callback_received_at = p_callback_received_at,
      callback_data        = coalesce(callback_data, '{}'::jsonb) || p_merged_callback_data,
      error_code           = p_error_code,
      error_message        = p_error_message,
      error_group          = p_error_group,
      updated_at           = now()
  where id = p_transaction_id
    and payment_status = 'pending';

  get diagnostics v_rows = row_count;

  if v_rows = 0 then
    return query select false, true, v_current_status, v_reconciliation;
  else
    return query select true, false, p_status, v_reconciliation;
  end if;
end;
$$;

revoke all on function public.atomic_finalize_payment_transaction(
  uuid, text, numeric, text, text, text, text, text, integer, text,
  integer, text, text, text, timestamptz, jsonb
) from public, anon, authenticated;

grant execute on function public.atomic_finalize_payment_transaction(
  uuid, text, numeric, text, text, text, text, text, integer, text,
  integer, text, text, text, timestamptz, jsonb
) to service_role;

comment on function public.atomic_finalize_payment_transaction(
  uuid, text, numeric, text, text, text, text, text, integer, text,
  integer, text, text, text, timestamptz, jsonb
) is
  'iyzico callback icin atomik odeme sonuclandirma. SELECT FOR UPDATE + pending kosullu UPDATE ile idempotent. Tutar/kur/ortam/fraud mutabakati saglanmazsa failure + reconciliation_status yazar, siparis OLUSTURMAZ. Yalnizca service_role. 2026-08-17.';

-- -----------------------------------------------------------------------------
-- 2) commit_online_order
-- -----------------------------------------------------------------------------
-- NOT: public.complete_online_payment BU MIGRATION'DA KALDIRILMAZ.
-- Canlida su an v35 callback'i deploy edilmis durumda ve o surum hala
-- complete_online_payment cagiriyor. Burada dusurulurse, yeni Edge Function
-- deploy edilene kadar gecen surede online odemeler siparis olusturamaz.
-- Kaldirma islemi 20260817000041'e alindi; o migration yalnizca yeni
-- callback deploy edildikten SONRA uygulanmalidir.
create or replace function public.commit_online_order(
  p_payment_transaction_id uuid
)
returns table (
  order_id       uuid,
  order_group_id uuid,
  order_number   text,
  status         text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_payment       record;
  v_session       record;
  v_shop_item     record;
  v_reservation   record;
  v_item          jsonb;
  v_order_id      uuid;
  v_primary_order uuid;
  v_order_number  text;
  v_group_id      uuid;
  v_order_count   integer := 0;
  v_now           timestamptz := now();
begin
  -- ---------------------------------------------------------------------------
  -- 1) Odeme kaydi
  -- ---------------------------------------------------------------------------
  select * into v_payment
  from public.payment_transactions
  where id = p_payment_transaction_id
  for update;

  if not found then
    raise exception 'Payment transaction bulunamadi' using errcode = 'P0002';
  end if;

  -- Idempotent: siparis zaten olusturulmus.
  if v_payment.order_id is not null then
    select o.order_number, o.order_group_id
      into v_order_number, v_group_id
    from public.orders o where o.id = v_payment.order_id;
    return query select v_payment.order_id, v_group_id,
                        coalesce(v_order_number, ''), 'committed'::text;
    return;
  end if;

  -- KRITIK: yalnizca success. pending/failure durumda siparis olusturulmaz.
  if v_payment.payment_status <> 'success' then
    raise exception 'Order olusturulamaz: payment_status=% (yalnizca success izinli)',
      v_payment.payment_status using errcode = 'P0001';
  end if;

  -- ---------------------------------------------------------------------------
  -- 2) Checkout session
  -- ---------------------------------------------------------------------------
  if v_payment.checkout_session_id is null then
    raise exception 'payment_transactions.checkout_session_id NULL' using errcode = 'P0001';
  end if;

  select * into v_session
  from private.server_checkout_sessions
  where id = v_payment.checkout_session_id
  for update;

  if not found then
    raise exception 'Checkout session bulunamadi' using errcode = 'P0002';
  end if;

  if v_session.status = 'committed' and v_session.order_id is not null then
    select o.order_number, o.order_group_id
      into v_order_number, v_group_id
    from public.orders o where o.id = v_session.order_id;
    return query select v_session.order_id, v_group_id,
                        coalesce(v_order_number, ''), 'committed'::text;
    return;
  end if;

  if v_session.user_id <> v_payment.user_id then
    raise exception 'Session user_id ile payment user_id uyumsuz' using errcode = '42501';
  end if;

  -- ---------------------------------------------------------------------------
  -- 3) Tutar / kur dogrulamasi (sunucu beklentisine karsi)
  -- ---------------------------------------------------------------------------
  if v_session.expected_paid_price is not null
     and v_payment.paid_price is not null
     and abs(v_payment.paid_price - v_session.expected_paid_price) > 0.005 then
    raise exception 'Amount mismatch (session=%, payment=%)',
      v_session.expected_paid_price, v_payment.paid_price using errcode = 'P0001';
  end if;

  if v_session.expected_currency is not null
     and v_payment.currency <> v_session.expected_currency then
    raise exception 'Currency mismatch (session=%, payment=%)',
      v_session.expected_currency, v_payment.currency using errcode = 'P0001';
  end if;

  -- ---------------------------------------------------------------------------
  -- 4) Urun/stok yeniden dogrulamasi
  -- ---------------------------------------------------------------------------
  for v_item in select * from jsonb_array_elements(v_session.items_snapshot)
  loop
    declare
      v_stock     integer;
      v_available boolean;
    begin
      select p.stock_quantity, p.is_available
        into v_stock, v_available
      from public.products p
      where p.id = (v_item->>'product_id')::uuid;

      if not found or not coalesce(v_available, false) then
        raise exception 'Urun artik mevcut degil: %', v_item->>'product_id'
          using errcode = 'P0001';
      end if;

      if v_stock < (v_item->>'quantity')::integer then
        raise exception 'Stok yetersiz: %', v_item->>'product_id'
          using errcode = 'P0001';
      end if;
    end;
  end loop;

  -- ---------------------------------------------------------------------------
  -- 5) Siparisler (magaza basina bir order)
  -- ---------------------------------------------------------------------------
  v_group_id := coalesce(v_session.order_group_id, gen_random_uuid());

  for v_shop_item in
    select (e->>'shop_id')::uuid as shop_id,
           jsonb_agg(e)          as items
    from jsonb_array_elements(v_session.items_snapshot) as e
    group by (e->>'shop_id')
  loop
    declare
      v_subtotal        numeric := 0;
      v_delivery_fee    numeric := 0;
      v_coupon_discount numeric := 0;
      v_total           numeric := 0;
      v_inner           jsonb;
      v_coupon_shop_id  uuid;
    begin
      for v_inner in select * from jsonb_array_elements(v_shop_item.items)
      loop
        v_subtotal := v_subtotal + (v_inner->>'subtotal')::numeric;
      end loop;

      v_delivery_fee := coalesce(
        (v_session.sub_order_delivery_fees->>v_shop_item.shop_id::text)::numeric, 0
      );

      if v_session.coupon_id is not null then
        select sc.shop_id into v_coupon_shop_id
        from public.shop_coupons sc where sc.id = v_session.coupon_id;

        if v_coupon_shop_id = v_shop_item.shop_id
           and jsonb_array_length(v_session.items_snapshot)
               = jsonb_array_length(v_shop_item.items) then
          v_coupon_discount := v_session.server_coupon_discount;
        end if;
      end if;

      v_total := v_subtotal + v_delivery_fee - v_coupon_discount;

      -- search_path = '' altinda sequence adi da nitelenmeli.
      v_order_number := 'ORD' || lpad(nextval('public.order_number_seq')::text, 8, '0');

      insert into public.orders (
        user_id, shop_id, order_number, order_group_id, group_order_number,
        delivery_address_text, address_id, customer_phone,
        payment_method, payment_status, status,
        subtotal, delivery_fee, discount, coupon_id, coupon_discount, total,
        notes, checkout_session_id, payment_transaction_id,
        iyzico_payment_id, iyzico_conversation_id, committed_at,
        invoice_type, invoice_full_name, invoice_tax_number, invoice_tc_no,
        invoice_tax_office, invoice_address, invoice_email,
        created_at, updated_at
      ) values (
        v_payment.user_id, v_shop_item.shop_id, v_order_number, v_group_id, null,
        v_session.delivery_address_snapshot->>'address_line1',
        v_session.address_id,
        v_session.delivery_address_snapshot->>'phone',
        'online', 'paid', 'pending',
        v_subtotal, v_delivery_fee, v_session.server_discount,
        v_session.coupon_id, v_coupon_discount, v_total,
        v_session.notes, v_session.id, p_payment_transaction_id,
        v_payment.payment_id, v_payment.conversation_id, v_now,
        v_session.invoice_data->>'invoice_type',
        v_session.invoice_data->>'invoice_full_name',
        v_session.invoice_data->>'invoice_tax_number',
        v_session.invoice_data->>'invoice_tc_no',
        v_session.invoice_data->>'invoice_tax_office',
        v_session.invoice_data->>'invoice_address',
        v_session.invoice_data->>'invoice_email',
        v_now, v_now
      )
      returning id into v_order_id;

      for v_inner in select * from jsonb_array_elements(v_shop_item.items)
      loop
        insert into public.order_items (
          order_id, product_id, product_name, price, product_price,
          quantity, subtotal, product_image_url, shop_id, shop_name,
          flash_sale_id, flash_price, variant_data, created_at
        ) values (
          v_order_id,
          (v_inner->>'product_id')::uuid,
          v_inner->>'product_name',
          (v_inner->>'unit_price')::numeric,
          (v_inner->>'unit_price')::numeric,
          (v_inner->>'quantity')::integer,
          (v_inner->>'subtotal')::numeric,
          v_inner->>'image_url',
          (v_inner->>'shop_id')::uuid,
          v_inner->>'shop_name',
          nullif(v_inner->>'flash_sale_id','')::uuid,
          nullif(v_inner->>'flash_price','')::numeric,
          v_inner->'variant_data',
          v_now
        );
      end loop;

      if v_order_count = 0 then
        v_primary_order := v_order_id;
      end if;
      v_order_count := v_order_count + 1;
    end;
  end loop;

  -- ---------------------------------------------------------------------------
  -- 6) Kupon kullanim kaydi
  --
  -- Eski surum burada IKI kez use_coupon cagiriyordu; ilki sahte bir order_id
  -- ile kayit birakip idempotency kontrolunu etkisiz kiliyordu. Artik
  -- commit_cod_order (20260804000002:3057-3071) ile ayni tek adimli desen.
  -- ---------------------------------------------------------------------------
  if v_session.coupon_id is not null and v_session.server_coupon_discount > 0 then
    if not exists (
      select 1 from public.coupon_usages
      where coupon_id = v_session.coupon_id
        and order_id = v_primary_order
    ) then
      insert into public.coupon_usages (coupon_id, order_id, user_id, discount_amount)
      values (v_session.coupon_id, v_primary_order, v_payment.user_id,
              v_session.server_coupon_discount);

      update public.shop_coupons
      set usage_count = usage_count + 1
      where id = v_session.coupon_id;
    end if;
  end if;

  -- ---------------------------------------------------------------------------
  -- 7) Flash sale rezervasyonlarini commit et
  -- ---------------------------------------------------------------------------
  for v_reservation in
    select * from private.flash_sale_reservations
    where session_id = v_session.id and status = 'active'
    for update
  loop
    update public.flash_sales
    set sold_count = sold_count + v_reservation.quantity
    where id = v_reservation.sale_id;

    update private.flash_sale_reservations
    set status = 'committed', committed_at = v_now
    where id = v_reservation.id;
  end loop;

  -- ---------------------------------------------------------------------------
  -- 8) Baglantilari kur
  -- ---------------------------------------------------------------------------
  update public.payment_transactions
  set order_id = v_primary_order, updated_at = v_now
  where id = p_payment_transaction_id and order_id is null;

  update private.server_checkout_sessions
  set status                 = 'committed',
      committed_at           = v_now,
      order_id               = v_primary_order,
      order_group_order_id   = v_group_id,
      payment_transaction_id = p_payment_transaction_id,
      updated_at             = v_now
  where id = v_session.id;

  insert into private.server_checkout_audit
    (session_id, payment_transaction_id, user_id, event_type, detail)
  values (v_session.id, p_payment_transaction_id, v_payment.user_id,
          'session_committed', jsonb_build_object(
    'order_id',       v_primary_order,
    'order_group_id', v_group_id,
    'order_count',    v_order_count,
    'total',          v_session.server_total,
    'paid_price',     v_payment.paid_price,
    'payment_method', 'online'
  ));

  return query select v_primary_order, v_group_id, v_order_number, 'committed'::text;
end;
$$;

revoke all on function public.commit_online_order(uuid)
  from public, anon, authenticated;
grant execute on function public.commit_online_order(uuid) to service_role;

comment on function public.commit_online_order(uuid) is
  'Odeme basarili olduktan sonra checkout session snapshot''indan siparis olusturur. callback_data KULLANMAZ; tum tutarlar sunucudaki session''dan gelir. Yalnizca service_role. 2026-08-17.';

-- -----------------------------------------------------------------------------
-- 3) get_checkout_session_for_payment
--
-- iyzico-payment-init session'i soyle okuyordu:
--
--   await supabase.schema("private")
--     .from("server_checkout_sessions").select("*")
--     .eq("id", ...).eq("user_id", ...).single()
--
-- private semasi PostgREST'e expose edilmedigi icin bu cagri PGRST106 ile
-- basarisiz olur ve fonksiyon her istekte 404 "Checkout session bulunamadi"
-- doner. Yani sunucu-otoriteli online odeme daha ILK adimda kiriliyordu.
--
-- user_id parametresi zorunlu: fonksiyon service_role baglaminda calistigi
-- icin auth.uid() NULL'dir, sahiplik kontrolu burada acikca yapilir.
-- -----------------------------------------------------------------------------
create or replace function public.get_checkout_session_for_payment(
  p_session_id uuid,
  p_user_id    uuid
)
returns table (
  id                         uuid,
  user_id                    uuid,
  status                     text,
  payment_method             text,
  expires_at                 timestamptz,
  address_id                 uuid,
  items_snapshot             jsonb,
  delivery_address_snapshot  jsonb,
  server_total               numeric,
  server_delivery_fee        numeric,
  expected_paid_price        numeric
)
language sql
stable
security definer
set search_path = ''
as $$
  select s.id, s.user_id, s.status, s.payment_method, s.expires_at,
         s.address_id, s.items_snapshot, s.delivery_address_snapshot,
         s.server_total, s.server_delivery_fee, s.expected_paid_price
  from private.server_checkout_sessions s
  where s.id = p_session_id
    and s.user_id = p_user_id;
$$;

revoke all on function public.get_checkout_session_for_payment(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.get_checkout_session_for_payment(uuid, uuid)
  to service_role;

comment on function public.get_checkout_session_for_payment(uuid, uuid) is
  'iyzico-payment-init icin checkout session okuma. private semasi PostgREST''e acik olmadigi icin gereklidir. Sahiplik p_user_id ile acikca dogrulanir. Yalnizca service_role. 2026-08-17.';

-- -----------------------------------------------------------------------------
-- 4) link_checkout_session_payment
--
-- iyzico-payment-init soyle yaziyordu:
--
--   await supabase.schema("private")
--     .from("server_checkout_sessions")
--     .update({ expected_paid_price, expected_currency, ... })
--
-- private semasi PostgREST'e expose edilmedigi icin bu cagri PGRST106 ile
-- basarisiz oluyor; donen hata da kontrol edilmiyordu. Sonuc: session'daki
-- expected_paid_price hicbir zaman dolmuyor, dolayisiyla commit_online_order
-- icindeki tutar dogrulamasi (IS NOT NULL korumali) sessizce ATLANIYOR.
-- Yani odemenin tutar kontrolu tek bir kirik satir yuzunden devre disi.
-- -----------------------------------------------------------------------------
create or replace function public.link_checkout_session_payment(
  p_session_id              uuid,
  p_payment_transaction_id  uuid,
  p_expected_paid_price     numeric,
  p_expected_currency       text,
  p_expected_conversation_id text,
  p_expected_basket_id      text,
  p_iyzico_environment      text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_rows integer;
begin
  update private.server_checkout_sessions
  set expected_paid_price      = p_expected_paid_price,
      expected_currency        = p_expected_currency,
      expected_conversation_id = p_expected_conversation_id,
      expected_basket_id       = p_expected_basket_id,
      iyzico_environment       = p_iyzico_environment,
      payment_transaction_id   = p_payment_transaction_id,
      updated_at               = now()
  where id = p_session_id
    and status = 'pending';

  get diagnostics v_rows = row_count;
  return v_rows > 0;
end;
$$;

revoke all on function public.link_checkout_session_payment(
  uuid, uuid, numeric, text, text, text, text
) from public, anon, authenticated;
grant execute on function public.link_checkout_session_payment(
  uuid, uuid, numeric, text, text, text, text
) to service_role;

comment on function public.link_checkout_session_payment(
  uuid, uuid, numeric, text, text, text, text
) is
  'iyzico-payment-init: checkout session''a beklenen tutar/kur/ortam bilgisini ve payment_transaction baglantisini yazar. private semasi PostgREST''e acik olmadigi icin gereklidir. Yalnizca service_role. 2026-08-17.';

commit;

notify pgrst, 'reload schema';
