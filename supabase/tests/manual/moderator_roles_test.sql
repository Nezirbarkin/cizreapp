-- Görev 4.6 — moderatör rolü ve RLS altyapısı canlı doğrulaması (kendini geri alır).
--
-- Çalıştırma: supabase db query --linked --file supabase/tests/manual/moderator_roles_test.sql
-- Başarı = 'TESTS_PASSED ...' istisnası; testin yazdığı her şey geri alınır.
DO $test$
DECLARE
  v_admin uuid; v_mod uuid; v_reporter uuid; v_other uuid; v_author uuid;
  v_post uuid; v_post_report uuid; v_user_report uuid;
  v_ilan_owner uuid; v_ilan_a uuid; v_ilan_b uuid;
  v_json jsonb;
  v_state text; v_hint text;
  v_n integer;
  v_row record;
  v_checks integer := 0;
BEGIN
  SELECT id INTO v_admin FROM public.profiles WHERE role::text = 'admin' ORDER BY created_at LIMIT 1;
  -- Moderatör adayı: normal, aktif, bot/misafir değil
  SELECT p.id INTO v_mod FROM public.profiles p
   WHERE p.role::text <> 'admin' AND NOT COALESCE(p.is_admin, false) AND NOT COALESCE(p.is_bot, false)
     AND p.status::text = 'active'
     AND NOT EXISTS (SELECT 1 FROM auth.users a WHERE a.id = p.id AND a.is_anonymous)
   ORDER BY p.created_at LIMIT 1;
  SELECT x.id, x.user_id INTO v_post, v_author FROM public.posts x
   WHERE x.is_active IS NOT FALSE AND x.user_id <> v_mod ORDER BY x.created_at DESC LIMIT 1;
  SELECT p.id INTO v_reporter FROM public.profiles p
   WHERE p.id NOT IN (v_mod, v_author) AND p.role::text <> 'admin' AND NOT COALESCE(p.is_bot, false)
     AND NOT EXISTS (SELECT 1 FROM auth.users a WHERE a.id = p.id AND a.is_anonymous)
   ORDER BY p.created_at LIMIT 1;
  SELECT p.id INTO v_other FROM public.profiles p
   WHERE p.id NOT IN (v_mod, v_author, v_reporter) AND p.role::text <> 'admin' AND NOT COALESCE(p.is_bot, false)
     AND NOT EXISTS (SELECT 1 FROM auth.users a WHERE a.id = p.id AND a.is_anonymous)
   ORDER BY p.created_at LIMIT 1;
  IF v_admin IS NULL OR v_mod IS NULL OR v_post IS NULL OR v_reporter IS NULL OR v_other IS NULL THEN
    RAISE EXCEPTION 'test verisi yok';
  END IF;
  DELETE FROM public.moderators WHERE user_id = v_mod;

  -- Test şikayetleri (şikayet edenin rolüyle, gerçek yol)
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_reporter, 'role', 'authenticated')::text, true);
  INSERT INTO public.post_reports (reporter_id, reported_post_id, reason, description)
  VALUES (v_reporter, v_post, 'spam', 'Test gönderi şikayeti') RETURNING id INTO v_post_report;
  INSERT INTO public.user_reports (reporter_id, reported_user_id, reason, description)
  VALUES (v_reporter, v_author, 'harassment', 'Test kullanıcı şikayeti') RETURNING id INTO v_user_report;
  EXECUTE 'RESET ROLE';

  -- [1] yönetici olmayan moderatör atayamaz; moderatör olmayan moderasyon RPC'si çağıramaz
  v_state := NULL;
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_mod, 'role', 'authenticated')::text, true);
    PERFORM public.admin_set_moderator(v_mod, ARRAY['reports'], NULL);
    RAISE EXCEPTION 'geçti';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE;
  END;
  IF v_state IS DISTINCT FROM '42501' THEN RAISE EXCEPTION '[1] kendine moderatörlük: %', v_state; END IF;
  v_state := NULL;
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_mod, 'role', 'authenticated')::text, true);
    PERFORM public.mod_reports('open', 10, 0);
    RAISE EXCEPTION 'geçti';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE;
  END;
  IF v_state IS DISTINCT FROM '42501' THEN RAISE EXCEPTION '[1] yetkisiz şikayet listesi: %', v_state; END IF;
  v_checks := v_checks + 1;

  -- [2] şikayet açıkları kapandı: başkası/anonim göremez, şikayet eden kendisininkini görür
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_other, 'role', 'authenticated')::text, true);
  SELECT (SELECT count(*) FROM public.user_reports WHERE id = v_user_report)
         + (SELECT count(*) FROM public.post_reports WHERE id = v_post_report) INTO v_n;
  EXECUTE 'RESET ROLE';
  IF v_n <> 0 THEN RAISE EXCEPTION '[2] başka kullanıcı şikayetleri gördü (%)', v_n; END IF;
  EXECUTE 'SET LOCAL ROLE anon';
  PERFORM set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
  SELECT count(*) INTO v_n FROM public.post_reports WHERE id = v_post_report;
  EXECUTE 'RESET ROLE';
  IF v_n <> 0 THEN RAISE EXCEPTION '[2] anonim gönderi şikayetini gördü'; END IF;
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_reporter, 'role', 'authenticated')::text, true);
  SELECT (SELECT count(*) FROM public.user_reports WHERE id = v_user_report)
         + (SELECT count(*) FROM public.post_reports WHERE id = v_post_report) INTO v_n;
  EXECUTE 'RESET ROLE';
  IF v_n <> 2 THEN RAISE EXCEPTION '[2] şikayet eden kendi kaydını göremedi (%)', v_n; END IF;
  v_checks := v_checks + 1;

  -- [3] yönetici atar: satır, denetim, bildirim; kişi kendi kapsamını görür
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  v_json := public.admin_set_moderator(v_mod, ARRAY['reports', 'content', 'reports'], 'Topluluk moderatörü');
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_mod, 'role', 'authenticated')::text, true);
  v_row := NULL;
  SELECT public.my_moderation() AS m, public.auth_is_moderator('reports') AS r,
         public.auth_is_moderator('ilanlar') AS i INTO v_row;
  EXECUTE 'RESET ROLE';
  IF v_json -> 'scopes' <> '["content", "reports"]'::jsonb
     OR (v_row.m -> 'scopes') <> '["content", "reports"]'::jsonb OR (v_row.m ->> 'is_admin')::boolean
     OR NOT v_row.r OR v_row.i
     OR NOT EXISTS (SELECT 1 FROM public.admin_audit_log WHERE action = 'set_moderator' AND target_id = v_mod::text)
     OR NOT EXISTS (SELECT 1 FROM public.notifications WHERE user_id = v_mod AND title = 'Moderatör oldun'
                     AND content LIKE '%İçerik, Şikayetler%') THEN
    RAISE EXCEPTION '[3] atama: % / %', v_json, v_row;
  END IF;
  v_checks := v_checks + 1;

  -- [4] moderatör şikayetleri görür (tablo + RPC)
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_mod, 'role', 'authenticated')::text, true);
  SELECT (SELECT count(*) FROM public.user_reports WHERE id = v_user_report)
         + (SELECT count(*) FROM public.post_reports WHERE id = v_post_report) INTO v_n;
  v_json := public.mod_reports('open', 100, 0);
  EXECUTE 'RESET ROLE';
  IF v_n <> 2
     OR NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_json -> 'rows') e
                     WHERE (e ->> 'id')::uuid = v_post_report AND e ->> 'kind' = 'post'
                       AND (e -> 'post' ->> 'id')::uuid = v_post AND e -> 'reporter' ->> 'id' = v_reporter::text)
     OR NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_json -> 'rows') e
                     WHERE (e ->> 'id')::uuid = v_user_report AND e ->> 'kind' = 'user'
                       AND (e -> 'user' ->> 'id')::uuid = v_author)
     OR (v_json -> 'counts' ->> 'open')::int < 2 THEN
    RAISE EXCEPTION '[4] moderatör şikayetleri: % / %', v_n, v_json;
  END IF;
  v_checks := v_checks + 1;

  -- [5] şikayeti sonuçlandır + gönderiyi gizle: yazara ve şikayet edene bildirim;
  --     gizli gönderiyi moderatör görür, başkası göremez
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_mod, 'role', 'authenticated')::text, true);
  v_json := public.mod_resolve_report('post', v_post_report, 'resolved', 'Spam içerik', true);
  SELECT count(*) INTO v_n FROM public.posts WHERE id = v_post;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_other, 'role', 'authenticated')::text, true);
  IF (SELECT count(*) FROM public.posts WHERE id = v_post) <> 0 THEN
    EXECUTE 'RESET ROLE';
    RAISE EXCEPTION '[5] gizli gönderi başkasına göründü';
  END IF;
  EXECUTE 'RESET ROLE';
  IF NOT (v_json ->> 'hidden_post')::boolean OR v_n <> 1
     OR (SELECT is_active FROM public.posts WHERE id = v_post) IS NOT FALSE
     OR (SELECT status FROM public.post_reports WHERE id = v_post_report) <> 'resolved'
     OR NOT EXISTS (SELECT 1 FROM public.notifications WHERE user_id = v_author AND entity_id = v_post::text
                     AND title = 'Gönderin gizlendi' AND content LIKE '%Spam içerik%')
     OR NOT EXISTS (SELECT 1 FROM public.notifications WHERE user_id = v_reporter AND entity_id = v_post_report::text
                     AND title = 'Şikayetin sonuçlandı')
     OR NOT EXISTS (SELECT 1 FROM public.admin_audit_log WHERE admin_id = v_mod AND action = 'mod_hide_post'
                     AND target_id = v_post::text) THEN
    RAISE EXCEPTION '[5] sonuçlandırma: % (moderatör gördü %)', v_json, v_n;
  END IF;
  v_checks := v_checks + 1;

  -- [6] gizlenenler listesinde; geri açılır. Kullanıcı şikayeti reddedilir.
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_mod, 'role', 'authenticated')::text, true);
  v_json := public.mod_posts('hidden', NULL, 100, 0);
  IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_json -> 'rows') e WHERE (e ->> 'id')::uuid = v_post) THEN
    EXECUTE 'RESET ROLE';
    RAISE EXCEPTION '[6] gizlenenlerde yok: %', v_json;
  END IF;
  v_json := public.mod_set_post_active(v_post, true, NULL);
  PERFORM public.mod_resolve_report('user', v_user_report, 'rejected', NULL, false);
  EXECUTE 'RESET ROLE';
  IF NOT (v_json ->> 'changed')::boolean OR (SELECT is_active FROM public.posts WHERE id = v_post) IS NOT TRUE
     OR (SELECT status FROM public.user_reports WHERE id = v_user_report) <> 'rejected'
     OR (SELECT admin_id FROM public.user_reports WHERE id = v_user_report) <> v_mod THEN
    RAISE EXCEPTION '[6] geri açma/ret: %', v_json;
  END IF;
  v_checks := v_checks + 1;

  -- [7] ilanlar: kapsam yokken reddedilir; verilince onay/ret yönetici dalından geçer
  UPDATE public.ilan_settings SET is_enabled = true, require_approval = true, max_active_per_user = 50 WHERE id = 1;
  UPDATE public.ilan_categories SET publish_fee = 0;
  SELECT owner_id INTO v_ilan_owner FROM public.ilanlar GROUP BY owner_id ORDER BY count(*) DESC LIMIT 1;
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_ilan_owner, 'role', 'authenticated')::text, true);
  INSERT INTO public.ilanlar (owner_id, category_id, title, description, item_condition, price, currency, attributes, city, district, neighborhood, contact_preference, contact_phone, latitude, longitude)
  SELECT v_ilan_owner, category_id, 'Moderasyon testi A', description, item_condition, price, currency, attributes, city, district, neighborhood, contact_preference, contact_phone, latitude, longitude
    FROM public.ilanlar WHERE owner_id = v_ilan_owner ORDER BY created_at LIMIT 1 RETURNING id INTO v_ilan_a;
  INSERT INTO public.ilanlar (owner_id, category_id, title, description, item_condition, price, currency, attributes, city, district, neighborhood, contact_preference, contact_phone, latitude, longitude)
  SELECT v_ilan_owner, category_id, 'Moderasyon testi B', description, item_condition, price, currency, attributes, city, district, neighborhood, contact_preference, contact_phone, latitude, longitude
    FROM public.ilanlar WHERE owner_id = v_ilan_owner ORDER BY created_at LIMIT 1 RETURNING id INTO v_ilan_b;
  EXECUTE 'RESET ROLE';
  IF (SELECT status FROM public.ilanlar WHERE id = v_ilan_a) <> 'pending' THEN
    RAISE EXCEPTION '[7] test ilanı onay beklemiyor';
  END IF;
  v_state := NULL;
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_mod, 'role', 'authenticated')::text, true);
    PERFORM public.mod_pending_ilanlar(10, 0);
    RAISE EXCEPTION 'geçti';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE;
  END;
  IF v_state IS DISTINCT FROM '42501' THEN RAISE EXCEPTION '[7] kapsamsız ilan listesi: %', v_state; END IF;

  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  PERFORM public.admin_set_moderator(v_mod, ARRAY['reports', 'content', 'ilanlar'], NULL);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_mod, 'role', 'authenticated')::text, true);
  v_json := public.mod_pending_ilanlar(100, 0);
  -- Doğrudan güncelleme yine RLS'e takılır (işaret yok)
  UPDATE public.ilanlar SET status = 'published' WHERE id = v_ilan_b;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  PERFORM public.mod_review_ilan(v_ilan_a, true, NULL);
  EXECUTE 'RESET ROLE';
  IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_json -> 'rows') e WHERE (e ->> 'id')::uuid = v_ilan_a)
     OR v_n <> 0
     OR (SELECT status FROM public.ilanlar WHERE id = v_ilan_b) <> 'pending' THEN
    RAISE EXCEPTION '[7] ilan listesi/RLS: % (doğrudan güncellenen %)', v_json, v_n;
  END IF;
  SELECT status, moderated_by, published_at, expires_at INTO v_row FROM public.ilanlar WHERE id = v_ilan_a;
  IF v_row.status <> 'published' OR v_row.moderated_by <> v_mod OR v_row.published_at IS NULL OR v_row.expires_at IS NULL
     OR NOT EXISTS (SELECT 1 FROM public.notifications WHERE user_id = v_ilan_owner AND entity_id = v_ilan_a::text
                     AND title = 'İlanın yayında') THEN
    RAISE EXCEPTION '[7] onay: %', v_row;
  END IF;
  v_hint := NULL;
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_mod, 'role', 'authenticated')::text, true);
    PERFORM public.mod_review_ilan(v_ilan_b, false, '   ');
    RAISE EXCEPTION 'geçti';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_hint = PG_EXCEPTION_HINT;
  END;
  IF v_hint IS DISTINCT FROM 'MOD_REASON_REQUIRED' THEN RAISE EXCEPTION '[7] nedensiz ret: %', v_hint; END IF;
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_mod, 'role', 'authenticated')::text, true);
  PERFORM public.mod_review_ilan(v_ilan_b, false, 'Yanıltıcı fiyat');
  EXECUTE 'RESET ROLE';
  SELECT status, rejection_reason, moderated_by INTO v_row FROM public.ilanlar WHERE id = v_ilan_b;
  IF v_row.status <> 'rejected' OR v_row.rejection_reason <> 'Yanıltıcı fiyat' OR v_row.moderated_by <> v_mod THEN
    RAISE EXCEPTION '[7] ret: %', v_row;
  END IF;
  v_checks := v_checks + 1;

  -- [8] canlı yayın listesi 'live' kapsamı ister
  v_state := NULL;
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_mod, 'role', 'authenticated')::text, true);
    PERFORM public.admin_live_sessions('live', 10, 0);
    RAISE EXCEPTION 'geçti';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE;
  END;
  IF v_state IS DISTINCT FROM '42501' THEN RAISE EXCEPTION '[8] kapsamsız canlı liste: %', v_state; END IF;
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  PERFORM public.admin_set_moderator(v_mod, ARRAY['live'], NULL);
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_mod, 'role', 'authenticated')::text, true);
  v_json := public.admin_live_sessions('live', 10, 0);
  EXECUTE 'RESET ROLE';
  IF NOT (v_json ? 'rows') THEN RAISE EXCEPTION '[8] canlı liste: %', v_json; END IF;
  v_checks := v_checks + 1;

  -- [9] askıya alınan moderatör yetkisini kaybeder
  UPDATE public.profiles SET status = 'suspended' WHERE id = v_mod;
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_mod, 'role', 'authenticated')::text, true);
  IF public.auth_is_moderator('live') OR public.my_moderation() -> 'scopes' <> '[]'::jsonb THEN
    EXECUTE 'RESET ROLE';
    RAISE EXCEPTION '[9] askıdaki moderatör yetkili';
  END IF;
  EXECUTE 'RESET ROLE';
  UPDATE public.profiles SET status = 'active' WHERE id = v_mod;
  v_checks := v_checks + 1;

  -- [10] kaldırma + geçersiz girişler
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  v_json := public.admin_set_moderator(v_mod, ARRAY[]::text[], NULL);
  EXECUTE 'RESET ROLE';
  IF NOT (v_json ->> 'removed')::boolean OR EXISTS (SELECT 1 FROM public.moderators WHERE user_id = v_mod)
     OR NOT EXISTS (SELECT 1 FROM public.notifications WHERE user_id = v_mod AND title = 'Moderatörlük yetkin kaldırıldı') THEN
    RAISE EXCEPTION '[10] kaldırma: %', v_json;
  END IF;
  v_hint := NULL;
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
    PERFORM public.admin_set_moderator(v_mod, ARRAY['her_sey'], NULL);
    RAISE EXCEPTION 'geçti';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_hint = PG_EXCEPTION_HINT;
  END;
  IF v_hint IS DISTINCT FROM 'MOD_SCOPE_INVALID' THEN RAISE EXCEPTION '[10] geçersiz kapsam: %', v_hint; END IF;
  v_hint := NULL;
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
    PERFORM public.admin_set_moderator(v_admin, ARRAY['live'], NULL);
    RAISE EXCEPTION 'geçti';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_hint = PG_EXCEPTION_HINT;
  END;
  IF v_hint IS DISTINCT FROM 'MOD_USER_IS_ADMIN' THEN RAISE EXCEPTION '[10] yöneticiye moderatörlük: %', v_hint; END IF;
  v_checks := v_checks + 1;

  RAISE EXCEPTION 'TESTS_PASSED % kontrol', v_checks;
END
$test$;
