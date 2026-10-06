-- Görev 3.5 — takip bütünlüğü + önerilen kişiler canlı doğrulaması (kendini geri alır).
--
-- Çalıştırma: supabase db query --linked --file supabase/tests/manual/follow_integrity_and_suggestions_test.sql
-- Başarı = 'TESTS_PASSED ...' istisnası: DO bloğu RAISE EXCEPTION ile biter,
-- testin yazdığı her şey (takipler, istekler, engeller, bildirimler) geri alınır.
DO $test$
DECLARE
  v_a uuid;      -- test eden kullanıcı
  v_pub uuid;    -- herkese açık hesap
  v_priv uuid;   -- gizli hesap
  v_blk uuid;    -- A'yı engelleyecek hesap
  v_fan uuid;    -- A'yı takip eden (öneride ilk sıra)
  v_mid uuid;    -- A'nın takip ettiği ara kişi (ortak takip için)
  v_cand uuid;   -- ara kişinin takip ettiği aday
  v_bot uuid;
  v_admin uuid;
  v_json jsonb;
  v_ids uuid[];
  v_hint text; v_state text; v_msg text;
  v_n integer;
  v_t0 timestamptz;
  v_ms numeric;
  v_checks integer := 0;
BEGIN
  SELECT id INTO v_a FROM public.profiles
   WHERE NOT COALESCE(is_bot, false) AND NOT COALESCE(is_admin, false) AND role::text = 'customer'
     AND COALESCE(profile_is_public, true) AND NULLIF(btrim(username), '') IS NOT NULL
   ORDER BY created_at LIMIT 1;
  SELECT id INTO v_priv FROM public.profiles
   WHERE NOT COALESCE(profile_is_public, true) AND id <> v_a AND NOT COALESCE(is_bot, false)
   ORDER BY created_at LIMIT 1;
  SELECT array_agg(id ORDER BY created_at) INTO v_ids FROM (
    SELECT id, created_at FROM public.profiles
     WHERE id NOT IN (v_a, v_priv) AND NOT COALESCE(is_bot, false) AND NOT COALESCE(is_admin, false)
       AND role::text <> 'admin' AND COALESCE(profile_is_public, true)
       AND NOT COALESCE(needs_username, false) AND NULLIF(btrim(username), '') IS NOT NULL
     ORDER BY created_at LIMIT 6) x;
  v_pub := v_ids[1]; v_blk := v_ids[2]; v_fan := v_ids[3]; v_mid := v_ids[4]; v_cand := v_ids[5];
  SELECT id INTO v_bot FROM public.profiles WHERE COALESCE(is_bot, false) ORDER BY created_at LIMIT 1;
  SELECT id INTO v_admin FROM public.profiles WHERE COALESCE(is_admin, false) OR role::text = 'admin' ORDER BY created_at LIMIT 1;
  IF v_cand IS NULL OR v_priv IS NULL OR v_bot IS NULL OR v_admin IS NULL THEN
    RAISE EXCEPTION 'test verisi yok';
  END IF;

  -- Temiz başlangıç: bu kişiler arasındaki ilişkileri sıfırla
  DELETE FROM public.follows WHERE follower_id = v_a OR following_id = v_a
     OR (follower_id = v_mid AND following_id = v_cand);
  DELETE FROM public.follow_requests WHERE follower_id = v_a OR following_id = v_a;
  DELETE FROM public.blocked_users WHERE blocker_id = v_a OR blocked_id = v_a;

  -- [1] yapı
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'follows'
                  AND policyname = 'follows_insert_self' AND with_check LIKE '%social_can_follow_directly%') THEN
    RAISE EXCEPTION '[1] follows ekleme politikası eski';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'follow_requests'
                  AND cmd = 'INSERT' AND with_check LIKE '%''pending''%') THEN
    RAISE EXCEPTION '[1] istek ekleme politikası eski';
  END IF;
  IF has_function_privilege('anon', 'public.social_follow(uuid, boolean)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.suggested_follows(integer)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.upsert_follow_request(uuid, uuid)', 'EXECUTE')
     OR has_table_privilege('authenticated', 'public.follow_suggestion_dismissals', 'SELECT')
     OR NOT (SELECT prosecdef FROM pg_proc WHERE oid = 'public.upsert_follow_request(uuid,uuid)'::regprocedure) THEN
    RAISE EXCEPTION '[1] yetkiler yanlış';
  END IF;
  v_checks := v_checks + 1;

  -- [2] GİZLİLİK AÇIĞI KAPANDI: gizli hesaba doğrudan takip yok; açığa var
  v_state := NULL;
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
    INSERT INTO public.follows (follower_id, following_id) VALUES (v_a, v_priv);
    RAISE EXCEPTION 'geçti';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
  END;
  IF v_state IS DISTINCT FROM '42501' THEN RAISE EXCEPTION '[2] gizli hesaba doğrudan takip: % %', v_state, v_msg; END IF;
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
  INSERT INTO public.follows (follower_id, following_id) VALUES (v_a, v_pub);
  EXECUTE 'RESET ROLE';
  IF NOT EXISTS (SELECT 1 FROM public.follows WHERE follower_id = v_a AND following_id = v_pub) THEN
    RAISE EXCEPTION '[2] açık hesabı takip edemedi';
  END IF;
  v_state := NULL;
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
    INSERT INTO public.follows (follower_id, following_id) VALUES (v_a, v_a);
    RAISE EXCEPTION 'geçti';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE;
  END;
  IF v_state NOT IN ('42501', '23514') THEN RAISE EXCEPTION '[2] kendini takip: %', v_state; END IF;
  -- engelleyen hesabı takip edemez
  INSERT INTO public.blocked_users (blocker_id, blocked_id) VALUES (v_blk, v_a);
  v_state := NULL;
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
    INSERT INTO public.follows (follower_id, following_id) VALUES (v_a, v_blk);
    RAISE EXCEPTION 'geçti';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE;
  END;
  IF v_state IS DISTINCT FROM '42501' THEN RAISE EXCEPTION '[2] engelleyeni takip etti: %', v_state; END IF;
  v_checks := v_checks + 1;

  -- [3] istek yalnız "bekliyor" olarak açılır
  v_state := NULL;
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
    INSERT INTO public.follow_requests (follower_id, following_id, status) VALUES (v_a, v_priv, 'accepted');
    RAISE EXCEPTION 'geçti';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE;
  END;
  IF v_state IS DISTINCT FROM '42501' THEN RAISE EXCEPTION '[3] kabul edilmiş istek eklendi: %', v_state; END IF;
  v_checks := v_checks + 1;

  -- [4] social_follow: açık → takip, gizli → istek (+bildirim), bırakınca istek de kalkar
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
  v_json := public.social_follow(v_cand, true);
  IF v_json ->> 'status' <> 'following' THEN RAISE EXCEPTION '[4] açık hesap: %', v_json; END IF;
  v_json := public.social_follow(v_cand, false);
  IF v_json ->> 'status' <> 'none' THEN RAISE EXCEPTION '[4] bırakma: %', v_json; END IF;
  v_json := public.social_follow(v_priv, true);
  IF v_json ->> 'status' <> 'requested' THEN RAISE EXCEPTION '[4] gizli hesap: %', v_json; END IF;
  v_json := public.social_follow(v_priv, true);
  EXECUTE 'RESET ROLE';
  SELECT count(*) INTO v_n FROM public.follow_requests WHERE follower_id = v_a AND following_id = v_priv;
  IF v_json ->> 'status' <> 'requested' OR v_n <> 1 THEN RAISE EXCEPTION '[4] ikinci istek: % (%)', v_json, v_n; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.notifications WHERE user_id = v_priv AND actor_id = v_a AND type = 'follow_request') THEN
    RAISE EXCEPTION '[4] gizli hesaba istek bildirimi gitmedi';
  END IF;
  IF EXISTS (SELECT 1 FROM public.follows WHERE follower_id = v_a AND following_id = v_priv) THEN
    RAISE EXCEPTION '[4] istek takip sayıldı';
  END IF;
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
  v_json := public.social_follow(v_priv, false);
  EXECUTE 'RESET ROLE';
  IF v_json ->> 'status' <> 'none' OR EXISTS (SELECT 1 FROM public.follow_requests WHERE follower_id = v_a AND following_id = v_priv) THEN
    RAISE EXCEPTION '[4] istek geri alınmadı: %', v_json;
  END IF;
  v_hint := NULL;
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
    PERFORM public.social_follow(v_blk, true);
    RAISE EXCEPTION 'geçti';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_hint = PG_EXCEPTION_HINT;
  END;
  IF v_hint IS DISTINCT FROM 'FOLLOW_BLOCKED' THEN RAISE EXCEPTION '[4] engelli: %', v_hint; END IF;
  v_hint := NULL;
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
    PERFORM public.social_follow(v_a, true);
    RAISE EXCEPTION 'geçti';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_hint = PG_EXCEPTION_HINT;
  END;
  IF v_hint IS DISTINCT FROM 'FOLLOW_SELF' THEN RAISE EXCEPTION '[4] kendini: %', v_hint; END IF;
  v_checks := v_checks + 1;

  -- [5] gizli hesap isteği onaylayınca takip oluşur ve içeriği görünür olur
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
  PERFORM public.social_follow(v_priv, true);
  IF public.can_view_social_author(v_priv) THEN RAISE EXCEPTION '[5] onaysız gizli içerik görünüyor'; END IF;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_priv, 'role', 'authenticated')::text, true);
  UPDATE public.follow_requests SET status = 'accepted' WHERE follower_id = v_a AND following_id = v_priv;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
  IF NOT public.can_view_social_author(v_priv) THEN RAISE EXCEPTION '[5] onaydan sonra görünmüyor'; END IF;
  EXECUTE 'RESET ROLE';
  IF NOT EXISTS (SELECT 1 FROM public.follows WHERE follower_id = v_a AND following_id = v_priv) THEN
    RAISE EXCEPTION '[5] onay takip oluşturmadı';
  END IF;
  v_checks := v_checks + 1;

  -- [6] upsert_follow_request: yalnız kendi adına; reddedilen istek yeniden bekliyor + yeni bildirim
  DELETE FROM public.follows WHERE follower_id = v_a AND following_id = v_priv;
  DELETE FROM public.follow_requests WHERE follower_id = v_a AND following_id = v_priv;
  INSERT INTO public.follow_requests (follower_id, following_id, status) VALUES (v_a, v_priv, 'rejected');
  DELETE FROM public.notifications WHERE user_id = v_priv AND actor_id = v_a AND type = 'follow_request';
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
  v_json := public.upsert_follow_request(v_pub, v_priv);   -- başkası adına
  IF (v_json ->> 'success')::boolean THEN RAISE EXCEPTION '[6] başkası adına istek: %', v_json; END IF;
  v_json := public.upsert_follow_request(v_a, v_priv);
  EXECUTE 'RESET ROLE';
  IF NOT (v_json ->> 'success')::boolean OR v_json ->> 'status' <> 'pending'
     OR (SELECT status FROM public.follow_requests WHERE follower_id = v_a AND following_id = v_priv) <> 'pending' THEN
    RAISE EXCEPTION '[6] reddedilen istek yenilenmedi: %', v_json;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.notifications WHERE user_id = v_priv AND actor_id = v_a AND type = 'follow_request') THEN
    RAISE EXCEPTION '[6] yenilenen istek bildirim üretmedi';
  END IF;
  v_checks := v_checks + 1;

  -- [7] öneriler: seni takip eden ilk; ortak takip gerekçesi; bot/admin/engelli/takip edilen/bekleyen yok
  INSERT INTO public.follows (follower_id, following_id) VALUES (v_fan, v_a) ON CONFLICT DO NOTHING;
  INSERT INTO public.follows (follower_id, following_id) VALUES (v_a, v_mid) ON CONFLICT DO NOTHING;
  INSERT INTO public.follows (follower_id, following_id) VALUES (v_mid, v_cand) ON CONFLICT DO NOTHING;
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
  v_t0 := clock_timestamp();
  v_json := public.suggested_follows(30);
  v_ms := extract(epoch FROM clock_timestamp() - v_t0) * 1000;
  EXECUTE 'RESET ROLE';
  IF jsonb_array_length(v_json) = 0 THEN RAISE EXCEPTION '[7] öneri boş'; END IF;
  IF (v_json -> 0 ->> 'id')::uuid <> v_fan OR v_json -> 0 ->> 'reason' <> 'follows_you'
     OR NOT (v_json -> 0 ->> 'follows_you')::boolean THEN
    RAISE EXCEPTION '[7] seni takip eden ilk değil: %', v_json -> 0;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_json) e
                  WHERE (e ->> 'id')::uuid = v_cand AND e ->> 'reason' = 'mutual'
                    AND (e ->> 'mutual_count')::int >= 1
                    AND e -> 'mutual_names' ? (SELECT username FROM public.profiles WHERE id = v_mid)) THEN
    RAISE EXCEPTION '[7] ortak takip gerekçesi yok';
  END IF;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_json) e
              WHERE (e ->> 'id')::uuid IN (v_a, v_pub, v_mid, v_priv, v_blk, v_bot, v_admin)) THEN
    RAISE EXCEPTION '[7] olmaması gereken öneri var';
  END IF;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_json) e JOIN public.profiles p ON p.id = (e ->> 'id')::uuid
              WHERE COALESCE(p.is_bot, false) OR COALESCE(p.is_admin, false)) THEN
    RAISE EXCEPTION '[7] bot/admin önerildi';
  END IF;
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('role', 'authenticated')::text, true);
  IF public.suggested_follows(10) <> '[]'::jsonb THEN RAISE EXCEPTION '[7] kimliksiz çağrı boş dönmedi'; END IF;
  EXECUTE 'RESET ROLE';
  v_checks := v_checks + 1;

  -- [8] "kaldır": 60 gün gösterilmez, sonra geri gelir
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
  PERFORM public.dismiss_follow_suggestion(v_fan);
  v_json := public.suggested_follows(30);
  EXECUTE 'RESET ROLE';
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_json) e WHERE (e ->> 'id')::uuid = v_fan) THEN
    RAISE EXCEPTION '[8] kaldırılan öneri döndü';
  END IF;
  UPDATE public.follow_suggestion_dismissals SET created_at = now() - interval '61 days'
   WHERE user_id = v_a AND dismissed_user_id = v_fan;
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
  v_json := public.suggested_follows(30);
  EXECUTE 'RESET ROLE';
  IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_json) e WHERE (e ->> 'id')::uuid = v_fan) THEN
    RAISE EXCEPTION '[8] 60 gün sonra geri gelmedi';
  END IF;
  v_checks := v_checks + 1;

  RAISE EXCEPTION 'TESTS_PASSED % kontrol (öneri sorgusu % ms)', v_checks, round(v_ms, 1);
END
$test$;
