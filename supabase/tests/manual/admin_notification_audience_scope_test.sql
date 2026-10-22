-- Kendini geri alan canlı test (sonunda bilerek RAISE EXCEPTION 'TESTS_PASSED ...').
-- Çalıştırma: supabase db query --linked --file supabase/tests/manual/admin_notification_audience_scope_test.sql
-- Sabit kimlikler canlıdaki gerçek admin/müşteri/satıcı/kurye/dükkân satırlarıdır; silinirse güncelleyin.
do $$
declare
  v_admin   uuid := '78665f8b-6a07-40f3-b13d-d4b5a29296c6';
  v_cust    uuid := '5daa4020-0e58-41ef-9336-54c5058295ec';
  v_owner   uuid := '0a446b29-0f81-4825-ad42-5ff2fa409165';
  v_courier uuid := '09d4668c-639e-417c-9304-fdd0ce5a045d';
  v_b_all   uuid := gen_random_uuid();
  v_b_old   uuid := gen_random_uuid();
  v_b_sel   uuid := gen_random_uuid();
  v_b_cou   uuid := gen_random_uuid();
  v_b_cus   uuid := gen_random_uuid();
  v_tok     text := 'test-token-' || gen_random_uuid();
  v_log     text := '';
  v_n       integer;
  v_ids     uuid[];
begin
  -- Hazırlık (postgres): her kitleden bir duyuru, test token'ları
  insert into public.admin_broadcasts (id, title, content, icon_type, target_audience, is_active, created_by)
  values (v_b_all, 'A', 'a', 'info', 'all_users', true, v_admin),
         (v_b_old, 'O', 'o', 'info', 'all', true, v_admin),
         (v_b_sel, 'S', 's', 'info', 'sellers', true, v_admin),
         (v_b_cou, 'K', 'k', 'info', 'couriers', true, v_admin),
         (v_b_cus, 'M', 'm', 'info', 'customers', true, v_admin);

  update public.profiles set fcm_token = v_tok where id = v_owner;
  insert into public.notification_tokens (user_id, token, device_type) values (v_owner, v_tok, 'android');

  -- Alıcılar: rolü customer'a çekilen dükkan sahibi yine "Satıcılar"da
  update public.profiles set role = 'customer' where id = v_owner;
  select array_agg(r) into v_ids from private.admin_notification_recipients('sellers', null, v_admin) r;
  if not (v_owner = any(v_ids)) then raise exception 'FAIL owner not in sellers'; end if;
  if v_cust = any(v_ids) then raise exception 'FAIL customer in sellers'; end if;
  update public.profiles set role = 'seller' where id = v_owner;
  v_log := v_log || 'recipients ok; ';

  perform set_config('role', 'authenticated', true);

  -- Müşteri: herkes + eski 'all' + müşteri; satıcı/kurye yok
  perform set_config('request.jwt.claims', json_build_object('sub', v_cust, 'role', 'authenticated')::text, true);
  select count(*) into v_n from public.admin_broadcasts where id in (v_b_all, v_b_old, v_b_cus);
  if v_n <> 3 then raise exception 'FAIL customer sees own % ', v_n; end if;
  if exists (select 1 from public.admin_broadcasts where id in (v_b_sel, v_b_cou)) then
    raise exception 'FAIL customer sees seller/courier broadcast';
  end if;
  v_log := v_log || 'customer scoped ok; ';

  -- Satıcı (dükkan sahibi): satıcı duyurusunu görür, kurye/müşteri duyurusunu görmez
  perform set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
  if not exists (select 1 from public.admin_broadcasts where id = v_b_sel) then
    raise exception 'FAIL seller cannot see seller broadcast';
  end if;
  if exists (select 1 from public.admin_broadcasts where id in (v_b_cou, v_b_cus)) then
    raise exception 'FAIL seller sees other audience';
  end if;
  v_log := v_log || 'seller scoped ok; ';

  -- Kurye
  perform set_config('request.jwt.claims', json_build_object('sub', v_courier, 'role', 'authenticated')::text, true);
  if not exists (select 1 from public.admin_broadcasts where id = v_b_cou)
     or exists (select 1 from public.admin_broadcasts where id in (v_b_sel, v_b_cus)) then
    raise exception 'FAIL courier scope';
  end if;
  v_log := v_log || 'courier scoped ok; ';

  -- Admin hepsini görür
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  select count(*) into v_n from public.admin_broadcasts where id in (v_b_all, v_b_old, v_b_sel, v_b_cou, v_b_cus);
  if v_n <> 5 then raise exception 'FAIL admin sees % ', v_n; end if;
  v_log := v_log || 'admin all ok; ';

  -- Token devri: müşteri aynı cihazdan giriş yapınca satıcıdaki token silinir
  perform set_config('request.jwt.claims', json_build_object('sub', v_cust, 'role', 'authenticated')::text, true);
  perform public.set_my_fcm_token(v_tok);
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  if (select fcm_token from public.profiles where id = v_owner) is not null then
    raise exception 'FAIL token kept on previous account';
  end if;
  if (select fcm_token from public.profiles where id = v_cust) is distinct from v_tok then
    raise exception 'FAIL token not set on new account';
  end if;
  v_log := v_log || 'token handover ok; ';

  raise exception 'TESTS_PASSED %', v_log;
end;
$$;
