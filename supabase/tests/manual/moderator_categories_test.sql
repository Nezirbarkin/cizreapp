-- Moderatör kategorileri canlı doğrulaması (kendini geri alır).
--
-- Çalıştırma: supabase db query --linked --file supabase/tests/manual/moderator_categories_test.sql
-- Başarı = 'TESTS_PASSED ...' istisnası; testin yazdığı her şey geri alınır.
DO $test$
DECLARE
  v_admin uuid; v_mod uuid; v_plain uuid;
  v_cat_a uuid; v_cat_b uuid; v_cat_a_name text; v_cat_empty uuid;
  v_ilan_a uuid; v_ilan_b uuid;
  v_shop_x uuid; v_shop_y uuid; v_owner_x uuid; v_owner_y uuid;
  v_cat_x uuid; v_cat_y uuid; v_cat_x_name text; v_shop_cat_empty uuid;
  v_sess_x uuid; v_sess_y uuid;
  v_json jsonb;
  v_hint text; v_state text;
  v_count integer;
  v_checks integer := 0;
BEGIN
  SELECT id INTO v_admin FROM public.profiles WHERE role::text = 'admin' ORDER BY created_at LIMIT 1;
  SELECT p.id INTO v_mod FROM public.profiles p
   WHERE p.role::text <> 'admin' AND NOT COALESCE(p.is_admin, false) AND NOT COALESCE(p.is_bot, false)
     AND p.status::text = 'active'
     AND NOT EXISTS (SELECT 1 FROM auth.users a WHERE a.id = p.id AND a.is_anonymous)
   ORDER BY p.created_at LIMIT 1;
  SELECT p.id INTO v_plain FROM public.profiles p
   WHERE p.role::text <> 'admin' AND NOT COALESCE(p.is_admin, false) AND NOT COALESCE(p.is_bot, false)
     AND p.status::text = 'active' AND p.id <> v_mod
     AND NOT EXISTS (SELECT 1 FROM public.moderators m WHERE m.user_id = p.id)
   ORDER BY p.created_at LIMIT 1;

  -- İki ayrı ilan kategorisinden birer ilan; onay bekler hâle getirilir (3.9 sistem yolu)
  SELECT i.category_id, i.id INTO v_cat_a, v_ilan_a
    FROM public.ilanlar i
   ORDER BY (SELECT count(*) FROM public.ilanlar j WHERE j.category_id = i.category_id) DESC, i.created_at, i.id
   LIMIT 1;
  SELECT i.category_id, i.id INTO v_cat_b, v_ilan_b
    FROM public.ilanlar i WHERE i.category_id <> v_cat_a ORDER BY i.created_at, i.id LIMIT 1;
  SELECT name INTO v_cat_a_name FROM public.ilan_categories WHERE id = v_cat_a;

  -- İki ayrı kategoriden birer aktif mağaza, ikisinde de canlı yayın
  SELECT s.id, s.owner_id, s.category_id INTO v_shop_x, v_owner_x, v_cat_x
    FROM public.shops s
   WHERE COALESCE(s.is_active, false) AND COALESCE(s.is_approved, false) AND s.category_id IS NOT NULL
   ORDER BY s.created_at LIMIT 1;
  SELECT s.id, s.owner_id, s.category_id INTO v_shop_y, v_owner_y, v_cat_y
    FROM public.shops s
   WHERE COALESCE(s.is_active, false) AND COALESCE(s.is_approved, false) AND s.category_id IS NOT NULL
     AND s.category_id <> v_cat_x
   ORDER BY s.created_at LIMIT 1;
  SELECT name INTO v_cat_x_name FROM public.categories WHERE id = v_cat_x;

  IF v_admin IS NULL OR v_mod IS NULL OR v_plain IS NULL OR v_ilan_a IS NULL OR v_ilan_b IS NULL
     OR v_shop_x IS NULL OR v_shop_y IS NULL THEN
    RAISE EXCEPTION 'test verisi yok';
  END IF;

  DELETE FROM public.moderators WHERE user_id = v_mod;
  PERFORM set_config('cizre.ilan_system_write', 'on', true);
  UPDATE public.ilanlar SET status = 'pending' WHERE id IN (v_ilan_a, v_ilan_b);
  PERFORM set_config('cizre.ilan_system_write', 'off', true);
  UPDATE public.app_settings SET value = '"true"'::jsonb WHERE key = 'live_stream_enabled';
  DELETE FROM public.live_sessions WHERE shop_id IN (v_shop_x, v_shop_y) AND status IN ('scheduled', 'live');
  INSERT INTO public.live_sessions (host_user_id, shop_id, title, channel_name, status, started_at, last_heartbeat_at)
  VALUES (v_owner_x, v_shop_x, 'Kategori X yayını', 'cz_test_' || replace(gen_random_uuid()::text, '-', ''), 'live', now(), now())
  RETURNING id INTO v_sess_x;
  INSERT INTO public.live_sessions (host_user_id, shop_id, title, channel_name, status, started_at, last_heartbeat_at)
  VALUES (v_owner_y, v_shop_y, 'Kategori Y yayını', 'cz_test_' || replace(gen_random_uuid()::text, '-', ''), 'live', now(), now())
  RETURNING id INTO v_sess_y;

  -- [1] yönetici kapsam + kategori atar; satır, dönüş ve bildirimde kategori adları
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  v_json := public.admin_set_moderator(v_mod, ARRAY['live', 'ilanlar'], 'Bölge sorumlusu',
                                       ARRAY[v_cat_a, v_cat_a], ARRAY[v_cat_x]);
  EXECUTE 'RESET ROLE';
  IF v_json -> 'ilan_category_ids' <> to_jsonb(ARRAY[v_cat_a]) OR v_json -> 'shop_category_ids' <> to_jsonb(ARRAY[v_cat_x])
     OR NOT EXISTS (SELECT 1 FROM public.moderators
                     WHERE user_id = v_mod AND ilan_category_ids = ARRAY[v_cat_a] AND shop_category_ids = ARRAY[v_cat_x]
                       AND scopes = ARRAY['ilanlar', 'live'])
     OR NOT EXISTS (SELECT 1 FROM public.notifications
                     WHERE user_id = v_mod AND type = 'admin_notification' AND title = 'Moderatör oldun'
                       AND content LIKE '%' || v_cat_a_name || '%' AND content LIKE '%' || v_cat_x_name || '%') THEN
    RAISE EXCEPTION '[1] atama: %', v_json;
  END IF;
  v_checks := v_checks + 1;

  -- [2] eski uygulamanın 3 parametreli (adlı) çağrısı kategorileri SIFIRLAMAZ;
  --     eski imza kaldırıldı
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  v_json := public.admin_set_moderator(p_user_id => v_mod, p_scopes => ARRAY['ilanlar', 'live'], p_note => 'Not güncellendi');
  EXECUTE 'RESET ROLE';
  IF NOT EXISTS (SELECT 1 FROM public.moderators
                  WHERE user_id = v_mod AND ilan_category_ids = ARRAY[v_cat_a] AND shop_category_ids = ARRAY[v_cat_x]
                    AND note = 'Not güncellendi')
     OR to_regprocedure('public.admin_set_moderator(uuid, text[], text)') IS NOT NULL THEN
    RAISE EXCEPTION '[2] eski çağrı: %', v_json;
  END IF;
  v_checks := v_checks + 1;

  -- [3] moderatör kendi kategorilerini adlarıyla görür; yönetici listesinde de var
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_mod, 'role', 'authenticated')::text, true);
  v_json := public.my_moderation();
  EXECUTE 'RESET ROLE';
  IF v_json -> 'ilan_categories' <> jsonb_build_array(jsonb_build_object('id', v_cat_a, 'name', v_cat_a_name))
     OR v_json -> 'shop_categories' <> jsonb_build_array(jsonb_build_object('id', v_cat_x, 'name', v_cat_x_name))
     OR (v_json ->> 'is_admin')::boolean OR NOT (v_json -> 'scopes' ? 'ilanlar') THEN
    RAISE EXCEPTION '[3] my_moderation: %', v_json;
  END IF;
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  v_json := public.admin_moderators_list();
  EXECUTE 'RESET ROLE';
  IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_json) e
                  WHERE (e ->> 'user_id')::uuid = v_mod
                    AND e -> 'ilan_categories' -> 0 ->> 'id' = v_cat_a::text
                    AND e -> 'shop_categories' -> 0 ->> 'id' = v_cat_x::text) THEN
    RAISE EXCEPTION '[3] yönetici listesi: %', v_json;
  END IF;
  v_checks := v_checks + 1;

  -- [4] onay bekleyen ilanlar: moderatör yalnız kendi kategorisini (sayı da); yönetici hepsini
  SELECT count(*) INTO v_count FROM public.ilanlar WHERE status = 'pending' AND category_id = v_cat_a;
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_mod, 'role', 'authenticated')::text, true);
  v_json := public.mod_pending_ilanlar(100, 0);
  EXECUTE 'RESET ROLE';
  IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_json -> 'rows') e
                  WHERE (e ->> 'id')::uuid = v_ilan_a AND (e ->> 'category_id')::uuid = v_cat_a)
     OR EXISTS (SELECT 1 FROM jsonb_array_elements(v_json -> 'rows') e WHERE (e ->> 'category_id')::uuid <> v_cat_a)
     OR (v_json ->> 'total')::int <> v_count THEN
    RAISE EXCEPTION '[4] moderatör ilan listesi: % (beklenen %)', v_json, v_count;
  END IF;
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  v_json := public.mod_pending_ilanlar(100, 0);
  EXECUTE 'RESET ROLE';
  IF (SELECT count(*) FROM jsonb_array_elements(v_json -> 'rows') e
       WHERE (e ->> 'id')::uuid IN (v_ilan_a, v_ilan_b)) <> 2 THEN
    RAISE EXCEPTION '[4] yönetici ilan listesi: %', v_json;
  END IF;
  v_checks := v_checks + 1;

  -- [5] kategori dışı ilan karara bağlanamaz; kendi kategorisindeki onaylanır
  v_hint := NULL; v_state := NULL;
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_mod, 'role', 'authenticated')::text, true);
    PERFORM public.mod_review_ilan(v_ilan_b, true, NULL);
    RAISE EXCEPTION 'geçti';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_hint = PG_EXCEPTION_HINT, v_state = RETURNED_SQLSTATE;
  END;
  IF v_hint IS DISTINCT FROM 'MOD_CATEGORY_FORBIDDEN' OR v_state IS DISTINCT FROM '42501'
     OR (SELECT status FROM public.ilanlar WHERE id = v_ilan_b) <> 'pending' THEN
    RAISE EXCEPTION '[5] kategori dışı ilan: % %', v_hint, v_state;
  END IF;
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_mod, 'role', 'authenticated')::text, true);
  v_json := public.mod_review_ilan(v_ilan_a, true, NULL);
  EXECUTE 'RESET ROLE';
  IF v_json ->> 'status' <> 'published'
     OR NOT EXISTS (SELECT 1 FROM public.ilanlar WHERE id = v_ilan_a AND status = 'published' AND moderated_by = v_mod) THEN
    RAISE EXCEPTION '[5] onay: %', v_json;
  END IF;
  v_checks := v_checks + 1;

  -- [6] canlı yayın listesi ve özet: moderatör yalnız kendi mağaza kategorisini görür
  SELECT count(*) INTO v_count
    FROM public.live_sessions ls JOIN public.shops s ON s.id = ls.shop_id
   WHERE ls.status = 'live' AND ls.last_heartbeat_at > now() - interval '2 minutes' AND s.category_id = v_cat_x;
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_mod, 'role', 'authenticated')::text, true);
  v_json := public.admin_live_sessions('live', 100, 0);
  EXECUTE 'RESET ROLE';
  IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_json -> 'rows') e WHERE (e ->> 'id')::uuid = v_sess_x)
     OR EXISTS (SELECT 1 FROM jsonb_array_elements(v_json -> 'rows') e WHERE (e ->> 'id')::uuid = v_sess_y)
     OR (v_json -> 'summary' ->> 'live_now')::int <> v_count
     OR (v_json ->> 'total')::int <> v_count THEN
    RAISE EXCEPTION '[6] moderatör yayın listesi: % (beklenen %)', v_json, v_count;
  END IF;
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  v_json := public.admin_live_sessions('live', 100, 0);
  EXECUTE 'RESET ROLE';
  IF (SELECT count(*) FROM jsonb_array_elements(v_json -> 'rows') e
       WHERE (e ->> 'id')::uuid IN (v_sess_x, v_sess_y)) <> 2 THEN
    RAISE EXCEPTION '[6] yönetici yayın listesi: %', v_json;
  END IF;
  v_checks := v_checks + 1;

  -- [7] kategori dışı mağazanın yayını kapatılamaz; kendi kategorisindeki kapatılır
  v_hint := NULL; v_state := NULL;
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_mod, 'role', 'authenticated')::text, true);
    PERFORM public.admin_end_live_session(v_sess_y, 'dene');
    RAISE EXCEPTION 'geçti';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_hint = PG_EXCEPTION_HINT, v_state = RETURNED_SQLSTATE;
  END;
  IF v_hint IS DISTINCT FROM 'MOD_CATEGORY_FORBIDDEN' OR v_state IS DISTINCT FROM '42501'
     OR (SELECT status FROM public.live_sessions WHERE id = v_sess_y) <> 'live' THEN
    RAISE EXCEPTION '[7] kategori dışı yayın: % %', v_hint, v_state;
  END IF;
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_mod, 'role', 'authenticated')::text, true);
  PERFORM public.admin_end_live_session(v_sess_x, 'Kurallara aykırı');
  EXECUTE 'RESET ROLE';
  IF NOT EXISTS (SELECT 1 FROM public.live_sessions
                  WHERE id = v_sess_x AND status = 'ended' AND ended_reason = 'admin' AND ended_by = v_mod) THEN
    RAISE EXCEPTION '[7] kapatma';
  END IF;
  v_checks := v_checks + 1;

  -- [8] boş dizi = tüm kategoriler (NULL saklanır); artık diğer kategori de görünür
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  PERFORM public.admin_set_moderator(v_mod, ARRAY['ilanlar', 'live'], NULL, ARRAY[]::uuid[], ARRAY[]::uuid[]);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_mod, 'role', 'authenticated')::text, true);
  v_json := public.my_moderation();
  EXECUTE 'RESET ROLE';
  IF v_json -> 'ilan_categories' <> 'null'::jsonb OR v_json -> 'shop_categories' <> 'null'::jsonb
     OR NOT EXISTS (SELECT 1 FROM public.moderators
                     WHERE user_id = v_mod AND ilan_category_ids IS NULL AND shop_category_ids IS NULL) THEN
    RAISE EXCEPTION '[8] tümü: %', v_json;
  END IF;
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_mod, 'role', 'authenticated')::text, true);
  v_json := public.mod_pending_ilanlar(100, 0);
  EXECUTE 'RESET ROLE';
  IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_json -> 'rows') e WHERE (e ->> 'id')::uuid = v_ilan_b) THEN
    RAISE EXCEPTION '[8] tüm kategoriler görünmüyor: %', v_json;
  END IF;
  v_checks := v_checks + 1;

  -- [9] hiçbir kaydı olmayan kategoriler → boş liste ve sıfır özet
  SELECT c.id INTO v_cat_empty FROM public.ilan_categories c
   WHERE NOT EXISTS (SELECT 1 FROM public.ilanlar i WHERE i.category_id = c.id AND i.status = 'pending')
   ORDER BY c.id LIMIT 1;
  SELECT c.id INTO v_shop_cat_empty FROM public.categories c
   WHERE NOT EXISTS (SELECT 1 FROM public.live_sessions ls JOIN public.shops s ON s.id = ls.shop_id
                      WHERE s.category_id = c.id AND ls.status IN ('live', 'scheduled'))
   ORDER BY c.id LIMIT 1;
  IF v_cat_empty IS NULL OR v_shop_cat_empty IS NULL THEN RAISE EXCEPTION '[9] boş kategori yok'; END IF;
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  PERFORM public.admin_set_moderator(v_mod, ARRAY['ilanlar', 'live'], NULL, ARRAY[v_cat_empty], ARRAY[v_shop_cat_empty]);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_mod, 'role', 'authenticated')::text, true);
  v_json := public.mod_pending_ilanlar(100, 0);
  IF (v_json ->> 'total')::int <> 0 OR jsonb_array_length(v_json -> 'rows') <> 0 THEN
    RAISE EXCEPTION '[9] boş ilan kategorisi: %', v_json;
  END IF;
  v_json := public.admin_live_sessions('live', 100, 0);
  EXECUTE 'RESET ROLE';
  IF (v_json ->> 'total')::int <> 0 OR (v_json -> 'summary' ->> 'live_now')::int <> 0
     OR (v_json -> 'summary' ->> 'preparing')::int <> 0 THEN
    RAISE EXCEPTION '[9] boş mağaza kategorisi: %', v_json;
  END IF;
  v_checks := v_checks + 1;

  -- [10] kapsam kalkınca o kapsamın sınırı silinir; geçersiz kategori reddedilir
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  v_json := public.admin_set_moderator(v_mod, ARRAY['ilanlar'], NULL, NULL, ARRAY[v_cat_x]);
  EXECUTE 'RESET ROLE';
  IF NOT EXISTS (SELECT 1 FROM public.moderators
                  WHERE user_id = v_mod AND scopes = ARRAY['ilanlar'] AND shop_category_ids IS NULL
                    AND ilan_category_ids = ARRAY[v_cat_empty])
     OR v_json -> 'shop_category_ids' <> 'null'::jsonb THEN
    RAISE EXCEPTION '[10] kapsam kalkınca: %', v_json;
  END IF;
  v_hint := NULL;
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
    PERFORM public.admin_set_moderator(v_mod, ARRAY['ilanlar'], NULL, ARRAY[gen_random_uuid()], NULL);
    RAISE EXCEPTION 'geçti';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_hint = PG_EXCEPTION_HINT;
  END;
  IF v_hint IS DISTINCT FROM 'MOD_CATEGORY_INVALID' THEN RAISE EXCEPTION '[10] geçersiz ilan kategorisi: %', v_hint; END IF;
  v_hint := NULL;
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
    -- ilan kategorisi mağaza kategorisi yerine verilemez
    PERFORM public.admin_set_moderator(v_mod, ARRAY['live'], NULL, NULL, ARRAY[v_cat_a]);
    RAISE EXCEPTION 'geçti';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_hint = PG_EXCEPTION_HINT;
  END;
  IF v_hint IS DISTINCT FROM 'MOD_CATEGORY_INVALID' THEN RAISE EXCEPTION '[10] geçersiz mağaza kategorisi: %', v_hint; END IF;
  v_checks := v_checks + 1;

  -- [11] kategori seçenekleri yalnız yöneticiye; sıradan kullanıcı moderasyon RPC'si çağıramaz
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  v_json := public.admin_moderation_categories();
  EXECUTE 'RESET ROLE';
  IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_json -> 'ilan') e WHERE (e ->> 'id')::uuid = v_cat_a)
     OR NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_json -> 'shop') e WHERE (e ->> 'id')::uuid = v_cat_x)
     OR jsonb_array_length(v_json -> 'ilan') <> (SELECT count(*) FROM public.ilan_categories)
     OR jsonb_array_length(v_json -> 'shop') <> (SELECT count(*) FROM public.categories) THEN
    RAISE EXCEPTION '[11] seçenekler: %', v_json;
  END IF;
  v_state := NULL;
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_mod, 'role', 'authenticated')::text, true);
    PERFORM public.admin_moderation_categories();
    RAISE EXCEPTION 'geçti';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE;
  END;
  IF v_state IS DISTINCT FROM '42501' THEN RAISE EXCEPTION '[11] moderatör seçenekleri okudu: %', v_state; END IF;
  v_state := NULL;
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_plain, 'role', 'authenticated')::text, true);
    PERFORM public.mod_pending_ilanlar(10, 0);
    RAISE EXCEPTION 'geçti';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE;
  END;
  IF v_state IS DISTINCT FROM '42501' THEN RAISE EXCEPTION '[11] sıradan kullanıcı: %', v_state; END IF;
  v_checks := v_checks + 1;

  -- [12] yetkiler
  IF has_function_privilege('anon', 'public.admin_set_moderator(uuid, text[], text, uuid[], uuid[])', 'EXECUTE')
     OR has_function_privilege('anon', 'public.admin_moderation_categories()', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.admin_set_moderator(uuid, text[], text, uuid[], uuid[])', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.admin_moderation_categories()', 'EXECUTE')
     OR has_function_privilege('anon', 'public.my_moderation()', 'EXECUTE') THEN
    RAISE EXCEPTION '[12] yetkiler';
  END IF;
  v_checks := v_checks + 1;

  RAISE EXCEPTION 'TESTS_PASSED % kontrol', v_checks;
END
$test$;
