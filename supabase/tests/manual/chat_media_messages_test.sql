-- Görev 3.1 — sohbette fotoğraf/konum mesajları canlı doğrulaması (kendini geri alır).
--
-- Çalıştırma: supabase db query --linked --file supabase/tests/manual/chat_media_messages_test.sql
-- Başarı = 'TESTS_PASSED ...' istisnası: DO bloğu RAISE EXCEPTION ile biter,
-- testin yazdığı her şey (konuşmalar, mesajlar, sahte depo nesneleri) geri alınır.
DO $test$
DECLARE
  v_a uuid;             -- gönderen
  v_b uuid;             -- alıcı
  v_c uuid;             -- üçüncü kişi (konuşmanın tarafı değil)
  v_conv_a uuid;        -- A'nın konuşma satırı (A → B)
  v_conv_b uuid;        -- B'nin konuşma satırı (B → A)
  v_path text;
  v_row record;
  v_n integer;
  v_json jsonb;
  v_checks integer := 0;
BEGIN
  SELECT id INTO v_a FROM public.profiles ORDER BY created_at LIMIT 1;
  SELECT id INTO v_b FROM public.profiles WHERE id <> v_a ORDER BY created_at LIMIT 1;
  SELECT id INTO v_c FROM public.profiles WHERE id NOT IN (v_a, v_b) ORDER BY created_at LIMIT 1;

  INSERT INTO public.conversations (user_id, other_user_id) VALUES (v_a, v_b) RETURNING id INTO v_conv_a;
  INSERT INTO public.conversations (user_id, other_user_id) VALUES (v_b, v_a) RETURNING id INTO v_conv_b;

  -- [1] sütunlar
  SELECT count(*) INTO v_n FROM information_schema.columns
   WHERE table_schema = 'public' AND table_name = 'messages'
     AND ((column_name = 'message_type' AND data_type = 'text' AND is_nullable = 'NO'
           AND column_default LIKE '''text''%')
       OR (column_name = 'attachment' AND data_type = 'jsonb'));
  IF v_n <> 2 THEN RAISE EXCEPTION '[1] message_type/attachment sütunları eksik'; END IF;
  -- eski mesajlar metin
  IF EXISTS (SELECT 1 FROM public.messages WHERE message_type <> 'text' AND created_at < '2026-09-28') THEN
    RAISE EXCEPTION '[1] eski mesajlar text değil';
  END IF;
  v_checks := v_checks + 1;

  -- [2] tür/ek CHECK'leri (NULL'a düşen ifade CHECK'i geçmemeli)
  BEGIN
    INSERT INTO public.messages (conversation_id, sender_id, content, message_type, attachment)
    VALUES (v_conv_a, v_a, 'x', 'text', '{"a":1}');
    RAISE EXCEPTION '[2] metin + ek kabul edildi';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN
    INSERT INTO public.messages (conversation_id, sender_id, content, message_type, attachment)
    VALUES (v_conv_a, v_a, 'x', 'image', NULL);
    RAISE EXCEPTION '[2] eksiz fotoğraf kabul edildi';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN
    INSERT INTO public.messages (conversation_id, sender_id, content, message_type, attachment)
    VALUES (v_conv_a, v_a, 'x', 'image', '{}');
    RAISE EXCEPTION '[2] yolsuz fotoğraf kabul edildi';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN
    INSERT INTO public.messages (conversation_id, sender_id, content, message_type, attachment)
    VALUES (v_conv_a, v_a, 'x', 'image', '{"path":"../../etc/passwd.jpg"}');
    RAISE EXCEPTION '[2] bozuk yol kabul edildi';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN
    INSERT INTO public.messages (conversation_id, sender_id, content, message_type, attachment)
    VALUES (v_conv_a, v_a, 'x', 'location', '{"lat":100,"lng":42}');
    RAISE EXCEPTION '[2] enlem 100 kabul edildi';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN
    INSERT INTO public.messages (conversation_id, sender_id, content, message_type, attachment)
    VALUES (v_conv_a, v_a, 'x', 'location', '{"lat":"37","lng":42}');
    RAISE EXCEPTION '[2] metin enlem kabul edildi';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN
    INSERT INTO public.messages (conversation_id, sender_id, content, message_type, attachment)
    VALUES (v_conv_a, v_a, 'x', 'video', NULL);
    RAISE EXCEPTION '[2] bilinmeyen tür kabul edildi';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN
    INSERT INTO public.messages (conversation_id, sender_id, content, message_type, attachment)
    VALUES (v_conv_a, v_a, 'x', 'location',
            jsonb_build_object('lat', 37, 'lng', 42, 'label', repeat('x', 3000)));
    RAISE EXCEPTION '[2] 2 KB üstü ek kabul edildi';
  EXCEPTION WHEN check_violation THEN NULL; END;
  v_checks := v_checks + 1;

  -- A olarak çağır
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);

  -- [3] eski sürüm istemci çağrısı (6 adlı parametre) aynen çalışır
  SELECT * INTO v_row FROM public.send_message_with_recipient(
    p_conversation_id => v_conv_a, p_content => 'merhaba', p_sender_id => v_a,
    p_reply_to_id => NULL, p_reply_to_content => NULL, p_reply_to_sender_name => NULL);
  IF v_row.message_type <> 'text' OR v_row.attachment IS NOT NULL OR v_row.content <> 'merhaba' THEN
    RAISE EXCEPTION '[3] eski çağrı: %', row_to_json(v_row);
  END IF;
  v_checks := v_checks + 1;

  -- [4] fotoğraf: yüklenmemiş dosyaya işaret edilemez
  v_path := v_a::text || '/' || v_b::text || '/' || gen_random_uuid()::text || '.jpg';
  BEGIN
    PERFORM public.send_message_with_recipient(
      p_conversation_id => v_conv_a, p_content => '', p_sender_id => v_a,
      p_message_type => 'image', p_attachment => jsonb_build_object('path', v_path, 'w', 1080, 'h', 1440));
    RAISE EXCEPTION '[4] yüklenmemiş fotoğraf kabul edildi';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  v_checks := v_checks + 1;

  -- [5] depo: A yalnız KENDİ klasörüne yükler; iki derinlik zorunlu
  BEGIN
    INSERT INTO storage.objects (bucket_id, name, owner_id, metadata)
    VALUES ('chat_attachments', v_b::text || '/' || v_a::text || '/x.jpg', v_a::text, '{}');
    RAISE EXCEPTION '[5] başkasının klasörüne yükleme kabul edildi';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    INSERT INTO storage.objects (bucket_id, name, owner_id, metadata)
    VALUES ('chat_attachments', v_a::text || '/x.jpg', v_a::text, '{}');
    RAISE EXCEPTION '[5] tek derinlikli yol kabul edildi';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  INSERT INTO storage.objects (bucket_id, name, owner_id, metadata)
  VALUES ('chat_attachments', v_path, v_a::text, '{"mimetype":"image/jpeg"}');
  v_checks := v_checks + 1;

  -- [6] yüklenmiş fotoğraf gönderilir: iki kopya da türü/eki taşır, içerik önizlemedir
  SELECT * INTO v_row FROM public.send_message_with_recipient(
    p_conversation_id => v_conv_a, p_content => '   ', p_sender_id => v_a,
    p_message_type => 'image',
    p_attachment => jsonb_build_object('path', v_path, 'w', 1080, 'h', 1440, 'caption', 'Akşam'));
  IF v_row.message_type <> 'image' OR v_row.content <> '📷 Fotoğraf'
     OR v_row.attachment ->> 'path' <> v_path THEN
    RAISE EXCEPTION '[6] fotoğraf dönüşü: %', row_to_json(v_row);
  END IF;
  EXECUTE 'RESET ROLE';
  SELECT count(*) INTO v_n FROM public.messages
   WHERE id IN (v_row.message_id, v_row.recipient_message_id)
     AND message_type = 'image' AND attachment ->> 'path' = v_path AND content = '📷 Fotoğraf';
  IF v_n <> 2 THEN RAISE EXCEPTION '[6] iki kopyadan % tanesi doğru', v_n; END IF;
  -- sohbet listesi önizlemesi
  IF (SELECT last_message FROM public.conversations WHERE id = v_conv_b) <> '📷 Fotoğraf' THEN
    RAISE EXCEPTION '[6] alıcı listesi önizlemesi yanlış';
  END IF;
  v_checks := v_checks + 1;

  -- [7] başkasının klasöründeki (B→A) dosyaya işaret edilemez
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
  BEGIN
    PERFORM public.send_message_with_recipient(
      p_conversation_id => v_conv_a, p_content => '', p_sender_id => v_a,
      p_message_type => 'image',
      p_attachment => jsonb_build_object('path', v_b::text || '/' || v_a::text || '/' || gen_random_uuid()::text || '.jpg'));
    RAISE EXCEPTION '[7] başkasının klasörü kabul edildi';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  -- metin türünde ek sessizce düşer
  SELECT * INTO v_row FROM public.send_message_with_recipient(
    p_conversation_id => v_conv_a, p_content => 'düz', p_sender_id => v_a,
    p_message_type => 'text', p_attachment => '{"lat":1,"lng":2}');
  IF v_row.attachment IS NOT NULL THEN RAISE EXCEPTION '[7] metin eki düşmedi'; END IF;
  v_checks := v_checks + 1;

  -- [8] konum: önizleme metni korunur ya da varsayılan; bozuk konum reddedilir
  SELECT * INTO v_row FROM public.send_message_with_recipient(
    p_conversation_id => v_conv_a, p_content => '📍 Konum: Ali Bey, Temiz Sk.', p_sender_id => v_a,
    p_message_type => 'location',
    p_attachment => '{"lat":37.3256,"lng":42.192,"label":"Ali Bey, Temiz Sk."}');
  IF v_row.message_type <> 'location' OR v_row.content <> '📍 Konum: Ali Bey, Temiz Sk.' THEN
    RAISE EXCEPTION '[8] konum dönüşü: %', row_to_json(v_row);
  END IF;
  SELECT * INTO v_row FROM public.send_message_with_recipient(
    p_conversation_id => v_conv_a, p_content => NULL, p_sender_id => v_a,
    p_message_type => 'location', p_attachment => '{"lat":37.3,"lng":42.1}');
  IF v_row.content <> '📍 Konum' THEN RAISE EXCEPTION '[8] varsayılan konum metni: %', v_row.content; END IF;
  BEGIN
    PERFORM public.send_message_with_recipient(
      p_conversation_id => v_conv_a, p_content => '', p_sender_id => v_a,
      p_message_type => 'location', p_attachment => '{"lat":37.3}');
    RAISE EXCEPTION '[8] boylamsız konum kabul edildi';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN
    PERFORM public.send_message_with_recipient(
      p_conversation_id => v_conv_a, p_content => '', p_sender_id => v_a,
      p_message_type => 'location', p_attachment => NULL);
    RAISE EXCEPTION '[8] eksiz konum kabul edildi';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  BEGIN
    PERFORM public.send_message_with_recipient(
      p_conversation_id => v_conv_a, p_content => 'x', p_sender_id => v_a,
      p_message_type => 'sticker', p_attachment => '{}');
    RAISE EXCEPTION '[8] bilinmeyen tür kabul edildi';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  v_checks := v_checks + 1;

  -- [9] "gönderen = çağıran" denetimi korunuyor
  BEGIN
    PERFORM public.send_message_with_recipient(
      p_conversation_id => v_conv_b, p_content => 'sahte', p_sender_id => v_b,
      p_message_type => 'location', p_attachment => '{"lat":1,"lng":2}');
    RAISE EXCEPTION '[9] başkası adına gönderildi';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  v_checks := v_checks + 1;

  -- [10] sayfa RPC'si türü ve eki döndürür
  SELECT m INTO v_json
    FROM public.get_conversation_messages(v_conv_a, NULL, 40) m
   WHERE m ->> 'message_type' = 'image'
   LIMIT 1;
  IF v_json IS NULL OR v_json -> 'attachment' ->> 'path' <> v_path THEN
    RAISE EXCEPTION '[10] get_conversation_messages türü/eki döndürmüyor: %', v_json;
  END IF;
  v_checks := v_checks + 1;

  -- [11] depo okuma: iki taraf görür, üçüncü kişi görmez
  SELECT count(*) INTO v_n FROM storage.objects WHERE bucket_id = 'chat_attachments' AND name = v_path;
  IF v_n <> 1 THEN RAISE EXCEPTION '[11] gönderen kendi fotoğrafını görmüyor'; END IF;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_b, 'role', 'authenticated')::text, true);
  SELECT count(*) INTO v_n FROM storage.objects WHERE bucket_id = 'chat_attachments' AND name = v_path;
  IF v_n <> 1 THEN RAISE EXCEPTION '[11] alıcı fotoğrafı görmüyor'; END IF;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_c, 'role', 'authenticated')::text, true);
  SELECT count(*) INTO v_n FROM storage.objects WHERE bucket_id = 'chat_attachments' AND name = v_path;
  IF v_n <> 0 THEN RAISE EXCEPTION '[11] üçüncü kişi fotoğrafı görüyor'; END IF;
  EXECUTE 'RESET ROLE';
  EXECUTE 'SET LOCAL ROLE anon';
  PERFORM set_config('request.jwt.claims', '{"role":"anon"}', true);
  SELECT count(*) INTO v_n FROM storage.objects WHERE bucket_id = 'chat_attachments';
  EXECUTE 'RESET ROLE';
  IF v_n <> 0 THEN RAISE EXCEPTION '[11] anon sohbet fotoğrafı görüyor'; END IF;
  v_checks := v_checks + 1;

  -- [12] yetkiler ve kova
  IF to_regprocedure('public.send_message_with_recipient(uuid, text, uuid, uuid, text, text)') IS NOT NULL THEN
    RAISE EXCEPTION '[12] eski 6 parametreli aşırı yükleme duruyor (PostgREST belirsizliği)';
  END IF;
  IF NOT has_function_privilege('authenticated',
       'public.send_message_with_recipient(uuid, text, uuid, uuid, text, text, text, jsonb)', 'EXECUTE')
     OR has_function_privilege('anon',
       'public.send_message_with_recipient(uuid, text, uuid, uuid, text, text, text, jsonb)', 'EXECUTE') THEN
    RAISE EXCEPTION '[12] yetkiler yanlış';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM storage.buckets
     WHERE id = 'chat_attachments' AND NOT public AND file_size_limit = 10485760
       AND allowed_mime_types @> ARRAY['image/jpeg', 'image/png']
  ) THEN RAISE EXCEPTION '[12] kova ayarı yanlış'; END IF;
  SELECT count(*) INTO v_n FROM pg_policies
   WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname LIKE 'chat_attachments_%';
  IF v_n <> 3 THEN RAISE EXCEPTION '[12] depo politikası sayısı %', v_n; END IF;
  v_checks := v_checks + 1;

  RAISE EXCEPTION 'TESTS_PASSED % kontrol', v_checks;
END
$test$;
