-- Görev 3.9 — ilan süresi hatırlatma + uzatma canlı doğrulaması (kendini geri alır).
--
-- Çalıştırma: supabase db query --linked --file supabase/tests/manual/ilan_expiry_reminders_test.sql
-- Başarı = 'TESTS_PASSED ...' istisnası; testin yazdığı her şey geri alınır.
DO $test$
DECLARE
  v_owner uuid;
  v_other uuid;
  v_a uuid;   -- süresi dün dolmuş (bildirim alır)
  v_b uuid;   -- 2 gün kaldı
  v_c uuid;   -- 10 saat kaldı
  v_d uuid;   -- 30 gün kaldı
  v_old uuid; -- 20 gün önce dolmuş (sessiz kapanır)
  v_json jsonb;
  v_hint text;
  v_n integer;
  v_exp timestamptz;
  v_checks integer := 0;
BEGIN
  -- Aynı sahibin en az 5 ilanı yoksa tek sahibin ilanlarını kullan; test
  -- ilanları mevcut satırlar üzerinde oynar ve geri alınır.
  SELECT owner_id INTO v_owner FROM public.ilanlar GROUP BY owner_id ORDER BY count(*) DESC LIMIT 1;
  SELECT id INTO v_other FROM public.profiles WHERE id <> v_owner ORDER BY created_at LIMIT 1;
  UPDATE public.ilan_settings SET is_enabled = true, max_active_per_user = 50, default_expiry_days = 60 WHERE id = 1;

  -- Test ilanları: sahibin ilk ilanını çoğalt (tetikleyiciyi atlamak için sistem işareti)
  PERFORM set_config('cizre.ilan_system_write', 'on', true);
  UPDATE public.ilanlar SET status = 'archived' WHERE owner_id = v_owner;  -- sahibin diğer ilanları sınırı etkilemesin
  PERFORM set_config('cizre.ilan_system_write', 'off', true);

  -- Sahibin rolüyle ekle (gerçek yol: doğrulayıcı tetikleyici çalışır; süre korunur)
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
  INSERT INTO public.ilanlar (owner_id, category_id, title, description, item_condition, price, currency, attributes, city, district, neighborhood, contact_preference, contact_phone, latitude, longitude, published_at, expires_at)
  SELECT v_owner, category_id, 'Test ilanı A', description, item_condition, price, currency, attributes, city, district, neighborhood, contact_preference, contact_phone, latitude, longitude, now() - interval '61 days', now() - interval '1 day'
    FROM public.ilanlar WHERE owner_id = v_owner ORDER BY created_at LIMIT 1 RETURNING id INTO v_a;
  INSERT INTO public.ilanlar (owner_id, category_id, title, description, item_condition, price, currency, attributes, city, district, neighborhood, contact_preference, contact_phone, latitude, longitude, published_at, expires_at)
  SELECT v_owner, category_id, 'Test ilanı B', description, item_condition, price, currency, attributes, city, district, neighborhood, contact_preference, contact_phone, latitude, longitude, now() - interval '58 days', now() + interval '2 days'
    FROM public.ilanlar WHERE owner_id = v_owner ORDER BY created_at LIMIT 1 RETURNING id INTO v_b;
  INSERT INTO public.ilanlar (owner_id, category_id, title, description, item_condition, price, currency, attributes, city, district, neighborhood, contact_preference, contact_phone, latitude, longitude, published_at, expires_at)
  SELECT v_owner, category_id, 'Test ilanı C', description, item_condition, price, currency, attributes, city, district, neighborhood, contact_preference, contact_phone, latitude, longitude, now() - interval '59 days', now() + interval '10 hours'
    FROM public.ilanlar WHERE owner_id = v_owner ORDER BY created_at LIMIT 1 RETURNING id INTO v_c;
  INSERT INTO public.ilanlar (owner_id, category_id, title, description, item_condition, price, currency, attributes, city, district, neighborhood, contact_preference, contact_phone, latitude, longitude, published_at, expires_at)
  SELECT v_owner, category_id, 'Test ilanı D', description, item_condition, price, currency, attributes, city, district, neighborhood, contact_preference, contact_phone, latitude, longitude, now() - interval '30 days', now() + interval '30 days'
    FROM public.ilanlar WHERE owner_id = v_owner ORDER BY created_at LIMIT 1 RETURNING id INTO v_d;
  INSERT INTO public.ilanlar (owner_id, category_id, title, description, item_condition, price, currency, attributes, city, district, neighborhood, contact_preference, contact_phone, latitude, longitude, published_at, expires_at)
  SELECT v_owner, category_id, 'Test ilanı eski', description, item_condition, price, currency, attributes, city, district, neighborhood, contact_preference, contact_phone, latitude, longitude, now() - interval '80 days', now() - interval '20 days'
    FROM public.ilanlar WHERE owner_id = v_owner ORDER BY created_at LIMIT 1 RETURNING id INTO v_old;
  EXECUTE 'RESET ROLE';
  DELETE FROM public.notifications WHERE user_id = v_owner AND type IN ('ilan_expiring', 'ilan_expired');

  -- [1] yapı
  IF has_table_privilege('authenticated', 'public.ilan_expiry_notices', 'SELECT')
     OR has_function_privilege('authenticated', 'public.expire_stale_ilanlar()', 'EXECUTE')
     OR has_function_privilege('anon', 'public.extend_my_ilan(uuid)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.extend_my_ilan(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION '[1] yetkiler yanlış';
  END IF;
  v_checks := v_checks + 1;

  -- [2] HATA DÜZELTMESİ: cron (oturumsuz) artık düşmüyor; dolanlar 'expired'
  PERFORM public.expire_stale_ilanlar();
  IF (SELECT status FROM public.ilanlar WHERE id = v_a) <> 'expired'
     OR (SELECT status FROM public.ilanlar WHERE id = v_old) <> 'expired' THEN
    RAISE EXCEPTION '[2] süresi dolan kapanmadı';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.notifications WHERE user_id = v_owner AND type = 'ilan_expired' AND entity_id = v_a::text
                    AND entity_type = 'ilan' AND data ->> 'stage' = 'expired') THEN
    RAISE EXCEPTION '[2] süresi doldu bildirimi yok';
  END IF;
  IF EXISTS (SELECT 1 FROM public.notifications WHERE type = 'ilan_expired' AND entity_id = v_old::text) THEN
    RAISE EXCEPTION '[2] haftalar önce dolan ilana bildirim gitti';
  END IF;
  v_checks := v_checks + 1;

  -- [3] hatırlatmalar: 2 gün → '3d', 10 saat → '1d'; 30 gün → yok; tekrar çalışınca yinelenmez
  IF NOT EXISTS (SELECT 1 FROM public.notifications WHERE type = 'ilan_expiring' AND entity_id = v_b::text AND data ->> 'stage' = '3d')
     OR NOT EXISTS (SELECT 1 FROM public.notifications WHERE type = 'ilan_expiring' AND entity_id = v_c::text AND data ->> 'stage' = '1d')
     OR EXISTS (SELECT 1 FROM public.notifications WHERE entity_id = v_d::text AND type LIKE 'ilan_%') THEN
    RAISE EXCEPTION '[3] hatırlatma aşamaları yanlış';
  END IF;
  PERFORM public.expire_stale_ilanlar();
  SELECT count(*) INTO v_n FROM public.notifications
   WHERE user_id = v_owner AND type IN ('ilan_expiring', 'ilan_expired') AND entity_id IN (v_a::text, v_b::text, v_c::text);
  IF v_n <> 3 THEN RAISE EXCEPTION '[3] bildirimler yinelendi: %', v_n; END IF;
  v_checks := v_checks + 1;

  -- [4] uzatma: süresi dolanı yeniden yayınlar; eski bildirimler silinir
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
  v_json := public.extend_my_ilan(v_a);
  EXECUTE 'RESET ROLE';
  SELECT expires_at INTO v_exp FROM public.ilanlar WHERE id = v_a;
  IF (SELECT status FROM public.ilanlar WHERE id = v_a) <> 'published'
     OR NOT (v_json ->> 'republished')::boolean
     OR abs(extract(epoch FROM (v_exp - (now() + interval '60 days')))) > 60 THEN
    RAISE EXCEPTION '[4] yeniden yayın: % %', v_json, v_exp;
  END IF;
  IF EXISTS (SELECT 1 FROM public.notifications WHERE entity_id = v_a::text AND type LIKE 'ilan_%') THEN
    RAISE EXCEPTION '[4] eski bildirim kalmış';
  END IF;
  -- yaklaşan ilan: mevcut bitişin üstüne 60 gün
  SELECT expires_at INTO v_exp FROM public.ilanlar WHERE id = v_b;
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
  v_json := public.extend_my_ilan(v_b);
  EXECUTE 'RESET ROLE';
  IF (SELECT expires_at FROM public.ilanlar WHERE id = v_b) <> v_exp + interval '60 days' OR (v_json ->> 'republished')::boolean THEN
    RAISE EXCEPTION '[4] uzatma: %', v_json;
  END IF;
  v_checks := v_checks + 1;

  -- [5] retler: erken, başkası, uzatılamaz durum, etkin ilan sınırı
  v_hint := NULL;
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
    PERFORM public.extend_my_ilan(v_d);
    RAISE EXCEPTION 'geçti';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_hint = PG_EXCEPTION_HINT;
  END;
  IF v_hint IS DISTINCT FROM 'ILAN_TOO_EARLY' THEN RAISE EXCEPTION '[5] erken: %', v_hint; END IF;
  v_hint := NULL;
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_other, 'role', 'authenticated')::text, true);
    PERFORM public.extend_my_ilan(v_c);
    RAISE EXCEPTION 'geçti';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_hint = PG_EXCEPTION_HINT;
  END;
  IF v_hint IS DISTINCT FROM 'ILAN_NOT_FOUND' THEN RAISE EXCEPTION '[5] başkası: %', v_hint; END IF;
  PERFORM set_config('cizre.ilan_system_write', 'on', true);
  UPDATE public.ilanlar SET status = 'sold' WHERE id = v_c;
  PERFORM set_config('cizre.ilan_system_write', 'off', true);
  v_hint := NULL;
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
    PERFORM public.extend_my_ilan(v_c);
    RAISE EXCEPTION 'geçti';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_hint = PG_EXCEPTION_HINT;
  END;
  IF v_hint IS DISTINCT FROM 'ILAN_NOT_EXTENDABLE' THEN RAISE EXCEPTION '[5] satıldı: %', v_hint; END IF;
  UPDATE public.ilan_settings SET max_active_per_user = 3 WHERE id = 1;  -- A, B, D etkin
  v_hint := NULL;
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
    PERFORM public.extend_my_ilan(v_old);
    RAISE EXCEPTION 'geçti';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_hint = PG_EXCEPTION_HINT;
  END;
  IF v_hint IS DISTINCT FROM 'ILAN_ACTIVE_LIMIT' THEN RAISE EXCEPTION '[5] sınır: %', v_hint; END IF;
  v_checks := v_checks + 1;

  -- [6] sahibi durumu elle 'published'a çeviremez (uzatma yalnız RPC'den)
  PERFORM set_config('cizre.ilan_system_write', 'off', true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
  UPDATE public.ilanlar SET status = 'published' WHERE id = v_old;
  EXECUTE 'RESET ROLE';
  IF (SELECT status FROM public.ilanlar WHERE id = v_old) <> 'expired' THEN
    RAISE EXCEPTION '[6] sahibi süresi dolanı elle yayına aldı';
  END IF;
  v_checks := v_checks + 1;

  RAISE EXCEPTION 'TESTS_PASSED % kontrol', v_checks;
END
$test$;
