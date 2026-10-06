-- Görev 3.3 — sepet takibi + indirim bildirimi canlı doğrulaması (kendini geri alır).
--
-- Çalıştırma: supabase db query --linked --file supabase/tests/manual/cart_price_drop_notifications_test.sql
-- Başarı = 'TESTS_PASSED ...' istisnası: DO bloğu RAISE EXCEPTION ile biter,
-- testin yazdığı her şey (sepetler, alarmlar, bildirimler, fiyatlar) geri alınır.
DO $test$
DECLARE
  v_shop uuid;
  v_owner uuid;
  v_other_owner uuid;
  v_product uuid;
  v_product2 uuid;
  v_price numeric;
  v_u1 uuid; v_u2 uuid; v_u3 uuid; v_u4 uuid; v_alert_user uuid;
  v_n integer;
  v_text text;
  v_stats jsonb;
  v_item jsonb;
  v_checks integer := 0;
BEGIN
  -- Aktif mağaza, iki fiziksel ürün
  SELECT s.id, s.owner_id INTO v_shop, v_owner
    FROM public.shops s
   WHERE COALESCE(s.is_active, false)
     AND (SELECT count(*) FROM public.products p
           WHERE p.shop_id = s.id AND COALESCE(p.product_type, 'normal') <> 'digital') >= 2
   ORDER BY s.created_at LIMIT 1;
  SELECT id INTO v_product FROM public.products
   WHERE shop_id = v_shop AND COALESCE(product_type, 'normal') <> 'digital' ORDER BY created_at LIMIT 1;
  SELECT id INTO v_product2 FROM public.products
   WHERE shop_id = v_shop AND COALESCE(product_type, 'normal') <> 'digital' AND id <> v_product ORDER BY created_at LIMIT 1;
  SELECT owner_id INTO v_other_owner FROM public.shops WHERE owner_id <> v_owner ORDER BY created_at LIMIT 1;
  SELECT id INTO v_u1 FROM public.profiles WHERE id NOT IN (v_owner, v_other_owner) ORDER BY created_at LIMIT 1;
  SELECT id INTO v_u2 FROM public.profiles WHERE id NOT IN (v_owner, v_other_owner, v_u1) ORDER BY created_at LIMIT 1;
  SELECT id INTO v_u3 FROM public.profiles WHERE id NOT IN (v_owner, v_other_owner, v_u1, v_u2) ORDER BY created_at LIMIT 1;
  SELECT id INTO v_u4 FROM public.profiles WHERE id NOT IN (v_owner, v_other_owner, v_u1, v_u2, v_u3) ORDER BY created_at LIMIT 1;
  SELECT id INTO v_alert_user FROM public.profiles WHERE id NOT IN (v_owner, v_other_owner, v_u1, v_u2, v_u3, v_u4) ORDER BY created_at LIMIT 1;
  IF v_product2 IS NULL OR v_alert_user IS NULL THEN RAISE EXCEPTION 'test verisi yok'; END IF;

  -- Temiz başlangıç: fiyat 100, indirim yok, satışta; sepetler ve günlük sıfır
  UPDATE public.products SET price = 100, discount_price = NULL, old_price = NULL, is_available = true
   WHERE id IN (v_product, v_product2);
  DELETE FROM public.cart WHERE product_id IN (v_product, v_product2);
  DELETE FROM public.cart_price_drop_notifications WHERE product_id IN (v_product, v_product2);
  DELETE FROM public.notifications WHERE entity_id IN (v_product::text, v_product2::text);
  UPDATE public.notification_preferences SET cart_price_drop_enabled = true WHERE user_id IN (v_u1, v_u2, v_u3, v_u4);

  INSERT INTO public.cart (user_id, product_id, quantity) VALUES
    (v_u1, v_product, 2),
    (v_u2, v_product, 1),
    (v_u3, v_product, 1),       -- tercihiyle kapatacak
    (v_owner, v_product, 5),    -- kendi ürünü: sayılmaz, bildirim almaz
    (v_u1, v_product2, 1);
  -- U3 bildirimi kapatır (satırı yoksa açılır)
  UPDATE public.notification_preferences SET cart_price_drop_enabled = false WHERE user_id = v_u3;
  IF NOT FOUND THEN
    INSERT INTO public.notification_preferences (user_id, cart_price_drop_enabled) VALUES (v_u3, false);
  END IF;

  -- [1] yapı
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'public' AND table_name = 'notification_preferences'
       AND column_name = 'cart_price_drop_enabled' AND column_default = 'true' AND is_nullable = 'NO'
  ) THEN RAISE EXCEPTION '[1] tercih sütunu yok/yanlış'; END IF;
  IF has_table_privilege('authenticated', 'public.cart_price_drop_notifications', 'SELECT')
     OR has_table_privilege('anon', 'public.cart_price_drop_notifications', 'SELECT') THEN
    RAISE EXCEPTION '[1] bildirim günlüğü istemciye açık';
  END IF;
  IF private.format_try(150) <> '₺150' OR private.format_try(129.9) <> '₺129,90' THEN
    RAISE EXCEPTION '[1] para biçimi: % / %', private.format_try(150), private.format_try(129.9);
  END IF;
  v_checks := v_checks + 1;

  -- [2] HATA DÜZELTMESİ: eşleşen fiyat alarmı varken satıcının indirimi geri alınmıyor
  INSERT INTO public.price_alerts (user_id, product_id, target_price, current_price_at_creation)
  VALUES (v_alert_user, v_product, 95, 100);
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
  v_n := public.seller_bulk_set_discount(ARRAY[v_product], 'percent', 10);   -- 100 → 90
  EXECUTE 'RESET ROLE';
  IF v_n <> 1 OR (SELECT discount_price FROM public.products WHERE id = v_product) <> 90 THEN
    RAISE EXCEPTION '[2] indirim uygulanmadı (%)', v_n;
  END IF;
  SELECT content INTO v_text FROM public.notifications
   WHERE user_id = v_alert_user AND type = 'price_drop' AND entity_id = v_product::text;
  IF v_text IS NULL OR v_text NOT LIKE '%₺90%' OR v_text NOT LIKE '%₺95%' THEN
    RAISE EXCEPTION '[2] fiyat alarmı bildirimi: %', v_text;
  END IF;
  v_checks := v_checks + 1;

  -- [3] sepetteki müşterilere bildirim: U1 ve U2 alır; sahip ve kapatan U3 almaz
  SELECT count(*) INTO v_n FROM public.notifications
   WHERE type = 'cart_price_drop' AND entity_id = v_product::text AND user_id IN (v_u1, v_u2);
  IF v_n <> 2 THEN RAISE EXCEPTION '[3] U1/U2 bildirimi: %', v_n; END IF;
  IF EXISTS (SELECT 1 FROM public.notifications
              WHERE type = 'cart_price_drop' AND entity_id = v_product::text AND user_id IN (v_owner, v_u3)) THEN
    RAISE EXCEPTION '[3] sahip ya da kapatan müşteri bildirim aldı';
  END IF;
  SELECT content INTO v_text FROM public.notifications
   WHERE type = 'cart_price_drop' AND entity_id = v_product::text AND user_id = v_u1;
  IF v_text NOT LIKE '%şimdi ₺90 (önce ₺100)%' THEN RAISE EXCEPTION '[3] içerik: %', v_text; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.notifications
     WHERE type = 'cart_price_drop' AND entity_id = v_product::text AND user_id = v_u1
       AND entity_type = 'product' AND (data ->> 'new_price')::numeric = 90
       AND (data ->> 'old_price')::numeric = 100 AND data ->> 'shop_id' = v_shop::text
  ) THEN RAISE EXCEPTION '[3] bildirim verisi eksik'; END IF;
  SELECT count(*) INTO v_n FROM public.cart_price_drop_notifications WHERE product_id = v_product;
  IF v_n <> 2 THEN RAISE EXCEPTION '[3] günlük satırı: %', v_n; END IF;
  -- push kuyruğuna girdi
  IF NOT EXISTS (
    SELECT 1 FROM public.notification_outbox o JOIN public.notifications n ON n.id = o.notification_id
     WHERE n.type = 'cart_price_drop' AND n.user_id = v_u1
  ) THEN RAISE EXCEPTION '[3] push kuyruğuna girmedi'; END IF;
  v_checks := v_checks + 1;

  -- [4] 24 saat sınırı: aynı ürün daha da ucuzlasa da tekrar bildirim yok
  DELETE FROM public.notifications WHERE type = 'cart_price_drop' AND entity_id = v_product::text;
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
  PERFORM public.seller_bulk_set_discount(ARRAY[v_product], 'percent', 20);  -- 90 → 80
  EXECUTE 'RESET ROLE';
  SELECT count(*) INTO v_n FROM public.notifications WHERE type = 'cart_price_drop' AND entity_id = v_product::text;
  IF v_n <> 0 THEN RAISE EXCEPTION '[4] 24 saat içinde tekrar bildirim: %', v_n; END IF;
  v_checks := v_checks + 1;

  -- [5] kuruşluk düşüş ve fiyat artışı bildirim sayılmaz
  INSERT INTO public.cart (user_id, product_id, quantity) VALUES (v_u4, v_product2, 1);
  UPDATE public.products SET discount_price = 99.50 WHERE id = v_product2;   -- %0,5 ve 1 TL'den az
  UPDATE public.products SET discount_price = NULL, price = 120 WHERE id = v_product2;  -- artış
  SELECT count(*) INTO v_n FROM public.notifications WHERE type = 'cart_price_drop' AND entity_id = v_product2::text;
  IF v_n <> 0 THEN RAISE EXCEPTION '[5] küçük düşüş/artış bildirim üretti: %', v_n; END IF;
  v_checks := v_checks + 1;

  -- [6] satışta olmayan ürün bildirim üretmez
  UPDATE public.products SET is_available = false WHERE id = v_product2;
  UPDATE public.products SET discount_price = 60 WHERE id = v_product2;
  SELECT count(*) INTO v_n FROM public.notifications WHERE type = 'cart_price_drop' AND entity_id = v_product2::text;
  IF v_n <> 0 THEN RAISE EXCEPTION '[6] satışta olmayan ürün bildirim üretti'; END IF;
  UPDATE public.products SET is_available = true, discount_price = NULL, price = 120 WHERE id = v_product2;
  v_checks := v_checks + 1;

  -- [7] gerçek düşüş (120 → 100) ikinci üründe U1 ve U4'e gider
  UPDATE public.products SET discount_price = 100 WHERE id = v_product2;
  SELECT count(*) INTO v_n FROM public.notifications
   WHERE type = 'cart_price_drop' AND entity_id = v_product2::text AND user_id IN (v_u1, v_u4);
  IF v_n <> 2 THEN RAISE EXCEPTION '[7] ikinci ürün bildirimleri: %', v_n; END IF;
  v_checks := v_checks + 1;

  -- [8] bildirim hatası ürün güncellemesini geri almaz
  ALTER TABLE public.notifications ADD CONSTRAINT zz_test_block_cart_price_drop
    CHECK (type <> 'cart_price_drop') NOT VALID;
  DELETE FROM public.cart_price_drop_notifications WHERE product_id = v_product2;
  UPDATE public.products SET discount_price = 70 WHERE id = v_product2;
  IF (SELECT discount_price FROM public.products WHERE id = v_product2) <> 70 THEN
    RAISE EXCEPTION '[8] bildirim hatası güncellemeyi geri aldı';
  END IF;
  ALTER TABLE public.notifications DROP CONSTRAINT zz_test_block_cart_price_drop;
  v_checks := v_checks + 1;

  -- [9] satıcı istatistiği: yalnız sayılar; sahibin sepeti sayılmaz
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
  v_stats := public.get_shop_cart_stats(v_shop);
  EXECUTE 'RESET ROLE';
  SELECT e INTO v_item FROM jsonb_array_elements(v_stats -> 'products') e
   WHERE e ->> 'product_id' = v_product::text;
  IF v_item IS NULL OR (v_item ->> 'users')::int <> 3 OR (v_item ->> 'quantity')::int <> 4 THEN
    RAISE EXCEPTION '[9] ürün satırı: %', v_item;
  END IF;
  IF (v_item ->> 'notified_users')::int <> 2 OR (v_item ->> 'effective_price')::numeric <> 80 THEN
    RAISE EXCEPTION '[9] bildirim/fiyat: %', v_item;
  END IF;
  IF (v_stats -> 'summary' ->> 'users')::int < 4 THEN
    RAISE EXCEPTION '[9] özet: %', v_stats -> 'summary';
  END IF;
  IF v_stats::text LIKE '%' || v_u1::text || '%' THEN
    RAISE EXCEPTION '[9] müşteri kimliği sızdı';
  END IF;
  v_checks := v_checks + 1;

  -- [10] başka satıcı ve anon göremez
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_other_owner, 'role', 'authenticated')::text, true);
  BEGIN
    PERFORM public.get_shop_cart_stats(v_shop);
    RAISE EXCEPTION '[10] başka satıcı istatistiği gördü';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  EXECUTE 'RESET ROLE';
  IF has_function_privilege('anon', 'public.get_shop_cart_stats(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION '[10] anon istatistik çağırabiliyor';
  END IF;
  v_checks := v_checks + 1;

  RAISE EXCEPTION 'TESTS_PASSED % kontrol', v_checks;
END
$test$;
