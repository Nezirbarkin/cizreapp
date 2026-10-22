-- Kendini geri alan canlı test (sonunda bilerek RAISE EXCEPTION 'TESTS_PASSED ...').
-- Çalıştırma: supabase db query --linked --file supabase/tests/manual/scheduled_orders_test.sql
-- Sabit kimlikler canlıdaki gerçek admin/müşteri/satıcı/kurye/dükkân satırlarıdır; silinirse güncelleyin.
do $$
declare
  v_shop    uuid := 'bfa361c4-16a5-407e-80a4-3506bb9aaf3d';
  v_owner   uuid := '0a446b29-0f81-4825-ad42-5ff2fa409165';
  v_product uuid := '80e5df6a-e564-463c-92b4-57184596ea20';
  v_cust    uuid := '5daa4020-0e58-41ef-9336-54c5058295ec';
  v_courier uuid := '09d4668c-639e-417c-9304-fdd0ce5a045d';
  v_admin   uuid := '78665f8b-6a07-40f3-b13d-d4b5a29296c6';
  v_tz      text := 'Europe/Istanbul';
  v_log     text := '';
  v_n       integer;
  v_slot    timestamptz;
  v_far     timestamptz;
  v_txt     text;
  v_o1      uuid;
  v_o2      uuid;
  v_o3      uuid;
  v_far_o   uuid;
  v_near_o  uuid;
  v_pt      uuid;
  v_sf      timestamptz;
  v_bool    boolean;
  v_j       jsonb;
  v_all_day jsonb := '{"monday":{"open":"09:00","close":"22:00","active":true},"tuesday":{"open":"09:00","close":"22:00","active":true},"wednesday":{"open":"09:00","close":"22:00","active":true},"thursday":{"open":"09:00","close":"22:00","active":true},"friday":{"open":"09:00","close":"22:00","active":true},"saturday":{"open":"09:00","close":"22:00","active":true},"sunday":{"open":"09:00","close":"22:00","active":true}}';
  v_night   jsonb := '{"monday":{"open":"20:00","close":"02:00","active":true},"tuesday":{"open":"20:00","close":"02:00","active":true},"wednesday":{"open":"20:00","close":"02:00","active":true},"thursday":{"open":"20:00","close":"02:00","active":true},"friday":{"open":"20:00","close":"02:00","active":true},"saturday":{"open":"20:00","close":"02:00","active":true},"sunday":{"open":"20:00","close":"02:00","active":true}}';
