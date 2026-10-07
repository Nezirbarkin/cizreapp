-- =============================================================================
-- send_message_lock_order_test.sql  (bkz. 20261007000002_send_message_lock_order.sql)
-- -----------------------------------------------------------------------------
-- Canlıda KENDİNİ GERİ ALAN test: tek bir DO bloğu, sonunda bilerek RAISE
-- EXCEPTION ile biter; bloktaki her şey geri alınır, CLI sonucu hata mesajı
-- olarak yazdırır. Çalıştırma:
--   supabase db query --linked --file supabase/tests/manual/send_message_lock_order_test.sql
-- Beklenen: TEST_RESULT [1] msg=t rcpt_msg=t ba_created=t unread_ba=1 unread_ab=0;
--           [2] msg=t unread_ab=1 unread_ba=0 msgs=4; [3] spoof blocked: 42501;
--
-- İki bot hesabı kullanılır (giriş yapamazlar). Eşzamanlı deadlock'un
-- kendisi tek oturumdan üretilemez; burada kilit eklemesinin normal akışı,
-- alıcı satırı yokken oluşturma (ON CONFLICT) yolunu ve gönderen kontrolünü
-- bozmadığı doğrulanır.
-- =============================================================================
DO $$
DECLARE
  v_a uuid;
  v_b uuid;
  v_conv_ab uuid;
  v_conv_ba uuid;
  r record;
  v_log text := '';
  v_unread_ba int;
  v_unread_ab int;
  v_msgs int;
BEGIN
  SELECT id INTO v_a FROM public.profiles WHERE is_bot ORDER BY id LIMIT 1;
  SELECT id INTO v_b FROM public.profiles WHERE is_bot AND id <> v_a ORDER BY id DESC LIMIT 1;

  -- Temiz başlangıç: aralarındaki konuşmalar silinir (geri alınacak).
  DELETE FROM public.conversations
   WHERE (user_id = v_a AND other_user_id = v_b) OR (user_id = v_b AND other_user_id = v_a);

  INSERT INTO public.conversations (user_id, other_user_id) VALUES (v_a, v_b)
  RETURNING id INTO v_conv_ab;

  -- 1) A -> B: B'nin satırı YOK, RPC oluşturmalı.
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
  SELECT * INTO r FROM public.send_message_with_recipient(v_conv_ab, 'lock-order test 1', v_a);

  SELECT id, unread_count INTO v_conv_ba, v_unread_ba FROM public.conversations WHERE user_id = v_b AND other_user_id = v_a;
  SELECT unread_count INTO v_unread_ab FROM public.conversations WHERE id = v_conv_ab;
  v_log := v_log || format('[1] msg=%s rcpt_msg=%s ba_created=%s unread_ba=%s unread_ab=%s; ',
    r.message_id IS NOT NULL, r.recipient_message_id IS NOT NULL, v_conv_ba IS NOT NULL, v_unread_ba, v_unread_ab);

  -- 2) B -> A: iki satır da var; A'nın okunmamışı 1, B'ninki 0 olmalı.
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_b, 'role', 'authenticated')::text, true);
  SELECT * INTO r FROM public.send_message_with_recipient(v_conv_ba, 'lock-order test 2', v_b);

  SELECT unread_count INTO v_unread_ab FROM public.conversations WHERE id = v_conv_ab;
  SELECT unread_count INTO v_unread_ba FROM public.conversations WHERE id = v_conv_ba;
  SELECT count(*) INTO v_msgs FROM public.messages WHERE conversation_id IN (v_conv_ab, v_conv_ba);
  v_log := v_log || format('[2] msg=%s unread_ab=%s unread_ba=%s msgs=%s; ',
    r.message_id IS NOT NULL, v_unread_ab, v_unread_ba, v_msgs);

  -- 3) Gönderen kontrolü korunuyor mu: A, B adına gönderemez.
  BEGIN
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_a, 'role', 'authenticated')::text, true);
    PERFORM public.send_message_with_recipient(v_conv_ba, 'spoof', v_b);
    v_log := v_log || '[3] SPOOF ALLOWED (BAD); ';
  EXCEPTION WHEN OTHERS THEN
    v_log := v_log || format('[3] spoof blocked: %s; ', SQLSTATE);
  END;

  RAISE EXCEPTION 'TEST_RESULT %', v_log;
END $$;
