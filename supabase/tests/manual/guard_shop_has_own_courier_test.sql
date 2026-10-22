-- Kendini geri alan canlı test (sonunda bilerek RAISE EXCEPTION 'TESTS_PASSED ...').
-- Çalıştırma: supabase db query --linked --file supabase/tests/manual/guard_shop_has_own_courier_test.sql
-- Sabit kimlikler canlıdaki gerçek admin/müşteri/satıcı/kurye/dükkân satırlarıdır; silinirse güncelleyin.
do $$
declare
  v_shop  uuid := 'bfa361c4-16a5-407e-80a4-3506bb9aaf3d';
  v_owner uuid := '0a446b29-0f81-4825-ad42-5ff2fa409165';
  v_admin uuid := '78665f8b-6a07-40f3-b13d-d4b5a29296c6';
  v_before boolean;
  v_after  boolean;
  v_log    text := '';
begin
  select has_own_courier into v_before from public.shops where id = v_shop;

  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
  update public.shops set has_own_courier = not coalesce(v_before, false), description = 'x-test'
   where id = v_shop;
  select has_own_courier into v_after from public.shops where id = v_shop;
  if v_after is distinct from v_before then raise exception 'FAIL seller changed courier'; end if;
  if (select description from public.shops where id = v_shop) <> 'x-test' then
    raise exception 'FAIL seller normal write blocked';
  end if;
  v_log := v_log || 'seller locked ok; ';

  perform set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  update public.shops set has_own_courier = not coalesce(v_before, false) where id = v_shop;
  select has_own_courier into v_after from public.shops where id = v_shop;
  if v_after is not distinct from v_before then raise exception 'FAIL admin cannot change'; end if;
  v_log := v_log || 'admin allowed ok; ';

  raise exception 'TESTS_PASSED %', v_log;
end;
$$;
