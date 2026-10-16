-- Admin görsel kütüphanesi sayfalı liste canlı doğrulaması
-- (20261016000004_admin_product_image_presets_page.sql). Kendini geri alır.
--
-- Çalıştırma: supabase db query --linked --file supabase/tests/manual/admin_product_image_presets_page_test.sql
-- Başarı = 'TESTS_PASSED ...' istisnası (DO bloğu RAISE EXCEPTION ile biter,
-- böylece testin yazdığı her şey geri alınır).
DO $test$
DECLARE
  v_admin uuid;
  v_user uuid;
  v_a uuid;
  v_b uuid;
  v_res jsonb;
  v_res2 jsonb;
  v_names text[];
  v_names2 text[];
  v_ids uuid[];
  v_ids2 uuid[];
  v_n integer;
  v_n2 integer;
  v_case record;
  v_t0 timestamptz;
  v_ms_first numeric;
  v_ms_search numeric;
  v_ms_ids numeric;
  v_bytes integer;
  v_checks integer := 0;
BEGIN
  SELECT id INTO v_admin FROM public.profiles
   WHERE role = 'admin'::public.user_role ORDER BY created_at LIMIT 1;
  SELECT id INTO v_user FROM public.profiles
   WHERE role <> 'admin'::public.user_role ORDER BY created_at LIMIT 1;
  IF v_admin IS NULL OR v_user IS NULL THEN
    RAISE EXCEPTION '[0] admin/normal kullanıcı bulunamadı';
  END IF;

  -- [1] şema: üç fonksiyon INVOKER, anon çalıştıramaz, authenticated çalıştırır
  SELECT count(*) INTO v_n FROM pg_proc
   WHERE pronamespace = 'public'::regnamespace AND NOT prosecdef
     AND proname IN ('admin_product_image_presets_page',
                     'admin_product_image_preset_ids',
                     'product_image_like_patterns');
  IF v_n <> 3 THEN RAISE EXCEPTION '[1] fonksiyonlar yok ya da DEFINER: %', v_n; END IF;
  IF has_function_privilege('anon',
       'public.admin_product_image_presets_page(uuid, boolean, text, text, text, integer, integer, boolean)', 'EXECUTE')
     OR has_function_privilege('anon',
       'public.admin_product_image_preset_ids(uuid, boolean, text, text)', 'EXECUTE') THEN
    RAISE EXCEPTION '[1] anon admin RPC''lerini çalıştırabiliyor';
  END IF;
  IF NOT has_function_privilege('authenticated',
       'public.admin_product_image_presets_page(uuid, boolean, text, text, text, integer, integer, boolean)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated',
       'public.admin_product_image_preset_ids(uuid, boolean, text, text)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated',
       'public.product_image_like_patterns(text)', 'EXECUTE') THEN
    RAISE EXCEPTION '[1] authenticated EXECUTE yetkisi eksik';
  END IF;
  v_checks := v_checks + 1;

  -- [2] arama kalıbı: Türkçe/aksan sadeleşir, fazla boşluk atılır, joker kaçışlı
  IF public.product_image_like_patterns('  Çiğ   KÖFTE ') IS DISTINCT FROM ARRAY['%cig%', '%kofte%']
     OR public.product_image_like_patterns('saf_b 100%') IS DISTINCT FROM ARRAY['%saf\_b%', '%100\%%']
     OR public.product_image_like_patterns('') IS DISTINCT FROM '{}'::text[]
     OR public.product_image_like_patterns(NULL) IS DISTINCT FROM '{}'::text[]
     OR cardinality(public.product_image_like_patterns(repeat('ab ', 30))) <> 16 THEN
    RAISE EXCEPTION '[2] arama kalıbı yanlış: %', public.product_image_like_patterns('saf_b 100%');
  END IF;
  v_checks := v_checks + 1;

  -- Test verisi (postgres olarak). Hepsinin adında 'qzxw' işareti var ki
  -- arama canlı kütüphaneden yalnız bunları döndürsün.
  INSERT INTO public.product_image_folders (name, display_order, is_active)
  VALUES ('ZZ Sayfa Test A', 950, true) RETURNING id INTO v_a;
  INSERT INTO public.product_image_folders (name, display_order, is_active)
  VALUES ('ZZ Sayfa Test B', 951, false) RETURNING id INTO v_b;

  INSERT INTO public.product_image_presets
    (name, description, image_url, is_active, display_order, folder_id, created_at)
  VALUES
    ('Qzxw Çiğ Köfte',    'acılı dürüm',  'https://example.invalid/p1.webp', true,  3, v_a, '2001-01-03'),
    ('Qzxw Domates',      NULL,           'https://example.invalid/p2.webp', true,  1, v_a, '2001-01-05'),
    ('Qzxw Biber',        'sebze',        'https://example.invalid/p3.webp', false, 2, v_a, '2001-01-01'),
    ('Qzxw Saf_Bal',      NULL,           'https://example.invalid/p4.webp', true,  2, v_b, '2001-01-04'),
    ('Qzxw Safabal',      NULL,           'https://example.invalid/p5.webp', false, 4, v_b, '2001-01-02'),
    ('Qzxw Klasörsüz Ayva', 'meyve',      'https://example.invalid/p6.webp', true,  7, NULL, '2001-01-06'),
    ('Qzxw Klasörsüz Nar',  NULL,         'https://example.invalid/p7.webp', false, 7, NULL, '2001-01-07');

  -- ------------------------------------------------------- normal kullanıcı
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', v_user, 'role', 'authenticated')::text, true);

  -- [3] admin değilse iki RPC de 42501
  BEGIN
    PERFORM public.admin_product_image_presets_page();
    RAISE EXCEPTION '[3] normal kullanıcı sayfayı aldı';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    PERFORM public.admin_product_image_preset_ids();
    RAISE EXCEPTION '[3] normal kullanıcı kimlikleri aldı';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  v_checks := v_checks + 1;

  -- ------------------------------------------------------------------ admin
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);

  -- [4] arama: yalnız işaretli satırlar; sıra no, sonra ad (Biber/Saf_Bal
  --     aynı sıra no; harmanlamadan bağımsız seçildi)
  v_res := public.admin_product_image_presets_page(p_query => 'QZXW', p_limit => 50);
  SELECT array_agg(e->>'name' ORDER BY o) INTO v_names
    FROM jsonb_array_elements(v_res->'items') WITH ORDINALITY AS t(e, o);
  IF v_names IS DISTINCT FROM ARRAY[
       'Qzxw Domates', 'Qzxw Biber', 'Qzxw Saf_Bal', 'Qzxw Çiğ Köfte',
       'Qzxw Safabal', 'Qzxw Klasörsüz Ayva', 'Qzxw Klasörsüz Nar'
     ] OR (v_res->>'total')::int <> 7 THEN
    RAISE EXCEPTION '[4] sıra numarası sıralaması yanlış: % (toplam %)', v_names, v_res->>'total';
  END IF;
  -- İstemcinin okuduğu 8 alan, fazlası yok (search_* sızmaz); özet istenmedi
  IF (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(v_res->'items'->0) k)
       IS DISTINCT FROM ARRAY['created_at', 'description', 'display_order', 'folder_id',
                              'id', 'image_url', 'is_active', 'name']
     OR v_res ? 'summary' THEN
    RAISE EXCEPTION '[4] satır alanları/özet yanlış: %', v_res->'items'->0;
  END IF;
  v_checks := v_checks + 1;

  -- [5] Türkçe/aksan duyarsız, kelimeler her sırada, arama kelimelerinde de
  FOR v_case IN
    SELECT * FROM (VALUES
      ('qzxw CIG kofte', 1, 'Qzxw Çiğ Köfte'),
      ('köfte qzxw çığ', 1, 'Qzxw Çiğ Köfte'),
      ('qzxw ACILI', 1, 'Qzxw Çiğ Köfte'),   -- açıklamada
      ('qzxw dürüm köfte', 1, 'Qzxw Çiğ Köfte'),
      ('qzxw saf_', 1, 'Qzxw Saf_Bal'),      -- _ joker değil: Safabal gelmez
      ('qzxw klasorsuz', 2, NULL),
      ('qzxw olmayan', 0, NULL)
    ) AS c(q, n, first_name)
  LOOP
    v_res := public.admin_product_image_presets_page(p_query => v_case.q);
    IF (v_res->>'total')::int <> v_case.n
       OR jsonb_array_length(v_res->'items') <> v_case.n
       OR (v_case.first_name IS NOT NULL AND v_res->'items'->0->>'name' <> v_case.first_name) THEN
      RAISE EXCEPTION '[5] "%" araması yanlış: %', v_case.q, v_res;
    END IF;
  END LOOP;
  v_checks := v_checks + 1;

  -- [6] durum ve klasör süzgeçleri (kapalı klasör admine görünür)
  FOR v_case IN
    SELECT * FROM (VALUES
      (NULL::uuid, false, 'all', 7),
      (NULL, false, 'active', 4),
      (NULL, false, 'passive', 3),
      (v_a, false, 'all', 3),
      (v_a, false, 'passive', 1),
      (v_b, false, 'all', 2),
      (v_b, false, 'active', 1),
      (NULL, true, 'all', 2),
      (NULL, true, 'active', 1)
    ) AS c(folder, unfiled, status, n)
  LOOP
    v_res := public.admin_product_image_presets_page(
      p_folder_id => v_case.folder, p_unfiled => v_case.unfiled,
      p_status => v_case.status, p_query => 'qzxw');
    IF (v_res->>'total')::int <> v_case.n THEN
      RAISE EXCEPTION '[6] süzgeç (%/%/%) toplamı % <> %',
        v_case.folder, v_case.unfiled, v_case.status, v_res->>'total', v_case.n;
    END IF;
    IF EXISTS (
      SELECT 1 FROM jsonb_array_elements(v_res->'items') e
       WHERE (v_case.status = 'active' AND NOT (e->>'is_active')::boolean)
          OR (v_case.status = 'passive' AND (e->>'is_active')::boolean)
          OR (v_case.folder IS NOT NULL AND (e->>'folder_id')::uuid IS DISTINCT FROM v_case.folder)
          OR (v_case.unfiled AND e->>'folder_id' IS NOT NULL)
    ) THEN
      RAISE EXCEPTION '[6] süzgeç (%/%/%) uymayan satır döndü', v_case.folder, v_case.unfiled, v_case.status;
    END IF;
  END LOOP;
  v_checks := v_checks + 1;

  -- [7] en yeni önce
  v_res := public.admin_product_image_presets_page(p_query => 'qzxw', p_sort => 'newest');
  SELECT array_agg(e->>'name' ORDER BY o) INTO v_names
    FROM jsonb_array_elements(v_res->'items') WITH ORDINALITY AS t(e, o);
  IF v_names IS DISTINCT FROM ARRAY[
       'Qzxw Klasörsüz Nar', 'Qzxw Klasörsüz Ayva', 'Qzxw Domates', 'Qzxw Saf_Bal',
       'Qzxw Çiğ Köfte', 'Qzxw Safabal', 'Qzxw Biber'
     ] THEN
    RAISE EXCEPTION '[7] en yeni sıralaması yanlış: %', v_names;
  END IF;
  v_checks := v_checks + 1;

  -- [8] sayfalar: 3'erli sayfalar art arda tüm listeyi verir, çakışma yok,
  --     toplam her sayfada aynı; limit 0 = boş sayfa + toplam; üst sınır 500
  FOR v_case IN SELECT * FROM (VALUES ('order'), ('newest')) AS c(sort) LOOP
    v_res := public.admin_product_image_presets_page(p_query => 'qzxw', p_sort => v_case.sort);
    SELECT array_agg(e->>'id' ORDER BY o) INTO v_names
      FROM jsonb_array_elements(v_res->'items') WITH ORDINALITY AS t(e, o);
    v_names2 := '{}';
    FOR v_n IN 0..3 LOOP
      v_res2 := public.admin_product_image_presets_page(
        p_query => 'qzxw', p_sort => v_case.sort, p_limit => 3, p_offset => v_n * 3);
      IF (v_res2->>'total')::int <> 7
         OR jsonb_array_length(v_res2->'items') <> (CASE v_n WHEN 2 THEN 1 WHEN 3 THEN 0 ELSE 3 END) THEN
        RAISE EXCEPTION '[8] % sayfa % yanlış: %', v_case.sort, v_n, v_res2;
      END IF;
      v_names2 := v_names2 || ARRAY(
        SELECT e->>'id' FROM jsonb_array_elements(v_res2->'items') WITH ORDINALITY AS t(e, o) ORDER BY o);
    END LOOP;
    IF v_names2 IS DISTINCT FROM v_names THEN
      RAISE EXCEPTION '[8] % sayfaları birleşince liste tutmuyor', v_case.sort;
    END IF;
  END LOOP;
  v_res := public.admin_product_image_presets_page(p_query => 'qzxw', p_limit => 0);
  IF v_res->'items' <> '[]'::jsonb OR (v_res->>'total')::int <> 7 THEN
    RAISE EXCEPTION '[8] limit 0 yanlış: %', v_res;
  END IF;
  v_res := public.admin_product_image_presets_page(p_limit => 100000);
  IF jsonb_array_length(v_res->'items') > 500 THEN
    RAISE EXCEPTION '[8] limit üst sınırı yok';
  END IF;
  v_checks := v_checks + 1;

  -- [9] özet: tüm klasörler (kapalı dahil, sırayla), klasör başına
  --     tüm/yayında, klasörsüzler, en büyük sıra no — tabloyla birebir
  v_res := public.admin_product_image_presets_page(p_limit => 0, p_with_summary => true);
  IF jsonb_array_length(v_res->'summary'->'folders') <> (SELECT count(*) FROM public.product_image_folders) THEN
    RAISE EXCEPTION '[9] özette klasör sayısı yanlış';
  END IF;
  IF EXISTS (
    SELECT 1
      FROM jsonb_array_elements(v_res->'summary'->'folders') e
      JOIN public.product_image_folders f ON f.id = (e->>'id')::uuid
     WHERE (e->>'image_count')::int <> (SELECT count(*) FROM public.product_image_presets p WHERE p.folder_id = f.id)
        OR (e->>'active_image_count')::int <> (SELECT count(*) FROM public.product_image_presets p
                                                WHERE p.folder_id = f.id AND p.is_active)
        OR e->>'name' <> f.name
        OR (e->>'is_active')::boolean <> f.is_active
        OR (e->>'display_order')::int <> f.display_order
  ) THEN
    RAISE EXCEPTION '[9] özetteki klasör sayaçları tabloyla tutmuyor';
  END IF;
  IF (SELECT e->>'image_count' FROM jsonb_array_elements(v_res->'summary'->'folders') e
       WHERE (e->>'id')::uuid = v_a) <> '3'
     OR (SELECT e->>'active_image_count' FROM jsonb_array_elements(v_res->'summary'->'folders') e
          WHERE (e->>'id')::uuid = v_b) <> '1' THEN
    RAISE EXCEPTION '[9] test klasörlerinin sayaçları yanlış';
  END IF;
  SELECT array_agg((e->>'id')::uuid ORDER BY o) INTO v_ids
    FROM jsonb_array_elements(v_res->'summary'->'folders') WITH ORDINALITY AS t(e, o);
  SELECT array_agg(f.id ORDER BY f.display_order, f.name, f.id) INTO v_ids2
    FROM public.product_image_folders f;
  IF v_ids IS DISTINCT FROM v_ids2 THEN
    RAISE EXCEPTION '[9] özetteki klasör sırası yanlış';
  END IF;
  IF (v_res->'summary'->>'unfiled_count')::int
       <> (SELECT count(*) FROM public.product_image_presets WHERE folder_id IS NULL)
     OR (v_res->'summary'->>'unfiled_active_count')::int
       <> (SELECT count(*) FROM public.product_image_presets WHERE folder_id IS NULL AND is_active)
     OR (v_res->'summary'->>'unfiled_count')::int < 2
     OR (v_res->'summary'->>'max_display_order')::int
       <> (SELECT max(display_order) FROM public.product_image_presets)
     OR (v_res->>'total')::int <> (SELECT count(*) FROM public.product_image_presets) THEN
    RAISE EXCEPTION '[9] özet toplamları yanlış: %', v_res->'summary' - 'folders';
  END IF;
  v_checks := v_checks + 1;

  -- [10] kimlik RPC'si sayfayla aynı süzgeç: test süzgeçlerinde ve tüm
  --      kütüphanede küme birebir aynı
  FOR v_case IN
    SELECT * FROM (VALUES
      (NULL::uuid, false, 'all', 'qzxw'),
      (NULL, false, 'passive', 'qzxw'),
      (v_a, false, 'all', 'qzxw'),
      (v_b, false, 'active', 'qzxw saf'),
      (NULL, true, 'all', 'qzxw'),
      (NULL, false, 'all', 'qzxw çiğ köfte'),
      (NULL, false, 'active', NULL)
    ) AS c(folder, unfiled, status, q)
  LOOP
    v_ids := public.admin_product_image_preset_ids(v_case.folder, v_case.unfiled, v_case.status, v_case.q);
    v_res := public.admin_product_image_presets_page(
      v_case.folder, v_case.unfiled, v_case.status, v_case.q, 'order', 500, 0);
    IF cardinality(v_ids) <> (v_res->>'total')::int THEN
      RAISE EXCEPTION '[10] kimlik sayısı % <> toplam % (%/%/%/%)',
        cardinality(v_ids), v_res->>'total', v_case.folder, v_case.unfiled, v_case.status, v_case.q;
    END IF;
    IF (v_res->>'total')::int <= 500 AND EXISTS (
      SELECT (e->>'id')::uuid FROM jsonb_array_elements(v_res->'items') e
      EXCEPT SELECT unnest(v_ids)
    ) THEN
      RAISE EXCEPTION '[10] kimlik kümesi sayfayla tutmuyor (%/%/%/%)',
        v_case.folder, v_case.unfiled, v_case.status, v_case.q;
    END IF;
  END LOOP;
  IF cardinality(public.admin_product_image_preset_ids())
       <> (SELECT count(*) FROM public.product_image_presets) THEN
    RAISE EXCEPTION '[10] süzgeçsiz kimlik sayısı tabloyla tutmuyor';
  END IF;
  v_checks := v_checks + 1;

  -- [11] geçersiz süzgeç/sıralama 22023
  BEGIN
    PERFORM public.admin_product_image_presets_page(p_status => 'hepsi');
    RAISE EXCEPTION '[11] geçersiz durum kabul edildi';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;
  BEGIN
    PERFORM public.admin_product_image_presets_page(p_sort => 'name');
    RAISE EXCEPTION '[11] geçersiz sıralama kabul edildi';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;
  BEGIN
    PERFORM public.admin_product_image_preset_ids(p_status => 'x');
    RAISE EXCEPTION '[11] kimliklerde geçersiz durum kabul edildi';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;
  v_checks := v_checks + 1;

  -- [12] canlı kütüphanede hız ve boyut: açılış isteği (ilk sayfa + özet),
  --      arama, tüm kimlikler. Eski açılış tüm kütüphaneyi (~5 MB) çekiyordu.
  PERFORM public.admin_product_image_presets_page(p_with_summary => true);
  v_t0 := clock_timestamp();
  v_res := public.admin_product_image_presets_page(p_with_summary => true);
  v_ms_first := round(extract(epoch FROM clock_timestamp() - v_t0) * 1000, 1);
  v_bytes := octet_length(v_res::text);
  v_t0 := clock_timestamp();
  PERFORM public.admin_product_image_presets_page(p_query => 'domates', p_sort => 'newest');
  v_ms_search := round(extract(epoch FROM clock_timestamp() - v_t0) * 1000, 1);
  v_t0 := clock_timestamp();
  PERFORM public.admin_product_image_preset_ids();
  v_ms_ids := round(extract(epoch FROM clock_timestamp() - v_t0) * 1000, 1);
  EXECUTE 'RESET ROLE';
  IF jsonb_array_length(v_res->'items') <> 60 THEN
    RAISE EXCEPTION '[12] varsayılan sayfa 60 satır değil';
  END IF;
  IF v_ms_first > 150 OR v_ms_search > 150 OR v_ms_ids > 150 OR v_bytes > 60000 THEN
    RAISE EXCEPTION '[12] yavaş/büyük: açılış % ms (% bayt), arama % ms, kimlikler % ms',
      v_ms_first, v_bytes, v_ms_search, v_ms_ids;
  END IF;
  v_checks := v_checks + 1;

  RAISE EXCEPTION 'TESTS_PASSED % kontrol (% görsellik canlı kütüphane: açılış % ms / % bayt, arama % ms, tüm kimlikler % ms)',
    v_checks, (SELECT count(*) FROM public.product_image_presets),
    v_ms_first, v_bytes, v_ms_search, v_ms_ids;
END
$test$;
