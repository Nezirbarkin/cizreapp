-- ============================================================================
-- 20261024000005_shop_favorites_and_review_fixes — canlı davranış testi
-- ----------------------------------------------------------------------------
-- Kendi kendini geri alır: DO bloğu sonunda bilerek RAISE EXCEPTION atar,
-- her şey geri alınır, CLI özet satırlarını hata mesajı olarak yazdırır.
-- Göç uygulanmadan önce denemek için göç gövdesini (BEGIN/COMMIT/NOTIFY
-- hariç) @@MIGRATION@@ satırının yerine koyun; uygulandıktan sonra olduğu
-- gibi çalıştırın:
--   supabase db query --linked --file supabase/tests/manual/shop_favorites_reviews_test.sql
-- Beklenen: "TESTS_DONE" mesajında FAIL satırı yok.
-- ============================================================================
BEGIN;

-- @@MIGRATION@@

DO $test$
declare
  v_review uuid; v_product uuid; v_owner uuid; v_reviewer uuid; v_stranger uuid; v_shop uuid;
  v_p2 uuid;
  v_row record;
  v_j jsonb;
  v_n int;
  r text := '';
begin
  -- ------------------------------------------------------------ fikstürler
  select pr.id, pr.product_id, s.owner_id, pr.user_id, s.id
    into v_review, v_product, v_owner, v_reviewer, v_shop
  from public.product_reviews pr
  join public.products p on p.id = pr.product_id
  join public.shops s on s.id = p.shop_id
  where pr.user_id is distinct from s.owner_id and pr.is_approved
  order by pr.created_at limit 1;

  select p.id into v_stranger
  from public.profiles p
  where p.id not in (v_owner, v_reviewer)
    and coalesce(p.role::text, 'user') not in ('admin') and not coalesce(p.is_admin, false)
    and not coalesce(p.is_bot, false)
  order by p.id limit 1;

  select p.id into v_p2
  from public.products p
  where not exists (select 1 from public.product_reviews r where r.product_id = p.id)
    and p.shop_id is not null
  order by p.id limit 1;

  r := r || chr(10) || format('fixtures review=%s stranger=%s p2=%s',
         v_review is not null, v_stranger is not null, v_p2 is not null);

  -- ------------------------------------------------------------ puanlar yeniden hesaplandı
  select count(*) into v_n
  from public.products p
  join (select product_id, avg(rating) a, count(*) n from public.product_reviews
        where is_approved group by product_id) s on s.product_id = p.id
  where p.rating is distinct from s.a::numeric(3,2) and abs(p.rating - s.a) > 0.01
     or p.total_reviews is distinct from s.n;
  r := r || chr(10) || case when v_n = 0 then 'PASS urun puanlari dogru' else 'FAIL yanlis puan n=' || v_n end;

  -- ------------------------------------------------------------ yeni yorum puanı günceller (DEFINER)
  perform set_config('request.jwt.claims', json_build_object('sub', v_reviewer, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  insert into public.product_reviews (product_id, user_id, rating, comment, is_approved, seller_reply, helpful_count)
  values (v_p2, v_reviewer, 3, 'test yorumu', true, 'sahte cevap', 50);
  execute 'reset role';
  select rating, total_reviews into v_row from public.products where id = v_p2;
  r := r || chr(10) || case when v_row.rating = 3 and v_row.total_reviews = 1
    then 'PASS musteri yorumu urun puanini guncelledi' else 'FAIL puan=' || v_row::text end;
  select seller_reply, helpful_count into v_row from public.product_reviews where product_id = v_p2 and user_id = v_reviewer;
  r := r || chr(10) || case when v_row.seller_reply is null and v_row.helpful_count = 0
    then 'PASS eklerken sahte cevap/sayac yok' else 'FAIL ekleme korumasi' end;

  -- ------------------------------------------------------------ yorum sahibi korumalı sütunları yazamaz
  perform set_config('request.jwt.claims', json_build_object('sub', v_reviewer, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  update public.product_reviews
     set seller_reply = 'kendi cevabim', helpful_count = 99, is_approved = false, comment = 'guncel yorum'
   where id = v_review;
  execute 'reset role';
  select seller_reply, helpful_count, is_approved, comment into v_row from public.product_reviews where id = v_review;
  r := r || chr(10) || case when v_row.seller_reply is distinct from 'kendi cevabim' and v_row.helpful_count <> 99
       and v_row.is_approved and v_row.comment = 'guncel yorum'
    then 'PASS yorum sahibi korumasi' else 'FAIL yorum sahibi korumasi ' || v_row::text end;

  -- ------------------------------------------------------------ yararlı oyu
  perform set_config('request.jwt.claims', json_build_object('sub', v_stranger, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  insert into public.product_review_helpful (review_id, user_id) values (v_review, v_stranger);
  execute 'reset role';
  select helpful_count into v_n from public.product_reviews where id = v_review;
  r := r || chr(10) || case when v_n = (select count(*) from public.product_review_helpful where review_id = v_review)
       and v_n >= 1
    then 'PASS yabanci oy sayaci artirdi' else 'FAIL sayac=' || v_n end;

  perform set_config('request.jwt.claims', json_build_object('sub', v_reviewer, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  begin
    insert into public.product_review_helpful (review_id, user_id) values (v_review, v_reviewer);
    r := r || chr(10) || 'FAIL kendi yorumuna oy';
  exception when insufficient_privilege then
    r := r || chr(10) || 'PASS kendi yorumuna oy yok';
  end;
  execute 'reset role';

  -- ------------------------------------------------------------ satıcı cevabı
  perform set_config('request.jwt.claims', json_build_object('sub', v_stranger, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  begin
    perform public.seller_reply_product_review(v_review, 'yabanci cevabi');
    r := r || chr(10) || 'FAIL yabanci cevap yazdi';
  exception when insufficient_privilege then
    r := r || chr(10) || 'PASS yabanci cevap yazamaz';
  end;
  execute 'reset role';

  perform set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  v_j := public.seller_reply_product_review(v_review, '  Teşekkür ederiz!  ');
  execute 'reset role';
  r := r || chr(10) || case when v_j->>'seller_reply' = 'Teşekkür ederiz!' and v_j->>'seller_replied_at' is not null
    then 'PASS satici cevabi yazildi' else 'FAIL satici cevabi ' || left(v_j::text, 150) end;
  select count(*) into v_n from public.notifications
  where user_id = v_reviewer and type = 'product_review_reply' and entity_id = v_product::text
    and created_at = now();
  r := r || chr(10) || case when v_n = 1 then 'PASS yorum sahibine bildirim' else 'FAIL bildirim n=' || v_n end;

  perform set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  v_j := public.seller_reply_product_review(v_review, '   ');
  execute 'reset role';
  r := r || chr(10) || case when v_j->>'seller_reply' is null and v_j->>'seller_replied_at' is null
    then 'PASS bos cevap = silme' else 'FAIL silme' end;

  -- ------------------------------------------------------------ favori dükkân
  perform set_config('request.jwt.claims', json_build_object('sub', v_stranger, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  insert into public.shop_subscribers (shop_id, user_id) values (v_shop, v_stranger);
  begin
    insert into public.shop_subscribers (shop_id, user_id) values (v_shop, v_owner);
    r := r || chr(10) || 'FAIL baskasi adina favori';
  exception when insufficient_privilege then
    r := r || chr(10) || 'PASS baskasi adina favori yok';
  end;
  select count(*) into v_n from public.shop_subscribers;
  r := r || chr(10) || case when v_n = 1 then 'PASS yalniz kendi favorileri gorunur' else 'FAIL favori n=' || v_n end;
  execute 'reset role';

  raise exception 'TESTS_DONE %', r;
end;
$test$;

ROLLBACK;
