-- =============================================================================
-- FIX: "column reference ... is ambiguous" (SQLSTATE 42702)
--
-- SORUN: 20260817000040'ta tanimlanan iki fonksiyon RETURNS TABLE kullaniyor.
-- plpgsql'de RETURNS TABLE sutunlari fonksiyon govdesinde DEGISKEN olarak
-- kapsamda olur. Ayni ada sahip bir tablo sutununa NITELENMEDEN atifta
-- bulunuldugunda plpgsql hangisinin kastedildigini cozemez ve
-- 42702 "column reference is ambiguous" hatasi verir.
--
-- Hata calisma zamaninda ve yalnizca ilgili deyime ULASILDIGINDA ortaya
-- cikar (plpgsql deyimleri tembel planlar); bu yuzden migration sorunsuz
-- uygulanir, ACL testleri gecer ve hata ancak gercek bir odemede gorulur.
--
-- Bulunan 4 nokta:
--
--   atomic_finalize_payment_transaction  (OUT: payment_status,
--                                              reconciliation_status)
--     1) ...where id = p_transaction_id and payment_status = 'pending'
--
--   commit_online_order                  (OUT: order_id, order_group_id,
--                                              order_number, status)
--     2) select 1 from public.coupon_usages
--          where coupon_id = ... and order_id = v_primary_order
--     3) from private.flash_sale_reservations
--          where session_id = ... and status = 'active'
--     4) update public.payment_transactions
--          ... where id = ... and order_id is null
--
-- Yalnizca (1) canli akista tetikleniyordu (eski callback bu RPC'yi cagiriyor).
-- (2)-(4) Flow A cutover'inda patlayacakti.
--
-- COZUM: tum hedef tablolara takma ad verilip atiflar nitelenir. Ayni desen
-- 20260727000004_fix_plpgsql_lint_errors.sql:497'de kullanilmisti; 20260817000040
-- yazilirken kaybedilmis.
--
-- NOT: OUT sutun adlari DEGISTIRILMEZ — Edge Function'lar donen JSON
-- anahtarlarini (updated, already_processed, reconciliation_status, order_id)
-- bu adlarla okuyor.
--
-- Imzalar birebir ayni oldugu icin CREATE OR REPLACE mevcut ACL'i korur;
-- yine de grant'lar sonda yeniden uygulanir.
-- =============================================================================

begin;

-- -----------------------------------------------------------------------------
-- 1) atomic_finalize_payment_transaction
-- -----------------------------------------------------------------------------
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
  p_status                text,
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

  if v_current_status is distinct from 'pending' then
    return query select false, true, v_current_status, null::text;
    return;
  end if;

  -- Mutabakat kontrolleri yalnizca sunucu-otoriteli akista (session dolu).
  -- Eski akis kayitlarinda checkout_session_id NULL'dur ve davranis degismez.
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

      update public.payment_transactions pt
      set payment_status        = 'failure',
          reconciliation_status = v_reconciliation,
          error_code            = p_error_code,
          error_message         = coalesce(p_error_message,
                                           'Reconciliation gerekli: ' || v_reconciliation),
          error_group           = p_error_group,
          callback_received_at  = p_callback_received_at,
          callback_data         = coalesce(pt.callback_data, '{}'::jsonb) || p_merged_callback_data,
          updated_at            = now()
      where pt.id = p_transaction_id;

      return query select true, false, 'failure'::text, v_reconciliation;
      return;
    end if;
  end if;

  update public.payment_transactions pt
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
      callback_data        = coalesce(pt.callback_data, '{}'::jsonb) || p_merged_callback_data,
      error_code           = p_error_code,
      error_message        = p_error_message,
      error_group          = p_error_group,
      updated_at           = now()
  where pt.id = p_transaction_id
    -- FIX: nitelenmemis "payment_status" OUT sutunuyla cakisiyordu (42702).
    and pt.payment_status = 'pending';

  get diagnostics v_rows = row_count;

  if v_rows = 0 then
    return query select false, true, v_current_status, v_reconciliation;
  else
    return query select true, false, p_status, v_reconciliation;
  end if;
