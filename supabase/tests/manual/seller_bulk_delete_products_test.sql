-- Satıcı toplu ürün silme RPC'si canlı doğrulaması
-- (20261015000003_seller_bulk_delete_products.sql). Kendini geri alır.
--
-- Çalıştırma: supabase db query --linked --file supabase/tests/manual/seller_bulk_delete_products_test.sql
-- Başarı = 'TESTS_PASSED ...' istisnası (DO bloğu RAISE EXCEPTION ile biter,
-- böylece testin sildiği/kapattığı her şey geri gelir).
DO $test$
DECLARE
  v_fn        CONSTANT text := 'public.seller_bulk_delete_products(uuid[],boolean)';
  v_order_p   uuid;  -- sipariş kalemi olan ürün
  v_shop1     uuid;
  v_owner1    uuid;
  v_new_p     uuid;  -- geçmişi olmayan, test için eklenen ürün
  v_foreign_p uuid;  -- başka mağazanın ürünü
  v_digital_p uuid;
  v_owner2    uuid;
  v_spons_p   uuid;
  v_owner3    uuid;
  v_n         integer;
  v_m         integer;
  v_res       jsonb;
  v_checks    integer := 0;
BEGIN
  SELECT oi.product_id, p.shop_id, s.owner_id INTO v_order_p, v_shop1, v_owner1
    FROM public.order_items oi
    JOIN public.products p ON p.id = oi.product_id
    JOIN public.shops s ON s.id = p.shop_id
   WHERE s.owner_id IS NOT NULL
   LIMIT 1;
  SELECT p.id INTO v_foreign_p
    FROM public.products p JOIN public.shops s ON s.id = p.shop_id
   WHERE s.owner_id <> v_owner1
   LIMIT 1;
  SELECT d.product_id, s.owner_id INTO v_digital_p, v_owner2
    FROM public.digital_orders d
    JOIN public.products p ON p.id = d.product_id
    JOIN public.shops s ON s.id = p.shop_id
   LIMIT 1;
  SELECT sp.product_id, s.owner_id INTO v_spons_p, v_owner3
    FROM public.shop_sponsorships sp
    JOIN public.products p ON p.id = sp.product_id
    JOIN public.shops s ON s.id = p.shop_id
   LIMIT 1;
  IF v_order_p IS NULL OR v_foreign_p IS NULL THEN
    RAISE EXCEPTION '[0] siparişli ürün / başka mağaza ürünü bulunamadı';
  END IF;

  INSERT INTO public.products (shop_id, name, slug, price, stock_quantity)
  VALUES (v_shop1, 'TEST Silinecek', 'test-silinecek-' || substr(md5(random()::text), 1, 8), 5, 1)
  RETURNING id INTO v_new_p;
  -- Satışa açık başlasın ki kapatma görülsün.
  UPDATE public.products SET is_available = true WHERE id = v_order_p;

  -- [1] yetkiler
  IF has_function_privilege('anon', v_fn, 'EXECUTE') THEN RAISE EXCEPTION '[1] anon çalıştırabiliyor'; END IF;
  IF NOT has_function_privilege('authenticated', v_fn, 'EXECUTE') THEN RAISE EXCEPTION '[1] authenticated çalıştıramıyor'; END IF;
  IF EXISTS (SELECT 1 FROM pg_proc p, aclexplode(p.proacl) a WHERE p.oid = v_fn::regprocedure AND a.grantee = 0) THEN
    RAISE EXCEPTION '[1] PUBLIC yetkisi kalmış';
  END IF;
  v_checks := v_checks + 1;

  -- [2] oturumsuz ve boş liste reddedilir
  PERFORM set_config('request.jwt.claims', '', true);
  BEGIN
    PERFORM public.seller_bulk_delete_products(ARRAY[v_new_p]);
    RAISE EXCEPTION '[2] oturumsuz çağrı geçti';
  EXCEPTION WHEN SQLSTATE '28000' THEN NULL;
  END;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner1, 'role', 'authenticated')::text, true);
  PERFORM set_config('role', 'authenticated', true);
  BEGIN
    PERFORM public.seller_bulk_delete_products(ARRAY[NULL::uuid]);
    RAISE EXCEPTION '[2] boş liste geçti';
  EXCEPTION WHEN SQLSTATE '22023' THEN NULL;
  END;
  v_checks := v_checks + 1;

  -- [3] kuru çalıştırma: sayılar doğru, hiçbir şey değişmez
  v_res := public.seller_bulk_delete_products(
    ARRAY[v_order_p, v_new_p, v_new_p, v_foreign_p, gen_random_uuid()], true);
  IF (v_res->>'deleted')::int <> 1 OR (v_res->>'deactivated')::int <> 1
     OR (v_res->>'not_found')::int <> 2 OR NOT (v_res->>'dry_run')::boolean THEN
    RAISE EXCEPTION '[3] kuru çalıştırma sayıları yanlış: %', v_res;
  END IF;
  PERFORM set_config('role', 'postgres', true);
  IF NOT EXISTS (SELECT 1 FROM public.products WHERE id = v_new_p) THEN
    RAISE EXCEPTION '[3] kuru çalıştırma ürünü sildi';
  END IF;
  IF NOT (SELECT is_available FROM public.products WHERE id = v_order_p) THEN
    RAISE EXCEPTION '[3] kuru çalıştırma ürünü kapattı';
  END IF;
  v_checks := v_checks + 1;

  -- [4] gerçek çalıştırma: geçmişsiz silinir, siparişli kapanır, yabancıya dokunulmaz
  SELECT count(*) INTO v_n FROM public.order_items WHERE product_id = v_order_p;
  PERFORM set_config('role', 'authenticated', true);
  v_res := public.seller_bulk_delete_products(ARRAY[v_order_p, v_new_p, v_foreign_p]);
  PERFORM set_config('role', 'postgres', true);
  IF (v_res->>'deleted')::int <> 1 OR (v_res->>'deactivated')::int <> 1 OR (v_res->>'not_found')::int <> 1
     OR v_res->'deleted_ids' <> to_jsonb(ARRAY[v_new_p]) OR v_res->'deactivated_ids' <> to_jsonb(ARRAY[v_order_p]) THEN
    RAISE EXCEPTION '[4] sonuç yanlış: %', v_res;
  END IF;
  IF EXISTS (SELECT 1 FROM public.products WHERE id = v_new_p) THEN
    RAISE EXCEPTION '[4] geçmişsiz ürün silinmedi';
  END IF;
  IF (SELECT is_available FROM public.products WHERE id = v_order_p) THEN
    RAISE EXCEPTION '[4] siparişli ürün satışa kapatılmadı';
  END IF;
  SELECT count(*) INTO v_m FROM public.order_items WHERE product_id = v_order_p;
  IF v_m <> v_n OR v_n = 0 THEN
    RAISE EXCEPTION '[4] sipariş kalemleri ürün bağlantısını kaybetti (% → %)', v_n, v_m;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.products WHERE id = v_foreign_p) THEN
    RAISE EXCEPTION '[4] başka mağazanın ürünü silindi';
  END IF;
  v_checks := v_checks + 1;

  -- [5] dijital siparişi olan ürün silinmez (eskiden 23503 ile düşerdi)
  IF v_digital_p IS NOT NULL THEN
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner2, 'role', 'authenticated')::text, true);
    PERFORM set_config('role', 'authenticated', true);
    v_res := public.seller_bulk_delete_products(ARRAY[v_digital_p]);
    PERFORM set_config('role', 'postgres', true);
    IF (v_res->>'deactivated')::int <> 1 OR (v_res->>'deleted')::int <> 0
       OR NOT EXISTS (SELECT 1 FROM public.products WHERE id = v_digital_p AND is_available = false) THEN
      RAISE EXCEPTION '[5] dijital siparişli ürün yanlış: %', v_res;
    END IF;
    v_checks := v_checks + 1;
  END IF;

  -- [6] öne çıkarma (para) kaydı olan ürün silinmez, kayıt kalır
  IF v_spons_p IS NOT NULL THEN
    SELECT count(*) INTO v_n FROM public.shop_sponsorships WHERE product_id = v_spons_p;
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner3, 'role', 'authenticated')::text, true);
    PERFORM set_config('role', 'authenticated', true);
    v_res := public.seller_bulk_delete_products(ARRAY[v_spons_p]);
    PERFORM set_config('role', 'postgres', true);
    SELECT count(*) INTO v_m FROM public.shop_sponsorships WHERE product_id = v_spons_p;
    IF (v_res->>'deactivated')::int <> 1 OR v_m <> v_n THEN
      RAISE EXCEPTION '[6] öne çıkarmalı ürün yanlış: % (% → %)', v_res, v_n, v_m;
    END IF;
    v_checks := v_checks + 1;
  END IF;

  RAISE EXCEPTION 'TESTS_PASSED % kontrol', v_checks;
END
$test$;
