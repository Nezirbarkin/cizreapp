-- =============================================================================
-- Admin > Dükkanlar sayfalı liste (admin_shops_page) — sunucu testi
--   supabase db query --linked --file supabase/tests/manual/admin_shops_page_test.sql
--
-- Önkoşul: 20260927000002_admin_shops_page.sql uygulanmış olmalı.
--
-- Neyi kanıtlar:
--   [A]  admin olmayan 42501 alır; anon çağıramaz
--   [E]  TÜM canlı dükkanlar için ürün/sipariş sayıları, kazançlar, komisyon,
--        kurye kesintisi ve net kazanç eski istemci hesabıyla BİREBİR; sahip
--        profili (ad, kullanıcı adı, e-posta) doğru
--   [S]  özet (summary) tüm dükkanları sayar; her filtrenin toplamı özetle aynı
--   [P]  sayfalar birleşince tam liste, aynı sıra, tekrarsız
--   [Q]  arama: dükkan adı ve sahip e-postası ile bulur
--   [O]  sıralamalar: varsayılan (sabitlenen önce), isim, kazanç, sipariş, en yeni
--   [L]  sayfa boyutu 1–100 arası sıkıştırılır; bilinmeyen filtre = filtresiz
--   [P]  süre (ms)
--
-- Betik TEK DO bloğudur ve SONUNDA bilerek istisna fırlatır: her şey geri alınır.
--   BAŞARILI:  "TESTS_PASSED ..."    BAŞARISIZ: "TEST_FAIL[x]: ..."
-- =============================================================================

