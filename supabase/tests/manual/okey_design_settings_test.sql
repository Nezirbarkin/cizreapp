-- 101 Okey tasarım ayarı — canlı doğrulama (kendini geri alır).
--
--   supabase db query --linked --file supabase/tests/manual/okey_design_settings_test.sql
--
-- Tek DO bloğu; sonunda bilerek RAISE EXCEPTION 'TESTS_PASSED ...' atar, böylece
-- yapılan her değişiklik geri alınır ve günlük hata mesajında görünür.
DO $$
DECLARE
  v_log text := '';
  v_cfg jsonb;
  v_n int;
  v_uid uuid;
  v_ok boolean;
BEGIN
  -- 1) Varsayılan satırlar ve okuyucu
  UPDATE public.app_settings SET value = '"salon"'::jsonb WHERE key = 'okey_design';
  UPDATE public.app_settings SET value = '"auto"'::jsonb WHERE key = 'okey_lobby_layout';
  UPDATE public.app_settings SET value = '"true"'::jsonb WHERE key = 'okey_design_user_choice';
  v_cfg := public.okey_design_config();
  IF v_cfg <> '{"design":"salon","layout":"auto","user_choice":true}'::jsonb THEN
    RAISE EXCEPTION 'varsayılan yanlış: %', v_cfg;
  END IF;
  v_log := v_log || '[1] varsayılan ';

  -- 2) İstemcinin yazdığı düz metin (PostgREST "neon" → jsonb metin)
  UPDATE public.app_settings SET value = to_jsonb('neon'::text) WHERE key = 'okey_design';
  UPDATE public.app_settings SET value = to_jsonb('kompakt'::text) WHERE key = 'okey_lobby_layout';
  UPDATE public.app_settings SET value = to_jsonb('false'::text) WHERE key = 'okey_design_user_choice';
  v_cfg := public.okey_design_config();
  IF v_cfg <> '{"design":"neon","layout":"kompakt","user_choice":false}'::jsonb THEN
    RAISE EXCEPTION 'düz metin yanlış: %', v_cfg;
  END IF;
  v_log := v_log || '[2] düz-metin ';

  -- 3) Yanlışlıkla tırnaklı yazılmış metin ('"false"') da okunur
  UPDATE public.app_settings SET value = to_jsonb('"false"'::text) WHERE key = 'okey_design_user_choice';
  UPDATE public.app_settings SET value = to_jsonb('"Ege"'::text) WHERE key = 'okey_design';
  v_cfg := public.okey_design_config();
  IF (v_cfg->>'user_choice')::boolean IS DISTINCT FROM false OR v_cfg->>'design' <> 'ege' THEN
    RAISE EXCEPTION 'tırnaklı metin yanlış: %', v_cfg;
  END IF;
  v_log := v_log || '[3] tırnak ';

  -- 4) Bozuk değerler varsayılana düşer
  UPDATE public.app_settings SET value = to_jsonb('x"); drop table y; --'::text) WHERE key = 'okey_design';
  UPDATE public.app_settings SET value = to_jsonb('grid'::text) WHERE key = 'okey_lobby_layout';
  UPDATE public.app_settings SET value = to_jsonb('belki'::text) WHERE key = 'okey_design_user_choice';
  v_cfg := public.okey_design_config();
  IF v_cfg <> '{"design":"salon","layout":"auto","user_choice":true}'::jsonb THEN
    RAISE EXCEPTION 'bozuk değer yanlış: %', v_cfg;
  END IF;
  v_log := v_log || '[4] bozuk ';

  -- 5) Satır hiç yoksa da varsayılan
  DELETE FROM public.app_settings
   WHERE key IN ('okey_design', 'okey_lobby_layout', 'okey_design_user_choice');
  v_cfg := public.okey_design_config();
  IF v_cfg <> '{"design":"salon","layout":"auto","user_choice":true}'::jsonb THEN
    RAISE EXCEPTION 'satırsız yanlış: %', v_cfg;
  END IF;
  v_log := v_log || '[5] satırsız ';

  -- 6) Yetkiler: misafir/üye okuyabilir, ham okuyucu kapalı
  IF NOT has_function_privilege('anon', 'public.okey_design_config()', 'EXECUTE') THEN
    RAISE EXCEPTION 'anon okuyamıyor';
  END IF;
  IF NOT has_function_privilege('authenticated', 'public.okey_design_config()', 'EXECUTE') THEN
    RAISE EXCEPTION 'authenticated okuyamıyor';
  END IF;
  IF has_function_privilege('anon', 'public.okey_design_setting(text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'ham okuyucu anon''a açık';
  END IF;
  v_log := v_log || '[6] yetki ';

  -- 7) Yönetici olmayan üye ayarı DEĞİŞTİREMEZ (app_settings yönetici politikası)
  INSERT INTO public.app_settings (key, value)
  VALUES ('okey_design', '"salon"'::jsonb)
  ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
  SELECT p.id INTO v_uid
    FROM public.profiles p
   WHERE p.role IS DISTINCT FROM 'admin'
   LIMIT 1;
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', v_uid, 'role', 'authenticated')::text,
    true
  );
  PERFORM set_config('role', 'authenticated', true);
  UPDATE public.app_settings SET value = '"neon"'::jsonb WHERE key = 'okey_design';
  GET DIAGNOSTICS v_n = ROW_COUNT;
  v_ok := (public.okey_design_config()->>'design') = 'salon';
  IF v_n <> 0 OR NOT v_ok THEN
    RAISE EXCEPTION 'üye ayarı değiştirebildi (% satır)', v_n;
  END IF;
  v_log := v_log || '[7] üye-yazamaz ';

  RAISE EXCEPTION 'TESTS_PASSED %', v_log;
END;
$$;
