-- Ürün görsel kütüphanesi klasörleri + arama RPC'si canlı doğrulaması
-- (20261006000001_product_image_folders.sql). Kendini geri alır.
--
-- Çalıştırma: supabase db query --linked --file supabase/tests/manual/product_image_folders_test.sql
-- Başarı = 'TESTS_PASSED ...' istisnası (DO bloğu RAISE EXCEPTION ile biter,
-- böylece testin yazdığı her şey geri alınır).
DO $test$
DECLARE
  v_admin uuid;
  v_seller uuid;
  v_a uuid;
  v_b uuid;
  v_c uuid;
  v_perf uuid;
  v_names text[];
  v_n integer;
  v_n2 integer;
  v_t0 timestamptz;
  v_ms numeric;
  v_ms_typo numeric;
  v_checks integer := 0;
BEGIN
  SELECT id INTO v_admin FROM public.profiles
   WHERE role = 'admin'::public.user_role ORDER BY created_at LIMIT 1;
  SELECT id INTO v_seller FROM public.profiles
   WHERE role <> 'admin'::public.user_role ORDER BY created_at LIMIT 1;
  IF v_admin IS NULL OR v_seller IS NULL THEN
    RAISE EXCEPTION '[0] admin/normal kullanıcı bulunamadı';
  END IF;

  -- [1] şema: sütunlar, üretilmiş sütunlar, UNIQUE source_key, RPC'ler INVOKER
  SELECT count(*) INTO v_n FROM information_schema.columns
   WHERE table_schema = 'public' AND table_name = 'product_image_presets'
     AND column_name IN ('folder_id', 'source_key', 'search_name', 'search_text');
  IF v_n <> 4 THEN RAISE EXCEPTION '[1] yeni sütunlar eksik: %', v_n; END IF;
  SELECT count(*) INTO v_n FROM information_schema.columns
   WHERE table_schema = 'public' AND table_name = 'product_image_presets'
     AND column_name IN ('search_name', 'search_text') AND is_generated = 'ALWAYS';
  IF v_n <> 2 THEN RAISE EXCEPTION '[1] arama sütunları üretilmiş değil'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'product_image_presets_source_key_key' AND contype = 'u') THEN
    RAISE EXCEPTION '[1] source_key UNIQUE yok';
  END IF;
  SELECT count(*) INTO v_n FROM pg_proc
   WHERE pronamespace = 'public'::regnamespace AND NOT prosecdef
     AND proname IN ('search_product_image_presets', 'product_image_folder_summary');
  IF v_n <> 2 THEN RAISE EXCEPTION '[1] RPC''ler yok ya da DEFINER'; END IF;
  v_checks := v_checks + 1;

  -- [2] başlangıç klasörleri var; göç öncesi görsellerin hepsi bir klasörde
  SELECT count(*) INTO v_n FROM public.product_image_folders
   WHERE public.search_normalize(name) IN ('market', 'manav', 'kozmetik', 'hirdavat');
  IF v_n <> 4 THEN RAISE EXCEPTION '[2] başlangıç klasörleri eksik: %', v_n; END IF;
  SELECT count(*) INTO v_n FROM public.product_image_presets
   WHERE folder_id IS NULL AND created_at < '2026-10-06 00:00:00+00';
  IF v_n <> 0 THEN RAISE EXCEPTION '[2] klasörsüz eski görsel: %', v_n; END IF;
  v_checks := v_checks + 1;

  -- Test verisi (postgres olarak, RLS'siz)
  INSERT INTO public.product_image_folders (name, display_order, is_active)
  VALUES ('ZZ Test Klasör A', 900, true) RETURNING id INTO v_a;
  INSERT INTO public.product_image_folders (name, display_order, is_active)
  VALUES ('ZZ Test Klasör B', 901, false) RETURNING id INTO v_b;

  INSERT INTO public.product_image_presets
    (name, description, image_url, is_active, display_order, folder_id)
  VALUES
    ('Organik Köy Domatesi', NULL,            'https://example.invalid/1.webp', true,  1, v_a),
    ('Salkım Domates',       NULL,            'https://example.invalid/2.webp', true,  2, v_a),
    ('Domates Salçası',      NULL,            'https://example.invalid/3.webp', true,  3, v_a),
    ('Kırmızı Biber',        'domates değil', 'https://example.invalid/4.webp', true,  4, v_a),
    ('Domates',              NULL,            'https://example.invalid/5.webp', true,  5, v_a),
    ('İncir',                NULL,            'https://example.invalid/6.webp', true,  6, v_a),
    ('Çilek',                'meyve',         'https://example.invalid/7.webp', true,  7, v_a),
    ('100% Saf_Bal',         NULL,            'https://example.invalid/8.webp', true,  8, v_a),
    ('Pasif Domates',        NULL,            'https://example.invalid/9.webp', false, 9, v_a),
    ('Gizli Domates',        NULL,            'https://example.invalid/10.webp', true, 1, v_b);

  -- Yazım hatası toleransının sınırları için ayrı klasör
  INSERT INTO public.product_image_folders (name, display_order, is_active)
  VALUES ('ZZ Test Klasör C', 903, true) RETURNING id INTO v_c;
  INSERT INTO public.product_image_presets
    (name, description, image_url, is_active, display_order, folder_id)
  VALUES
    ('Ay Çekirdeği', NULL, 'https://example.invalid/c1.webp', true, 1, v_c),
    ('Salatalık',    NULL, 'https://example.invalid/c2.webp', true, 2, v_c),
    ('Kavun',        NULL, 'https://example.invalid/c3.webp', true, 3, v_c);

  -- ---------------------------------------------------------------- satıcı
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', v_seller, 'role', 'authenticated')::text, true);

  -- [3] sıralama: birebir > başlıyor > kelime başı (kısa ad önce) > arama
  --     kelimesi; pasif yok
  SELECT array_agg(r.name ORDER BY r.ordinality) INTO v_names
    FROM public.search_product_image_presets('domates', v_a, 60, 0) WITH ORDINALITY r;
  IF v_names IS DISTINCT FROM ARRAY[
       'Domates', 'Domates Salçası', 'Salkım Domates', 'Organik Köy Domatesi', 'Kırmızı Biber'
     ] THEN
    RAISE EXCEPTION '[3] sıralama yanlış: %', v_names;
  END IF;
  v_checks := v_checks + 1;

  -- [4] Türkçe: İ/ı/ç büyük-küçük ve aksan duyarsız; çok kelime (ters sıra)
  SELECT array_agg(r.name) INTO v_names
    FROM public.search_product_image_presets('incir', v_a) r;
  IF v_names IS DISTINCT FROM ARRAY['İncir'] THEN
    RAISE EXCEPTION '[4] incir -> İncir bulunamadı: %', v_names;
  END IF;
  SELECT array_agg(r.name) INTO v_names
    FROM public.search_product_image_presets('  CILEK ', v_a) r;
  IF v_names IS DISTINCT FROM ARRAY['Çilek'] THEN
    RAISE EXCEPTION '[4] CILEK -> Çilek bulunamadı: %', v_names;
  END IF;
  SELECT array_agg(r.name) INTO v_names
    FROM public.search_product_image_presets('DOMATES   salkim', v_a) r;
  IF v_names IS DISTINCT FROM ARRAY['Salkım Domates'] THEN
    RAISE EXCEPTION '[4] çok kelimeli arama yanlış: %', v_names;
  END IF;
  -- arama kelimesiyle bulunur (description)
  SELECT array_agg(r.name) INTO v_names
    FROM public.search_product_image_presets('meyve', v_a) r;
  IF v_names IS DISTINCT FROM ARRAY['Çilek'] THEN
    RAISE EXCEPTION '[4] arama kelimesiyle bulunamadı: %', v_names;
  END IF;
  v_checks := v_checks + 1;

  -- [5] yazım hatası toleransı
  SELECT array_agg(r.name ORDER BY r.ordinality) INTO v_names
    FROM public.search_product_image_presets('domtes', v_a) WITH ORDINALITY r;
  IF v_names IS NULL OR v_names[1] <> 'Domates' THEN
    RAISE EXCEPTION '[5] domtes -> Domates ilk sırada değil: %', v_names;
  END IF;
  SELECT array_agg(r.name) INTO v_names
    FROM public.search_product_image_presets('salatlik', v_c) r;
  IF v_names IS DISTINCT FROM ARRAY['Salatalık'] THEN
    RAISE EXCEPTION '[5] salatlik -> Salatalık: %', v_names;
  END IF;
  SELECT array_agg(r.name) INTO v_names
    FROM public.search_product_image_presets('kavn', v_c) r;
  IF v_names IS DISTINCT FROM ARRAY['Kavun'] THEN
    RAISE EXCEPTION '[5] kavn -> Kavun: %', v_names;
  END IF;
  -- yanlış pozitif yok: 'cekic' ile 'cekirdegi' arası mesafe büyük; 3 harfte tolerans yok
  SELECT count(*) INTO v_n FROM public.search_product_image_presets('cekic', v_c);
  SELECT count(*) INTO v_n2 FROM public.search_product_image_presets('kvn', v_c);
  IF v_n <> 0 OR v_n2 <> 0 THEN
    RAISE EXCEPTION '[5] yanlış pozitif: cekic=% kvn=%', v_n, v_n2;
  END IF;
  v_checks := v_checks + 1;

  -- [6] % ve _ joker DEĞİL
  SELECT count(*) INTO v_n FROM public.search_product_image_presets('%', v_a);
  SELECT count(*) INTO v_n2 FROM public.search_product_image_presets('_', v_a);
  IF v_n <> 1 OR v_n2 <> 1 THEN
    RAISE EXCEPTION '[6] joker karakter sızıyor: %=% _=%', '%', v_n, v_n2;
  END IF;
  v_checks := v_checks + 1;

  -- [7] kapalı klasör satıcıya tamamen gizli (RPC, tablo, klasör)
  SELECT count(*) INTO v_n FROM public.search_product_image_presets('gizli domates');
  IF v_n <> 0 THEN RAISE EXCEPTION '[7] kapalı klasör görseli RPC''de'; END IF;
  SELECT count(*) INTO v_n FROM public.search_product_image_presets(NULL, v_b);
  IF v_n <> 0 THEN RAISE EXCEPTION '[7] kapalı klasör filtreyle açılıyor'; END IF;
  SELECT count(*) INTO v_n FROM public.product_image_presets WHERE folder_id = v_b;
  IF v_n <> 0 THEN RAISE EXCEPTION '[7] RLS kapalı klasör görselini sızdırıyor'; END IF;
  SELECT count(*) INTO v_n FROM public.product_image_presets WHERE name = 'Pasif Domates';
  IF v_n <> 0 THEN RAISE EXCEPTION '[7] RLS pasif görseli sızdırıyor'; END IF;
  SELECT count(*) INTO v_n FROM public.product_image_folders WHERE id = v_b;
  IF v_n <> 0 THEN RAISE EXCEPTION '[7] kapalı klasör satıcıya görünüyor'; END IF;
  v_checks := v_checks + 1;

  -- [8] satıcı özeti: yalnız açık klasör, yalnız yayındaki görseller
  SELECT s.image_count INTO v_n FROM public.product_image_folder_summary() s WHERE s.id = v_a;
  IF v_n IS DISTINCT FROM 8 THEN RAISE EXCEPTION '[8] satıcı sayacı yanlış: %', v_n; END IF;
  IF EXISTS (SELECT 1 FROM public.product_image_folder_summary() s WHERE s.id = v_b) THEN
    RAISE EXCEPTION '[8] kapalı klasör satıcı özetinde';
  END IF;
  v_checks := v_checks + 1;

  -- [9] sayfalama: çakışmasız, toplam doğru, sırası boş aramada display_order
  SELECT count(*) INTO v_n FROM (
    SELECT id FROM public.search_product_image_presets(NULL, v_a, 3, 0)
    INTERSECT
    SELECT id FROM public.search_product_image_presets(NULL, v_a, 3, 3)
  ) x;
  SELECT count(*) INTO v_n2 FROM (
    SELECT id FROM public.search_product_image_presets(NULL, v_a, 3, 0)
    UNION ALL SELECT id FROM public.search_product_image_presets(NULL, v_a, 3, 3)
    UNION ALL SELECT id FROM public.search_product_image_presets(NULL, v_a, 3, 6)
  ) x;
  IF v_n <> 0 OR v_n2 <> 8 THEN
    RAISE EXCEPTION '[9] sayfalama bozuk: kesişim=% toplam=%', v_n, v_n2;
  END IF;
  SELECT array_agg(r.name ORDER BY r.ordinality) INTO v_names
    FROM public.search_product_image_presets(NULL, v_a, 2, 0) WITH ORDINALITY r;
  IF v_names IS DISTINCT FROM ARRAY['Organik Köy Domatesi', 'Salkım Domates'] THEN
    RAISE EXCEPTION '[9] boş arama sırası yanlış: %', v_names;
  END IF;
  v_checks := v_checks + 1;

  -- [10] satıcı yazamaz: klasör ekleyemez, görsel taşıyamaz
  BEGIN
    INSERT INTO public.product_image_folders (name) VALUES ('Satıcı klasörü');
    RAISE EXCEPTION '[10] satıcı klasör ekledi';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  UPDATE public.product_image_presets SET folder_id = NULL WHERE folder_id = v_a;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n <> 0 THEN RAISE EXCEPTION '[10] satıcı görsel güncelledi: %', v_n; END IF;
  UPDATE public.product_image_folders SET is_active = false WHERE id = v_a;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n <> 0 THEN RAISE EXCEPTION '[10] satıcı klasör güncelledi'; END IF;
  v_checks := v_checks + 1;

  -- [15] "kelimelerden biri yeter" (ürün adından öneri): miktar/birim yok
  --      sayılır, çok kelimesi tutan önce
  SELECT count(*) INTO v_n
    FROM public.search_product_image_presets('Salkım Domates 1 kg', v_a);
  IF v_n <> 0 THEN RAISE EXCEPTION '[15] varsayılan mod tüm kelimeleri istemiyor: %', v_n; END IF;
  SELECT array_agg(r.name ORDER BY r.ordinality) INTO v_names
    FROM public.search_product_image_presets('Salkım Domates 1 kg', v_a, 60, 0, true)
         WITH ORDINALITY r;
  IF v_names IS NULL OR v_names[1] <> 'Salkım Domates' OR cardinality(v_names) <> 5 THEN
    RAISE EXCEPTION '[15] any modu sırası yanlış: %', v_names;
  END IF;
  SELECT count(*) INTO v_n
    FROM public.search_product_image_presets('1 kg 2,5', v_a, 60, 0, true);
  SELECT count(*) INTO v_n2
    FROM public.search_product_image_presets('', v_a, 60, 0, true);
  IF v_n <> 0 OR v_n2 <> 0 THEN
    RAISE EXCEPTION '[15] anlamlı kelimesiz any araması sonuç döndü: %/%', v_n, v_n2;
  END IF;
  -- yazım hatası any modunda da çalışır
  SELECT array_agg(r.name ORDER BY r.ordinality) INTO v_names
    FROM public.search_product_image_presets('taze salatlik 500 gr', v_c, 60, 0, true)
         WITH ORDINALITY r;
  IF v_names IS DISTINCT FROM ARRAY['Salatalık'] THEN
    RAISE EXCEPTION '[15] any + yazım hatası: %', v_names;
  END IF;
  v_checks := v_checks + 1;

  EXECUTE 'RESET ROLE';

  -- ---------------------------------------------------------------- admin
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);

  -- [11] admin her şeyi görür; özet tüm/yayındaki sayılarını ayırır
  SELECT count(*) INTO v_n FROM public.product_image_presets WHERE folder_id IN (v_a, v_b);
  IF v_n <> 10 THEN RAISE EXCEPTION '[11] admin tüm görselleri görmüyor: %', v_n; END IF;
  SELECT s.image_count, s.active_image_count INTO v_n, v_n2
    FROM public.product_image_folder_summary() s WHERE s.id = v_a;
  IF v_n <> 9 OR v_n2 <> 8 THEN
    RAISE EXCEPTION '[11] admin sayaçları yanlış: %/%', v_n, v_n2;
  END IF;
  SELECT s.image_count INTO v_n FROM public.product_image_folder_summary() s WHERE s.id = v_b;
  IF v_n IS DISTINCT FROM 1 THEN RAISE EXCEPTION '[11] admin kapalı klasörü görmüyor'; END IF;
  -- RPC adminde de yalnız yayındakileri döner (satıcı ekranı davranışı)
  SELECT count(*) INTO v_n FROM public.search_product_image_presets('domates', v_a);
  IF v_n <> 5 THEN RAISE EXCEPTION '[11] admin RPC''de pasif görüyor: %', v_n; END IF;

  -- [12] admin yazabilir: klasör adı benzersiz (normalize), source_key benzersiz
  BEGIN
    INSERT INTO public.product_image_folders (name) VALUES ('  zz test klasor a');
    RAISE EXCEPTION '[12] aynı klasör adı ikinci kez eklendi';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;
  INSERT INTO public.product_image_presets (name, image_url, folder_id, source_key)
  VALUES ('Kaynak 1', 'https://example.invalid/k1.webp', v_a, 'zz-test/kaynak.webp');
  BEGIN
    INSERT INTO public.product_image_presets (name, image_url, folder_id, source_key)
    VALUES ('Kaynak 2', 'https://example.invalid/k2.webp', v_a, 'zz-test/kaynak.webp');
    RAISE EXCEPTION '[12] aynı source_key ikinci kez eklendi';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;
  UPDATE public.product_image_presets SET name = 'Kaynak Bir'
   WHERE source_key = 'zz-test/kaynak.webp';
  IF NOT EXISTS (SELECT 1 FROM public.product_image_presets
                  WHERE source_key = 'zz-test/kaynak.webp' AND search_name = 'kaynak bir') THEN
    RAISE EXCEPTION '[12] search_name ad değişince güncellenmedi';
  END IF;
  -- klasör silinince görseller klasörsüz kalır, silinmez
  DELETE FROM public.product_image_folders WHERE id = v_b;
  IF NOT EXISTS (SELECT 1 FROM public.product_image_presets
                  WHERE name = 'Gizli Domates' AND folder_id IS NULL) THEN
    RAISE EXCEPTION '[12] klasör silinince görsel kayboldu';
  END IF;
  v_checks := v_checks + 2;

  EXECUTE 'RESET ROLE';

  -- [13] misafir (anon) RPC çağıramaz; eski 4 parametreli sürüm kalmadı
  IF to_regprocedure('public.search_product_image_presets(text, uuid, integer, integer)') IS NOT NULL THEN
    RAISE EXCEPTION '[13] eski 4 parametreli arama fonksiyonu duruyor (belirsiz çağrı)';
  END IF;
  IF has_function_privilege('anon', 'public.search_product_image_presets(text, uuid, integer, integer, boolean)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.product_image_folder_summary()', 'EXECUTE') THEN
    RAISE EXCEPTION '[13] anon RPC çağırabiliyor';
  END IF;
  v_checks := v_checks + 1;

  -- [14] hız: 3000 görsel, satıcı rolüyle
  INSERT INTO public.product_image_folders (name, display_order)
  VALUES ('ZZ Test Hız', 902) RETURNING id INTO v_perf;
  INSERT INTO public.product_image_presets (name, description, image_url, display_order, folder_id)
  SELECT (ARRAY['Domates', 'Şampuan', 'Çekiç', 'Vida', 'Sabun', 'Deterjan', 'Elma', 'Biber',
                'Diş Macunu', 'Pirinç', 'Makarna', 'Ayçiçek Yağı'])[1 + (g % 12)]
           || ' ' || (ARRAY['Büyük', 'Küçük', 'Ekonomik', 'Organik', 'Klasik'])[1 + (g % 5)]
           || ' ' || g,
         'kelime' || g || ' ürün',
         'https://example.invalid/p' || g || '.webp',
         g,
         CASE WHEN g % 2 = 0 THEN v_perf ELSE v_a END
    FROM generate_series(1, 3000) g;

  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', v_seller, 'role', 'authenticated')::text, true);
  PERFORM count(*) FROM public.search_product_image_presets('isinma', NULL, 60, 0);
  v_t0 := clock_timestamp();
  PERFORM count(*) FROM public.search_product_image_presets('domates', NULL, 60, 0);
  v_ms := round(extract(epoch FROM clock_timestamp() - v_t0) * 1000, 1);
  v_t0 := clock_timestamp();
  SELECT count(*) INTO v_n FROM public.search_product_image_presets('samuan', NULL, 60, 0);
  v_ms_typo := round(extract(epoch FROM clock_timestamp() - v_t0) * 1000, 1);
  EXECUTE 'RESET ROLE';
  IF v_n = 0 THEN RAISE EXCEPTION '[14] samuan -> Şampuan bulunamadı'; END IF;
  IF v_ms > 300 OR v_ms_typo > 300 THEN
    RAISE EXCEPTION '[14] arama yavaş: % ms / yazım hatası % ms', v_ms, v_ms_typo;
  END IF;
  v_checks := v_checks + 1;

  RAISE EXCEPTION 'TESTS_PASSED % kontrol (3000+ görselde arama % ms, yazım hatalı arama % ms)',
    v_checks, v_ms, v_ms_typo;
END
$test$;