begin
  -- 1) Global kapalı → saat yok
  update public.app_about_settings set scheduled_orders_enabled = false where true;
  update public.shops set scheduled_orders_enabled = true, scheduled_slot_minutes = 60,
         scheduled_max_days = 2, scheduled_min_lead_minutes = 60, working_hours = v_all_day
   where id = v_shop;
  select count(*) into v_n from public.get_shop_schedule_slots(v_shop);
  if v_n <> 0 then raise exception 'FAIL global off slots=%', v_n; end if;
  if public.validate_scheduled_order_slot(v_shop, now() + interval '3 hours')
     <> 'Randevulu sipariş şu an kullanılamıyor.' then raise exception 'FAIL global off validate'; end if;
  v_log := v_log || 'global off ok; ';

  -- 2) Açık: 09-22, 60 dk, 2 gün, 60 dk hazırlık
  update public.app_about_settings set scheduled_orders_enabled = true where true;
  select count(*) into v_n from public.get_shop_schedule_slots(v_shop);
  if v_n < 20 then raise exception 'FAIL slots too few %', v_n; end if;
  if exists (select 1 from public.get_shop_schedule_slots(v_shop) g
              where extract(minute from g.slot_at at time zone v_tz) <> 0
                 or (g.slot_at at time zone v_tz)::time < '09:00'
                 or (g.slot_at at time zone v_tz)::time > '21:00'
                 or g.slot_at < now() + interval '60 minutes'
                 or (g.slot_at at time zone v_tz)::date > (now() at time zone v_tz)::date + 2) then
    raise exception 'FAIL slot bounds';
  end if;
  v_log := v_log || 'slots(' || v_n || ') bounds ok; ';

  -- 3) Gece yarısını aşan çalışma: 20:00-02:00 → 01:00 var, 02:00 ve gündüz yok
  update public.shops set working_hours = v_night where id = v_shop;
  if not exists (select 1 from public.get_shop_schedule_slots(v_shop) g
                  where extract(hour from g.slot_at at time zone v_tz) = 1) then
    raise exception 'FAIL overnight 01:00 missing';
  end if;
  if exists (select 1 from public.get_shop_schedule_slots(v_shop) g
              where extract(hour from g.slot_at at time zone v_tz) between 2 and 19) then
    raise exception 'FAIL overnight bounds';
  end if;
  v_log := v_log || 'overnight ok; ';

  -- 4) Yalnız pazar 10-12, 14 gün ileri
  update public.shops set scheduled_max_days = 14,
         working_hours = '{"sunday":{"open":"10:00","close":"12:00","active":true},"monday":{"open":"10:00","close":"12:00","active":false}}'
   where id = v_shop;
  select count(*) into v_n from public.get_shop_schedule_slots(v_shop);
  if v_n < 2 or exists (select 1 from public.get_shop_schedule_slots(v_shop) g
                         where extract(isodow from g.slot_at at time zone v_tz) <> 7
                            or extract(hour from g.slot_at at time zone v_tz) not in (10, 11)) then
    raise exception 'FAIL sunday only n=%', v_n;
  end if;
  v_log := v_log || 'inactive days ok; ';

  -- 5) Çalışma saati yoksa 09-22
  update public.shops set working_hours = null, scheduled_max_days = 2 where id = v_shop;
  select count(*) into v_n from public.get_shop_schedule_slots(v_shop);
  if v_n < 20 then raise exception 'FAIL null hours %', v_n; end if;
  v_log := v_log || 'null hours default ok; ';

  update public.shops set working_hours = v_all_day where id = v_shop;
  select g.slot_at into v_slot from public.get_shop_schedule_slots(v_shop) g order by g.slot_at limit 1 offset 2;
  select g.slot_at into v_far from public.get_shop_schedule_slots(v_shop) g order by g.slot_at desc limit 1;

  -- 6) Doğrulama
  if public.validate_scheduled_order_slot(v_shop, v_slot) is not null then
    raise exception 'FAIL valid slot rejected';
  end if;
  if public.validate_scheduled_order_slot(v_shop, v_slot + interval '15 minutes') not like 'Seçtiğiniz%' then
    raise exception 'FAIL misaligned accepted';
  end if;
  update public.shops set scheduled_orders_admin_blocked = true where id = v_shop;
  if public.validate_scheduled_order_slot(v_shop, v_slot) <> 'Bu dükkan randevulu sipariş almıyor.'
     or exists (select 1 from public.get_shop_schedule_slots(v_shop)) then
    raise exception 'FAIL blocked';
  end if;
  update public.shops set scheduled_orders_admin_blocked = false where id = v_shop;
  v_log := v_log || 'validate ok; ';

  -- 7) Sunucu bağlamında ekleme asla düşmez
  insert into public.orders (order_number, user_id, shop_id, delivery_address_text, payment_method,
                             subtotal, total, status, scheduled_for)
  values ('TST-SCH-1', v_cust, v_shop, 'Test', 'cash', 10, 10, 'pending', now() - interval '1 hour')
  returning id, scheduled_for into v_o1, v_sf;
  if v_sf is not null then raise exception 'FAIL past kept'; end if;

  insert into public.orders (order_number, user_id, shop_id, delivery_address_text, payment_method,
                             subtotal, total, status, scheduled_for)
  values ('TST-SCH-2', v_cust, v_shop, 'Test', 'cash', 10, 10, 'confirmed', now() + interval '20 minutes')
  returning id, scheduled_for into v_near_o, v_sf;
  if v_sf is null then raise exception 'FAIL near future dropped'; end if;

  insert into public.orders (order_number, user_id, shop_id, delivery_address_text, payment_method,
                             subtotal, total, status, scheduled_for)
  values ('TST-SCH-3', v_cust, v_shop, 'Test', 'cash', 10, 10, 'confirmed', v_far)
  returning id, scheduled_for into v_far_o, v_sf;
  if v_sf is distinct from v_far then raise exception 'FAIL far valid changed'; end if;
  v_log := v_log || 'server insert ok; ';

  -- 8) Online ödeme sonrası sipariş randevuyu taşır (bozuk değer düşürmez)
  insert into public.payment_transactions (user_id, amount, conversation_id, currency, payment_status, callback_data)
  values (v_cust, 10, 'tst_sched_' || gen_random_uuid(), 'TRY', 'success',
          jsonb_build_object('user_id', v_cust, 'order_data', jsonb_build_object(
            'shop_id', v_shop, 'delivery_address_text', 'Test', 'total', 10, 'subtotal', 10,
            'delivery_fee', 0, 'scheduled_for', v_slot,
            'items', jsonb_build_array(jsonb_build_object(
              'product_id', v_product, 'product_name', 'Test', 'quantity', 1, 'price', 10)))))
  returning id into v_pt;
  v_o2 := public.complete_online_payment(v_pt);
  select scheduled_for into v_sf from public.orders where id = v_o2;
  if v_sf is distinct from v_slot then raise exception 'FAIL online slot % vs %', v_sf, v_slot; end if;

  insert into public.payment_transactions (user_id, amount, conversation_id, currency, payment_status, callback_data)
  values (v_cust, 10, 'tst_sched_' || gen_random_uuid(), 'TRY', 'success',
          jsonb_build_object('user_id', v_cust, 'order_data', jsonb_build_object(
            'shop_id', v_shop, 'delivery_address_text', 'Test', 'total', 10, 'subtotal', 10,
            'delivery_fee', 0, 'scheduled_for', 'bozuk-tarih',
            'items', jsonb_build_array(jsonb_build_object(
              'product_id', v_product, 'product_name', 'Test', 'quantity', 1, 'price', 10)))))
  returning id into v_pt;
  v_o3 := public.complete_online_payment(v_pt);
  if v_o3 is null or (select scheduled_for from public.orders where id = v_o3) is not null then
    raise exception 'FAIL online garbage';
  end if;
  v_log := v_log || 'online ok; ';

  -- 9) Hatırlatma: 20 dk kalan siparişe bir kez
  v_n := private.notify_due_scheduled_orders();
  if not exists (select 1 from public.notifications where user_id = v_owner
                  and type = 'scheduled_order_reminder' and entity_id = v_near_o::text) then
    raise exception 'FAIL reminder missing (n=%)', v_n;
  end if;
  if exists (select 1 from public.notifications where type = 'scheduled_order_reminder'
              and entity_id = v_far_o::text) then
    raise exception 'FAIL far reminded';
  end if;
  if private.notify_due_scheduled_orders() <> 0 then raise exception 'FAIL reminder twice'; end if;
  v_log := v_log || 'reminder ok; ';

  -- ===== istemci bağlamı =====
  perform set_config('role', 'authenticated', true);

  -- 10) Satıcı: admin engelini değiştiremez, kendi ayarını değiştirebilir
  perform set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
  update public.shops set scheduled_orders_admin_blocked = true, scheduled_slot_minutes = 30 where id = v_shop;
  select scheduled_orders_admin_blocked into v_bool from public.shops where id = v_shop;
  if v_bool then raise exception 'FAIL seller set admin block'; end if;
  if (select scheduled_slot_minutes from public.shops where id = v_shop) <> 30 then
    raise exception 'FAIL seller own setting';
  end if;
  update public.shops set scheduled_slot_minutes = 60 where id = v_shop;
  v_log := v_log || 'shop guard ok; ';

  -- 11) Satıcı: randevu zamanını değiştiremez
  begin
    update public.orders set scheduled_for = now() + interval '1 day' where id = v_far_o;
    raise exception 'FAIL seller changed scheduled_for';
  exception when sqlstate '42501' then null;
  end;
  -- 12) Satıcı erken kurye çağıramaz
  begin
    perform public.assign_order_to_courier(v_far_o, null);
    raise exception 'FAIL early assign allowed';
  exception when others then
    if sqlerrm not like '%scheduled_too_early%' then raise exception 'FAIL early assign msg %', sqlerrm; end if;
  end;
  v_log := v_log || 'order guard + early assign ok; ';

  -- 13) Müşteri: geçersiz randevuyla ekleyemez, geçerliyle ekler
  perform set_config('request.jwt.claims', json_build_object('sub', v_cust, 'role', 'authenticated')::text, true);
  begin
    insert into public.orders (order_number, user_id, shop_id, delivery_address_text, payment_method,
                               subtotal, total, status, payment_status, scheduled_for)
    values ('TST-SCH-C1', v_cust, v_shop, 'Test', 'cash', 10, 10, 'pending', 'pending', v_slot + interval '7 minutes');
    raise exception 'FAIL client invalid accepted';
  exception when sqlstate '22023' then null;
  end;
  insert into public.orders (order_number, user_id, shop_id, delivery_address_text, payment_method,
                             subtotal, total, status, payment_status, scheduled_for)
  values ('TST-SCH-C2', v_cust, v_shop, 'Test', 'cash', 10, 10, 'pending', 'pending', v_slot);
  v_log := v_log || 'client insert ok; ';

  -- 14) Kurye havuzu: uzak randevu gizli, yakın görünür
  perform set_config('request.jwt.claims', json_build_object('sub', v_courier, 'role', 'authenticated')::text, true);
  if exists (select 1 from public.get_available_orders_for_courier() g where g.id = v_far_o) then
    raise exception 'FAIL far visible to courier';
  end if;
  if not exists (select 1 from public.get_available_orders_for_courier() g
                  where g.id = v_near_o and g.scheduled_for is not null) then
    raise exception 'FAIL near not visible to courier';
  end if;
  v_log := v_log || 'courier pool ok; ';

  -- 15) Admin dükkan listesi randevu alanlarını döndürür
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  v_j := public.admin_shops_page(null, null, 'default', 100, 0);
  if not (v_j -> 'rows' -> 0 ? 'scheduled_orders_enabled')
     or not (v_j -> 'rows' -> 0 ? 'scheduled_orders_admin_blocked') then
    raise exception 'FAIL admin_shops_page fields';
  end if;
  v_log := v_log || 'admin page ok; ';

  raise exception 'TESTS_PASSED %', v_log;
end;
$$;
