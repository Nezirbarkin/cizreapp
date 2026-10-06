-- =============================================================================
-- HAZIR PROFİL ARKA PLANLARI testi (göç 20260928000001_profile_background_presets)
-- -----------------------------------------------------------------------------
-- ÇALIŞTIRMA:
--   supabase db query --linked --file supabase/tests/manual/profile_background_presets_test.sql
--
-- Tek DO bloğu; HER ZAMAN 'TESTS_PASSED ...' ya da 'TEST_FAIL[...]' istisnasıyla
-- biter, istisna her şeyi geri alır.
--
-- İDDİALAR:
--   [1] 'profile-backgrounds' kovası herkese açık, yalnız görsel türleri, 2 MB sınır
--   [2] kova politikaları: herkes okur; yükleme/güncelleme/silme yalnız admin
--   [3] katalog: 50 aktif kayıt, 10 tema × 5, kod = dosya adı, sıra artan
--   [4] anon aktif kayıtları okur, pasif kaydı GÖRMEZ, yazamaz
--   [5] admin olmayan kullanıcı yazamaz; admin yazabilir
-- =============================================================================

DO $$
DECLARE
  v_bucket record;
  v_count int;
  v_bad int;
  v_raised boolean;
  v_user uuid;
  v_admin uuid;
  v_checks int := 0;
