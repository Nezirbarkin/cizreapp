BEGIN;
DO $$
DECLARE
  v_admin uuid; v_user uuid; v_room public.okey_rooms%ROWTYPE; v_n int;
BEGIN
  SELECT id INTO v_admin FROM public.profiles WHERE role::text='admin' LIMIT 1;
  IF v_admin IS NULL THEN RAISE EXCEPTION 'TEST_SKIP: admin yok'; END IF;
  SELECT id INTO v_user FROM public.profiles WHERE role::text<>'admin' LIMIT 1;

  -- [1] Admin olmayan admin_okey_overview cagirinca bos donmeli
  PERFORM set_config('request.jwt.claim.sub', v_user::text, true);
  SELECT count(*) INTO v_n FROM public.admin_okey_overview();
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'TEST_FAIL[1]: admin olmayan masalari gorebiliyor!';
  END IF;
  RAISE NOTICE 'TEST_OK[1]: admin_okey_overview admin olmayana bos donuyor';

  -- [2] Admin olmayan ayar degistiremez
  BEGIN
    PERFORM public.admin_okey_update_settings(202, 30);
    RAISE EXCEPTION 'TEST_FAIL[2]: admin olmayan ayar degistirebildi!';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE 'APP:forbidden%' THEN RAISE; END IF;
  END;
  RAISE NOTICE 'TEST_OK[2]: ayar degisimi admin ile sinirli';

  -- [3] Admin olmayan ses yukleyemez
  BEGIN
    PERFORM public.admin_okey_set_sound('laugh','x/y.mp3','https://x/y.mp3');
    RAISE EXCEPTION 'TEST_FAIL[3]: admin olmayan ses ekleyebildi!';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE 'APP:forbidden%' THEN RAISE; END IF;
  END;
  RAISE NOTICE 'TEST_OK[3]: ses yukleme admin ile sinirli';

  -- [4] Admin ses ekleyip silebilir, herkes okuyabilir
  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
  PERFORM public.admin_okey_set_sound('laugh','laugh/1.mp3','https://ornek/laugh.mp3');
  SELECT count(*) INTO v_n FROM public.okey_sound_assets WHERE sound_key='laugh';
  IF v_n <> 1 THEN RAISE EXCEPTION 'TEST_FAIL[4]: ses kaydedilmedi'; END IF;
  RAISE NOTICE 'TEST_OK[4]: admin ses ekledi';

  -- [5] Yasak: yasakli kullanici oda kuramaz
  PERFORM public.admin_okey_set_ban(v_user, 'test', NULL);
  PERFORM set_config('request.jwt.claim.sub', v_user::text, true);
  BEGIN
    PERFORM public.create_okey_room(false,'katlamasiz','essiz','yardimli');
    RAISE EXCEPTION 'TEST_FAIL[5]: yasakli kullanici oda kurabildi!';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE 'APP:okey_banned%' THEN RAISE; END IF;
  END;
  RAISE NOTICE 'TEST_OK[5]: yasakli kullanici oda kuramiyor';

  -- [6] Yasak kalkinca tekrar kurabilir
  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
  PERFORM public.admin_okey_remove_ban(v_user);
  PERFORM set_config('request.jwt.claim.sub', v_user::text, true);
  SELECT * INTO v_room FROM public.create_okey_room(false,'katlamasiz','essiz','yardimli');
  IF v_room.id IS NULL THEN RAISE EXCEPTION 'TEST_FAIL[6]: yasak kalkinca kuramadi'; END IF;
  RAISE NOTICE 'TEST_OK[6]: yasak kalkinca tekrar kurabiliyor';

  -- [7] Admin masayi gorebiliyor ve oyuncu atabiliyor
  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);
  SELECT count(*) INTO v_n FROM public.admin_okey_overview();
  IF v_n < 1 THEN RAISE EXCEPTION 'TEST_FAIL[7]: admin masayi goremiyor'; END IF;
  PERFORM public.admin_okey_kick_player(v_room.id, 0::smallint);
  SELECT count(*) INTO v_n FROM public.okey_room_players
    WHERE room_id=v_room.id AND seat_no=0 AND is_bot AND user_id IS NULL;
  IF v_n <> 1 THEN RAISE EXCEPTION 'TEST_FAIL[7]: kick sonrasi koltuk bota devredilmedi'; END IF;
  RAISE NOTICE 'TEST_OK[7]: admin masayi gorup oyuncu atabiliyor (koltuk bota devredildi)';

  RAISE NOTICE 'TUM_ADMIN_TESTLERI_GECTI';
END;
$$;
ROLLBACK;
