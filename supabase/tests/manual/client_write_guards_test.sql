-- ============================================================================
-- 20261017000001_security_client_write_guards — canlı davranış testi
-- ----------------------------------------------------------------------------
-- Kendi kendini geri alır (sonda ROLLBACK). Göç uygulanmadan önce denemek
-- için göç gövdesini (BEGIN/COMMIT/NOTIFY hariç) @@MIGRATION@@ işaretli satırın
-- yerine koyun; uygulandıktan sonra olduğu gibi çalıştırın:
--   supabase db query --linked --file supabase/tests/manual/client_write_guards_test.sql
-- Çıktı: tek satır "result" = her kontrolün PASS/FAIL özeti.
-- ============================================================================
BEGIN;

-- @@MIGRATION@@

CREATE TEMP TABLE _guard_results (n serial, line text) ON COMMIT DROP;

DO $test$
declare
  v_owner uuid; v_shop uuid; v_order uuid; v_order_cust uuid;
  v_rev uuid; v_rev_author uuid;
  v_courier uuid; v_asg uuid;
  v_before jsonb; v_after jsonb;
  v_cnt int;
  r text := '';

begin
  -- Fikstürler: kendi dükkânında teslim edilmiş nakit siparişi olan satıcı
  select s.owner_id, s.id, o.id, o.user_id
    into v_owner, v_shop, v_order, v_order_cust
  from public.shops s
  join public.orders o on o.shop_id = s.id
  join public.profiles p on p.id = s.owner_id
  where p.role <> 'admin' and coalesce(p.is_admin, false) = false
    and o.user_id <> s.owner_id
    and o.payment_method = 'cash'
  order by o.created_at desc
  limit 1;

  select sr.id, sr.user_id into v_rev, v_rev_author
  from public.shop_reviews sr
  join public.shops s on s.id = sr.shop_id
  join public.profiles p on p.id = s.owner_id
  where sr.user_id <> s.owner_id
    and p.role <> 'admin' and coalesce(p.is_admin, false) = false
    and not exists (select 1 from public.profiles a where a.id = sr.user_id and (a.role = 'admin' or a.is_admin))
  limit 1;

  select ca.courier_id, ca.id into v_courier, v_asg
  from public.courier_assignments ca
  join public.profiles p on p.id = ca.courier_id
  where p.role <> 'admin' and coalesce(p.is_admin, false) = false
  limit 1;

  r := r || chr(10) || format('fixtures shop=%s order=%s review=%s assignment=%s',
                   v_shop is not null, v_order is not null, v_rev is not null, v_asg is not null);

  -- ---------------------------------------------------------------- satıcı
  perform set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';

  begin
    update public.shops set commission_rate = 0 where id = v_shop;
    r := r || chr(10) || 'FAIL shops.commission_rate degisti';
  exception when insufficient_privilege then
    r := r || chr(10) || 'PASS shops.commission_rate engellendi';
  end;

  begin
    update public.shops set pending_payout = coalesce(pending_payout, 0) + 1000 where id = v_shop;
    r := r || chr(10) || 'FAIL shops.pending_payout degisti';
  exception when insufficient_privilege then
    r := r || chr(10) || 'PASS shops.pending_payout engellendi';
  end;

  execute 'reset role';
  select to_jsonb(s) into v_before from public.shops s where id = v_shop;
  execute 'set local role authenticated';
  update public.shops
     set is_approved = not coalesce(is_approved, false),
         is_verified = true, is_pinned = true, rating = 5, review_count = 999,
         description = coalesce(description, '')
   where id = v_shop;
  get diagnostics v_cnt = row_count;
  execute 'reset role';
  select to_jsonb(s) into v_after from public.shops s where id = v_shop;
  r := r || chr(10) || case when v_cnt = 1
                  and v_after->'is_approved' = v_before->'is_approved'
                  and v_after->'is_verified' = v_before->'is_verified'
                  and v_after->'is_pinned'   = v_before->'is_pinned'
                  and v_after->'rating'      = v_before->'rating'
                  and v_after->'review_count' = v_before->'review_count'
             then 'PASS shops moderasyon sutunlari sessizce korundu, guncelleme gecti'
             else format('FAIL shops moderasyon rows=%s before=%s after=%s', v_cnt,
                         v_before->>'is_approved', v_after->>'is_approved') end;
  execute 'set local role authenticated';

  begin
    update public.orders set seller_credit_amount = 999999 where id = v_order;
    r := r || chr(10) || 'FAIL orders.seller_credit_amount degisti';
  exception when insufficient_privilege then
    r := r || chr(10) || 'PASS orders.seller_credit_amount engellendi';
  end;

  begin
    update public.orders set status = 'pending' where id = v_order and status in ('delivered', 'cancelled');
    get diagnostics v_cnt = row_count;
    r := r || chr(10) || case when v_cnt = 0 then 'SKIP terminal siparis yok' else 'FAIL terminal siparis geri acildi' end;
  exception when insufficient_privilege then
    r := r || chr(10) || 'PASS terminal siparis durumu degistirilemedi';
  end;

  if v_rev is not null then
    execute 'reset role';
    perform set_config('request.jwt.claims',
      json_build_object('sub', (select s.owner_id from public.shops s join public.shop_reviews sr on sr.shop_id = s.id where sr.id = v_rev), 'role', 'authenticated')::text, true);
    select to_jsonb(sr) into v_before from public.shop_reviews sr where id = v_rev;
    execute 'set local role authenticated';
    update public.shop_reviews set rating = 5, comment = 'degisti', seller_reply = 'test cevap' where id = v_rev;
    get diagnostics v_cnt = row_count;
    execute 'reset role';
    select to_jsonb(sr) into v_after from public.shop_reviews sr where id = v_rev;
    r := r || chr(10) || case when v_cnt = 1
                    and v_after->'rating' = v_before->'rating'
                    and v_after->'comment' = v_before->'comment'
                    and v_after->>'seller_reply' = 'test cevap'
               then 'PASS satici yorum puanini degistiremedi, cevap yazabildi'
               else format('FAIL satici yorum rows=%s rating %s->%s reply=%s', v_cnt,
                           v_before->>'rating', v_after->>'rating', v_after->>'seller_reply') end;

    -- yorum sahibi
    perform set_config('request.jwt.claims', json_build_object('sub', v_rev_author, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    update public.shop_reviews set seller_reply = 'sahte cevap', comment = 'yazar degistirdi' where id = v_rev;
    get diagnostics v_cnt = row_count;
    execute 'reset role';
    select to_jsonb(sr) into v_after from public.shop_reviews sr where id = v_rev;
    r := r || chr(10) || case when v_cnt = 1
                    and v_after->>'seller_reply' = 'test cevap'
                    and v_after->>'comment' = 'yazar degistirdi'
               then 'PASS yazar sahte satici cevabi yazamadi, kendi metnini degistirebildi'
               else format('FAIL yazar rows=%s reply=%s comment=%s', v_cnt,
                           v_after->>'seller_reply', v_after->>'comment') end;
  end if;
  execute 'reset role';

  -- ---------------------------------------------------------------- müşteri
  perform set_config('request.jwt.claims', json_build_object('sub', v_order_cust, 'role', 'authenticated')::text, true);
  select to_jsonb(o) into v_before from public.orders o where id = v_order;
  execute 'set local role authenticated';
  update public.orders
     set payment_status = (case when payment_status = 'paid' then 'pending' else 'paid' end)::public.payment_status,
         review_reminder_dismissed = true
   where id = v_order;
  get diagnostics v_cnt = row_count;
  execute 'reset role';
  select to_jsonb(o) into v_after from public.orders o where id = v_order;
  r := r || chr(10) || case when v_cnt = 1
                  and v_after->'payment_status' = v_before->'payment_status'
                  and v_after->>'review_reminder_dismissed' = 'true'
             then 'PASS musteri payment_status degistiremedi, hatirlatici kapatabildi'
             else format('FAIL musteri rows=%s ps %s->%s', v_cnt,
                         v_before->>'payment_status', v_after->>'payment_status') end;

  execute 'set local role authenticated';
  begin
    update public.orders set total = 1 where id = v_order;
    r := r || chr(10) || 'FAIL musteri total degistirdi';
  exception when insufficient_privilege then
    r := r || chr(10) || 'PASS musteri total engellendi';
  end;
  begin
    insert into public.coupons (code, discount_type, discount_value, start_date, end_date)
      values ('GUARDTEST', 'percentage', 100, now(), now() + interval '1 day');
    r := r || chr(10) || 'FAIL musteri kupon ekledi';
  exception when insufficient_privilege then
    r := r || chr(10) || 'PASS musteri kupon ekleyemedi';
  when others then
    r := r || chr(10) || ('FAIL kupon beklenmeyen hata ' || sqlstate || ' ' || left(sqlerrm, 80));
  end;
  execute 'reset role';

  -- --------------------------------------- yasal akış: satıcı teslim eder
  -- Siparişi sunucu bağlamında "hazırlanıyor"a çek, satıcı olarak teslim et.
  update public.orders set status = 'preparing', payment_status = 'pending' where id = v_order;
  select to_jsonb(s) into v_before from public.shops s where id = v_shop;
  perform set_config('request.jwt.claims', json_build_object('sub', v_order_cust, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  begin
    update public.orders set status = 'delivered' where id = v_order;
    r := r || chr(10) || 'FAIL musteri siparisi teslim edildi yapti';
  exception when insufficient_privilege then
    r := r || chr(10) || 'PASS musteri teslim edildi yapamadi';
  end;
  execute 'reset role';

  perform set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  begin
    update public.orders
       set status = 'delivered', payment_status = 'paid', updated_at = now()
     where id = v_order;
    get diagnostics v_cnt = row_count;
    execute 'reset role';
    select to_jsonb(s) into v_after from public.shops s where id = v_shop;
    r := r || chr(10) || case when v_cnt = 1
                    and (select payment_status::text from public.orders where id = v_order) = 'paid'
                    and (select status::text from public.orders where id = v_order) = 'delivered'
               then format('PASS satici teslim etti (nakit gelir %s -> %s)',
                           v_before->>'cash_payment_revenue', v_after->>'cash_payment_revenue')
               else format('FAIL satici teslim rows=%s', v_cnt) end;
  exception when others then
    execute 'reset role';
    r := r || chr(10) || ('FAIL satici teslim hatasi: ' || sqlstate || ' ' || left(sqlerrm, 120));
  end;

  -- ---------------------------------------------------------------- kurye
  if v_asg is not null then
    perform set_config('request.jwt.claims', json_build_object('sub', v_courier, 'role', 'authenticated')::text, true);
    select to_jsonb(ca) into v_before from public.courier_assignments ca where id = v_asg;
    execute 'set local role authenticated';
    begin
      update public.courier_assignments set fee_amount = 9999 where id = v_asg;
      get diagnostics v_cnt = row_count;
      execute 'reset role';
      select to_jsonb(ca) into v_after from public.courier_assignments ca where id = v_asg;
      r := r || chr(10) || case when v_after->'fee_amount' = v_before->'fee_amount'
                 then 'PASS kurye fee_amount degistiremedi (rows=' || v_cnt || ')'
                 else 'FAIL kurye fee_amount degisti' end;
    exception when others then
      execute 'reset role';
      r := r || chr(10) || ('FAIL kurye beklenmeyen hata ' || sqlstate);
    end;
  end if;

  insert into _guard_results(line) values (r);
end
$test$;

SELECT string_agg(line, E'\n' ORDER BY n) AS result FROM _guard_results;

ROLLBACK;
