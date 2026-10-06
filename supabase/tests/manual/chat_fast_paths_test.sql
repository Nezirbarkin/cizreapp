-- =============================================================================
-- Sohbet hızlı yolları + gönderen doğrulaması — sunucu testi
--   supabase db query --linked --file supabase/tests/manual/chat_fast_paths_test.sql
--
-- Önkoşul: 20260927000001_chat_fast_paths.sql uygulanmış olmalı.
--
-- Neyi kanıtlar:
--   [G1-7]  get_my_conversations: partner başına tek satır, kimlik alanları
--           (user_id=ben, other_user_id=partner), yalnız karşı tarafın satırı
--           olan konuşma, son mesaj/sahibi/okundu kuralları, yumuşak silme,
--           updated_at sırası, profil anahtarları
--   [G8-10] başkasının konuşması görünmez; anon çağıramaz; kimliksiz boş döner
--   [M1-8]  get_conversation_messages: iki kopya tek mesaja iner, en yeniden
--           eskiye, okundu kuralları (iki bakış açısından), kimlik benim kopyam,
--           sayfalama (p_limit / p_before) çakışmasız, sınırlar, JSON anahtarları,
--           yumuşak silme
--   [S1-5]  send_message_with_recipient: kendi adına çalışır, başkası adına ve
--           kimliksiz 42501; mark_sender_messages_read istemciye kapalı
--   [P]     canlıdaki en yoğun kullanıcı için iki RPC'nin süresi (ms)
--
-- Betik TEK DO bloğudur ve SONUNDA bilerek istisna fırlatır: istisna tüm
-- değişiklikleri geri alır (canlı veriye dokunulmaz).
--   BAŞARILI:  "TESTS_PASSED ..."    BAŞARISIZ: "TEST_FAIL[x]: ..."
-- Denekler bot vitrin hesaplarıdır.
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

-- Posta kutusu modelindeki gibi İKİ kopya yazar: gönderenin kopyası okunmuş,
-- alıcınınki p_recipient_read. Alıcı konuşması yoksa yalnız gönderen kopyası.
CREATE OR REPLACE FUNCTION pg_temp.msg(
  p_sender_conv uuid, p_recipient_conv uuid, p_sender uuid, p_content text,
  p_at timestamptz, p_recipient_read boolean
) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO public.messages (conversation_id, sender_id, content, is_read, created_at, updated_at)
  VALUES (p_sender_conv, p_sender, p_content, true, p_at, p_at);
  IF p_recipient_conv IS NOT NULL THEN
    INSERT INTO public.messages (conversation_id, sender_id, content, is_read, created_at, updated_at)
    VALUES (p_recipient_conv, p_sender, p_content, p_recipient_read, p_at, p_at);
  END IF;
END $$;

DO $test$
DECLARE
  v_ids uuid[];
  a uuid; b uuid; c uuid;
  ab uuid; ba uuid; ca uuid;             -- ab: a'nın b ile konuşması, vb.
  t0 timestamptz := now() - interval '1 hour';
  r record;
  v_n bigint;
  v_arr jsonb[];
  v_j jsonb;
  v_heavy uuid; v_heavy_conv uuid;
  v_clock timestamptz;
  v_list_ms numeric; v_msgs_ms numeric;
