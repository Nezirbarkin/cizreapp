-- Görev 2.8 — posts.image_aspect_ratio canlı doğrulaması (kendini geri alır).
--
-- Çalıştırma: supabase db query --linked --file supabase/tests/manual/post_image_aspect_ratio_test.sql
-- Başarı = 'TESTS_PASSED ...' istisnası (DO bloğu RAISE EXCEPTION ile biter,
-- böylece testin yazdığı her şey geri alınır).
DO $test$
DECLARE
  v_user uuid;
  v_post uuid;
  v_ratio real;
  v_def text;
  v_n integer;
  v_explore boolean;
  v_checks integer := 0;
BEGIN
  -- [1] kolon var, tipi real
  SELECT count(*) INTO v_n
    FROM information_schema.columns
   WHERE table_schema = 'public' AND table_name = 'posts'
     AND column_name = 'image_aspect_ratio' AND data_type = 'real';
  IF v_n <> 1 THEN RAISE EXCEPTION '[1] posts.image_aspect_ratio real değil/yok'; END IF;
  v_checks := v_checks + 1;

  -- [2] view kolonu taşıyor ve hâlâ security_invoker
  SELECT count(*) INTO v_n
    FROM information_schema.columns
   WHERE table_schema = 'public' AND table_name = 'posts_with_profiles'
     AND column_name = 'image_aspect_ratio';
  IF v_n <> 1 THEN RAISE EXCEPTION '[2] posts_with_profiles kolonu taşımıyor'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_class c
     WHERE c.oid = 'public.posts_with_profiles'::regclass
       AND 'security_invoker=true' = ANY (c.reloptions)
  ) THEN RAISE EXCEPTION '[2] view security_invoker değil'; END IF;
  v_checks := v_checks + 1;

  -- [3] misafir RPC'si kolonu döndürüyor; DEFINER + boş search_path korunmuş
  SELECT pg_get_function_result(p.oid) INTO v_def
    FROM pg_proc p
   WHERE p.proname = 'public_explore_feed' AND p.pronamespace = 'public'::regnamespace;
  IF v_def NOT LIKE '%image_aspect_ratio real%' THEN
    RAISE EXCEPTION '[3] public_explore_feed kolonu döndürmüyor: %', v_def;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
     WHERE p.proname = 'public_explore_feed' AND p.pronamespace = 'public'::regnamespace
       AND p.prosecdef AND p.proconfig @> ARRAY['search_path=""']
  ) THEN RAISE EXCEPTION '[3] DEFINER/search_path sözleşmesi bozuk'; END IF;
  IF NOT has_function_privilege('anon', 'public.public_explore_feed(integer, integer)', 'EXECUTE') THEN
    RAISE EXCEPTION '[3] anon misafir akışını çağıramıyor';
  END IF;
  v_checks := v_checks + 1;

  -- [4] aralık kısıtı: 0.4 ve 2.5 reddedilir, 0.8/1/1.3333 kabul
  SELECT id INTO v_user FROM public.profiles ORDER BY created_at LIMIT 1;
  INSERT INTO public.posts (user_id, content, images, image_aspect_ratio, is_active)
  VALUES (v_user, 'aspect test', ARRAY['https://example.invalid/a.jpg'], 0.8, true)
  RETURNING id INTO v_post;
  BEGIN
    UPDATE public.posts SET image_aspect_ratio = 0.4 WHERE id = v_post;
    RAISE EXCEPTION '[4] 0.4 kabul edildi';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  BEGIN
    UPDATE public.posts SET image_aspect_ratio = 2.5 WHERE id = v_post;
    RAISE EXCEPTION '[4] 2.5 kabul edildi';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  UPDATE public.posts SET image_aspect_ratio = 4.0 / 3 WHERE id = v_post;
  UPDATE public.posts SET image_aspect_ratio = 1 WHERE id = v_post;
  UPDATE public.posts SET image_aspect_ratio = 0.8 WHERE id = v_post;
  v_checks := v_checks + 1;

  -- [5] üye akışı (view) değeri okur — authenticated rolüyle, 42501 yok
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_user, 'role', 'authenticated')::text, true);
  SELECT image_aspect_ratio INTO v_ratio FROM public.posts_with_profiles WHERE id = v_post;
  EXECUTE 'RESET ROLE';
  IF v_ratio IS DISTINCT FROM 0.8::real THEN
    RAISE EXCEPTION '[5] view oranı yanlış: %', v_ratio;
  END IF;
  v_checks := v_checks + 1;

  -- [6] misafir akışı (anon) oranı döndürür (anahtar açıksa)
  SELECT COALESCE(NULLIF(btrim(s.value #>> '{}'), '')::boolean, false) INTO v_explore
    FROM public.app_settings s WHERE s.key = 'explore_public_access';
  IF COALESCE(v_explore, false) THEN
    EXECUTE 'SET LOCAL ROLE anon';
    PERFORM set_config('request.jwt.claims', '{"role":"anon"}', true);
    SELECT count(*) INTO v_n
      FROM public.public_explore_feed(50, 0) f
     WHERE cardinality(f.images) > 0 AND f.image_aspect_ratio IS NOT NULL;
    EXECUTE 'RESET ROLE';
    IF v_n = 0 THEN RAISE EXCEPTION '[6] misafir akışında oranlı fotoğraf yok'; END IF;
  END IF;
  v_checks := v_checks + 1;

  -- [7] geri doldurma: fotoğraflı eski gönderilerin hepsinde oran var ve
  --     akış aralığında
  DELETE FROM public.posts WHERE id = v_post;
  SELECT count(*) INTO v_n FROM public.posts
   WHERE cardinality(images) > 0 AND image_aspect_ratio IS NULL
     AND created_at < '2026-09-28 12:00:00+00';
  IF v_n <> 0 THEN RAISE EXCEPTION '[7] oranı boş eski fotoğraflı gönderi: %', v_n; END IF;
  SELECT count(*) INTO v_n FROM public.posts
   WHERE image_aspect_ratio IS NOT NULL
     AND (image_aspect_ratio < 0.8 OR image_aspect_ratio > 1.91);
  IF v_n <> 0 THEN RAISE EXCEPTION '[7] aralık dışı oran: %', v_n; END IF;
  v_checks := v_checks + 1;

  -- [8] updated_at tetikleyicisi yeniden AÇIK (geri doldurma kapatıp açtı)
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
     WHERE tgrelid = 'public.posts'::regclass
       AND tgname = 'update_posts_updated_at' AND tgenabled = 'O'
  ) THEN RAISE EXCEPTION '[8] update_posts_updated_at kapalı kalmış'; END IF;
  v_checks := v_checks + 1;

  RAISE EXCEPTION 'TESTS_PASSED % kontrol', v_checks;
END
$test$;
