-- Görev 4.7 — bot yorumları canlı doğrulaması (kendini geri alır).
--
-- Çalıştırma: supabase db query --linked --file supabase/tests/manual/bot_comments_test.sql
-- Başarı = 'TESTS_PASSED ...' istisnası; testin yazdığı her şey geri alınır.
DO $test$
DECLARE
  v_admin uuid; v_bot uuid; v_bot2 uuid; v_user uuid; v_post uuid; v_bot_post uuid; v_fresh uuid;
  v_json jsonb;
  v_job uuid; v_comment uuid;
  v_n integer; v_uses integer;
  v_state text; v_hint text;
  v_checks integer := 0;
BEGIN
  SELECT id INTO v_admin FROM public.profiles WHERE role::text = 'admin' ORDER BY created_at LIMIT 1;
  SELECT p.id INTO v_bot FROM public.profiles p JOIN public.bot_accounts ba ON ba.id = p.id
   WHERE p.is_bot AND p.status::text = 'active' AND ba.is_active ORDER BY p.created_at LIMIT 1;
  SELECT p.id INTO v_bot2 FROM public.profiles p JOIN public.bot_accounts ba ON ba.id = p.id
   WHERE p.is_bot AND p.status::text = 'active' AND ba.is_active AND p.id <> v_bot ORDER BY p.created_at LIMIT 1;
  SELECT po.id, po.user_id INTO v_post, v_user FROM public.posts po JOIN public.profiles a ON a.id = po.user_id
   WHERE po.is_active AND NOT COALESCE(a.is_bot, false) AND a.status::text = 'active'
   ORDER BY po.created_at DESC LIMIT 1;
  SELECT po.id INTO v_bot_post FROM public.posts po JOIN public.profiles a ON a.id = po.user_id
   WHERE po.is_active AND a.is_bot AND a.id NOT IN (v_bot, v_bot2) ORDER BY po.created_at DESC LIMIT 1;
  IF v_admin IS NULL OR v_bot IS NULL OR v_bot2 IS NULL OR v_post IS NULL THEN
    RAISE EXCEPTION 'test verisi yok';
  END IF;

  -- [1] yönetici olmayan çağıramaz; tablolar istemciye kapalı
  v_state := NULL;
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_user, 'role', 'authenticated')::text, true);
    PERFORM public.admin_bot_comment(v_bot, v_post, 'Deneme', NULL);
    RAISE EXCEPTION 'geçti';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE;
  END;
  IF v_state IS DISTINCT FROM '42501'
     OR has_table_privilege('authenticated', 'public.bot_comment_jobs', 'SELECT')
     OR has_table_privilege('authenticated', 'public.bot_comment_library', 'SELECT')
     OR has_function_privilege('authenticated', 'public.schedule_bot_comments(integer)', 'EXECUTE') THEN
    RAISE EXCEPTION '[1] yetkiler: %', v_state;
  END IF;
  v_checks := v_checks + 1;

  -- [2] manuel "şimdi": yorum botun adına yazılır, gerçek sahibine bildirim, denetim
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  v_json := public.admin_bot_comment(v_bot, v_post, '  Harika paylaşım 👏 ', NULL);
  EXECUTE 'RESET ROLE';
  v_comment := (v_json ->> 'comment_id')::uuid;
  IF v_json ->> 'status' <> 'done'
     OR NOT EXISTS (SELECT 1 FROM public.post_comments c WHERE c.id = v_comment AND c.user_id = v_bot
                     AND c.post_id = v_post AND c.content = 'Harika paylaşım 👏')
     OR NOT EXISTS (SELECT 1 FROM public.notifications n WHERE n.user_id = v_user AND n.type = 'post_comment'
                     AND n.actor_id = v_bot AND n.entity_id = v_post::text)
     OR NOT EXISTS (SELECT 1 FROM public.admin_audit_log WHERE action = 'bot_comment' AND target_id = v_post::text) THEN
    RAISE EXCEPTION '[2] manuel yorum: %', v_json;
  END IF;
  v_checks := v_checks + 1;

  -- [3] zamanlı: vadesi gelmeden işlenmez; iptal edilir
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  v_json := public.admin_bot_comment(v_bot2, v_post, 'Sonra gelecek yorum', now() + interval '2 hours');
  EXECUTE 'RESET ROLE';
  v_job := (v_json ->> 'job_id')::uuid;
  PERFORM public.process_bot_comment_jobs(500);
  IF v_json ->> 'status' <> 'pending' OR (SELECT status FROM public.bot_comment_jobs WHERE id = v_job) <> 'pending'
     OR EXISTS (SELECT 1 FROM public.post_comments WHERE post_id = v_post AND content = 'Sonra gelecek yorum') THEN
    RAISE EXCEPTION '[3] zamanlı yorum erken yazıldı: %', v_json;
  END IF;
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  v_json := public.admin_bot_comment_cancel(v_job);
  EXECUTE 'RESET ROLE';
  IF v_json ->> 'status' <> 'cancelled' OR (SELECT status FROM public.bot_comment_jobs WHERE id = v_job) <> 'cancelled' THEN
    RAISE EXCEPTION '[3] iptal: %', v_json;
  END IF;
  v_checks := v_checks + 1;

  -- [4] doğrulamalar: boş metin, bot olmayan hesap, gizli gönderi, çok ileri tarih
  FOR v_n IN 1..4 LOOP
    v_hint := NULL;
    BEGIN
      EXECUTE 'SET LOCAL ROLE authenticated';
      PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
      CASE v_n
        WHEN 1 THEN PERFORM public.admin_bot_comment(v_bot, v_post, '   ', NULL);
        WHEN 2 THEN PERFORM public.admin_bot_comment(v_user, v_post, 'Merhaba', NULL);
        WHEN 3 THEN
          EXECUTE 'RESET ROLE';
          UPDATE public.posts SET is_active = false WHERE id = v_post;
          EXECUTE 'SET LOCAL ROLE authenticated';
          PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
          PERFORM public.admin_bot_comment(v_bot, v_post, 'Merhaba', NULL);
        ELSE PERFORM public.admin_bot_comment(v_bot, v_post, 'Merhaba', now() + interval '40 days');
      END CASE;
      RAISE EXCEPTION 'geçti';
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_hint = PG_EXCEPTION_HINT;
    END;
    IF v_hint IS DISTINCT FROM (ARRAY['BOT_COMMENT_INVALID', 'BOT_INACTIVE', 'BOT_POST_UNAVAILABLE', 'BOT_COMMENT_TOO_LATE'])[v_n] THEN
      RAISE EXCEPTION '[4] doğrulama %: %', v_n, v_hint;
    END IF;
  END LOOP;
  v_checks := v_checks + 1;

  -- [5] otomatik: gönderi bir kez değerlendirilir; [min,max] bot, sahibi hariç;
  --     vadesi gelen yazılır, kitaplık sayacı artar
  UPDATE public.app_settings SET value = CASE key
      WHEN 'bot_auto_comment_enabled' THEN '"true"'::jsonb
      WHEN 'bot_comment_probability' THEN '"100"'::jsonb
      WHEN 'bot_comment_min_count' THEN '"2"'::jsonb
      WHEN 'bot_comment_max_count' THEN '"2"'::jsonb
      WHEN 'bot_comment_min_hours' THEN '"0"'::jsonb
      WHEN 'bot_comment_max_hours' THEN '"0"'::jsonb
      WHEN 'bot_comment_lookback_days' THEN '"1"'::jsonb
      ELSE value END
   WHERE key LIKE 'bot_comment%' OR key = 'bot_auto_comment_enabled';
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_user, 'role', 'authenticated')::text, true);
  INSERT INTO public.posts (user_id, content) VALUES (v_user, 'Bot yorum testi gönderisi') RETURNING id INTO v_fresh;
  EXECUTE 'RESET ROLE';
  SELECT COALESCE(sum(use_count), 0) INTO v_uses FROM public.bot_comment_library;
  PERFORM public.schedule_bot_comments(500);
  SELECT count(*) INTO v_n FROM public.bot_comment_jobs WHERE post_id = v_fresh AND source = 'auto';
  PERFORM public.schedule_bot_comments(500);
  IF v_n <> 2
     OR (SELECT count(*) FROM public.bot_comment_jobs WHERE post_id = v_fresh AND source = 'auto') <> 2
     OR (SELECT count(DISTINCT bot_id) FROM public.bot_comment_jobs WHERE post_id = v_fresh) <> 2
     OR EXISTS (SELECT 1 FROM public.bot_comment_jobs WHERE post_id = v_fresh AND bot_id = v_user)
     OR NOT EXISTS (SELECT 1 FROM public.bot_comment_seen_posts WHERE post_id = v_fresh AND scheduled = 2) THEN
    RAISE EXCEPTION '[5] zamanlama: % iş', v_n;
  END IF;
  UPDATE public.bot_comment_jobs SET due_at = now() - interval '1 minute' WHERE post_id = v_fresh;
  PERFORM public.process_bot_comment_jobs(500);
  IF (SELECT count(*) FROM public.post_comments c JOIN public.profiles p ON p.id = c.user_id
       WHERE c.post_id = v_fresh AND p.is_bot) <> 2
     OR (SELECT COALESCE(sum(use_count), 0) FROM public.bot_comment_library) <> v_uses + 2 THEN
    RAISE EXCEPTION '[5] işleme';
  END IF;
  v_checks := v_checks + 1;

  -- [6] bot gönderisine yorum: bot sahibine bildirim yazılmaz
  IF v_bot_post IS NOT NULL THEN
    SELECT user_id INTO v_state FROM public.posts WHERE id = v_bot_post;
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
    PERFORM public.admin_bot_comment(v_bot, v_bot_post, 'Bot bota yorum', NULL);
    EXECUTE 'RESET ROLE';
    IF EXISTS (SELECT 1 FROM public.notifications WHERE user_id = v_state::uuid AND type = 'post_comment'
                AND actor_id = v_bot AND entity_id = v_bot_post::text) THEN
      RAISE EXCEPTION '[6] bot sahibine bildirim yazıldı';
    END IF;
  END IF;
  v_checks := v_checks + 1;

  -- [7] yazılmış yorumu silme (yalnız o bot yorumu)
  SELECT id INTO v_job FROM public.bot_comment_jobs WHERE comment_id = v_comment;
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  v_json := public.admin_bot_comment_cancel(v_job);
  EXECUTE 'RESET ROLE';
  IF v_json ->> 'status' <> 'deleted' OR EXISTS (SELECT 1 FROM public.post_comments WHERE id = v_comment) THEN
    RAISE EXCEPTION '[7] silme: %', v_json;
  END IF;
  v_checks := v_checks + 1;

  -- [8] listeler ve kitaplık doğrulaması
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  v_json := public.admin_bot_comment_jobs('done', 100, 0);
  IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_json -> 'rows') e
                  WHERE (e -> 'post' ->> 'id')::uuid = v_fresh AND e -> 'bot' ->> 'name' IS NOT NULL
                    AND e ->> 'source' = 'auto')
     OR (v_json -> 'summary' ->> 'done_24h')::int < 2 THEN
    EXECUTE 'RESET ROLE';
    RAISE EXCEPTION '[8] iş listesi: %', v_json;
  END IF;
  v_json := public.admin_bot_recent_posts('Bot yorum testi', 10);
  IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_json) e WHERE (e ->> 'id')::uuid = v_fresh) THEN
    EXECUTE 'RESET ROLE';
    RAISE EXCEPTION '[8] gönderi seçici: %', v_json;
  END IF;
  EXECUTE 'RESET ROLE';
  v_hint := NULL;
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
    PERFORM public.admin_bot_comment_library_upsert(NULL, 'eline sağlık', 'genel', true);
    RAISE EXCEPTION 'geçti';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_hint = PG_EXCEPTION_HINT;
  END;
  IF v_hint IS DISTINCT FROM 'BOT_COMMENT_DUPLICATE' THEN RAISE EXCEPTION '[8] tekrar metin: %', v_hint; END IF;
  v_checks := v_checks + 1;

  -- [9] otomatik kapalıyken zamanlayıcı bir şey yapmaz
  UPDATE public.app_settings SET value = '"false"'::jsonb WHERE key = 'bot_auto_comment_enabled';
  IF public.schedule_bot_comments(500) <> 0 THEN RAISE EXCEPTION '[9] kapalıyken zamanladı'; END IF;
  v_checks := v_checks + 1;

  RAISE EXCEPTION 'TESTS_PASSED % kontrol', v_checks;
END
$test$;
