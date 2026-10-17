-- ============================================================================
-- 20261017000004_stock_back_alerts — canlı davranış testi (kendini geri alır)
-- Göç öncesi: göç gövdesini @@MIGRATION@@ işaretli satırın yerine koyun.
--   supabase db query --linked --file supabase/tests/manual/stock_back_alerts_test.sql
-- ============================================================================
BEGIN;

-- @@MIGRATION@@

CREATE TEMP TABLE _stock_results (n serial, line text) ON COMMIT DROP;

DO $test$
declare
  v_a uuid; v_b uuid; v_product uuid;
  v_cnt int;
  r text := '';
begin
  select p.id into v_product from public.products p
  where coalesce(p.product_type, 'physical') <> 'digital'
  order by p.created_at desc limit 1;

  select id into v_a from public.profiles
  where role = 'customer' and coalesce(is_admin, false) = false
  order by created_at limit 1;
  select id into v_b from public.profiles
  where role = 'customer' and coalesce(is_admin, false) = false and id <> v_a
  order by created_at limit 1;

  r := r || format('fixtures product=%s a=%s b=%s', v_product is not null, v_a is not null, v_b is not null);

  -- Ürünü tükenmiş yap (sunucu bağlamı).
  update public.products
     set stock_quantity = 0, stock_unlimited = false, is_available = true
   where id = v_product;

  -- A abone olur
  perform set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  insert into public.stock_alerts (user_id, product_id) values (v_a, v_product);
  execute 'reset role';

  -- B, A adına abone olamaz ve A'nın aboneliğini göremez
  perform set_config('request.jwt.claims', json_build_object('sub', v_b, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  begin
    insert into public.stock_alerts (user_id, product_id) values (v_a, v_product);
    r := r || chr(10) || 'FAIL B, A adina abone olabildi';
  exception when others then
    r := r || chr(10) || 'PASS B, A adina abone olamadi (' || sqlstate || ')';
  end;
  select count(*) into v_cnt from public.stock_alerts where product_id = v_product;
  r := r || chr(10) || case when v_cnt = 0 then 'PASS B baskasinin aboneligini goremedi'
                            else 'FAIL B baskasinin aboneligini gordu' end;
  execute 'reset role';

  -- Stok geri gelir → A'ya bildirim, abonelik silinir
  update public.products set stock_quantity = 5 where id = v_product;
  select count(*) into v_cnt from public.notifications
   where user_id = v_a and type = 'stock_back' and entity_id = v_product::text
     and created_at > now() - interval '1 minute';
  r := r || chr(10) || case when v_cnt = 1 then 'PASS stok gelince bildirim gitti'
                            else format('FAIL bildirim sayisi %s', v_cnt) end;
  select count(*) into v_cnt from public.stock_alerts where product_id = v_product;
  r := r || chr(10) || case when v_cnt = 0 then 'PASS abonelik tek seferlik silindi'
                            else 'FAIL abonelik kaldi' end;

  -- Stok artışı (5 → 6) tekrar bildirim üretmez
  update public.products set stock_quantity = 6 where id = v_product;
  select count(*) into v_cnt from public.notifications
   where user_id = v_a and type = 'stock_back' and entity_id = v_product::text;
  r := r || chr(10) || case when v_cnt = 1 then 'PASS stok artisi tekrar bildirmedi'
                            else format('FAIL tekrar bildirim (%s)', v_cnt) end;

  -- is_available false → true de "geri geldi" sayılır
  perform set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
  update public.products set is_available = false where id = v_product;
  execute 'set local role authenticated';
  insert into public.stock_alerts (user_id, product_id) values (v_a, v_product);
  execute 'reset role';
  update public.products set is_available = true where id = v_product;
  select count(*) into v_cnt from public.stock_alerts where product_id = v_product;
  r := r || chr(10) || case when v_cnt = 0 then 'PASS satisa yeniden acilinca bildirildi'
                            else 'FAIL is_available donusu bildirmedi' end;

  insert into _stock_results(line) values (r);
end
$test$;

SELECT string_agg(line, E'\n' ORDER BY n) AS result FROM _stock_results;

ROLLBACK;
