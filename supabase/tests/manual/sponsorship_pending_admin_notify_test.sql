-- Görev 4.2 — onay bekleyen öne çıkarmada yönetici bildirimi (kendini geri alır).
--
-- Çalıştırma: supabase db query --linked --file supabase/tests/manual/sponsorship_pending_admin_notify_test.sql
-- Başarı = 'TESTS_PASSED ...' istisnası; testin yazdığı her şey geri alınır.
DO $test$
DECLARE
  v_shop uuid; v_shop_name text; v_owner uuid; v_pkg uuid;
  v_id uuid;
  v_admins integer; v_got integer;
  v_content text; v_meta jsonb;
  v_checks integer := 0;
BEGIN
  SELECT s.id, s.name, s.owner_id INTO v_shop, v_shop_name, v_owner FROM public.shops s
   WHERE COALESCE(s.is_active, false) AND COALESCE(s.is_approved, false) ORDER BY s.created_at LIMIT 1;
  SELECT id INTO v_pkg FROM public.sponsorship_packages
   WHERE placement = 'shop_list' AND is_active ORDER BY duration_days LIMIT 1;
  IF v_shop IS NULL OR v_pkg IS NULL THEN RAISE EXCEPTION 'test verisi yok'; END IF;
  SELECT count(*) INTO v_admins FROM public.profiles p
   WHERE (p.role::text = 'admin' OR COALESCE(p.is_admin, false)) AND p.id <> v_owner;

  INSERT INTO public.user_balances (user_id, balance) VALUES (v_owner, 1000)
  ON CONFLICT (user_id) DO UPDATE SET balance = 1000;
  UPDATE public.app_settings SET value = 'true'::jsonb WHERE key = 'sponsorship_enabled';

  -- [1] onay gerekirken satın alma: satın alan hariç her yöneticiye bir bildirim
  UPDATE public.app_settings SET value = 'true'::jsonb WHERE key = 'sponsorship_requires_approval';
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
  v_id := (public.purchase_shop_sponsorship(v_shop, v_pkg, NULL) ->> 'id')::uuid;
  EXECUTE 'RESET ROLE';
  SELECT count(*) INTO v_got FROM public.notifications
   WHERE entity_id = v_id::text AND type = 'admin_notification';
  IF v_admins = 0 OR v_got <> v_admins
     OR EXISTS (SELECT 1 FROM public.notifications WHERE entity_id = v_id::text
                  AND type = 'admin_notification' AND user_id = v_owner) THEN
    RAISE EXCEPTION '[1] bildirim sayısı % beklenen %', v_got, v_admins;
  END IF;
  v_checks := v_checks + 1;

  -- [2] içerik mağazayı ve tutarı söyler; metadata admin menüsünü gösterir
  SELECT content, metadata INTO v_content, v_meta FROM public.notifications
   WHERE entity_id = v_id::text AND type = 'admin_notification' LIMIT 1;
  IF position(v_shop_name IN v_content) = 0 OR v_content NOT LIKE '%onayınızı bekliyor%'
     OR v_meta ->> 'admin_section' <> 'Öne Çıkarma' OR (v_meta ->> 'sponsorship_id')::uuid <> v_id THEN
    RAISE EXCEPTION '[2] içerik/metadata: % %', v_content, v_meta;
  END IF;
  v_checks := v_checks + 1;

  -- [3] onay gerekmezken (hemen yayında) yöneticiye bildirim yok
  UPDATE public.app_settings SET value = 'false'::jsonb WHERE key = 'sponsorship_requires_approval';
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
  v_id := (public.purchase_shop_sponsorship(v_shop, v_pkg, NULL) ->> 'id')::uuid;
  EXECUTE 'RESET ROLE';
  IF EXISTS (SELECT 1 FROM public.notifications WHERE entity_id = v_id::text AND type = 'admin_notification') THEN
    RAISE EXCEPTION '[3] onaysız satın almada yönetici bildirimi üretildi';
  END IF;
  v_checks := v_checks + 1;

  RAISE EXCEPTION 'TESTS_PASSED % kontrol', v_checks;
END
$test$;
