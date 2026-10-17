-- Canlı yayın tekrar izleme (20261016000040_live_replays) — canlı doğrulama
-- (kendini geri alır).
--
-- Çalıştırma: supabase db query --linked --file supabase/tests/manual/live_replays_test.sql
-- Başarı = 'TESTS_PASSED ...' istisnası; testin yazdığı her şey geri alınır.
-- Depolama yüklemesi storage.objects'e rol taklidiyle INSERT edilerek sınanır
-- (politikalar aynen çalışır); silme SQL'den yapılamadığı için yalnız yetki
-- fonksiyonu sınanır.

-- Kişi taklidiyle (NULL = misafir) jsonb döndüren sorgu çalıştırır.
CREATE OR REPLACE FUNCTION pg_temp.rx(p_uid uuid, p_sql text)
RETURNS jsonb
LANGUAGE plpgsql
AS $fn$
DECLARE
  r jsonb;
BEGIN
  IF p_uid IS NULL THEN
    PERFORM set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
    EXECUTE 'SET LOCAL ROLE anon';
  ELSE
    PERFORM set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
    EXECUTE 'SET LOCAL ROLE authenticated';
  END IF;
  EXECUTE p_sql INTO r;
  EXECUTE 'RESET ROLE';
  RETURN r;
END;
$fn$;

-- Başarılıysa 'ok', değilse sunucu ipucu (HINT) ya da SQLSTATE.
CREATE OR REPLACE FUNCTION pg_temp.err(p_uid uuid, p_sql text)
RETURNS text
LANGUAGE plpgsql
AS $fn$
DECLARE
  v_hint text;
  v_state text;
BEGIN
  PERFORM pg_temp.rx(p_uid, p_sql);
  RETURN 'ok';
EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS v_hint = PG_EXCEPTION_HINT, v_state = RETURNED_SQLSTATE;
  RETURN COALESCE(NULLIF(v_hint, ''), v_state);
END;
$fn$;

-- Yayıncı adına parça "yükler" (storage.objects INSERT, politikalarla).
CREATE OR REPLACE FUNCTION pg_temp.upload(p_uid uuid, p_name text, p_size bigint DEFAULT 1000)
RETURNS text
LANGUAGE plpgsql
AS $fn$
BEGIN
  RETURN pg_temp.err(p_uid, format(
    'INSERT INTO storage.objects (bucket_id, name, metadata) VALUES (%L, %L, %L::jsonb) RETURNING jsonb_build_object(''n'', name)',
    'live-replays', p_name, json_build_object('size', p_size, 'mimetype', 'video/mp4')::text));
END;
$fn$;

DO $test$
DECLARE
  v_host uuid; v_viewer uuid; v_fan uuid; v_blocked uuid; v_admin uuid;
  v_s uuid; v_s2 uuid; v_s3 uuid;
  v_json jsonb;
  v_r text;
  v_checks integer := 0;
