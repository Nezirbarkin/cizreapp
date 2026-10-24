-- Kendini geri alan canlı test (sonunda bilerek RAISE EXCEPTION 'TESTS_PASSED ...').
-- Çalıştırma: supabase db query --linked --file supabase/tests/manual/scheduled_slot_capacity_test.sql
do $$
declare
  v_shop  uuid := 'bfa361c4-16a5-407e-80a4-3506bb9aaf3d';
  v_owner uuid := '0a446b29-0f81-4825-ad42-5ff2fa409165';
  v_cust  uuid := '5daa4020-0e58-41ef-9336-54c5058295ec';
  v_all   jsonb := '{"monday":{"open":"09:00","close":"22:00","active":true},"tuesday":{"open":"09:00","close":"22:00","active":true},"wednesday":{"open":"09:00","close":"22:00","active":true},"thursday":{"open":"09:00","close":"22:00","active":true},"friday":{"open":"09:00","close":"22:00","active":true},"saturday":{"open":"09:00","close":"22:00","active":true},"sunday":{"open":"09:00","close":"22:00","active":true}}';
  v_slot  timestamptz;
  v_a uuid; v_b uuid; v_c uuid;
  v_sf    timestamptz;
  v_full  boolean;
  v_rem   integer;
  v_log   text := '';
begin
  update public.app_about_settings set scheduled_orders_enabled = true where true;
  update public.shops set scheduled_orders_enabled = true, scheduled_orders_admin_blocked = false,
         scheduled_slot_minutes = 60, scheduled_max_days = 2, scheduled_min_lead_minutes = 60,
         working_hours = v_all, scheduled_slot_capacity = null
   where id = v_shop;
  select g.slot_at into v_slot from public.get_shop_schedule_slots(v_shop) g order by g.slot_at limit 1 offset 3;

  -- Sınırsız: dolu değil, kalan NULL
  select is_full, remaining into v_full, v_rem from public.get_shop_schedule_slot_status(v_shop) where slot_at = v_slot;
  if v_full or v_rem is not null then raise exception 'FAIL unlimited % %', v_full, v_rem; end if;
  v_log := v_log || 'unlimited ok; ';

  update public.shops set scheduled_slot_capacity = 2 where id = v_shop;
  select is_full, remaining into v_full, v_rem from public.get_shop_schedule_slot_status(v_shop) where slot_at = v_slot;
  if v_full or v_rem <> 2 then raise exception 'FAIL cap2 empty % %', v_full, v_rem; end if;

  insert into public.orders (order_number, user_id, shop_id, delivery_address_text, payment_method, subtotal, total, status, scheduled_for)
  values ('TST-CAP-A', v_cust, v_shop, 'T', 'cash', 10, 10, 'pending', v_slot) returning id into v_a;
  insert into public.orders (order_number, user_id, shop_id, delivery_address_text, payment_method, subtotal, total, status, scheduled_for)
  values ('TST-CAP-B', v_cust, v_shop, 'T', 'cash', 10, 10, 'pending', v_slot) returning id into v_b;
  select is_full, remaining into v_full, v_rem from public.get_shop_schedule_slot_status(v_shop) where slot_at = v_slot;
  if not v_full or v_rem <> 0 then raise exception 'FAIL cap2 full % %', v_full, v_rem; end if;
  if public.validate_scheduled_order_slot(v_shop, v_slot) not like 'Seçtiğiniz saat doldu%' then
    raise exception 'FAIL validate full';
  end if;
  -- Başka saat etkilenmez
  if public.validate_scheduled_order_slot(v_shop, v_slot + interval '1 hour') is not null then
    raise exception 'FAIL other slot affected';
  end if;
  v_log := v_log || 'fills ok; ';

  -- Sunucu bağlamı (online ödeme sonrası): dolu saate de alınır, satıcıya bildirim
  insert into public.orders (order_number, user_id, shop_id, delivery_address_text, payment_method, subtotal, total, status, scheduled_for)
  values ('TST-CAP-C', v_cust, v_shop, 'T', 'online', 10, 10, 'pending', v_slot) returning id, scheduled_for into v_c, v_sf;
  if v_sf is distinct from v_slot then raise exception 'FAIL server overbook dropped'; end if;
  if not exists (select 1 from public.notifications where user_id = v_owner
                  and type = 'scheduled_slot_overbooked' and entity_id = v_c::text) then
    raise exception 'FAIL overbook notification';
  end if;
  v_log := v_log || 'server overbook kept+notified ok; ';

  -- İptal saati açar
  update public.orders set status = 'cancelled' where id in (v_a, v_c);
  select is_full, remaining into v_full, v_rem from public.get_shop_schedule_slot_status(v_shop) where slot_at = v_slot;
  if v_full or v_rem <> 1 then raise exception 'FAIL cancel frees % %', v_full, v_rem; end if;
  v_log := v_log || 'cancel frees ok; ';

  -- İstemci: son yeri alır, sonraki reddedilir
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', v_cust, 'role', 'authenticated')::text, true);
  insert into public.orders (order_number, user_id, shop_id, delivery_address_text, payment_method, subtotal, total, status, payment_status, scheduled_for)
  values ('TST-CAP-D', v_cust, v_shop, 'T', 'cash', 10, 10, 'pending', 'pending', v_slot);
  begin
    insert into public.orders (order_number, user_id, shop_id, delivery_address_text, payment_method, subtotal, total, status, payment_status, scheduled_for)
    values ('TST-CAP-E', v_cust, v_shop, 'T', 'cash', 10, 10, 'pending', 'pending', v_slot);
    raise exception 'FAIL client overbook accepted';
  exception when sqlstate '22023' then
    if sqlerrm not like 'Seçtiğiniz saat doldu%' then raise exception 'FAIL msg %', sqlerrm; end if;
  end;
  -- müşteri de doluluk RPC'sini okuyabilir
  select is_full into v_full from public.get_shop_schedule_slot_status(v_shop) where slot_at = v_slot;
  if not v_full then raise exception 'FAIL client view'; end if;
  v_log := v_log || 'client last seat + reject ok; ';

  raise exception 'TESTS_PASSED %', v_log;
end;
$$;
