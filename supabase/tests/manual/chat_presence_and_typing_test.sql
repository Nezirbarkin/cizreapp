-- =============================================================================
-- Sohbet & profil: SON GÖRÜLME / ÇEVRİMİÇİ / YAZIYOR — sunucu kuralları testi
--   supabase db query --linked --file supabase/tests/manual/chat_presence_and_typing_test.sql
--
-- Önkoşul: 20260921000008_chat_presence_and_typing.sql uygulanmış olmalı.
--
-- Neyi kanıtlar (hepsi SUNUCUDA; istemci ne çizerse çizsin):
--   [T0]  görünümlerin şekli (sütun adı/sırası) ve security_invoker korunmuş
--   [T1-2] görüntüleyici çevrimiçi / çevrimdışı durumu görür
--   [T3]  SON GÖRÜLME admin'in günden (7) eskiyse HİÇ dönmez; gün ayarı
--         değişince sınır kayar; bozuk/aralık dışı ayar 7'ye düşer
--   [T4]  show_last_seen=false → son görülme gizli, çevrimiçi hâlâ görünür
--   [T5]  "yalnız arkadaşlar": tek yönlü takip yetmez, karşılıklı gerekir
--   [T6]  Hayalet modu → çevrimiçi de son görülme de gizli
--   [T7]  "çevrimiçi görünme" kapalı → rozet gizli; aktifken son görülme de
--         gizli (kendini ele vermez), sonra görünür
--   [T8]  engel (iki yönde) → her şey gizli
--   [T9]  gizli hesap → takip etmeyen görmez
--   [T10] admin anahtarları: ana / bağlam (sohbet|profil) / çevrimiçi; bozuk değer
--   [T11] anon hiçbir şey görmez ve görünüm anon'a hâlâ açık (hata vermez)
--   [T12] kişi kendi durumunu görür
--   [T13] görünümler MASKELİ döner (eski istemciler de korunur)
--   [T14] get_online_users gizli/engelli/hayalet kişiyi dönmez
--   [T15] get_user_presence: toplu, tekrarsız, bilinmeyen kimlik yok sayılır
--   [T16] yazıyor kanalı: iki yönde AYNI, başka çiftte FARKLI, engel/kapalı/
--         kendisi → NULL, grup yalnız üyeye, anon çağıramaz
--   [T17] update_my_chat_privacy: yalnız kendi satırı, last_seen'e dokunmaz
--   [T18] admin RPC'leri: doğrulama, yetki, özet
--   [T19] iç yardımcılara dışarıdan erişilemez
--
-- ## Nasıl okunur
--
-- Betik TEK bir DO bloğudur ve SONUNDA bilerek istisna fırlatır: istisna tüm
-- değişiklikleri geri alır (canlı veriye dokunulmaz) ve mesajı sonucu taşır.
--
--   BAŞARILI:  "TESTS_PASSED ..." ile başlayan bir hata mesajı
--   BAŞARISIZ: "TEST_FAIL[x]: ..." ile başlayan bir hata mesajı
--
-- Denekler bot vitrin hesaplarıdır (gerçek kullanıcıya dokunulmaz); zaten her şey
-- geri alınır.
-- =============================================================================