BEGIN
  SELECT p.id INTO v_admin FROM public.profiles p
   WHERE p.role::text = 'admin' AND p.status::text = 'active' ORDER BY p.created_at LIMIT 1;
  SELECT to_jsonb(array_agg(id ORDER BY created_at)) INTO STRICT v_json
    FROM (SELECT p.id, p.created_at FROM public.profiles p
           WHERE p.status::text = 'active' AND NOT COALESCE(p.is_bot, false)
             AND p.role::text <> 'admin'
             AND NOT EXISTS (SELECT 1 FROM public.moderators m WHERE m.user_id = p.id)
             AND NOT EXISTS (SELECT 1 FROM public.shops s WHERE s.owner_id = p.id)
             AND NULLIF(btrim(p.username), '') IS NOT NULL
           ORDER BY p.created_at LIMIT 4) x;
  v_host := (v_json ->> 0)::uuid; v_viewer := (v_json ->> 1)::uuid;
  v_fan := (v_json ->> 2)::uuid; v_blocked := (v_json ->> 3)::uuid;
  IF v_admin IS NULL OR v_blocked IS NULL THEN RAISE EXCEPTION 'test verisi yok'; END IF;

  -- Temiz başlangıç (hepsi geri alınır)
  DELETE FROM public.live_sessions WHERE host_user_id IN (v_host, v_viewer);
  DELETE FROM public.user_live_permissions WHERE user_id = v_host;
  DELETE FROM public.follows WHERE following_id = v_host AND follower_id IN (v_viewer, v_fan, v_blocked);
  DELETE FROM public.blocked_users WHERE (blocker_id = v_host AND blocked_id IN (v_viewer, v_fan, v_blocked))
                                      OR (blocked_id = v_host AND blocker_id IN (v_viewer, v_fan, v_blocked));
  UPDATE public.profiles SET profile_is_public = true WHERE id = v_host;
  INSERT INTO public.follows (follower_id, following_id) VALUES (v_fan, v_host);
  INSERT INTO public.blocked_users (blocker_id, blocked_id) VALUES (v_host, v_blocked);
  INSERT INTO public.app_settings (key, value)
  VALUES ('live_stream_enabled', '"true"'), ('live_user_streams', '"open"'),
         ('live_notify_enabled', '"false"'),
         ('live_replay_enabled', '"true"'), ('live_replay_days', '"30"')
  ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;

  -- [1] canlı yayında kayıt başlar; numara 1'den; izleyici başlatamaz
  v_json := pg_temp.rx(v_host, $q$SELECT public.live_create_user_session('Kayıt testi', NULL)$q$);
  v_s := (v_json ->> 'id')::uuid;
  IF pg_temp.err(v_host, format('SELECT public.live_replay_begin(%L)', v_s)) <> 'LIVE_NOT_LIVE' THEN
    RAISE EXCEPTION '[1] hazırlıktaki yayında kayıt başladı';
  END IF;
  PERFORM pg_temp.rx(v_host, format('SELECT public.start_live_session(%L)', v_s));
  IF pg_temp.err(v_viewer, format('SELECT public.live_replay_begin(%L)', v_s)) <> 'LIVE_NOT_HOST' THEN
    RAISE EXCEPTION '[1] izleyici kaydı başlattı';
  END IF;
  v_json := pg_temp.rx(v_host, format('SELECT public.live_replay_begin(%L)', v_s));
  IF (v_json ->> 'enabled')::boolean IS NOT TRUE OR (v_json ->> 'next_part')::int <> 1
     OR (v_json ->> 'part_seconds')::int <> 180 OR (v_json ->> 'days')::int <> 30 THEN
    RAISE EXCEPTION '[1] begin: %', v_json;
  END IF;
  IF (SELECT replay_state FROM public.live_sessions WHERE id = v_s) <> 'recording' THEN
    RAISE EXCEPTION '[1] durum recording değil';
  END IF;
  v_json := pg_temp.rx(v_host, format('SELECT public.live_session_detail(%L)', v_s));
  IF v_json -> 'replay' ->> 'state' <> 'recording' OR (v_json -> 'replay' ->> 'parts')::int <> 0 THEN
    RAISE EXCEPTION '[1] detail replay: %', v_json -> 'replay';
  END IF;
  v_checks := v_checks + 1;

  -- [2] yükleme politikası: yalnız yayıncı, yalnız biçimdeki yol, 1–999
  IF pg_temp.upload(v_viewer, v_s::text || '/part-0001.mp4') <> '42501' THEN
    RAISE EXCEPTION '[2] izleyici yükledi';
  END IF;
  IF pg_temp.upload(NULL, v_s::text || '/part-0001.mp4') <> '42501' THEN
    RAISE EXCEPTION '[2] misafir yükledi';
  END IF;
  IF pg_temp.upload(v_host, v_s::text || '/kayit.mp4') <> '42501'
     OR pg_temp.upload(v_host, v_s::text || '/part-1000.mp4') <> '42501'
     OR pg_temp.upload(v_host, v_s::text || '/part-0000.mp4') <> '42501'
     OR pg_temp.upload(v_host, upper(v_s::text) || '/part-0001.mp4') <> '42501' THEN
    RAISE EXCEPTION '[2] biçim dışı yol kabul edildi';
  END IF;
  v_r := pg_temp.upload(v_host, v_s::text || '/part-0001.mp4', 12345);
  IF v_r <> 'ok' THEN RAISE EXCEPTION '[2] yayıncı yükleyemedi: %', v_r; END IF;
  v_checks := v_checks + 1;

  -- [3] parça kaydı: depoda olmayan reddedilir, boyut depodan okunur
  IF pg_temp.err(v_host, format('SELECT public.live_replay_add_part(%L, 2, 1000)', v_s)) <> 'LIVE_REPLAY_PART_MISSING' THEN
    RAISE EXCEPTION '[3] depoda olmayan parça kabul edildi';
  END IF;
  IF pg_temp.err(v_host, format('SELECT public.live_replay_add_part(%L, 1, 0)', v_s)) <> 'LIVE_REPLAY_PART_INVALID'
     OR pg_temp.err(v_host, format('SELECT public.live_replay_add_part(%L, 1000, 1000)', v_s)) <> 'LIVE_REPLAY_PART_INVALID' THEN
    RAISE EXCEPTION '[3] geçersiz parça kabul edildi';
  END IF;
  IF pg_temp.err(v_viewer, format('SELECT public.live_replay_add_part(%L, 1, 1000)', v_s)) <> 'LIVE_NOT_HOST' THEN
    RAISE EXCEPTION '[3] izleyici parça ekledi';
  END IF;
  v_json := pg_temp.rx(v_host, format('SELECT public.live_replay_add_part(%L, 1, 180000)', v_s));
  IF (v_json ->> 'parts')::int <> 1 OR (v_json ->> 'duration_ms')::bigint <> 180000
     OR (v_json ->> 'size_bytes')::bigint <> 12345 OR v_json ->> 'state' <> 'recording' THEN
    RAISE EXCEPTION '[3] add_part: %', v_json;
  END IF;
  -- aynı parça yeniden kaydedilirse çift sayılmaz
  v_json := pg_temp.rx(v_host, format('SELECT public.live_replay_add_part(%L, 1, 179000)', v_s));
  IF (v_json ->> 'parts')::int <> 1 OR (v_json ->> 'duration_ms')::bigint <> 179000 THEN
    RAISE EXCEPTION '[3] tekrar kayıt: %', v_json;
  END IF;
  v_checks := v_checks + 1;

  -- [4] yayın sürerken izleyici kaydı göremez; yayıncı görür
  IF pg_temp.rx(v_viewer, format('SELECT public.live_replay_parts(%L)', v_s)) IS NOT NULL
     OR pg_temp.rx(v_viewer, format('SELECT to_jsonb(public.live_replay_object_visible(%L))', v_s::text || '/part-0001.mp4'))::boolean THEN
    RAISE EXCEPTION '[4] canlıyken izleyici kaydı gördü';
  END IF;
  v_json := pg_temp.rx(v_host, format('SELECT public.live_replay_parts(%L)', v_s));
  IF jsonb_array_length(v_json -> 'items') <> 1 THEN RAISE EXCEPTION '[4] yayıncı parçaları: %', v_json; END IF;
  v_checks := v_checks + 1;

  -- [5] yayın bitince 'processing'; misafir ve izleyici izler
  PERFORM pg_temp.rx(v_host, format('SELECT public.end_live_session(%L)', v_s));
  v_json := pg_temp.rx(NULL, format('SELECT public.live_replay_parts(%L)', v_s));
  IF v_json IS NULL OR v_json ->> 'state' <> 'processing' OR jsonb_array_length(v_json -> 'items') <> 1
     OR v_json -> 'items' -> 0 ->> 'path' <> v_s::text || '/part-0001.mp4'
     OR (v_json -> 'items' -> 0 ->> 'duration_ms')::int <> 179000 THEN
    RAISE EXCEPTION '[5] misafir parçaları: %', v_json;
  END IF;
  IF NOT pg_temp.rx(v_viewer, format('SELECT to_jsonb(public.live_replay_object_visible(%L))', v_s::text || '/part-0001.mp4'))::boolean
     OR NOT pg_temp.rx(NULL, format('SELECT to_jsonb(public.live_replay_object_visible(%L))', v_s::text || '/part-0001.mp4'))::boolean THEN
    RAISE EXCEPTION '[5] bitmiş yayının nesnesi görünmüyor';
  END IF;
  -- RLS altında nesne satırı gerçekten seçilebiliyor (imzalı adres bunu ister)
  IF (pg_temp.rx(NULL, format('SELECT to_jsonb(count(*)) FROM storage.objects WHERE bucket_id = %L AND name = %L',
        'live-replays', v_s::text || '/part-0001.mp4')))::int <> 1 THEN
    RAISE EXCEPTION '[5] misafir nesne satırını seçemiyor';
  END IF;
  v_checks := v_checks + 1;

  -- [6] bitişten sonra kalan parça yüklenir; finish → ready; sonra kapalı
  v_r := pg_temp.upload(v_host, v_s::text || '/part-0002.mp4', 5000);
  IF v_r <> 'ok' THEN RAISE EXCEPTION '[6] bitiş sonrası yükleme: %', v_r; END IF;
  v_json := pg_temp.rx(v_host, format('SELECT public.live_replay_add_part(%L, 2, 61000)', v_s));
  IF (v_json ->> 'parts')::int <> 2 OR (v_json ->> 'duration_ms')::bigint <> 240000 OR v_json ->> 'state' <> 'processing' THEN
    RAISE EXCEPTION '[6] ikinci parça: %', v_json;
  END IF;
  IF pg_temp.err(v_viewer, format('SELECT public.live_replay_finish(%L)', v_s)) <> 'LIVE_NOT_HOST' THEN
    RAISE EXCEPTION '[6] izleyici bitirdi';
  END IF;
  v_json := pg_temp.rx(v_host, format('SELECT public.live_replay_finish(%L)', v_s));
  IF v_json ->> 'state' <> 'ready' OR v_json ->> 'expires_at' IS NULL THEN
    RAISE EXCEPTION '[6] finish: %', v_json;
  END IF;
  IF pg_temp.upload(v_host, v_s::text || '/part-0003.mp4') <> '42501' THEN
    RAISE EXCEPTION '[6] hazır kayda yükleme kabul edildi';
  END IF;
  IF pg_temp.err(v_host, format('SELECT public.live_replay_add_part(%L, 2, 1000)', v_s)) <> 'LIVE_REPLAY_CLOSED' THEN
    RAISE EXCEPTION '[6] hazır kayda parça eklendi';
  END IF;
  v_checks := v_checks + 1;

  -- [7] listeler kaydı taşır (geçmiş, ayrıntı, Yayınlarım, ana sayfa kartı)
  v_json := pg_temp.rx(NULL, 'SELECT public.live_history(50, 0, NULL)');
  SELECT e INTO v_json FROM jsonb_array_elements(v_json -> 'rows') e WHERE (e ->> 'id')::uuid = v_s;
  IF v_json IS NULL OR v_json -> 'replay' ->> 'state' <> 'ready' OR (v_json -> 'replay' ->> 'parts')::int <> 2 THEN
    RAISE EXCEPTION '[7] geçmiş: %', v_json -> 'replay';
  END IF;
  v_json := pg_temp.rx(v_host, 'SELECT public.live_my_history(20, 0)');
  IF v_json -> 'rows' -> 0 -> 'replay' ->> 'state' <> 'ready' THEN RAISE EXCEPTION '[7] yayınlarım: %', v_json; END IF;
  v_json := pg_temp.rx(v_viewer, format('SELECT public.live_session_detail(%L)', v_s));
  IF (v_json -> 'replay' ->> 'duration_ms')::bigint <> 240000 THEN RAISE EXCEPTION '[7] ayrıntı: %', v_json -> 'replay'; END IF;
  v_checks := v_checks + 1;

  -- [8] gizli hesap: takipçi olmayan göremez, takipçi görür; engellenen hiç
  UPDATE public.profiles SET profile_is_public = false WHERE id = v_host;
  IF pg_temp.rx(v_viewer, format('SELECT public.live_replay_parts(%L)', v_s)) IS NOT NULL
     OR pg_temp.rx(NULL, format('SELECT public.live_replay_parts(%L)', v_s)) IS NOT NULL
     OR (pg_temp.rx(v_viewer, format('SELECT to_jsonb(count(*)) FROM storage.objects WHERE bucket_id = %L AND name LIKE %L',
           'live-replays', v_s::text || '/%')))::int <> 0 THEN
    RAISE EXCEPTION '[8] gizli hesabın kaydı takipçi olmayana göründü';
  END IF;
  IF pg_temp.rx(v_fan, format('SELECT public.live_replay_parts(%L)', v_s)) IS NULL THEN
    RAISE EXCEPTION '[8] takipçi gizli hesabın kaydını göremedi';
  END IF;
  UPDATE public.profiles SET profile_is_public = true WHERE id = v_host;
  IF pg_temp.rx(v_blocked, format('SELECT public.live_replay_parts(%L)', v_s)) IS NOT NULL
     OR pg_temp.rx(v_blocked, format('SELECT to_jsonb(public.live_replay_object_visible(%L))', v_s::text || '/part-0001.mp4'))::boolean THEN
    RAISE EXCEPTION '[8] engellenen kaydı gördü';
  END IF;
  v_checks := v_checks + 1;

  -- [9] silme: izleyici silemez; yayıncı siler → izlenemez, yollar döner
  IF pg_temp.err(v_viewer, format('SELECT public.live_replay_delete(%L)', v_s)) <> 'LIVE_NOT_HOST' THEN
    RAISE EXCEPTION '[9] izleyici sildi';
  END IF;
  IF NOT pg_temp.rx(v_host, format('SELECT to_jsonb(public.live_replay_delete_allowed(%L))', v_s::text || '/part-0001.mp4'))::boolean
     OR NOT pg_temp.rx(v_admin, format('SELECT to_jsonb(public.live_replay_delete_allowed(%L))', v_s::text || '/part-0001.mp4'))::boolean
     OR pg_temp.rx(v_viewer, format('SELECT to_jsonb(public.live_replay_delete_allowed(%L))', v_s::text || '/part-0001.mp4'))::boolean THEN
    RAISE EXCEPTION '[9] silme yetkisi';
  END IF;
  v_json := pg_temp.rx(v_host, format('SELECT public.live_replay_delete(%L)', v_s));
  IF v_json -> 'replay' ->> 'state' <> 'deleted' OR v_json -> 'replay' ->> 'deleted_reason' <> 'host'
     OR jsonb_array_length(v_json -> 'paths') <> 2 THEN
    RAISE EXCEPTION '[9] delete: %', v_json;
  END IF;
  IF pg_temp.rx(v_host, format('SELECT public.live_replay_parts(%L)', v_s)) IS NOT NULL
     OR EXISTS (SELECT 1 FROM public.live_replay_parts WHERE session_id = v_s) THEN
    RAISE EXCEPTION '[9] silinen kayıt hâlâ izlenebilir';
  END IF;
  v_json := public.live_replay_cleanup_batch(1000);
  IF NOT (v_json -> 'paths') @> to_jsonb(ARRAY[v_s::text || '/part-0001.mp4', v_s::text || '/part-0002.mp4']) THEN
    RAISE EXCEPTION '[9] temizlik silinen kaydın dosyalarını vermedi: %', v_json;
  END IF;
  v_checks := v_checks + 1;

  -- [10] saklama süresi: dolunca 'expired' → temizlikte 'deleted' (expired)
  INSERT INTO public.live_sessions (host_user_id, shop_id, title, channel_name, status, started_at, ended_at,
                                    ended_reason, replay_state, replay_parts, replay_duration_ms)
  VALUES (v_host, NULL, 'Eski kayıt', 'cz_' || md5(random()::text), 'ended',
          now() - interval '31 days 1 hour', now() - interval '31 days', 'host', 'ready', 1, 60000)
  RETURNING id INTO v_s2;
  INSERT INTO public.live_replay_parts (session_id, part_no, object_path, duration_ms)
  VALUES (v_s2, 1, private.live_replay_part_path(v_s2, 1), 60000);
  v_json := pg_temp.rx(v_host, format('SELECT public.live_session_detail(%L)', v_s2));
  IF v_json -> 'replay' ->> 'state' <> 'expired' OR (v_json -> 'replay' ->> 'parts')::int <> 0 THEN
    RAISE EXCEPTION '[10] süresi dolan: %', v_json -> 'replay';
  END IF;
  IF pg_temp.rx(v_viewer, format('SELECT public.live_replay_parts(%L)', v_s2)) IS NOT NULL THEN
    RAISE EXCEPTION '[10] süresi dolan kayıt izleyiciye açık';
  END IF;
  PERFORM public.live_replay_cleanup_batch(10);
  IF (SELECT replay_state || '/' || replay_deleted_reason FROM public.live_sessions WHERE id = v_s2) <> 'deleted/expired'
     OR EXISTS (SELECT 1 FROM public.live_replay_parts WHERE session_id = v_s2) THEN
    RAISE EXCEPTION '[10] temizlik süresi dolanı silmedi';
  END IF;
  v_checks := v_checks + 1;

  -- [11] 7 gün yükleme penceresi kapanınca 'recording' kayıt sonlanır
  UPDATE public.live_sessions
     SET replay_state = 'recording', replay_parts = 1, replay_deleted_at = NULL, replay_deleted_reason = NULL,
         started_at = now() - interval '8 days 1 hour', ended_at = now() - interval '8 days'
   WHERE id = v_s2;
  PERFORM public.live_replay_cleanup_batch(10);
  IF (SELECT replay_state FROM public.live_sessions WHERE id = v_s2) <> 'ready' THEN
    RAISE EXCEPTION '[11] bayat kayıt sonlanmadı';
  END IF;
  v_checks := v_checks + 1;

  -- [12] yönetici: kayıt kapalıysa yeni yayın kaydedilmez; gün sınırı 1–365
  IF pg_temp.err(v_host, $q$SELECT public.admin_set_live_options('{"replay_enabled": false}'::jsonb)$q$) <> '42501' THEN
    RAISE EXCEPTION '[12] yönetici olmayan ayar değiştirdi';
  END IF;
  v_json := pg_temp.rx(v_admin, $q$SELECT public.admin_set_live_options('{"replay_enabled": false, "replay_days": 900}'::jsonb)$q$);
  IF (v_json ->> 'replay_enabled')::boolean OR (v_json ->> 'replay_days')::int <> 365
     OR v_json -> 'stats' -> 'replays' IS NULL OR v_json -> 'stats' -> 'replay_size_bytes' IS NULL THEN
    RAISE EXCEPTION '[12] ayar: %', v_json;
  END IF;
  v_json := pg_temp.rx(v_host, $q$SELECT public.live_create_user_session('Kayıtsız yayın', NULL)$q$);
  v_s3 := (v_json ->> 'id')::uuid;
  PERFORM pg_temp.rx(v_host, format('SELECT public.start_live_session(%L)', v_s3));
  v_json := pg_temp.rx(v_host, format('SELECT public.live_replay_begin(%L)', v_s3));
  IF (v_json ->> 'enabled')::boolean OR v_json ->> 'reason' <> 'disabled'
     OR (SELECT replay_state FROM public.live_sessions WHERE id = v_s3) IS NOT NULL THEN
    RAISE EXCEPTION '[12] kapalıyken kayıt başladı: %', v_json;
  END IF;
  IF pg_temp.upload(v_host, v_s3::text || '/part-0001.mp4') <> '42501' THEN
    RAISE EXCEPTION '[12] kayıtsız yayına yükleme kabul edildi';
  END IF;
  v_json := pg_temp.rx(NULL, format('SELECT public.live_session_detail(%L)', v_s3));
  IF v_json ? 'replay' AND jsonb_typeof(v_json -> 'replay') <> 'null' THEN
    RAISE EXCEPTION '[12] kayıtsız yayında replay: %', v_json -> 'replay';
  END IF;
  IF pg_temp.err(v_admin, format('SELECT public.live_replay_delete(%L)', v_s3)) <> 'LIVE_REPLAY_NOT_ENDED' THEN
    RAISE EXCEPTION '[12] süren yayının kaydı silindi';
  END IF;
  v_checks := v_checks + 1;

  -- [13] yetkiler
  IF has_function_privilege('anon', 'public.live_replay_begin(uuid)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.live_replay_add_part(uuid, integer, integer)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.live_replay_finish(uuid)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.live_replay_delete(uuid)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.live_replay_cleanup_batch(integer)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.live_replay_cleanup_batch(integer)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.live_replay_cleanup_batch(integer)', 'EXECUTE')
     OR NOT has_function_privilege('anon', 'public.live_replay_parts(uuid)', 'EXECUTE')
     OR NOT has_function_privilege('anon', 'public.live_replay_object_visible(text)', 'EXECUTE')
     OR has_table_privilege('authenticated', 'public.live_replay_parts', 'SELECT')
     OR has_table_privilege('anon', 'public.live_replay_parts', 'SELECT') THEN
    RAISE EXCEPTION '[13] yetkiler yanlış';
  END IF;
  v_checks := v_checks + 1;

  RAISE EXCEPTION 'TESTS_PASSED live_replays %/13', v_checks;
END;
$test$;