BEGIN
  SELECT array_agg(id) INTO v_ids
  FROM (SELECT id FROM public.profiles WHERE is_bot = true ORDER BY id LIMIT 3) s;
  IF COALESCE(array_length(v_ids, 1), 0) < 3 THEN
    RAISE EXCEPTION 'TEST_FAIL[setup]: en az 3 bot profili gerekli';
  END IF;
  a := v_ids[1]; b := v_ids[2]; c := v_ids[3];

  -- ---------------------------------------------------------------- kurulum
  -- Botların gerçek kullanıcılarla konuşmaları da olabilir; sonuçlar yalnız test
  -- verisine bağlı olsun diye hepsi kaldırılır (blok sonunda zaten geri alınır).
  DELETE FROM public.conversations
   WHERE user_id = ANY(v_ids) OR other_user_id = ANY(v_ids);

  INSERT INTO public.conversations (user_id, other_user_id, created_at, updated_at)
  VALUES (a, b, t0, t0) RETURNING id INTO ab;
  INSERT INTO public.conversations (user_id, other_user_id, created_at, updated_at)
  VALUES (b, a, t0, t0) RETURNING id INTO ba;
  -- a'nın c ile KENDİ satırı yok; yalnız c'nin a'ya dönük satırı var.
  INSERT INTO public.conversations (user_id, other_user_id, created_at, updated_at)
  VALUES (c, a, t0, t0) RETURNING id INTO ca;

  PERFORM pg_temp.msg(ab, ba, a, 'merhaba',  t0 + interval '1 min', true);   -- m1
  PERFORM pg_temp.msg(ba, ab, b, 'selam',    t0 + interval '2 min', true);   -- m2
  PERFORM pg_temp.msg(ab, ba, a, 'nasılsın', t0 + interval '3 min', false);  -- m3 (b okumadı)
  PERFORM pg_temp.msg(ca, NULL, c, 'c1',     t0 + interval '4 min', false);  -- yalnız c'nin kopyası

  -- Sıra: c'nin satırı daha yeni.
  UPDATE public.conversations SET updated_at = t0 + interval '10 min' WHERE id = ab;
  UPDATE public.conversations SET updated_at = t0 + interval '20 min' WHERE id = ca;

  -- ------------------------------------------------------ liste (a gözüyle)
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM pg_temp.as_user(a);

  SELECT count(*) INTO v_n FROM public.get_my_conversations();
  PERFORM pg_temp.ok(v_n = 2, 'G1 partner başına tek satır (b, c)');

  SELECT * INTO r FROM public.get_my_conversations() g WHERE g.other_user_id = b;
  PERFORM pg_temp.ok(r.id = ab AND r.user_id = a, 'G2a b satırı a''nın kendi konuşması');
  PERFORM pg_temp.ok(r.last_message = 'nasılsın'
                     AND r.last_message_time = t0 + interval '3 min', 'G2b son mesaj en yenisi');
  PERFORM pg_temp.ok(r.last_message_by_me AND NOT r.last_message_read,
                     'G2c benim son mesajım karşı taraf okumadıysa okunmadı');
  PERFORM pg_temp.ok(r.unread_count = (SELECT cc.unread_count FROM public.conversations cc WHERE cc.id = ab),
                     'G2d okunmamış sayısı kendi satırımdan');
  PERFORM pg_temp.ok(r.other_user ? 'id' AND r.other_user ? 'full_name' AND r.other_user ? 'username'
                     AND r.other_user ? 'avatar_url' AND r.other_user ? 'is_online'
                     AND r.other_user ? 'last_seen' AND (r.other_user->>'id')::uuid = b,
                     'G7 profil anahtarları');

  SELECT * INTO r FROM public.get_my_conversations() g WHERE g.other_user_id = c;
  PERFORM pg_temp.ok(r.id = ca AND r.user_id = a,
                     'G3 yalnız karşı tarafın satırı olan konuşma görünür, kimlik alanları çevrilmiş');
  PERFORM pg_temp.ok(r.last_message = 'c1' AND NOT r.last_message_by_me AND r.last_message_read,
                     'G4 gelen son mesaj okunmuş sayılır');

  SELECT array_agg(g.other_user_id ORDER BY ordinality) INTO v_ids
    FROM public.get_my_conversations() WITH ORDINALITY g;
  PERFORM pg_temp.ok(v_ids = ARRAY[c, b], 'G5 updated_at azalan sıra');

  -- b, m3'ü okudu → a'nın listesinde "görüldü".
  EXECUTE 'RESET ROLE';
  UPDATE public.messages SET is_read = true
   WHERE conversation_id = ba AND content = 'nasılsın';
  EXECUTE 'SET LOCAL ROLE authenticated';
  SELECT * INTO r FROM public.get_my_conversations() g WHERE g.other_user_id = b;
  PERFORM pg_temp.ok(r.last_message_read, 'G6a karşı taraf okuyunca okundu');

  -- ------------------------------------------- konuşma mesajları (a gözüyle)
  SELECT array_agg(j) INTO v_arr FROM public.get_conversation_messages(ab) j;
  PERFORM pg_temp.ok(array_length(v_arr, 1) = 3, 'M1 iki kopya tek mesaja iner (3 mesaj)');
  PERFORM pg_temp.ok(v_arr[1]->>'content' = 'nasılsın' AND v_arr[2]->>'content' = 'selam'
                     AND v_arr[3]->>'content' = 'merhaba', 'M2 en yeniden eskiye');
  PERFORM pg_temp.ok((v_arr[1]->>'is_read')::boolean AND (v_arr[3]->>'is_read')::boolean,
                     'M3a benim mesajlarım partner kopyasına göre okundu');
  PERFORM pg_temp.ok((v_arr[2]->>'is_read')::boolean, 'M3b gelen mesaj benim kopyama göre okundu');
  PERFORM pg_temp.ok((v_arr[1]->>'conversation_id')::uuid = ab AND (v_arr[2]->>'conversation_id')::uuid = ab,
                     'M4 temel satır benim kopyam (kimlik realtime ile eşleşir)');
  PERFORM pg_temp.ok(v_arr[1] ? 'reply_to_content' AND v_arr[1] ? 'deleted_for_user_id'
                     AND v_arr[1] ? 'sender_id' AND NOT (v_arr[1] ? 'is_my_copy')
                     AND NOT (v_arr[1] ? 'my_read') AND NOT (v_arr[1] ? 'partner_read'),
                     'M5 tüm mesaj sütunları var, yardımcı alanlar yok');

  SELECT array_agg(j) INTO v_arr FROM public.get_conversation_messages(ab, NULL, 2) j;
  PERFORM pg_temp.ok(array_length(v_arr, 1) = 2 AND v_arr[2]->>'content' = 'selam', 'M6a ilk sayfa (2)');
  SELECT array_agg(j) INTO v_arr
    FROM public.get_conversation_messages(ab, (v_arr[2]->>'created_at')::timestamptz, 2) j;
  PERFORM pg_temp.ok(array_length(v_arr, 1) = 1 AND v_arr[1]->>'content' = 'merhaba',
                     'M6b önceki sayfa çakışmasız');
  SELECT count(*) INTO v_n FROM public.get_conversation_messages(ab, NULL, 0);
  PERFORM pg_temp.ok(v_n = 1, 'M7a p_limit alt sınırı 1');
  SELECT count(*) INTO v_n FROM public.get_conversation_messages(ab, NULL, 100000);
  PERFORM pg_temp.ok(v_n = 3, 'M7b p_limit üst sınırı (100) veriyi kesmez');

  -- b gözüyle: m2 onun mesajı (a'nın kopyası okundu), m3 gelen (kendi kopyası okundu).
  PERFORM pg_temp.as_user(b);
  SELECT array_agg(j) INTO v_arr FROM public.get_conversation_messages(ba) j;
  PERFORM pg_temp.ok(array_length(v_arr, 1) = 3 AND (v_arr[2]->>'is_read')::boolean
                     AND (v_arr[1]->>'is_read')::boolean
                     AND (v_arr[1]->>'conversation_id')::uuid = ba,
                     'M8 karşı taraf gözüyle aynı kurallar');

  -- Yumuşak silme: m3'ün iki kopyası a için silindi.
  EXECUTE 'RESET ROLE';
  UPDATE public.messages SET deleted_for_user_id = a
   WHERE conversation_id IN (ab, ba) AND content = 'nasılsın';
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM pg_temp.as_user(a);
  SELECT count(*) INTO v_n FROM public.get_conversation_messages(ab);
  PERFORM pg_temp.ok(v_n = 2, 'M9 bana silinen mesaj dönmez');
  SELECT * INTO r FROM public.get_my_conversations() g WHERE g.other_user_id = b;
  PERFORM pg_temp.ok(r.last_message = 'selam' AND NOT r.last_message_by_me,
                     'G6b bana silinen mesaj son mesaj sayılmaz');

  -- --------------------------------------------------------- görünürlük / yetki
  PERFORM pg_temp.as_user(c);
  SELECT count(*) INTO v_n FROM public.get_my_conversations() g WHERE g.id IN (ab, ba);
  PERFORM pg_temp.ok(v_n = 0, 'G8a başkasının konuşması listede yok');
  SELECT count(*) INTO v_n FROM public.get_conversation_messages(ab);
  PERFORM pg_temp.ok(v_n = 0, 'G8b başkasının mesajları dönmez');

  PERFORM pg_temp.as_user(NULL);
  SELECT count(*) INTO v_n FROM public.get_my_conversations();
  PERFORM pg_temp.ok(v_n = 0, 'G10 kimliksiz çağrı boş döner');
  EXECUTE 'RESET ROLE';

  BEGIN
    EXECUTE 'SET LOCAL ROLE anon';
    PERFORM count(*) FROM public.get_my_conversations();
    EXECUTE 'RESET ROLE';
    RAISE EXCEPTION 'TEST_FAIL[G9]: anon get_my_conversations çağırabildi';
  EXCEPTION WHEN insufficient_privilege THEN
    EXECUTE 'RESET ROLE';
  END;
  PERFORM pg_temp.ok(true, 'G9 anon çağıramaz');

  -- ------------------------------------------------------------- gönderen
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM pg_temp.as_user(a);
  SELECT count(*) INTO v_n FROM public.send_message_with_recipient(ab, 'kendi adıma', a);
  PERFORM pg_temp.ok(v_n = 1, 'S1 kendi adına gönderim çalışır');
  EXECUTE 'RESET ROLE';
  SELECT count(*) INTO v_n FROM public.messages WHERE content = 'kendi adıma' AND conversation_id IN (ab, ba);
  PERFORM pg_temp.ok(v_n = 2, 'S1b iki kopya yazıldı');

  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM pg_temp.as_user(b);
    PERFORM public.send_message_with_recipient(ab, 'sahte', a);
    EXECUTE 'RESET ROLE';
    RAISE EXCEPTION 'TEST_FAIL[S2]: b, a adına mesaj gönderebildi';
  EXCEPTION WHEN insufficient_privilege THEN
    EXECUTE 'RESET ROLE';
  END;
  PERFORM pg_temp.ok(true, 'S2 başkası adına gönderim 42501');

  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM pg_temp.as_user(b);
  SELECT count(*) INTO v_n FROM public.send_message_with_recipient(ba, 'b kendi adına', b);
  PERFORM pg_temp.ok(v_n = 1, 'S3 karşı taraf da kendi adına gönderebilir');
  EXECUTE 'RESET ROLE';

  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM pg_temp.as_user(NULL);
    PERFORM public.send_message_with_recipient(ab, 'kimliksiz', a);
    EXECUTE 'RESET ROLE';
    RAISE EXCEPTION 'TEST_FAIL[S4]: kimliksiz çağrı gönderebildi';
  EXCEPTION WHEN insufficient_privilege THEN
    EXECUTE 'RESET ROLE';
  END;
  PERFORM pg_temp.ok(true, 'S4 kimliksiz gönderim 42501');

  BEGIN
    EXECUTE 'SET LOCAL ROLE authenticated';
    PERFORM pg_temp.as_user(a);
    PERFORM public.mark_sender_messages_read(ab, a);
    EXECUTE 'RESET ROLE';
    RAISE EXCEPTION 'TEST_FAIL[S5]: mark_sender_messages_read istemciye açık';
  EXCEPTION WHEN insufficient_privilege THEN
    EXECUTE 'RESET ROLE';
  END;
  PERFORM pg_temp.ok(true, 'S5 mark_sender_messages_read istemciye kapalı');

  -- --------------------------------------------------------------- süre
  SELECT cc.user_id INTO v_heavy
    FROM public.conversations cc JOIN public.messages m ON m.conversation_id = cc.id
   WHERE NOT (cc.user_id = ANY(ARRAY[a, b, c]))
   GROUP BY cc.user_id ORDER BY count(*) DESC LIMIT 1;
  SELECT m.conversation_id INTO v_heavy_conv
    FROM public.messages m JOIN public.conversations cc ON cc.id = m.conversation_id
   WHERE cc.user_id = v_heavy
   GROUP BY 1 ORDER BY count(*) DESC LIMIT 1;

  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM pg_temp.as_user(v_heavy);
  v_clock := clock_timestamp();
  FOR i IN 1..5 LOOP
    PERFORM count(*) FROM public.get_my_conversations();
  END LOOP;
  v_list_ms := round((extract(epoch FROM clock_timestamp() - v_clock) * 1000 / 5)::numeric, 1);
  v_clock := clock_timestamp();
  FOR i IN 1..5 LOOP
    PERFORM count(*) FROM public.get_conversation_messages(v_heavy_conv);
  END LOOP;
  v_msgs_ms := round((extract(epoch FROM clock_timestamp() - v_clock) * 1000 / 5)::numeric, 1);
  EXECUTE 'RESET ROLE';

  RAISE EXCEPTION 'TESTS_PASSED checks=% perf_list_ms=% perf_msgs_ms=%',
    current_setting('t.n', true), v_list_ms, v_msgs_ms;
END
$test$;
