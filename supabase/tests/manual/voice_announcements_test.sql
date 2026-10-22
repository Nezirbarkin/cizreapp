-- Kendini geri alan canlı test (sonunda bilerek RAISE EXCEPTION 'TESTS_PASSED ...').
-- Çalıştırma: supabase db query --linked --file supabase/tests/manual/voice_announcements_test.sql
-- Sabit kimlikler canlıdaki gerçek admin/müşteri/satıcı/kurye/dükkân satırlarıdır; silinirse güncelleyin.
-- Görev 1 kuru çalıştırma testi: göç gövdesi + doğrulamalar; sonunda bilerek
-- RAISE EXCEPTION ile her şey geri alınır.
do $$
declare
  v_admin uuid := '78665f8b-6a07-40f3-b13d-d4b5a29296c6';
  v_cust  uuid := '5daa4020-0e58-41ef-9336-54c5058295ec';
  v_log   text := '';
  v_s     jsonb;
  v_res   jsonb;
  v_cid   uuid;
  v_meta  jsonb;
  v_hist  record;
  v_n     integer;
begin
  -- Ayar okuyucu
  v_s := public.voice_announce_settings();
  if v_s->>'enabled' <> 'true' or v_s->>'gender' <> 'female'
     or v_s->>'areas' <> 'admin_notifications,startup,seller,courier'
     or v_s->>'greeting' <> 'true' then
    raise exception 'FAIL settings %', v_s;
  end if;
  v_log := v_log || 'settings ok; ';

  -- 'none' → boş alan listesi
  update public.app_settings set value = '"none"'::jsonb where key = 'voice_announce_areas';
  if public.voice_announce_settings()->>'areas' <> '' then
    raise exception 'FAIL areas none';
  end if;
  update public.app_settings set value = '"male"'::jsonb where key = 'voice_announce_gender';
  if public.voice_announce_settings()->>'gender' <> 'male' then
    raise exception 'FAIL gender male';
  end if;
  v_log := v_log || 'areas none/male ok; ';

  -- Tercih sütunları varsayılan true
  if exists (select 1 from public.notification_preferences
             where voice_announcements_enabled is distinct from true
                or notification_sound_enabled is distinct from true) then
    raise exception 'FAIL pref defaults';
  end if;
  v_log := v_log || 'pref defaults ok; ';

  -- Admin olarak gönder (yeni imza, sesli alanlarla)
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);

  v_res := public.admin_send_notification(
    'personal', 'Test başlık', 'Test içerik', 'info', array[v_cust], null,
    '  Sesli metin  ', 'MALE');
  v_cid := (v_res->>'campaign_id')::uuid;
  select metadata into v_meta from public.notifications
   where metadata @> jsonb_build_object('campaign_id', v_cid) and user_id = v_cust;
  if v_meta->>'voice_text' <> 'Sesli metin' or v_meta->>'voice_gender' <> 'male' then
    raise exception 'FAIL meta %', v_meta;
  end if;
  v_log := v_log || 'send+meta ok; ';

  -- Eski imza (named, sesli alan yok) çalışır ve metadata'da voice yok
  v_res := public.admin_send_notification(
    p_audience => 'personal', p_title => 'Eski', p_content => 'Eski içerik',
    p_icon_type => 'info', p_user_ids => array[v_cust], p_scheduled_for => null);
  select metadata into v_meta from public.notifications
   where metadata @> jsonb_build_object('campaign_id', (v_res->>'campaign_id')::uuid);
  if v_meta ? 'voice_text' or v_meta ? 'voice_gender' then
    raise exception 'FAIL old sig meta %', v_meta;
  end if;
  v_log := v_log || 'old sig ok; ';

  -- Eski sarmalayıcı (7 argümanla create çağırır)
  perform public.admin_send_personal_notification(v_cust, 'Kişisel', 'Kişisel içerik', 'info');
  v_log := v_log || 'personal wrapper ok; ';

  -- Sesli metni düzelt
  v_n := public.admin_set_campaign_voice(v_cid, 'Yeni sesli', null);
  select metadata into v_meta from public.notifications
   where metadata @> jsonb_build_object('campaign_id', v_cid) and user_id = v_cust;
  if v_n <> 1 or v_meta->>'voice_text' <> 'Yeni sesli' or v_meta ? 'voice_gender' then
    raise exception 'FAIL set voice n=% meta=%', v_n, v_meta;
  end if;
  v_log := v_log || 'set voice ok; ';

  -- Geçmiş yeni sütunları döndürür
  select * into v_hist from public.admin_notification_history(50) h where h.id = v_cid;
  if v_hist.voice_text <> 'Yeni sesli' or v_hist.voice_gender is not null then
    raise exception 'FAIL history %', row_to_json(v_hist);
  end if;
  v_log := v_log || 'history ok; ';

  -- Çok uzun sesli metin reddedilir
  begin
    perform public.admin_send_notification(
      'personal', 'T', 'C', 'info', array[v_cust], null, repeat('a', 1001), null);
    raise exception 'FAIL long voice accepted';
  exception when sqlstate '22000' then
    v_log := v_log || 'long voice rejected ok; ';
  end;

  -- Admin olmayan kullanıcı set_campaign_voice çağıramaz
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_cust, 'role', 'authenticated')::text, true);
  begin
    perform public.admin_set_campaign_voice(v_cid, 'x', null);
    raise exception 'FAIL non-admin allowed';
  exception when sqlstate '42501' then
    v_log := v_log || 'non-admin blocked ok; ';
  end;

  raise exception 'TESTS_PASSED %', v_log;
end;
$$;
