-- Satıcı toplu ürün yükleme RPC'si canlı doğrulaması
-- (20261015000001_seller_bulk_upsert_products.sql). Kendini geri alır.
--
-- Çalıştırma: supabase db query --linked --file supabase/tests/manual/seller_bulk_upsert_products_test.sql
-- Başarı = 'TESTS_PASSED ...' istisnası (DO bloğu RAISE EXCEPTION ile biter,
-- böylece testin yazdığı her şey geri alınır).
DO $test$
DECLARE
  v_shop      uuid;
  v_owner     uuid;
  v_other     uuid;
  v_other_shop uuid;
  v_provider  uuid;
  v_foreign   uuid;
  v_existing  uuid;
  v_res       jsonb;
  v_r         jsonb;
  v_n         integer;
  v_items     jsonb;
  v_p         public.products%ROWTYPE;
  v_checks    integer := 0;
  v_err       text;
BEGIN
  -- Ürünü olan bir mağaza + sahibi; başka bir mağaza (yabancı sağlayıcı için)
  SELECT s.id, s.owner_id INTO v_shop, v_owner
    FROM public.shops s
   WHERE s.owner_id IS NOT NULL
   ORDER BY (SELECT count(*) FROM public.products p WHERE p.shop_id = s.id) DESC
   LIMIT 1;
  SELECT s.id, s.owner_id INTO v_other_shop, v_other
    FROM public.shops s
   WHERE s.id <> v_shop AND s.owner_id IS NOT NULL AND s.owner_id <> v_owner
   LIMIT 1;
  IF v_shop IS NULL OR v_other_shop IS NULL THEN
    RAISE EXCEPTION '[0] test için iki mağaza gerekli';
  END IF;

  -- Test verisi (postgres olarak)
  INSERT INTO public.smm_providers (owner_type, owner_id, name, api_url, api_key, is_active)
  VALUES ('seller', v_shop, 'TEST toplu', 'https://example.invalid/api/v2', 'x', true)
  RETURNING id INTO v_provider;
  INSERT INTO public.smm_providers (owner_type, owner_id, name, api_url, api_key, is_active)
  VALUES ('seller', v_other_shop, 'TEST yabanci', 'https://example.invalid/api/v2', 'x', true)
  RETURNING id INTO v_foreign;

  INSERT INTO public.products (shop_id, name, slug, price, stock_quantity, discount_price, old_price, category)
  VALUES (v_shop, 'TEST Mevcut Ürün', 'test-mevcut-urun-' || substr(md5(random()::text), 1, 6),
          100, 5, 90, 120, 'TEST Eski Kategori')
  RETURNING id INTO v_existing;

  -- [1] yetkiler: anon/PUBLIC yok, authenticated var, DEFINER
  IF has_function_privilege('anon', 'public.seller_bulk_upsert_products(uuid,jsonb)', 'EXECUTE') THEN
    RAISE EXCEPTION '[1] anon çalıştırabiliyor';
  END IF;
  IF NOT has_function_privilege('authenticated', 'public.seller_bulk_upsert_products(uuid,jsonb)', 'EXECUTE') THEN
    RAISE EXCEPTION '[1] authenticated çalıştıramıyor';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_proc p, aclexplode(p.proacl) a
     WHERE p.oid = 'public.seller_bulk_upsert_products(uuid,jsonb)'::regprocedure
       AND a.grantee = 0
  ) THEN
    RAISE EXCEPTION '[1] PUBLIC yetkisi kalmış';
  END IF;
  v_checks := v_checks + 1;

  -- [2] oturumsuz çağrı reddedilir
  PERFORM set_config('request.jwt.claims', '', true);
  BEGIN
    PERFORM public.seller_bulk_upsert_products(v_shop, '[{"name":"x"}]');
    RAISE EXCEPTION '[2] oturumsuz çağrı geçti';
  EXCEPTION WHEN SQLSTATE '28000' THEN NULL;
  END;
  v_checks := v_checks + 1;

  -- [3] başka kullanıcı bu mağazaya ekleyemez
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', v_other, 'role', 'authenticated')::text, true);
  PERFORM set_config('role', 'authenticated', true);
  BEGIN
    PERFORM public.seller_bulk_upsert_products(v_shop, '[{"name":"Sızma","price":1,"stock":1}]');
    RAISE EXCEPTION '[3] başka kullanıcı ekleyebildi';
  EXCEPTION WHEN SQLSTATE '42501' THEN NULL;
  END;
  v_checks := v_checks + 1;

  -- [4] 100'den fazla satır reddedilir
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
  SELECT jsonb_agg(jsonb_build_object('name', 'Ürün ' || g, 'price', 1, 'stock', 1))
    INTO v_items FROM generate_series(1, 101) g;
  BEGIN
    PERFORM public.seller_bulk_upsert_products(v_shop, v_items);
    RAISE EXCEPTION '[4] 101 satır kabul edildi';
  EXCEPTION WHEN SQLSTATE '22023' THEN NULL;
  END;
  v_checks := v_checks + 1;

  -- [5] karışık parti: geçerli satırlar kaydedilir, hatalılar satır satır döner
  v_items := jsonb_build_array(
    -- 0 geçerli fiziksel (yeni kategori)
    jsonb_build_object('name', '  TEST   Toplu Domates ', 'price', 12.5, 'stock', 10,
      'old_price', 15, 'category', 'TEST Toplu Kat', 'description', 'açıklama',
      'image_url', 'https://example.com/a.jpg',
      'additional_images', jsonb_build_array('https://example.com/b.jpg'),
      'free_shipping', true, 'shipping_fee', 20, 'badges', jsonb_build_array('yeni')),
    -- 1 fiyat 0
    jsonb_build_object('name', 'TEST Sıfır', 'price', 0, 'stock', 1),
    -- 2 eski fiyat ≤ fiyat
    jsonb_build_object('name', 'TEST Eski', 'price', 10, 'old_price', 10, 'stock', 1),
    -- 3 geçerli dijital
    jsonb_build_object('product_type', 'digital', 'name', 'TEST Instagram Takipçi',
      'smm_provider_id', v_provider, 'smm_service_id', '901', 'price_per_1000', 45.5,
      'min_quantity', 100, 'max_quantity', 10000, 'max_orders_per_user', 3,
      'provider_rate', 30.25, 'service_name', 'Instagram Followers', 'is_available', false,
      'category', 'test toplu kat'),
    -- 4 aynı servis tekrar
    jsonb_build_object('product_type', 'digital', 'name', 'TEST Tekrar',
      'smm_provider_id', v_provider, 'smm_service_id', '901', 'price_per_1000', 1,
      'min_quantity', 1, 'max_quantity', 2),
    -- 5 başka mağazanın sağlayıcısı
    jsonb_build_object('product_type', 'digital', 'name', 'TEST Yabancı',
      'smm_provider_id', v_foreign, 'smm_service_id', '5', 'price_per_1000', 1,
      'min_quantity', 1, 'max_quantity', 2),
    -- 6 aynı ad: farklı slug ile eklenir
    jsonb_build_object('name', 'TEST Toplu Domates', 'price', 13, 'stock', 0),
    -- 7 mevcut ürün: yalnız fiyat 85'e iner → 90'lık indirimli fiyat temizlenir,
    --   120'lik eski fiyat hâlâ büyük olduğu için kalır
    jsonb_build_object('id', v_existing, 'price', 85),
    -- 8 bedenli tür desteklenmez
    jsonb_build_object('product_type', 'clothing', 'name', 'TEST Tişört', 'price', 1, 'stock', 1),
    -- 9 bozuk ürün kodu
    jsonb_build_object('id', 'bozuk', 'stock', 1),
    -- 10 http görsel reddedilir
    jsonb_build_object('name', 'TEST Http', 'price', 1, 'stock', 1, 'image_url', 'http://x.com/a.jpg'),
    -- 11 kesirli stok
    jsonb_build_object('name', 'TEST Kesir', 'price', 1, 'stock', 1.5),
    -- 12 geçersiz rozet (constraint eşlemesi)
    jsonb_build_object('name', 'TEST Rozet', 'price', 1, 'stock', 1, 'badges', jsonb_build_array('uydurma'))
  );
  v_res := public.seller_bulk_upsert_products(v_shop, v_items);
  PERFORM set_config('role', 'postgres', true);

  IF (v_res->>'created')::int <> 3 OR (v_res->>'updated')::int <> 1 OR (v_res->>'failed')::int <> 9 THEN
    RAISE EXCEPTION '[5] sayılar yanlış: %', v_res - 'results';
  END IF;
  IF jsonb_array_length(v_res->'results') <> 13 THEN
    RAISE EXCEPTION '[5] sonuç sayısı yanlış';
  END IF;
  FOR v_r IN SELECT value FROM jsonb_array_elements(v_res->'results') LOOP
    IF ((v_r->>'i')::int IN (0, 3, 6, 7)) <> (v_r->>'ok')::boolean THEN
      RAISE EXCEPTION '[5] satır % beklenmeyen sonuç: %', v_r->>'i', v_r;
    END IF;
    IF NOT (v_r->>'ok')::boolean AND COALESCE(v_r->>'error', '') IN ('', 'Kaydedilemedi') THEN
      RAISE EXCEPTION '[5] satır % için anlaşılır hata yok: %', v_r->>'i', v_r;
    END IF;
  END LOOP;
  v_err := (SELECT value->>'error' FROM jsonb_array_elements(v_res->'results') WHERE (value->>'i')::int = 4);
  IF v_err NOT LIKE '%zaten%' THEN RAISE EXCEPTION '[5] tekrar servis hatası: %', v_err; END IF;
  v_err := (SELECT value->>'error' FROM jsonb_array_elements(v_res->'results') WHERE (value->>'i')::int = 12);
  IF v_err NOT LIKE '%rozet%' THEN RAISE EXCEPTION '[5] rozet hatası: %', v_err; END IF;
  v_checks := v_checks + 1;

  -- [6] fiziksel ürün alanları doğru yazıldı (ad sıkıştırıldı, ücretsiz kargo ücreti sildi)
  SELECT * INTO v_p FROM public.products
   WHERE id = (SELECT (value->>'id')::uuid FROM jsonb_array_elements(v_res->'results') WHERE (value->>'i')::int = 0);
  IF v_p.name <> 'TEST Toplu Domates' OR v_p.price <> 12.5 OR v_p.stock_quantity <> 10
     OR v_p.old_price <> 15 OR v_p.category <> 'TEST Toplu Kat' OR v_p.product_type <> 'normal'
     OR v_p.image_url <> 'https://example.com/a.jpg'
     OR v_p.additional_images <> '["https://example.com/b.jpg"]'::jsonb
     OR NOT v_p.free_shipping OR v_p.shipping_fee IS NOT NULL
     OR v_p.badges <> ARRAY['yeni'] OR NOT v_p.is_available OR v_p.is_points_eligible
     OR v_p.slug <> 'test-toplu-domates' THEN
    RAISE EXCEPTION '[6] fiziksel ürün yanlış: % / % / %', v_p.name, v_p.slug, v_p.shipping_fee;
  END IF;
  SELECT count(*) INTO v_n FROM public.products
   WHERE shop_id = v_shop AND name = 'TEST Toplu Domates' AND slug LIKE 'test-toplu-domates-%';
  IF v_n <> 1 THEN RAISE EXCEPTION '[6] aynı ad için ikinci slug yok'; END IF;
  v_checks := v_checks + 1;

  -- [7] dijital ürün + taban (taban products'ta değil, ayrı tabloda)
  SELECT * INTO v_p FROM public.products
   WHERE id = (SELECT (value->>'id')::uuid FROM jsonb_array_elements(v_res->'results') WHERE (value->>'i')::int = 3);
  IF v_p.product_type <> 'digital' OR v_p.price <> 45.5 OR v_p.price_per_1000 <> 45.5
     OR v_p.smm_provider_id <> v_provider OR v_p.smm_service_id <> '901'
     OR v_p.min_quantity <> 100 OR v_p.max_quantity <> 10000 OR v_p.max_orders_per_user <> 3
     OR v_p.stock_quantity <> 0 OR v_p.is_available THEN
    RAISE EXCEPTION '[7] dijital ürün yanlış';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.smm_product_baselines
                  WHERE product_id = v_p.id AND provider_rate = 30.25
                    AND service_name = 'Instagram Followers') THEN
    RAISE EXCEPTION '[7] taban yazılmadı';
  END IF;
  v_checks := v_checks + 1;

  -- [8] güncelleme: yalnız fiyat değişti; indirimli fiyat temizlendi, ad/stok/kategori aynı
  SELECT * INTO v_p FROM public.products WHERE id = v_existing;
  IF v_p.price <> 85 OR v_p.discount_price IS NOT NULL OR v_p.old_price <> 120
     OR v_p.stock_quantity <> 5 OR v_p.name <> 'TEST Mevcut Ürün'
     OR v_p.category <> 'TEST Eski Kategori' THEN
    RAISE EXCEPTION '[8] güncelleme yanlış: price=% disc=% old=% stock=%',
      v_p.price, v_p.discount_price, v_p.old_price, v_p.stock_quantity;
  END IF;
  v_checks := v_checks + 1;

  -- [9] kategoriler: yeni kategori BİR kez eklendi (büyük/küçük harf), gönderilmeyen eklenmedi
  SELECT count(*) INTO v_n
    FROM public.shops s, jsonb_array_elements_text(s.seller_categories) c
   WHERE s.id = v_shop AND lower(c) = 'test toplu kat';
  IF v_n <> 1 THEN RAISE EXCEPTION '[9] kategori % kez', v_n; END IF;
  IF (v_res->'added_categories') <> '["TEST Toplu Kat"]'::jsonb THEN
    RAISE EXCEPTION '[9] added_categories yanlış: %', v_res->'added_categories';
  END IF;
  SELECT count(*) INTO v_n
    FROM public.shops s, jsonb_array_elements_text(s.seller_categories) c
   WHERE s.id = v_shop AND c = 'TEST Eski Kategori';
  IF v_n <> 0 THEN RAISE EXCEPTION '[9] gönderilmeyen kategori eklendi'; END IF;
  v_checks := v_checks + 1;

  -- [10] güncellemede açıkça gönderilen geçersiz eski fiyat reddedilir; fiyat
  --      eski fiyatı geçince (eski fiyat gönderilmeden) üstü çizili fiyat temizlenir
  PERFORM set_config('role', 'authenticated', true);
  v_res := public.seller_bulk_upsert_products(v_shop, jsonb_build_array(
    jsonb_build_object('id', v_existing, 'old_price', 50),
    jsonb_build_object('id', v_existing, 'stock', 42, 'price', 130, 'is_available', false)
  ));
  PERFORM set_config('role', 'postgres', true);
  IF (v_res->>'updated')::int <> 1 OR (v_res->>'failed')::int <> 1 THEN
    RAISE EXCEPTION '[10] sonuç yanlış: %', v_res;
  END IF;
  SELECT * INTO v_p FROM public.products WHERE id = v_existing;
  IF v_p.stock_quantity <> 42 OR v_p.price <> 130 OR v_p.old_price IS NOT NULL OR v_p.is_available THEN
    RAISE EXCEPTION '[10] güncelleme yanlış: stock=% price=% old=%', v_p.stock_quantity, v_p.price, v_p.old_price;
  END IF;
  v_checks := v_checks + 1;

  RAISE EXCEPTION 'TESTS_PASSED % kontrol', v_checks;
END
$test$;