CREATE OR REPLACE FUNCTION pg_temp.ok(p_cond boolean, p_label text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF p_cond IS NOT TRUE THEN
    RAISE EXCEPTION 'TEST_FAIL[%]', p_label;
  END IF;
  PERFORM set_config('t.n', (COALESCE(NULLIF(current_setting('t.n', true), ''), '0')::int + 1)::text, true);
END $$;

CREATE OR REPLACE FUNCTION pg_temp.as_user(p_user uuid)
RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claim.sub', COALESCE(p_user::text, ''), true)
$$;

-- Admin olarak bir sayfa (rol değişimi fonksiyon içinde yapılmaz; çağıran ayarlar).
CREATE OR REPLACE FUNCTION pg_temp.page(
  p_search text, p_filter text, p_sort text, p_limit int, p_offset int
) RETURNS jsonb LANGUAGE sql AS $$
  SELECT public.admin_shops_page(p_search, p_filter, p_sort, p_limit, p_offset)
$$;

DO $test$
DECLARE
  v_admin uuid;
  v_user uuid;
  v_all jsonb;
  v_rows jsonb;
  v_row jsonb;
  v_ids uuid[];
  v_paged uuid[] := '{}';
  v_page jsonb;
  v_offset int := 0;
  v_fee double precision;
  v_shop_count int;
  v_filter text;
  v_prev jsonb;
  v_email text;
  v_email_shop uuid;
  v_name_shop uuid;
  v_name text;
  v_rev numeric := 0;
  v_com numeric := 0;
  v_clock timestamptz;
  v_ms numeric;
  r record;
  i int;
BEGIN
  SELECT id INTO v_admin FROM public.profiles
   WHERE role = 'admin'::public.user_role ORDER BY created_at LIMIT 1;
  SELECT id INTO v_user FROM public.profiles
   WHERE role = 'customer'::public.user_role ORDER BY created_at LIMIT 1;
  IF v_admin IS NULL OR v_user IS NULL THEN
    RAISE EXCEPTION 'TEST_FAIL[setup]: admin ve müşteri profili gerekli';
  END IF;
  SELECT count(*) INTO v_shop_count FROM public.shops;

  -- ------------------------------------------------------------------ yetki
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM pg_temp.as_user(v_user);
    PERFORM public.admin_shops_page();
    EXECUTE 'RESET ROLE';
    RAISE EXCEPTION 'TEST_FAIL[A1]: admin olmayan dükkan listesini aldı';
  EXCEPTION WHEN insufficient_privilege THEN
    EXECUTE 'RESET ROLE';
  END;
  PERFORM pg_temp.ok(true, 'A1 admin olmayan 42501');

  BEGIN
    EXECUTE 'SET LOCAL ROLE anon';
    PERFORM public.admin_shops_page();
    EXECUTE 'RESET ROLE';
    RAISE EXCEPTION 'TEST_FAIL[A2]: anon çağırabildi';
  EXCEPTION WHEN insufficient_privilege THEN
    EXECUTE 'RESET ROLE';
  END;
  PERFORM pg_temp.ok(true, 'A2 anon çağıramaz');

  -- ------------------------------------------------- admin gözüyle tam liste
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM pg_temp.as_user(v_admin);
  v_all := pg_temp.page(NULL, NULL, 'default', 100, 0);
  EXECUTE 'RESET ROLE';
  v_rows := v_all->'rows';

  PERFORM pg_temp.ok((v_all->>'total')::int = v_shop_count, 'E1 toplam dükkan sayısı');
  PERFORM pg_temp.ok(jsonb_array_length(v_rows) = LEAST(v_shop_count, 100), 'E1b ilk sayfa tüm dükkanlar');

  -- Eski _getCourierFee karşılığı
  SELECT cs.fee_per_delivery INTO v_fee FROM public.courier_settings cs
   ORDER BY cs.updated_at DESC LIMIT 1;
  v_fee := COALESCE(v_fee, 15);

  -- Eski istemci hesabı (dükkan başına ayrı sorgular) ile birebir karşılaştırma.
  FOR r IN
    SELECT s.id, s.commission_rate, s.has_own_courier, s.owner_id,
           (SELECT count(*) FROM public.products p WHERE p.shop_id = s.id) AS pc,
           (SELECT count(*) FROM public.orders o WHERE o.shop_id = s.id) AS tot,
           (SELECT count(*) FROM public.orders o
             WHERE o.shop_id = s.id AND o.status::text = 'delivered') AS del,
           (SELECT count(*) FROM public.orders o
             WHERE o.shop_id = s.id AND o.status::text = 'cancelled') AS can,
           (SELECT COALESCE(sum(o.total), 0) FROM public.orders o
             WHERE o.shop_id = s.id AND o.status::text = 'delivered') AS earn,
           (SELECT COALESCE(sum(o.total), 0) FROM public.orders o
             WHERE o.shop_id = s.id AND o.status::text = 'delivered'
               AND o.created_at > now() - interval '7 days') AS week,
           (SELECT COALESCE(sum(o.total), 0) FROM public.orders o
             WHERE o.shop_id = s.id AND o.status::text = 'delivered'
               AND o.created_at > now() - interval '30 days') AS month,
           pf.username, pf.full_name, pf.email
      FROM public.shops s
      LEFT JOIN public.profiles pf ON pf.id = s.owner_id
  LOOP
    SELECT e INTO v_row FROM jsonb_array_elements(v_rows) e WHERE (e->>'id')::uuid = r.id;
    PERFORM pg_temp.ok(v_row IS NOT NULL, 'E2 dükkan listede: ' || r.id);
    PERFORM pg_temp.ok((v_row->>'product_count')::bigint = r.pc, 'E3 ürün sayısı: ' || r.id);
    PERFORM pg_temp.ok((v_row->>'total_orders')::bigint = r.tot
                       AND (v_row->>'delivered_orders')::bigint = r.del
                       AND (v_row->>'cancelled_orders')::bigint = r.can
                       AND (v_row->>'pending_orders')::bigint = r.tot - r.del - r.can,
                       'E4 sipariş sayıları: ' || r.id);
    PERFORM pg_temp.ok(abs((v_row->>'total_earnings')::numeric - r.earn) < 0.005
                       AND abs((v_row->>'weekly_earnings')::numeric - r.week) < 0.005
                       AND abs((v_row->>'monthly_earnings')::numeric - r.month) < 0.005,
                       'E5 kazançlar: ' || r.id);
    PERFORM pg_temp.ok(
      abs((v_row->>'admin_commission_total')::numeric
          - r.earn * COALESCE(r.commission_rate, 10) / 100) < 0.005,
      'E6 komisyon: ' || r.id);
    PERFORM pg_temp.ok(
      abs((v_row->>'courier_deduction')::numeric
          - CASE WHEN NOT COALESCE(r.has_own_courier, true) THEN r.del * v_fee ELSE 0 END) < 0.005,
      'E7 kurye kesintisi: ' || r.id);
    PERFORM pg_temp.ok(
      abs((v_row->>'net_earnings')::numeric
          - (r.earn - r.earn * COALESCE(r.commission_rate, 10) / 100
             - CASE WHEN NOT COALESCE(r.has_own_courier, true) THEN r.del * v_fee ELSE 0 END)) < 0.005,
      'E8 net kazanç: ' || r.id);
    PERFORM pg_temp.ok(
      (r.owner_id IS NULL AND v_row->'profiles' = 'null'::jsonb)
      OR (v_row->'profiles'->>'username' IS NOT DISTINCT FROM r.username
          AND v_row->'profiles'->>'full_name' IS NOT DISTINCT FROM r.full_name
          AND v_row->'profiles'->>'email' IS NOT DISTINCT FROM r.email),
      'E9 sahip profili: ' || r.id);
    v_rev := v_rev + r.earn;
    v_com := v_com + r.earn * COALESCE(r.commission_rate, 10) / 100;
  END LOOP;

  PERFORM pg_temp.ok(NOT (v_rows->0 ? 'rn') AND NOT (v_rows->0 ? 'is_overridden')
                     AND v_rows->0 ? 'pre_override_delivery_fee' AND v_rows->0 ? 'online_payment_revenue',
                     'E10 kart alanları var, yardımcı alanlar yok');

  -- ------------------------------------------------------------------ özet
  PERFORM pg_temp.ok((v_all->'summary'->>'total')::int = v_shop_count, 'S1 özet toplamı');
  PERFORM pg_temp.ok(abs((v_all->'summary'->>'revenue')::numeric - v_rev) < 0.01
                     AND abs((v_all->'summary'->>'commission')::numeric - v_com) < 0.01,
                     'S2 toplam ciro ve komisyon');

  EXECUTE 'SET LOCAL ROLE authenticated';
  FOREACH v_filter IN ARRAY ARRAY['pending', 'active', 'passive', 'pinned',
                                  'verified', 'admin_courier', 'overridden'] LOOP
    v_page := pg_temp.page(NULL, v_filter, 'default', 1, 0);
    PERFORM pg_temp.ok((v_page->>'total')::int = (v_all->'summary'->>v_filter)::int,
                       'S3 filtre toplamı özetle aynı: ' || v_filter);
  END LOOP;
  v_page := pg_temp.page(NULL, 'bilinmeyen', 'default', 1, 0);
  PERFORM pg_temp.ok((v_page->>'total')::int = v_shop_count, 'L3 bilinmeyen filtre = filtresiz');

  -- ------------------------------------------------------------- sayfalama
  SELECT array_agg((e->>'id')::uuid ORDER BY ord) INTO v_ids
    FROM jsonb_array_elements(v_rows) WITH ORDINALITY AS t(e, ord);
  LOOP
    v_page := pg_temp.page(NULL, NULL, 'default', 5, v_offset);
    EXIT WHEN jsonb_array_length(v_page->'rows') = 0;
    v_paged := v_paged || ARRAY(
      SELECT (e->>'id')::uuid FROM jsonb_array_elements(v_page->'rows') WITH ORDINALITY AS t(e, ord)
      ORDER BY ord);
    v_offset := v_offset + 5;
  END LOOP;
  PERFORM pg_temp.ok(v_paged = v_ids, 'P1 sayfalar birleşince aynı sıra, tekrarsız');

  -- ------------------------------------------------------------------ sınırlar
  v_page := pg_temp.page(NULL, NULL, 'default', 0, 0);
  PERFORM pg_temp.ok(jsonb_array_length(v_page->'rows') = LEAST(v_shop_count, 1), 'L1 alt sınır 1');
  v_page := pg_temp.page(NULL, NULL, 'default', 100000, 0);
  PERFORM pg_temp.ok(jsonb_array_length(v_page->'rows') <= 100, 'L2 üst sınır 100');

  -- ------------------------------------------------------------------- arama
  SELECT e->>'name', (e->>'id')::uuid INTO v_name, v_name_shop
    FROM jsonb_array_elements(v_rows) e WHERE COALESCE(e->>'name', '') <> '' LIMIT 1;
  IF v_name IS NOT NULL THEN
    -- Adın bir parçası (Türkçe ı/İ dönüşümü yanlış negatif vermesin diye
    -- harf büyütülmeden).
    v_page := pg_temp.page(left(v_name, 3), NULL, 'default', 100, 0);
    PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM jsonb_array_elements(v_page->'rows') e
                               WHERE (e->>'id')::uuid = v_name_shop),
                       'Q1 dükkan adıyla bulur');
  END IF;
  SELECT e->'profiles'->>'email', (e->>'id')::uuid INTO v_email, v_email_shop
    FROM jsonb_array_elements(v_rows) e
   WHERE COALESCE(e->'profiles'->>'email', '') LIKE '%@%' LIMIT 1;
  IF v_email IS NOT NULL THEN
    v_page := pg_temp.page(split_part(v_email, '@', 1), NULL, 'default', 100, 0);
    PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM jsonb_array_elements(v_page->'rows') e
                               WHERE (e->>'id')::uuid = v_email_shop),
                       'Q2 sahip e-postasıyla bulur');
  END IF;

  -- -------------------------------------------------------------- sıralamalar
  v_page := pg_temp.page(NULL, NULL, 'default', 100, 0);
  v_prev := NULL;
  FOR v_row IN SELECT e FROM jsonb_array_elements(v_page->'rows') WITH ORDINALITY AS t(e, ord) ORDER BY ord LOOP
    IF v_prev IS NOT NULL THEN
      PERFORM pg_temp.ok(NOT (COALESCE((v_row->>'is_pinned')::boolean, false)
                              AND NOT COALESCE((v_prev->>'is_pinned')::boolean, false)),
                         'O1 varsayılan: sabitlenenler önce');
    END IF;
    v_prev := v_row;
  END LOOP;

  v_page := pg_temp.page(NULL, NULL, 'name', 100, 0);
  v_prev := NULL;
  FOR v_row IN SELECT e FROM jsonb_array_elements(v_page->'rows') WITH ORDINALITY AS t(e, ord) ORDER BY ord LOOP
    IF v_prev IS NOT NULL THEN
      PERFORM pg_temp.ok(lower(COALESCE(v_prev->>'name', '')) <= lower(COALESCE(v_row->>'name', '')),
                         'O2 isme göre artan');
    END IF;
    v_prev := v_row;
  END LOOP;

  v_page := pg_temp.page(NULL, NULL, 'earnings', 100, 0);
  v_prev := NULL;
  FOR v_row IN SELECT e FROM jsonb_array_elements(v_page->'rows') WITH ORDINALITY AS t(e, ord) ORDER BY ord LOOP
    IF v_prev IS NOT NULL THEN
      PERFORM pg_temp.ok((v_prev->>'total_earnings')::numeric >= (v_row->>'total_earnings')::numeric,
                         'O3 kazanca göre azalan');
    END IF;
    v_prev := v_row;
  END LOOP;

  v_page := pg_temp.page(NULL, NULL, 'orders', 100, 0);
  v_prev := NULL;
  FOR v_row IN SELECT e FROM jsonb_array_elements(v_page->'rows') WITH ORDINALITY AS t(e, ord) ORDER BY ord LOOP
    IF v_prev IS NOT NULL THEN
      PERFORM pg_temp.ok((v_prev->>'total_orders')::bigint >= (v_row->>'total_orders')::bigint,
                         'O4 siparişe göre azalan');
    END IF;
    v_prev := v_row;
  END LOOP;

  v_page := pg_temp.page(NULL, NULL, 'newest', 100, 0);
  v_prev := NULL;
  FOR v_row IN SELECT e FROM jsonb_array_elements(v_page->'rows') WITH ORDINALITY AS t(e, ord) ORDER BY ord LOOP
    IF v_prev IS NOT NULL AND v_row->>'created_at' IS NOT NULL THEN
      PERFORM pg_temp.ok(v_prev->>'created_at' IS NOT NULL
                         AND (v_prev->>'created_at')::timestamptz >= (v_row->>'created_at')::timestamptz,
                         'O5 en yeni önce');
    END IF;
    v_prev := v_row;
  END LOOP;

  -- ------------------------------------------------------------------- süre
  v_clock := clock_timestamp();
  FOR i IN 1..5 LOOP
    PERFORM pg_temp.page(NULL, NULL, 'default', 20, 0);
  END LOOP;
  v_ms := round((extract(epoch FROM clock_timestamp() - v_clock) * 1000 / 5)::numeric, 1);
  EXECUTE 'RESET ROLE';

  RAISE EXCEPTION 'TESTS_PASSED checks=% shops=% perf_ms=%',
    current_setting('t.n', true), v_shop_count, v_ms;
END
$test$;