CREATE OR REPLACE FUNCTION pg_temp.ok(p_cond boolean, p_label text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF p_cond IS NOT TRUE THEN
    RAISE EXCEPTION 'TEST_FAIL[%]', p_label;
  END IF;
  PERFORM set_config('t.n', (COALESCE(NULLIF(current_setting('t.n', true), ''), '0')::int + 1)::text, true);
END $$;

CREATE OR REPLACE FUNCTION pg_temp.as_user(p_user uuid)
RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claim.sub', COALESCE(p_user::text, ''), true)
$$;

-- Görüntüleyici p_viewer iken çözümleyici sonucu.
CREATE OR REPLACE FUNCTION pg_temp.pr(p_viewer uuid, p_target uuid, p_ctx text DEFAULT 'chat')
RETURNS TABLE (can_see_online boolean, online boolean, last_seen timestamptz)
LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', COALESCE(p_viewer::text, ''), true);
  RETURN QUERY
    SELECT r.can_see_online, r.online, r.last_seen
    FROM public.presence_resolve(p_target, p_ctx) r;
END $$;

-- Hedefin durumunu kurar. is_online değişince trigger last_seen'i now() yapar;
-- bu yüzden last_seen ikinci bir UPDATE ile yazılır.
CREATE OR REPLACE FUNCTION pg_temp.set_t(
  p_id uuid, p_online boolean, p_seen timestamptz,
  p_ghost boolean DEFAULT false, p_pref boolean DEFAULT true, p_show boolean DEFAULT true,
  p_friends boolean DEFAULT false, p_public boolean DEFAULT true
) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  UPDATE public.profiles
     SET is_online = p_online, is_ghost_mode = p_ghost, is_online_enabled = p_pref,
         show_last_seen = p_show, last_seen_friends_only = p_friends,
         profile_is_public = p_public
   WHERE id = p_id;
  UPDATE public.profiles SET last_seen = p_seen WHERE id = p_id;
END $$;

CREATE OR REPLACE FUNCTION pg_temp.clean(p_a uuid, p_b uuid)
RETURNS void LANGUAGE sql AS $$
  DELETE FROM public.follows
   WHERE (follower_id = p_a AND following_id = p_b) OR (follower_id = p_b AND following_id = p_a);
  DELETE FROM public.blocked_users
   WHERE (blocker_id = p_a AND blocked_id = p_b) OR (blocker_id = p_b AND blocked_id = p_a);
$$;

CREATE OR REPLACE FUNCTION pg_temp.follow(p_a uuid, p_b uuid)
RETURNS void LANGUAGE sql AS $$
  INSERT INTO public.follows (follower_id, following_id) VALUES (p_a, p_b) ON CONFLICT DO NOTHING
$$;

CREATE OR REPLACE FUNCTION pg_temp.unfollow(p_a uuid, p_b uuid)
RETURNS void LANGUAGE sql AS $$
  DELETE FROM public.follows WHERE follower_id = p_a AND following_id = p_b
$$;

CREATE OR REPLACE FUNCTION pg_temp.block(p_blocker uuid, p_blocked uuid)
RETURNS void LANGUAGE sql AS $$
  INSERT INTO public.blocked_users (blocker_id, blocked_id) VALUES (p_blocker, p_blocked)
$$;

CREATE OR REPLACE FUNCTION pg_temp.setting(p_key text, p_json text)
RETURNS void LANGUAGE sql AS $$
  INSERT INTO public.app_settings (key, value) VALUES (p_key, p_json::jsonb)
  ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value
$$;

DO $test$
DECLARE
  v_ids uuid[];
  a uuid; b uuid; c uuid; d uuid;          -- a: hedef, b: görüntüleyici, c/d: diğerleri
  v_admin uuid;
  r record;
  v_txt text;
  v_topic_ab text; v_topic_ba text; v_topic_ac text;
  v_j jsonb;
  v_n bigint; v_n2 bigint;
  v_gid uuid; v_gm uuid;
  v_before timestamptz; v_after timestamptz;
  v_skipped text := '';
BEGIN
  SELECT array_agg(id) INTO v_ids
  FROM (SELECT id FROM public.profiles WHERE is_bot = true ORDER BY id LIMIT 4) s;
  IF COALESCE(array_length(v_ids, 1), 0) < 4 THEN
    RAISE EXCEPTION 'TEST_FAIL[setup]: en az 4 bot profili gerekli';
  END IF;
  a := v_ids[1]; b := v_ids[2]; c := v_ids[3]; d := v_ids[4];

  -- Canlı ayarlardan bağımsız: bilinen taban.
  PERFORM pg_temp.setting('chat_presence_last_seen_enabled', '"true"');
  PERFORM pg_temp.setting('chat_presence_last_seen_in_chat', '"true"');
  PERFORM pg_temp.setting('chat_presence_last_seen_in_profile', '"true"');
  PERFORM pg_temp.setting('chat_presence_last_seen_max_days', '"7"');
  PERFORM pg_temp.setting('chat_presence_online_enabled', '"true"');
  PERFORM pg_temp.setting('chat_presence_typing_enabled', '"true"');
  PERFORM pg_temp.setting('chat_presence_typing_in_groups', '"true"');
  PERFORM pg_temp.clean(a, b); PERFORM pg_temp.clean(a, c); PERFORM pg_temp.clean(b, c);

  -- ---------------------------------------------------------------- [T0] şekil
  SELECT string_agg(x.attname, ',' ORDER BY x.attnum) INTO v_txt
  FROM pg_attribute x
  WHERE x.attrelid = 'public.public_profiles_chat'::regclass AND x.attnum > 0 AND NOT x.attisdropped;
  PERFORM pg_temp.ok(v_txt = 'id,username,full_name,avatar_url,messages_enabled,is_online,last_seen,is_ghost_mode,created_at,bio',
    'T0a public_profiles_chat sütunları/sırası: ' || v_txt);
  SELECT string_agg(x.attname, ',' ORDER BY x.attnum) INTO v_txt
  FROM pg_attribute x
  WHERE x.attrelid = 'public.public_profiles_safe'::regclass AND x.attnum > 0 AND NOT x.attisdropped;
  PERFORM pg_temp.ok(v_txt = 'id,username,full_name,avatar_url,cover_url,bio,website,location,gender,profile_is_public,created_at,updated_at,last_seen,status,is_ghost_mode',
    'T0b public_profiles_safe sütunları/sırası: ' || v_txt);
  PERFORM pg_temp.ok(
    (SELECT c2.reloptions::text FROM pg_class c2 WHERE c2.oid = 'public.public_profiles_chat'::regclass) LIKE '%security_invoker=true%',
    'T0c public_profiles_chat security_invoker korunmalı');
  PERFORM pg_temp.ok(
    (SELECT c2.reloptions::text FROM pg_class c2 WHERE c2.oid = 'public.public_profiles_safe'::regclass) LIKE '%security_invoker=true%',
    'T0d public_profiles_safe security_invoker korunmalı');

  -- ------------------------------------------------ [T1] çevrimiçi görünür
  PERFORM pg_temp.set_t(a, true, now());
  SELECT * INTO r FROM pg_temp.pr(b, a);
  PERFORM pg_temp.ok(r.can_see_online AND r.online AND r.last_seen IS NOT NULL, 'T1 çevrimiçi kişi görünür');

  -- ------------------------------------- [T2] çevrimdışı: son görülme görünür
  PERFORM pg_temp.set_t(a, false, now() - interval '10 minutes');
  SELECT * INTO r FROM pg_temp.pr(b, a);
  PERFORM pg_temp.ok(r.can_see_online AND NOT r.online AND r.last_seen = now() - interval '10 minutes',
    'T2 çevrimdışı kişinin son görülmesi dönmeli');
  -- Bayat is_online=true (uygulama öldürülmüş): 3 dk'dan eski nabız çevrimiçi sayılmaz
  PERFORM pg_temp.set_t(a, true, now() - interval '10 minutes');
  SELECT * INTO r FROM pg_temp.pr(b, a);
  PERFORM pg_temp.ok(NOT r.online AND r.last_seen IS NOT NULL, 'T2b bayat nabız çevrimiçi sayılmaz');

  -- ------------------------------------------ [T3] 7 gün sınırı ve ayarı
  PERFORM pg_temp.set_t(a, false, now() - interval '8 days');
  SELECT * INTO r FROM pg_temp.pr(b, a);
  PERFORM pg_temp.ok(r.last_seen IS NULL, 'T3a 8 günlük son görülme GİZLİ (7 gün sınırı)');
  PERFORM pg_temp.ok(r.can_see_online, 'T3a2 sınır çevrimiçi iznini etkilemez');
  PERFORM pg_temp.set_t(a, false, now() - interval '6 days 23 hours');
  SELECT * INTO r FROM pg_temp.pr(b, a);
  PERFORM pg_temp.ok(r.last_seen IS NOT NULL, 'T3b 6 gün 23 saatlik son görülme görünür');
  PERFORM pg_temp.setting('chat_presence_last_seen_max_days', '"30"');
  PERFORM pg_temp.set_t(a, false, now() - interval '8 days');
  SELECT * INTO r FROM pg_temp.pr(b, a);
  PERFORM pg_temp.ok(r.last_seen IS NOT NULL, 'T3c gün ayarı 30 iken 8 günlük görünür');
  PERFORM pg_temp.setting('chat_presence_last_seen_max_days', '"3"');
  PERFORM pg_temp.set_t(a, false, now() - interval '5 days');
  SELECT * INTO r FROM pg_temp.pr(b, a);
  PERFORM pg_temp.ok(r.last_seen IS NULL, 'T3d gün ayarı 3 iken 5 günlük gizli');
  -- Bozuk / aralık dışı ayar varsayılan 7'ye düşer (yanlış yazımla özellik kapanmaz)
  FOREACH v_txt IN ARRAY ARRAY['"abc"', '"0"', '"999"', '"-4"', '""', 'null'] LOOP
    PERFORM pg_temp.setting('chat_presence_last_seen_max_days', v_txt);
    PERFORM pg_temp.set_t(a, false, now() - interval '6 days');
    SELECT * INTO r FROM pg_temp.pr(b, a);
    PERFORM pg_temp.ok(r.last_seen IS NOT NULL, 'T3e bozuk gün ayarı ' || v_txt || ' → 7 gün (6 günlük görünür)');
    PERFORM pg_temp.set_t(a, false, now() - interval '8 days');
    SELECT * INTO r FROM pg_temp.pr(b, a);
    PERFORM pg_temp.ok(r.last_seen IS NULL, 'T3e bozuk gün ayarı ' || v_txt || ' → 7 gün (8 günlük gizli)');
  END LOOP;
  PERFORM pg_temp.setting('chat_presence_last_seen_max_days', '"7"');

  -- ------------------------------------- [T4] show_last_seen=false
  PERFORM pg_temp.set_t(a, false, now() - interval '10 minutes', p_show => false);
  SELECT * INTO r FROM pg_temp.pr(b, a);
  PERFORM pg_temp.ok(r.last_seen IS NULL AND r.can_see_online, 'T4 son görülme kapalı: gizli, çevrimiçi izni açık');
  PERFORM pg_temp.set_t(a, true, now(), p_show => false);
  SELECT * INTO r FROM pg_temp.pr(b, a);
  PERFORM pg_temp.ok(r.online, 'T4b son görülmesi kapalı biri çevrimiçiyken yine "çevrimiçi" görünür');

  -- ------------------------------------- [T5] yalnız arkadaşlar
  PERFORM pg_temp.set_t(a, false, now() - interval '10 minutes', p_friends => true);
  SELECT * INTO r FROM pg_temp.pr(b, a);
  PERFORM pg_temp.ok(r.last_seen IS NULL, 'T5a arkadaş değil → gizli');
  PERFORM pg_temp.follow(b, a);
  SELECT * INTO r FROM pg_temp.pr(b, a);
  PERFORM pg_temp.ok(r.last_seen IS NULL, 'T5b yalnız görüntüleyici takip ediyor → hâlâ gizli');
  PERFORM pg_temp.follow(a, b);
  SELECT * INTO r FROM pg_temp.pr(b, a);
  PERFORM pg_temp.ok(r.last_seen IS NOT NULL, 'T5c karşılıklı takip → görünür');
  PERFORM pg_temp.unfollow(b, a);
  SELECT * INTO r FROM pg_temp.pr(b, a);
  PERFORM pg_temp.ok(r.last_seen IS NULL, 'T5d yalnız hedef takip ediyor → gizli');
  PERFORM pg_temp.ok(r.can_see_online, 'T5e arkadaşlık kısıtı çevrimiçi iznini etkilemez');
  PERFORM pg_temp.clean(a, b);

  -- ------------------------------------- [T6] hayalet modu
  PERFORM pg_temp.set_t(a, true, now(), p_ghost => true);
  SELECT * INTO r FROM pg_temp.pr(b, a);
  PERFORM pg_temp.ok(NOT r.can_see_online AND NOT r.online AND r.last_seen IS NULL, 'T6a hayalet: hiçbir şey görünmez');
  PERFORM pg_temp.set_t(a, false, now() - interval '10 minutes', p_ghost => true);
  SELECT * INTO r FROM pg_temp.pr(b, a);
  PERFORM pg_temp.ok(r.last_seen IS NULL, 'T6b hayalet: son görülme de gizli');

  -- ------------------------------------- [T7] "çevrimiçi görünme" kapalı
  PERFORM pg_temp.set_t(a, true, now(), p_pref => false);
  SELECT * INTO r FROM pg_temp.pr(b, a);
  PERFORM pg_temp.ok(NOT r.can_see_online AND NOT r.online, 'T7a çevrimiçi görünme kapalı: rozet yok');
  PERFORM pg_temp.ok(r.last_seen IS NULL, 'T7b aktifken son görülme de gizli (kendini ele vermez)');
  PERFORM pg_temp.set_t(a, false, now() - interval '1 minute', p_pref => false);
  SELECT * INTO r FROM pg_temp.pr(b, a);
  PERFORM pg_temp.ok(r.last_seen IS NULL, 'T7c 1 dk önce = hâlâ taze nabız → gizli');
  PERFORM pg_temp.set_t(a, false, now() - interval '10 minutes', p_pref => false);
  SELECT * INTO r FROM pg_temp.pr(b, a);
  PERFORM pg_temp.ok(r.last_seen IS NOT NULL AND NOT r.can_see_online, 'T7d 10 dk sonra son görülme görünür, rozet yine yok');

  -- ------------------------------------- [T8] engel (iki yönde)
  PERFORM pg_temp.set_t(a, true, now());
  PERFORM pg_temp.block(a, b);
  SELECT * INTO r FROM pg_temp.pr(b, a);
  PERFORM pg_temp.ok(NOT r.can_see_online AND NOT r.online AND r.last_seen IS NULL, 'T8a hedef görüntüleyiciyi engellemiş → gizli');
  PERFORM pg_temp.clean(a, b);
  PERFORM pg_temp.block(b, a);
  SELECT * INTO r FROM pg_temp.pr(b, a);
  PERFORM pg_temp.ok(NOT r.can_see_online AND NOT r.online AND r.last_seen IS NULL, 'T8b görüntüleyici hedefi engellemiş → gizli');
  SELECT * INTO r FROM pg_temp.pr(c, a);
  PERFORM pg_temp.ok(r.can_see_online AND r.online, 'T8c engel yalnız o çifti etkiler');
  PERFORM pg_temp.clean(a, b);

  -- ------------------------------------- [T9] gizli hesap
  PERFORM pg_temp.set_t(a, true, now(), p_public => false);
  SELECT * INTO r FROM pg_temp.pr(b, a);
  PERFORM pg_temp.ok(NOT r.can_see_online AND NOT r.online AND r.last_seen IS NULL, 'T9a gizli hesap, takip yok → gizli');
  PERFORM pg_temp.follow(b, a);
  SELECT * INTO r FROM pg_temp.pr(b, a);
  PERFORM pg_temp.ok(r.can_see_online AND r.online, 'T9b gizli hesabı takip eden görür');
  PERFORM pg_temp.clean(a, b);

  -- ------------------------------------- [T10] admin anahtarları
  PERFORM pg_temp.set_t(a, false, now() - interval '10 minutes');
  PERFORM pg_temp.setting('chat_presence_last_seen_enabled', '"false"');
  SELECT * INTO r FROM pg_temp.pr(b, a);
  PERFORM pg_temp.ok(r.last_seen IS NULL AND r.can_see_online, 'T10a ana anahtar kapalı: son görülme hiçbir yerde yok');
  PERFORM pg_temp.setting('chat_presence_last_seen_enabled', '"true"');
  PERFORM pg_temp.setting('chat_presence_last_seen_in_chat', '"false"');
  SELECT * INTO r FROM pg_temp.pr(b, a, 'chat');
  PERFORM pg_temp.ok(r.last_seen IS NULL, 'T10b "sohbette göster" kapalı → sohbet bağlamında yok');
  SELECT * INTO r FROM pg_temp.pr(b, a, 'list');
  PERFORM pg_temp.ok(r.last_seen IS NULL, 'T10b2 liste bağlamı sohbet gibi davranır');
  SELECT * INTO r FROM pg_temp.pr(b, a, 'profile');
  PERFORM pg_temp.ok(r.last_seen IS NOT NULL, 'T10c ...ama profil bağlamında var');
  PERFORM pg_temp.setting('chat_presence_last_seen_in_chat', '"true"');
  PERFORM pg_temp.setting('chat_presence_last_seen_in_profile', '"false"');
  SELECT * INTO r FROM pg_temp.pr(b, a, 'profile');
  PERFORM pg_temp.ok(r.last_seen IS NULL, 'T10d "profilde göster" kapalı → profil bağlamında yok');
  SELECT * INTO r FROM pg_temp.pr(b, a, 'chat');
  PERFORM pg_temp.ok(r.last_seen IS NOT NULL, 'T10e ...ama sohbet bağlamında var');
  PERFORM pg_temp.setting('chat_presence_last_seen_in_profile', '"true"');
  PERFORM pg_temp.set_t(a, true, now());
  PERFORM pg_temp.setting('chat_presence_online_enabled', '"false"');
  SELECT * INTO r FROM pg_temp.pr(b, a);
  PERFORM pg_temp.ok(NOT r.can_see_online AND NOT r.online, 'T10f çevrimiçi özelliği kapalı → rozet yok');
  PERFORM pg_temp.setting('chat_presence_online_enabled', '"true"');
  -- Bozuk bayrak değeri özelliği KAPATMAZ (varsayılan açık)
  PERFORM pg_temp.setting('chat_presence_online_enabled', '"garbage"');
  SELECT * INTO r FROM pg_temp.pr(b, a);
  PERFORM pg_temp.ok(r.online, 'T10g anlamsız bayrak değeri varsayılana (açık) düşer');
  -- Tırnaksız / düz metin yazımı da tanınır (istemci düz metin yazar)
  PERFORM pg_temp.setting('chat_presence_online_enabled', 'false');
  SELECT * INTO r FROM pg_temp.pr(b, a);
  PERFORM pg_temp.ok(NOT r.online, 'T10h JSON boolean false da kapatır');
  PERFORM pg_temp.setting('chat_presence_online_enabled', '"false"');
  SELECT * INTO r FROM pg_temp.pr(b, a);
  PERFORM pg_temp.ok(NOT r.online, 'T10i JSON string "false" da kapatır');
  PERFORM pg_temp.setting('chat_presence_online_enabled', '"true"');

  -- ------------------------------------- [T11] anon
  PERFORM pg_temp.set_t(a, true, now());
  PERFORM pg_temp.as_user(NULL);
  EXECUTE 'SET LOCAL ROLE anon';
  SELECT pr.can_see_online, pr.online, pr.last_seen INTO r FROM public.presence_resolve(a, 'chat') pr;
  EXECUTE 'RESET ROLE';
  PERFORM pg_temp.ok(NOT r.can_see_online AND NOT r.online AND r.last_seen IS NULL, 'T11a oturumsuz: hiçbir şey görünmez');
  EXECUTE 'SET LOCAL ROLE anon';
  EXECUTE 'SELECT count(*), count(last_seen) FROM public.public_profiles_safe' INTO v_n, v_n2;
  EXECUTE 'RESET ROLE';
  PERFORM pg_temp.ok(v_n > 0, 'T11b anon public_profiles_safe okuyabilir (hata yok)');
  PERFORM pg_temp.ok(v_n2 = 0, 'T11c anon hiçbir last_seen göremez (sızıntı: ' || v_n2 || ')');

  -- ------------------------------------- [T12] kendi durumu
  PERFORM pg_temp.set_t(a, true, now(), p_ghost => true, p_show => false);
  SELECT * INTO r FROM pg_temp.pr(a, a);
  PERFORM pg_temp.ok(r.can_see_online AND r.online, 'T12 kişi kendi durumunu (hayalet olsa da) görür');

  -- ------------------------------------- [T13] görünümler maskeli
  PERFORM pg_temp.set_t(a, true, now());
  PERFORM pg_temp.as_user(b);
  EXECUTE 'SET LOCAL ROLE authenticated';
  EXECUTE 'SELECT is_online, last_seen IS NOT NULL AS has_seen FROM public.public_profiles_chat WHERE id = $1'
    INTO r USING a;
  EXECUTE 'RESET ROLE';
  PERFORM pg_temp.ok(r.is_online AND r.has_seen, 'T13a görünür kullanıcı görünümde is_online + last_seen ile döner');
  PERFORM pg_temp.set_t(a, true, now(), p_ghost => true);
  PERFORM pg_temp.as_user(b);
  EXECUTE 'SET LOCAL ROLE authenticated';
  EXECUTE 'SELECT is_online, last_seen IS NOT NULL AS has_seen FROM public.public_profiles_chat WHERE id = $1'
    INTO r USING a;
  EXECUTE 'RESET ROLE';
  PERFORM pg_temp.ok(NOT r.is_online AND NOT r.has_seen, 'T13b hayalet kullanıcı görünümde MASKELİ (is_online=false, last_seen NULL)');
  PERFORM pg_temp.set_t(a, false, now() - interval '2 days');
  PERFORM pg_temp.as_user(b);
  EXECUTE 'SET LOCAL ROLE authenticated';
  EXECUTE 'SELECT last_seen FROM public.public_profiles_safe WHERE id = $1' INTO v_after USING a;
  EXECUTE 'RESET ROLE';
  PERFORM pg_temp.ok(v_after = now() - interval '2 days', 'T13c public_profiles_safe izin verilen son görülmeyi taşır');
  PERFORM pg_temp.set_t(a, false, now() - interval '9 days');
  PERFORM pg_temp.as_user(b);
  EXECUTE 'SET LOCAL ROLE authenticated';
  EXECUTE 'SELECT last_seen FROM public.public_profiles_safe WHERE id = $1' INTO v_after USING a;
  EXECUTE 'RESET ROLE';
  PERFORM pg_temp.ok(v_after IS NULL, 'T13d 9 günlük son görülme görünümde de NULL (eski istemci korunur)');
  -- Görünüm satır sayısı değişmemeli (LEFT JOIN LATERAL satır düşürmemeli)
  PERFORM pg_temp.as_user(b);
  EXECUTE 'SET LOCAL ROLE authenticated';
  EXECUTE 'SELECT count(*) FROM public.public_profiles_chat' INTO v_n;
  EXECUTE 'RESET ROLE';
  SELECT count(*) INTO v_n2 FROM public.profiles WHERE COALESCE(profile_is_public, true) = true OR id = b;
  PERFORM pg_temp.ok(v_n = v_n2, 'T13e public_profiles_chat satır sayısı profiles ile aynı (' || v_n || ' / ' || v_n2 || ')');

  -- ------------------------------------- [T14] get_online_users
  PERFORM pg_temp.set_t(a, true, now());
  PERFORM pg_temp.as_user(b);
  EXECUTE 'SET LOCAL ROLE authenticated';
  EXECUTE 'SELECT count(*) FROM public.get_online_users(NULL) WHERE user_id = $1' INTO v_n USING a;
  EXECUTE 'RESET ROLE';
  PERFORM pg_temp.ok(v_n = 1, 'T14a çevrimiçi kişi aktif şeridinde');
  PERFORM pg_temp.as_user(b);
  EXECUTE 'SET LOCAL ROLE authenticated';
  EXECUTE 'SELECT count(*) FROM public.get_online_users($1) WHERE user_id = $1' INTO v_n USING a;
  EXECUTE 'RESET ROLE';
  PERFORM pg_temp.ok(v_n = 0, 'T14b p_exclude_user_id dışlar');
  PERFORM pg_temp.set_t(a, true, now(), p_ghost => true);
  PERFORM pg_temp.as_user(b);
  EXECUTE 'SET LOCAL ROLE authenticated';
  EXECUTE 'SELECT count(*) FROM public.get_online_users(NULL) WHERE user_id = $1' INTO v_n USING a;
  EXECUTE 'RESET ROLE';
  PERFORM pg_temp.ok(v_n = 0, 'T14c hayalet kullanıcı şeritte YOK (eskiden last_seen ile dönüyordu)');
  PERFORM pg_temp.set_t(a, true, now());
  PERFORM pg_temp.block(a, b);
  PERFORM pg_temp.as_user(b);
  EXECUTE 'SET LOCAL ROLE authenticated';
  EXECUTE 'SELECT count(*) FROM public.get_online_users(NULL) WHERE user_id = $1' INTO v_n USING a;
  EXECUTE 'RESET ROLE';
  PERFORM pg_temp.ok(v_n = 0, 'T14d engelleyen kullanıcı şeritte YOK');
  PERFORM pg_temp.clean(a, b);
  PERFORM pg_temp.setting('chat_presence_online_enabled', '"false"');
  PERFORM pg_temp.as_user(b);
  EXECUTE 'SET LOCAL ROLE authenticated';
  EXECUTE 'SELECT count(*) FROM public.get_online_users(NULL)' INTO v_n;
  EXECUTE 'RESET ROLE';
  PERFORM pg_temp.ok(v_n = 0, 'T14e admin çevrimiçiyi kapatınca şerit boş');
  PERFORM pg_temp.setting('chat_presence_online_enabled', '"true"');

  -- ------------------------------------- [T15] get_user_presence
  PERFORM pg_temp.set_t(a, true, now());
  PERFORM pg_temp.set_t(c, false, now() - interval '3 hours');
  PERFORM pg_temp.as_user(b);
  EXECUTE 'SET LOCAL ROLE authenticated';
  EXECUTE 'SELECT count(*) FROM public.get_user_presence(ARRAY[$1, $2, $1, NULL, gen_random_uuid()]::uuid[], ''chat'')'
    INTO v_n USING a, c;
  EXECUTE 'RESET ROLE';
  PERFORM pg_temp.ok(v_n = 2, 'T15a tekrarlar/NULL/bilinmeyen kimlik elenir (2 satır bekleniyordu: ' || v_n || ')');
  EXECUTE 'SET LOCAL ROLE authenticated';
  EXECUTE 'SELECT count(*) FROM public.get_user_presence(NULL, ''chat'')' INTO v_n;
  EXECUTE 'RESET ROLE';
  PERFORM pg_temp.ok(v_n = 0, 'T15b NULL dizi boş döner');

  -- ------------------------------------- [T16] yazıyor kanalı
  PERFORM pg_temp.clean(a, b);
  PERFORM pg_temp.as_user(b);
  v_j := public.get_typing_channel(a);
  v_topic_ab := v_j ->> 'topic';
  PERFORM pg_temp.ok(v_topic_ab LIKE 'typing:%' AND length(v_topic_ab) = 7 + 64, 'T16a konu adı typing:<64 hex>');
  PERFORM pg_temp.as_user(a);
  v_topic_ba := public.get_typing_channel(b) ->> 'topic';
  PERFORM pg_temp.ok(v_topic_ab = v_topic_ba, 'T16b iki yönde AYNI kanal');
  PERFORM pg_temp.as_user(c);
  v_topic_ac := public.get_typing_channel(a) ->> 'topic';
  PERFORM pg_temp.ok(v_topic_ac IS NOT NULL AND v_topic_ac <> v_topic_ab, 'T16c başka çift FARKLI kanal');
  PERFORM pg_temp.as_user(b);
  PERFORM pg_temp.ok(public.get_typing_channel(b) ->> 'topic' IS NULL, 'T16d kendisiyle kanal yok');
  PERFORM pg_temp.ok(public.get_typing_channel(NULL) ->> 'topic' IS NULL, 'T16e NULL eş → kanal yok');
  PERFORM pg_temp.ok((public.get_typing_channel(a) ->> 'send')::boolean, 'T16f varsayılan: yazıyor bilgisi gönderilir');
  -- kullanıcı yazıyor bilgisini kapatınca send=false (kanal yine verilir: karşıyı görebilir)
  UPDATE public.profiles SET show_typing_indicator = false WHERE id = b;
  v_j := public.get_typing_channel(a);
  PERFORM pg_temp.ok(NOT (v_j ->> 'send')::boolean AND v_j ->> 'topic' IS NOT NULL, 'T16g tercih kapalı: send=false, topic hâlâ var');
  UPDATE public.profiles SET show_typing_indicator = true WHERE id = b;
  -- engel
  PERFORM pg_temp.block(a, b);
  PERFORM pg_temp.ok(public.get_typing_channel(a) ->> 'topic' IS NULL, 'T16h engelli çiftte kanal verilmez');
  PERFORM pg_temp.clean(a, b);
  -- admin
  PERFORM pg_temp.setting('chat_presence_typing_enabled', '"false"');
  PERFORM pg_temp.ok(public.get_typing_channel(a) ->> 'topic' IS NULL, 'T16i admin yazıyoru kapatınca kanal verilmez');
  PERFORM pg_temp.setting('chat_presence_typing_enabled', '"true"');
  -- anon çağıramaz
  BEGIN
    EXECUTE 'SET LOCAL ROLE anon';
    PERFORM public.get_typing_channel(a);
    EXECUTE 'RESET ROLE';
    RAISE EXCEPTION 'TEST_FAIL[T16j]: anon get_typing_channel çağırabildi';
  EXCEPTION WHEN insufficient_privilege THEN
    EXECUTE 'RESET ROLE';
  END;
  PERFORM pg_temp.ok(true, 'T16j anon get_typing_channel çağıramaz');
  -- oturumsuz (rol authenticated ama sub yok) → NULL
  PERFORM pg_temp.as_user(NULL);
  PERFORM pg_temp.ok(public.get_typing_channel(a) ->> 'topic' IS NULL, 'T16k oturumsuz çağrı → kanal yok');

  -- grup
  SELECT gm.group_id, gm.user_id INTO v_gid, v_gm
  FROM public.group_members gm JOIN public.profiles pf ON pf.id = gm.user_id
  ORDER BY gm.joined_at LIMIT 1;
  IF v_gid IS NULL THEN
    v_skipped := v_skipped || ' [T16 grup testleri: canlıda üyeli grup yok]';
  ELSE
    PERFORM pg_temp.as_user(v_gm);
    v_topic_ab := public.get_group_typing_channel(v_gid) ->> 'topic';
    PERFORM pg_temp.ok(v_topic_ab LIKE 'typing\_g:%' AND length(v_topic_ab) = 9 + 64, 'T16l üye grup kanalını alır');
    -- üye olmayan
    SELECT x INTO d FROM unnest(v_ids) x
      WHERE NOT EXISTS (SELECT 1 FROM public.group_members g2 WHERE g2.group_id = v_gid AND g2.user_id = x) LIMIT 1;
    IF d IS NOT NULL THEN
      PERFORM pg_temp.as_user(d);
      PERFORM pg_temp.ok(public.get_group_typing_channel(v_gid) ->> 'topic' IS NULL, 'T16m üye olmayan grup kanalını alamaz');
    END IF;
    PERFORM pg_temp.as_user(v_gm);
    PERFORM pg_temp.setting('chat_presence_typing_in_groups', '"false"');
    PERFORM pg_temp.ok(public.get_group_typing_channel(v_gid) ->> 'topic' IS NULL, 'T16n grup yazıyor anahtarı kapalıyken kanal yok');
    PERFORM pg_temp.setting('chat_presence_typing_in_groups', '"true"');
    PERFORM pg_temp.ok(public.get_group_typing_channel(v_gid) ->> 'topic' = v_topic_ab, 'T16o grup kanalı kararlı');
  END IF;

  -- ------------------------------------- [T17] update_my_chat_privacy
  PERFORM pg_temp.set_t(a, true, now() - interval '20 minutes');
  PERFORM pg_temp.set_t(b, true, now() - interval '20 minutes');
  SELECT last_seen INTO v_before FROM public.profiles WHERE id = b;
  PERFORM pg_temp.as_user(b);
  PERFORM public.update_my_chat_privacy(p_show_last_seen => true, p_last_seen_friends_only => true, p_show_typing_indicator => false);
  SELECT last_seen INTO v_after FROM public.profiles WHERE id = b;
  PERFORM pg_temp.ok(v_before = v_after, 'T17a gizlilik değişimi last_seen değerine dokunmaz');
  PERFORM pg_temp.ok((SELECT last_seen_friends_only AND NOT show_typing_indicator AND show_last_seen FROM public.profiles WHERE id = b),
    'T17b üç alan yazıldı');
  PERFORM pg_temp.ok((SELECT NOT last_seen_friends_only AND show_typing_indicator FROM public.profiles WHERE id = a),
    'T17c başkasının satırına dokunulmaz');
  PERFORM public.update_my_chat_privacy(p_show_last_seen => false);
  PERFORM pg_temp.ok((SELECT NOT show_last_seen AND last_seen_friends_only AND NOT show_typing_indicator FROM public.profiles WHERE id = b),
    'T17d NULL parametre alanı değiştirmez');
  PERFORM pg_temp.as_user(NULL);
  BEGIN
    PERFORM public.update_my_chat_privacy(p_show_last_seen => true);
    RAISE EXCEPTION 'TEST_FAIL[T17e]: oturumsuz yazabildi';
  EXCEPTION WHEN sqlstate '28000' THEN NULL;
  END;
  PERFORM pg_temp.ok(true, 'T17e oturumsuz çağrı reddedilir');

  -- ------------------------------------- [T18] admin RPC'leri
  SELECT id INTO v_admin FROM public.profiles WHERE role = 'admin' ORDER BY created_at LIMIT 1;
  IF v_admin IS NULL THEN
    v_skipped := v_skipped || ' [T18 admin testleri: admin profili yok]';
  ELSE
    PERFORM pg_temp.as_user(v_admin);
    v_j := public.admin_set_chat_presence_setting('chat_presence_last_seen_max_days', '14');
    PERFORM pg_temp.ok((v_j ->> 'last_seen_max_days')::int = 14, 'T18a gün ayarı yazıldı ve geri döndü');
    PERFORM pg_temp.ok((SELECT value #>> '{}' FROM public.app_settings WHERE key = 'chat_presence_last_seen_max_days') = '14',
      'T18b değer düz metin olarak saklanır');
    v_j := public.admin_set_chat_presence_setting('chat_presence_typing_enabled', 'false');
    PERFORM pg_temp.ok(NOT (v_j ->> 'typing')::boolean, 'T18c bayrak kapandı');
    PERFORM pg_temp.ok((SELECT value #>> '{}' FROM public.app_settings WHERE key = 'chat_presence_typing_enabled') = 'false',
      'T18d bayrak değeri "false" metni');
    FOREACH v_txt IN ARRAY ARRAY['0', '366', 'abc', '', '-1', '7.5'] LOOP
      BEGIN
        PERFORM public.admin_set_chat_presence_setting('chat_presence_last_seen_max_days', v_txt);
        RAISE EXCEPTION 'TEST_FAIL[T18e]: geçersiz gün kabul edildi: %', v_txt;
      EXCEPTION WHEN sqlstate '22023' THEN NULL;
      END;
    END LOOP;
    PERFORM pg_temp.ok(true, 'T18e geçersiz gün değerleri reddedilir');
    FOREACH v_txt IN ARRAY ARRAY['yes', '1', '', 'evet'] LOOP
      BEGIN
        PERFORM public.admin_set_chat_presence_setting('chat_presence_online_enabled', v_txt);
        RAISE EXCEPTION 'TEST_FAIL[T18f]: geçersiz bayrak kabul edildi: %', v_txt;
      EXCEPTION WHEN sqlstate '22023' THEN NULL;
      END;
    END LOOP;
    PERFORM pg_temp.ok(true, 'T18f geçersiz bayrak değerleri reddedilir');
    BEGIN
      PERFORM public.admin_set_chat_presence_setting('leaderboard_enabled', 'false');
      RAISE EXCEPTION 'TEST_FAIL[T18g]: beyaz liste dışı anahtar yazıldı';
    EXCEPTION WHEN sqlstate '22023' THEN NULL;
    END;
    PERFORM pg_temp.ok(true, 'T18g beyaz liste dışı anahtar reddedilir (başka ayarlar bu yoldan değişmez)');
    v_j := public.admin_chat_presence_stats();
    PERFORM pg_temp.ok((v_j ->> 'total')::int > 0 AND v_j ? 'ghost' AND v_j ? 'typing_off' AND v_j ? 'online_now',
      'T18h özet alanları dolu: ' || v_j::text);
    -- admin olmayan
    PERFORM pg_temp.as_user(b);
    BEGIN
      PERFORM public.admin_set_chat_presence_setting('chat_presence_typing_enabled', 'true');
      RAISE EXCEPTION 'TEST_FAIL[T18i]: admin olmayan ayar yazabildi';
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
    BEGIN
      PERFORM public.admin_chat_presence_stats();
      RAISE EXCEPTION 'TEST_FAIL[T18j]: admin olmayan özeti okudu';
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
    PERFORM pg_temp.ok(true, 'T18i/j admin olmayan reddedilir');
  END IF;

  -- ------------------------------------- [T19] iç yardımcılar dışarıya kapalı
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM public.chat_presence_cfg();
    EXECUTE 'RESET ROLE';
    RAISE EXCEPTION 'TEST_FAIL[T19a]: authenticated chat_presence_cfg çağırabildi';
  EXCEPTION WHEN insufficient_privilege THEN
    EXECUTE 'RESET ROLE';
  END;
  PERFORM pg_temp.ok(true, 'T19a chat_presence_cfg doğrudan çağrılamaz');
  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM count(*) FROM public.chat_typing_secret;
    EXECUTE 'RESET ROLE';
    RAISE EXCEPTION 'TEST_FAIL[T19b]: authenticated gizli anahtar tablosunu okudu';
  EXCEPTION WHEN insufficient_privilege THEN
    EXECUTE 'RESET ROLE';
  END;
  PERFORM pg_temp.ok(true, 'T19b chat_typing_secret istemciye kapalı');
  BEGIN
    EXECUTE 'SET LOCAL ROLE anon';
    PERFORM public.get_user_presence(ARRAY[a]::uuid[], 'chat');
    EXECUTE 'RESET ROLE';
    RAISE EXCEPTION 'TEST_FAIL[T19c]: anon get_user_presence çağırabildi';
  EXCEPTION WHEN insufficient_privilege THEN
    EXECUTE 'RESET ROLE';
  END;
  PERFORM pg_temp.ok(true, 'T19c anon get_user_presence çağıramaz');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.chat_typing_secret) = 1 AND
                     (SELECT length(secret) FROM public.chat_typing_secret) = 64,
                     'T19d tek satırlık 32 baytlık gizli anahtar');

  RAISE EXCEPTION 'TESTS_PASSED checks=% %', current_setting('t.n', true), v_skipped;
END
$test$;