end;
$$;

-- -----------------------------------------------------------------------------
-- 2) commit_online_order
-- -----------------------------------------------------------------------------
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
  select * into v_payment
  from public.payment_transactions pt
  where pt.id = p_payment_transaction_id
  for update;

  if not found then
    raise exception 'Payment transaction bulunamadi' using errcode = 'P0002';
  end if;

  if v_payment.order_id is not null then
    select o.order_number, o.order_group_id
      into v_order_number, v_group_id
    from public.orders o where o.id = v_payment.order_id;
    return query select v_payment.order_id, v_group_id,
                        coalesce(v_order_number, ''), 'committed'::text;
    return;
  end if;

  if v_payment.payment_status <> 'success' then
    raise exception 'Order olusturulamaz: payment_status=% (yalnizca success izinli)',
      v_payment.payment_status using errcode = 'P0001';
  end if;

  if v_payment.checkout_session_id is null then
    raise exception 'payment_transactions.checkout_session_id NULL' using errcode = 'P0001';
  end if;

  select * into v_session
  from private.server_checkout_sessions s
  where s.id = v_payment.checkout_session_id
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

  if v_session.coupon_id is not null and v_session.server_coupon_discount > 0 then
    if not exists (
      select 1 from public.coupon_usages cu
      where cu.coupon_id = v_session.coupon_id
        -- FIX: nitelenmemis "order_id" OUT sutunuyla cakisiyordu (42702).
        and cu.order_id = v_primary_order
    ) then
      insert into public.coupon_usages (coupon_id, order_id, user_id, discount_amount)
      values (v_session.coupon_id, v_primary_order, v_payment.user_id,
              v_session.server_coupon_discount);

      update public.shop_coupons sc
      set usage_count = sc.usage_count + 1
      where sc.id = v_session.coupon_id;
    end if;
  end if;

  for v_reservation in
    select * from private.flash_sale_reservations fsr
    -- FIX: nitelenmemis "status" OUT sutunuyla cakisiyordu (42702).
    where fsr.session_id = v_session.id and fsr.status = 'active'
    for update
  loop
    update public.flash_sales fs
    set sold_count = fs.sold_count + v_reservation.quantity
    where fs.id = v_reservation.sale_id;

    update private.flash_sale_reservations fsr
    set status = 'committed', committed_at = v_now
    where fsr.id = v_reservation.id;
  end loop;

  update public.payment_transactions pt
  set order_id = v_primary_order, updated_at = v_now
  where pt.id = p_payment_transaction_id
    -- FIX: nitelenmemis "order_id" OUT sutunuyla cakisiyordu (42702).
    and pt.order_id is null;

  update private.server_checkout_sessions s
  set status                 = 'committed',
      committed_at           = v_now,
      order_id               = v_primary_order,
      order_group_order_id   = v_group_id,
      payment_transaction_id = p_payment_transaction_id,
      updated_at             = v_now
  where s.id = v_session.id;

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

-- -----------------------------------------------------------------------------
-- Grant'lari yeniden uygula (imza degismedi, ACL korunur; yine de acik olsun)
-- -----------------------------------------------------------------------------
revoke all on function public.atomic_finalize_payment_transaction(
  uuid, text, numeric, text, text, text, text, text, integer, text,
  integer, text, text, text, timestamptz, jsonb
) from public, anon, authenticated;
grant execute on function public.atomic_finalize_payment_transaction(
  uuid, text, numeric, text, text, text, text, text, integer, text,
  integer, text, text, text, timestamptz, jsonb
) to service_role;

revoke all on function public.commit_online_order(uuid) from public, anon, authenticated;
grant execute on function public.commit_online_order(uuid) to service_role;

commit;

notify pgrst, 'reload schema';