BEGIN
  ----------------------------------------------------------------------------
  -- [1] Kova
  ----------------------------------------------------------------------------
  SELECT * INTO v_bucket FROM storage.buckets WHERE id = 'profile-backgrounds';
  IF v_bucket.id IS NULL THEN
    RAISE EXCEPTION 'TEST_FAIL[1]: kova yok';
  END IF;
  IF v_bucket.public IS NOT TRUE
     OR v_bucket.file_size_limit IS DISTINCT FROM 2097152
     OR NOT (v_bucket.allowed_mime_types @> ARRAY['image/jpeg']::text[])
     OR v_bucket.allowed_mime_types @> ARRAY['image/gif']::text[] THEN
    RAISE EXCEPTION 'TEST_FAIL[1]: kova ayarları yanlış';
  END IF;
  v_checks := v_checks + 2;

  ----------------------------------------------------------------------------
  -- [2] Kova politikaları
  ----------------------------------------------------------------------------
  SELECT count(*) INTO v_count
  FROM pg_policies
  WHERE schemaname = 'storage' AND tablename = 'objects'
    AND qual LIKE '%profile-backgrounds%' AND cmd = 'SELECT';
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'TEST_FAIL[2]: okuma politikası % adet', v_count;
  END IF;
  SELECT count(*) INTO v_count
  FROM pg_policies
  WHERE schemaname = 'storage' AND tablename = 'objects'
    AND (coalesce(qual, '') || coalesce(with_check, '')) LIKE '%profile-backgrounds%'
    AND cmd IN ('INSERT', 'UPDATE', 'DELETE')
    AND (coalesce(qual, '') || coalesce(with_check, '')) LIKE '%auth_is_admin()%';
  IF v_count <> 3 THEN
    RAISE EXCEPTION 'TEST_FAIL[2]: admin yazma politikaları % adet', v_count;
  END IF;
  v_checks := v_checks + 2;

  ----------------------------------------------------------------------------
  -- [3] Katalog
  ----------------------------------------------------------------------------
  SELECT count(*) INTO v_count FROM public.profile_background_presets WHERE is_active;
  IF v_count <> 50 THEN
    RAISE EXCEPTION 'TEST_FAIL[3]: % aktif kayıt', v_count;
  END IF;
  SELECT count(*) INTO v_bad FROM (
    SELECT category FROM public.profile_background_presets
    GROUP BY category HAVING count(*) <> 5
  ) AS q;
  SELECT count(DISTINCT category) INTO v_count FROM public.profile_background_presets;
  IF v_count <> 10 OR v_bad <> 0 THEN
    RAISE EXCEPTION 'TEST_FAIL[3]: tema dağılımı (% tema, % bozuk)', v_count, v_bad;
  END IF;
  SELECT count(*) INTO v_bad FROM public.profile_background_presets
  WHERE image_path <> 'presets/' || code || '.jpg' OR thumb_path <> 'thumbs/' || code || '.jpg';
  IF v_bad <> 0 THEN
    RAISE EXCEPTION 'TEST_FAIL[3]: % kayıtta yol koda uymuyor', v_bad;
  END IF;
  SELECT count(*) INTO v_bad FROM (
    SELECT code, sort_order, lag(sort_order) OVER (ORDER BY code) AS prev
    FROM public.profile_background_presets
  ) AS q WHERE prev IS NOT NULL AND sort_order <= prev;
  IF v_bad <> 0 THEN
    RAISE EXCEPTION 'TEST_FAIL[3]: sıra koda göre artmıyor';
  END IF;
  v_checks := v_checks + 4;

  ----------------------------------------------------------------------------
  -- [4] anon: aktifleri okur, pasifi görmez, yazamaz
  ----------------------------------------------------------------------------
  UPDATE public.profile_background_presets SET is_active = false WHERE code = 'bg_50';

  EXECUTE 'SET LOCAL ROLE anon';
  SELECT count(*) INTO v_count FROM public.profile_background_presets;
  EXECUTE 'RESET ROLE';
  IF v_count <> 49 THEN
    RAISE EXCEPTION 'TEST_FAIL[4]: anon % kayıt gördü (49 bekleniyordu)', v_count;
  END IF;

  v_raised := false;
  BEGIN
    EXECUTE 'SET LOCAL ROLE anon';
    INSERT INTO public.profile_background_presets (code, name, category, image_path, thumb_path)
    VALUES ('bg_99', 'Sahte', 'Test', 'presets/bg_99.jpg', 'thumbs/bg_99.jpg');
  EXCEPTION WHEN insufficient_privilege THEN
    v_raised := true;
  END;
  EXECUTE 'RESET ROLE';
  IF NOT v_raised THEN
    RAISE EXCEPTION 'TEST_FAIL[4]: anon yazabildi';
  END IF;
  v_checks := v_checks + 2;

  ----------------------------------------------------------------------------
  -- [5] admin olmayan yazamaz, admin yazar
  ----------------------------------------------------------------------------
  SELECT p.id INTO v_user FROM public.profiles p
  WHERE NOT coalesce(p.is_admin, false) AND p.role::text <> 'admin'
  ORDER BY p.created_at LIMIT 1;
  SELECT p.id INTO v_admin FROM public.profiles p
  WHERE coalesce(p.is_admin, false) OR p.role::text = 'admin'
  ORDER BY p.created_at LIMIT 1;
  IF v_user IS NULL OR v_admin IS NULL THEN
    RAISE EXCEPTION 'TEST_SKIP: admin ve normal kullanıcı gerekli';
  END IF;

  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_user, 'role', 'authenticated')::text, true);
  PERFORM set_config('request.jwt.claim.sub', v_user::text, true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  v_raised := false;
  BEGIN
    INSERT INTO public.profile_background_presets (code, name, category, image_path, thumb_path)
    VALUES ('bg_98', 'Sahte', 'Test', 'presets/bg_98.jpg', 'thumbs/bg_98.jpg');
  EXCEPTION WHEN insufficient_privilege THEN
    v_raised := true;
  END;
  UPDATE public.profile_background_presets SET name = 'Ele geçirildi' WHERE code = 'bg_01';
  GET DIAGNOSTICS v_count = ROW_COUNT;
  EXECUTE 'RESET ROLE';
  IF NOT v_raised OR v_count <> 0 THEN
    RAISE EXCEPTION 'TEST_FAIL[5]: normal kullanıcı yazabildi (insert engeli=%, güncellenen=%)', v_raised, v_count;
  END IF;

  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  UPDATE public.profile_background_presets SET is_active = true WHERE code = 'bg_50';
  GET DIAGNOSTICS v_count = ROW_COUNT;
  EXECUTE 'RESET ROLE';
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'TEST_FAIL[5]: admin güncelleyemedi';
  END IF;
  v_checks := v_checks + 3;

  RAISE EXCEPTION 'TESTS_PASSED checks=%', v_checks;
END;
$$;
