-- ============================================================================
-- 20261017000003_abuse_privacy_fixes — canlı davranış testi
-- ----------------------------------------------------------------------------
-- Kendi kendini geri alır (sonda ROLLBACK). Göç öncesi denemek için göç
-- gövdesini (BEGIN/COMMIT/NOTIFY hariç) @@MIGRATION@@ işaretli satırın yerine
-- koyun; uygulandıktan sonra olduğu gibi çalıştırın:
--   supabase db query --linked --file supabase/tests/manual/abuse_privacy_fixes_test.sql
-- ============================================================================
BEGIN;

-- @@MIGRATION@@

CREATE TEMP TABLE _abuse_results (n serial, line text) ON COMMIT DROP;

DO $test$
declare
  v_a uuid; v_b uuid;           -- v_a: eski akışta teslim edilmiş siparişi olan müşteri
  v_order uuid; v_shop uuid;
  v_sale uuid; v_product uuid; v_price numeric;
  v_sold0 int; v_sold int; v_mine int; v_cnt int;
  v_res jsonb; v_id uuid;
  r text := '';
begin
  select o.user_id, o.id, o.shop_id into v_a, v_order, v_shop
  from public.orders o
  where o.checkout_session_id is null and o.status = 'delivered' and o.return_status is null
  order by o.created_at desc limit 1;

  select p.id into v_b from public.profiles p
  where p.id <> v_a and p.role = 'customer' and coalesce(p.is_admin, false) = false
  order by p.created_at limit 1;

  select f.id, f.product_id, f.flash_price into v_sale, v_product, v_price
  from public.flash_sales f order by f.created_at desc limit 1;

  r := r || format('fixtures a=%s b=%s order=%s sale=%s',
                   v_a is not null, v_b is not null, v_order is not null, v_sale is not null);

  -- Flaş satışı test süresince aktif ve stoklu yap (geri alınır).
  update public.flash_sales
     set is_active = true, start_at = now() - interval '1 hour', end_at = now() + interval '1 hour',
         stock_limit = 100, sold_count = 10
   where id = v_sale;

  -- ------------------------------------------------ 1) get_pending_reviews
  perform set_config('request.jwt.claims', json_build_object('sub', v_b, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  select count(*) into v_cnt from public.get_pending_reviews(v_a);
  execute 'reset role';
  r := r || chr(10) || case when v_cnt = 0
    then 'PASS baskasinin bekleyen yorumlari okunamadi'
    else format('FAIL baskasinin bekleyen yorumlari okundu (%s satir)', v_cnt) end;

  -- ------------------------------------------------ 2) add_notification
  perform set_config('request.jwt.claims', json_build_object('sub', v_b, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  v_id := public.add_notification(v_a, 'admin_broadcast', 'Hesabiniz askiya alindi', 'tiklayin');
  execute 'reset role';
  r := r || chr(10) || case when v_id is null
    then 'PASS istemci admin turunde bildirim yazamadi'
    else 'FAIL istemci admin bildirimi yazdi' end;

  execute 'set local role authenticated';
  v_id := public.add_notification(v_a, 'order_update', 'Siparis', 'icerik', v_a, 'Sahte Ad', 'x.png', 'guard-test-entity');
  execute 'reset role';
  select count(*) into v_cnt from public.notifications
   where id = v_id and actor_id = v_b and actor_name is distinct from 'Sahte Ad';
  r := r || chr(10) || case when v_cnt = 1
    then 'PASS gonderen taklidi caginana cevrildi'
    else 'FAIL gonderen taklidi gecti' end;

  execute 'set local role authenticated';
  for i in 1..35 loop
    v_id := public.add_notification(v_a, 'post_like', 'Begeni', 'x', null, null, null, 'guard-rate-' || i);
  end loop;
  execute 'reset role';
  select count(*) into v_cnt from public.notifications
   where user_id = v_a and entity_id like 'guard-rate-%';
  r := r || chr(10) || case when v_cnt between 28 and 30
    then format('PASS hiz siniri calisti (%s/35 yazildi)', v_cnt)
    else format('FAIL hiz siniri (%s/35 yazildi)', v_cnt) end;

  -- ------------------------------------------------ 3) flaş satış
  select sold_count into v_sold0 from public.flash_sales where id = v_sale;

  perform set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  v_res := public.claim_flash_sale(v_sale, 2, v_b);  -- p_user_id yok sayılmalı
  execute 'reset role';
  select sold_count into v_sold from public.flash_sales where id = v_sale;
  select quantity into v_mine from private.flash_sale_claims where user_id = v_a and sale_id = v_sale;
  r := r || chr(10) || case when (v_res->>'success')::boolean and v_sold = v_sold0 + 2 and v_mine = 2
    then 'PASS claim stok ve talep defterini artirdi'
    else format('FAIL claim res=%s sold=%s mine=%s', v_res, v_sold, v_mine) end;

  perform set_config('request.jwt.claims', json_build_object('sub', v_b, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  v_res := public.release_flash_sale(v_sale, 50);
  execute 'reset role';
  select sold_count into v_sold from public.flash_sales where id = v_sale;
  r := r || chr(10) || case when v_sold = v_sold0 + 2
    then 'PASS baskasi release ile stok sayacini dusuremedi'
    else format('FAIL yabanci release sold=%s', v_sold) end;

  perform set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  v_res := public.claim_flash_sale(v_sale, 4, v_a);
  execute 'reset role';
  r := r || chr(10) || case when not (v_res->>'success')::boolean
    then 'PASS kisi basi talep siniri (5) uygulandi'
    else 'FAIL kisi basi sinir asildi' end;

  -- Eski akış: kalem siparişe dönüşür → talep tüketilir, sonraki clearCart release'i boşa düşer.
  insert into public.order_items (order_id, product_id, product_name, quantity, price, flash_sale_id, shop_id)
  values (v_order, v_product, 'guard-test', 2, v_price, v_sale, v_shop);
  select quantity into v_mine from private.flash_sale_claims where user_id = v_a and sale_id = v_sale;
  select sold_count into v_sold from public.flash_sales where id = v_sale;
  r := r || chr(10) || case when v_mine = 0 and v_sold = v_sold0 + 2
    then 'PASS siparis kalemi talebi tuketti, satis sayili kaldi'
    else format('FAIL tuketim mine=%s sold=%s', v_mine, v_sold) end;

  perform set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  v_res := public.release_flash_sale(v_sale, 2);   -- cartProvider.clearCart() davranışı
  execute 'reset role';
  select sold_count into v_sold from public.flash_sales where id = v_sale;
  r := r || chr(10) || case when v_sold = v_sold0 + 2
    then 'PASS odeme sonrasi clearCart satilani geri vermedi'
    else format('FAIL clearCart sonrasi sold=%s (beklenen %s)', v_sold, v_sold0 + 2) end;

  -- Talepsiz kalem (süresi dolmuş talep) → satış o anda sayılır.
  insert into public.order_items (order_id, product_id, product_name, quantity, price, flash_sale_id, shop_id)
  values (v_order, v_product, 'guard-test-2', 1, v_price, v_sale, v_shop);
  select sold_count into v_sold from public.flash_sales where id = v_sale;
  r := r || chr(10) || case when v_sold = v_sold0 + 3
    then 'PASS talepsiz flas kalem satis olarak sayildi'
    else format('FAIL talepsiz kalem sold=%s', v_sold) end;

  -- İptal → talep geri yazılır; süresi dolunca stok döner.
  update public.orders set status = 'cancelled' where id = v_order;
  select quantity into v_mine from private.flash_sale_claims where user_id = v_a and sale_id = v_sale;
  r := r || chr(10) || case when v_mine = 3
    then 'PASS iptal flas adetlerini talep olarak geri yazdi'
    else format('FAIL iptal sonrasi mine=%s', v_mine) end;

  update private.flash_sale_claims set updated_at = now() - interval '3 hours'
   where user_id = v_a and sale_id = v_sale;
  perform private.release_expired_flash_sale_claims();
  select sold_count into v_sold from public.flash_sales where id = v_sale;
  r := r || chr(10) || case when v_sold = v_sold0
    then 'PASS suresi dolan talep stoga dondu'
    else format('FAIL sure dolumu sold=%s (beklenen %s)', v_sold, v_sold0) end;

  insert into _abuse_results(line) values (r);
end
$test$;

SELECT string_agg(line, E'\n' ORDER BY n) AS result FROM _abuse_results;

ROLLBACK;
