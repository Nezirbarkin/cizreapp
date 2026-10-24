-- ============================================================================
-- 20261024000001_new_member_messages — canlı davranış testi
-- ----------------------------------------------------------------------------
-- Kendi kendini geri alır: DO bloğu sonunda bilerek RAISE EXCEPTION atar,
-- her şey geri alınır, CLI özet satırlarını hata mesajı olarak yazdırır.
-- Göç uygulanmadan önce denemek için göç gövdesini (BEGIN/COMMIT/NOTIFY
-- hariç) @@MIGRATION@@ satırının yerine koyun; uygulandıktan sonra olduğu
-- gibi çalıştırın:
--   supabase db query --linked --file supabase/tests/manual/new_member_messages_test.sql
-- Beklenen: "TESTS_DONE" mesajında FAIL satırı yok.
-- ============================================================================
BEGIN;

-- @@MIGRATION@@

DO $test$
declare
  v_u1 uuid; v_u2 uuid; v_bot uuid; v_old uuid; v_admin uuid; v_stranger uuid;
  v_welcome uuid; v_profile uuid; v_post_step uuid;
  v_n int;
  v_txt text;
  v_meta jsonb;
  v_j jsonb;
  v_id uuid;
  v_has_post boolean;
  r text := '';
begin
  -- ------------------------------------------------------------ fikstürler
  select p.id into v_u1
  from public.profiles p join auth.users au on au.id = p.id
  where not coalesce(p.is_bot, false) and not coalesce(au.is_anonymous, false)
    and au.deleted_at is null and coalesce(p.status::text, 'active') = 'active'
    and coalesce(p.role::text, 'user') <> 'admin'
    and nullif(btrim(coalesce(p.full_name, '')), '') is not null
  order by p.id limit 1;

  select p.id into v_u2
  from public.profiles p join auth.users au on au.id = p.id
  where p.id <> v_u1 and not coalesce(p.is_bot, false) and not coalesce(au.is_anonymous, false)
    and au.deleted_at is null and coalesce(p.status::text, 'active') = 'active'
    and coalesce(p.role::text, 'user') <> 'admin'
  order by p.id limit 1;

  select p.id into v_bot from public.profiles p where coalesce(p.is_bot, false) order by p.id limit 1;

  select p.id into v_old
  from public.profiles p join auth.users au on au.id = p.id
  where p.id not in (v_u1, v_u2) and not coalesce(p.is_bot, false)
    and not coalesce(au.is_anonymous, false) and au.deleted_at is null
    and coalesce(p.status::text, 'active') = 'active'
  order by p.id limit 1;

  select p.id into v_stranger
  from public.profiles p
  where p.id not in (v_u1, v_u2, v_old) and not coalesce(p.is_bot, false)
    and coalesce(p.role::text, 'user') <> 'admin' and not coalesce(p.is_admin, false)
  order by p.id limit 1;

  select p.id into v_admin from public.profiles p where p.role::text = 'admin' order by p.id limit 1;

  select id into v_welcome   from public.new_member_message_steps where step_key = 'welcome';
  select id into v_profile   from public.new_member_message_steps where step_key = 'complete_profile';
  select id into v_post_step from public.new_member_message_steps where step_key = 'first_post';

  r := r || chr(10) || format('fixtures u1=%s u2=%s bot=%s old=%s admin=%s steps=%s',
         v_u1 is not null, v_u2 is not null, v_bot is not null, v_old is not null,
         v_admin is not null, (select count(*) from public.new_member_message_steps));

  -- Deterministik ortam: tüm adımlar 10 gün önce açılmış, sessiz saat yok sayılır,
  -- ana anahtar 10 gün önce açılmış.
  update public.new_member_message_steps
     set activated_at = now() - interval '10 days', respect_quiet_hours = false, is_active = true
   where true;
  update public.app_settings set value = '"true"'::jsonb where key = 'new_member_messages_enabled';
  update public.app_settings set value = to_jsonb((now() - interval '10 days')::text)
   where key = 'new_member_messages_enabled_at';

  -- ------------------------------------------------------------ saf yardımcılar
  r := r || chr(10) || case when private.new_member_fill('Merhaba {ad}, x', '') = 'Merhaba, x'
    then 'PASS fill bos ad' else 'FAIL fill bos ad: ' || private.new_member_fill('Merhaba {ad}, x', '') end;
  r := r || chr(10) || case when private.new_member_fill('Hoş geldin {ad} 👋', 'Ali') = 'Hoş geldin Ali 👋'
    then 'PASS fill ad' else 'FAIL fill ad' end;
  r := r || chr(10) || case when private.new_member_fill('{ad}, profilini tamamla', '') = 'profilini tamamla'
    then 'PASS fill bastaki ad' else 'FAIL fill bastaki ad: ' || private.new_member_fill('{ad}, profilini tamamla', '') end;
  r := r || chr(10) || case when private.new_member_first_name('', 'misafir_ab12') = ''
       and private.new_member_first_name('Ayşe  Nur', 'x') = 'Ayşe'
       and private.new_member_first_name(null, 'veli') = 'veli'
    then 'PASS first_name' else 'FAIL first_name' end;
  r := r || chr(10) || case
       when private.new_member_is_quiet('2026-10-24 20:30:00+00')      -- 23:30 TR
        and private.new_member_is_quiet('2026-10-24 05:30:00+00')      -- 08:30 TR
        and not private.new_member_is_quiet('2026-10-24 06:30:00+00')  -- 09:30 TR
        and not private.new_member_is_quiet('2026-10-24 18:30:00+00')  -- 21:30 TR
    then 'PASS sessiz saat' else 'FAIL sessiz saat' end;

  -- ------------------------------------------------------------ hoş geldin (token var)
  update public.profiles
     set created_at = now() - interval '3 minutes', fcm_token = 'test-token-u1',
         needs_username = false, avatar_url = null
   where id = v_u1;
  perform private.process_new_member_messages();

  select n.title, n.metadata into v_txt, v_meta
  from public.new_member_message_deliveries d
  join public.notifications n on n.id = d.notification_id
  where d.user_id = v_u1 and d.step_id = v_welcome and d.status = 'sent';
  r := r || chr(10) || case when v_txt is not null
       and v_txt like '%' || private.new_member_first_name(
             (select full_name from public.profiles where id = v_u1), null) || '%'
       and v_meta->>'voice_text' like '%{ad}%'
       and v_meta->>'icon_type' = 'gift'
       and not (v_meta ? 'route')
    then 'PASS hos geldin gitti: ' || v_txt else 'FAIL hos geldin: ' || coalesce(v_txt, 'yok') end;

  select count(*) into v_n from public.notifications
  where user_id = v_u1 and type = 'new_member' and entity_id = 'admin_icon:gift';
  perform private.process_new_member_messages();
  r := r || chr(10) || case when (select count(*) from public.notifications
       where user_id = v_u1 and type = 'new_member' and entity_id = 'admin_icon:gift') = v_n and v_n = 1
    then 'PASS ikinci gonderim yok' else 'FAIL ikinci gonderim n=' || v_n end;

  r := r || chr(10) || case when exists (select 1 from public.notification_outbox o
       join public.notifications n on n.id = o.notification_id
       where n.user_id = v_u1 and n.type = 'new_member')
    then 'PASS outbox satiri' else 'FAIL outbox satiri yok' end;

  -- ------------------------------------------------------------ koşullu adımlar
  -- 61 dk: profil fotoğrafı yok → gider; ilk gönderi adımı (1 gün) henüz değil.
  update public.profiles set created_at = now() - interval '61 minutes' where id = v_u1;
  perform private.process_new_member_messages();
  select (n.metadata->>'route') into v_txt
  from public.new_member_message_deliveries d
  join public.notifications n on n.id = d.notification_id
  where d.user_id = v_u1 and d.step_id = v_profile and d.status = 'sent';
  r := r || chr(10) || case when v_txt = 'edit_profile'
    then 'PASS profil adimi + rota' else 'FAIL profil adimi: ' || coalesce(v_txt, 'yok') end;
  r := r || chr(10) || case when not exists (select 1 from public.new_member_message_deliveries
       where user_id = v_u1 and step_id = v_post_step)
    then 'PASS gecikmesi dolmayan adim yok' else 'FAIL erken adim' end;

  -- Fotoğraflı kullanıcıda profil adımı atlanır.
  update public.profiles
     set created_at = now() - interval '61 minutes', fcm_token = 'test-token-u2',
         needs_username = false, avatar_url = 'https://example.com/a.jpg'
   where id = v_u2;
  perform private.process_new_member_messages();
  r := r || chr(10) || case when (select status from public.new_member_message_deliveries
       where user_id = v_u2 and step_id = v_profile) = 'skipped'
    then 'PASS fotografli kullanici atlandi' else 'FAIL fotograf kosulu' end;

  -- 1 gün: gönderisi olan atlanır, olmayan alır.
  v_has_post := exists (select 1 from public.posts where user_id = v_u2);
  update public.profiles set created_at = now() - interval '1 day 5 minutes' where id = v_u2;
  perform private.process_new_member_messages();
  r := r || chr(10) || case when (select status from public.new_member_message_deliveries
       where user_id = v_u2 and step_id = v_post_step)
       = case when v_has_post then 'skipped' else 'sent' end
    then 'PASS ilk gonderi kosulu (gonderi=' || v_has_post || ')' else 'FAIL ilk gonderi kosulu' end;

  -- ------------------------------------------------------------ token bekleme
  delete from public.new_member_message_deliveries where user_id = v_u2;
  delete from public.notification_tokens where user_id = v_u2;
  update public.profiles set created_at = now() - interval '5 minutes', fcm_token = null where id = v_u2;
  perform private.process_new_member_messages();
  r := r || chr(10) || case when not exists (select 1 from public.new_member_message_deliveries
       where user_id = v_u2 and step_id = v_welcome)
    then 'PASS token yokken bekledi' else 'FAIL token beklemedi' end;

  update public.profiles set created_at = now() - interval '40 minutes' where id = v_u2;
  perform private.process_new_member_messages();
  r := r || chr(10) || case when (select status from public.new_member_message_deliveries
       where user_id = v_u2 and step_id = v_welcome) = 'sent'
    then 'PASS 30 dk sonra tokensiz gitti' else 'FAIL 30 dk sonra gitmedi' end;

  -- ------------------------------------------------------------ hariç tutulanlar
  if v_bot is not null then
    update public.profiles set created_at = now() - interval '3 minutes', fcm_token = 'test-token-bot'
     where id = v_bot;
    perform private.process_new_member_messages();
    r := r || chr(10) || case when not exists (select 1 from public.new_member_message_deliveries where user_id = v_bot)
      then 'PASS bot haric' else 'FAIL bot aldi' end;
  end if;

  update public.profiles set created_at = now() - interval '11 days', fcm_token = 'test-token-old' where id = v_old;
  perform private.process_new_member_messages();
  r := r || chr(10) || case when not exists (select 1 from public.new_member_message_deliveries where user_id = v_old)
    then 'PASS eski uye geriye donuk almadi' else 'FAIL eski uye aldi' end;

  -- Ana anahtar kapalı → hiçbir şey gitmez.
  update public.app_settings set value = '"false"'::jsonb where key = 'new_member_messages_enabled';
  update public.profiles set created_at = now() - interval '3 minutes', fcm_token = 'test-token-old',
         needs_username = false where id = v_old;
  perform private.process_new_member_messages();
  r := r || chr(10) || case when not exists (select 1 from public.new_member_message_deliveries where user_id = v_old)
    then 'PASS ana anahtar kapali' else 'FAIL ana anahtar kapaliyken gitti' end;
  update public.app_settings set value = '"true"'::jsonb where key = 'new_member_messages_enabled';

  -- ------------------------------------------------------------ sahte karşılama
  perform set_config('request.jwt.claims', json_build_object('sub', v_stranger, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  select public.add_notification(v_u1, 'new_member', 'sahte', 'sahte') into v_id;
  r := r || chr(10) || case when v_id is null then 'PASS istemci new_member yazamadi' else 'FAIL sahte new_member' end;
  select public.add_notification(v_u1, 'product_review_reply', 'sahte', 'sahte') into v_id;
  r := r || chr(10) || case when v_id is null then 'PASS istemci review_reply yazamadi' else 'FAIL sahte review_reply' end;
  begin
    perform public.admin_new_member_steps();
    r := r || chr(10) || 'FAIL admin olmayan seriyi okudu';
  exception when insufficient_privilege then
    r := r || chr(10) || 'PASS admin olmayan seriyi okuyamadi';
  end;
  begin
    perform 1 from public.new_member_message_steps;
    r := r || chr(10) || 'FAIL tablo istemciye acik';
  exception when insufficient_privilege then
    r := r || chr(10) || 'PASS tablo istemciye kapali';
  end;
  execute 'reset role';

  -- ------------------------------------------------------------ admin RPC'leri
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  v_j := public.admin_new_member_steps();
  r := r || chr(10) || case when jsonb_array_length(v_j->'steps') >= 5 and (v_j->>'enabled')::boolean
       and ((v_j->'steps'->0)->>'sent')::int >= 2
    then 'PASS admin listesi + sayaclar' else 'FAIL admin listesi: ' || left(v_j::text, 200) end;

  v_id := public.admin_send_new_member_step_test(v_welcome);
  r := r || chr(10) || case when v_id is not null
    then 'PASS test gonderimi' else 'FAIL test gonderimi' end;

  v_j := public.admin_upsert_new_member_step(null, 'Özel adım {ad}', 'Metin', '{ad} dinle', 'male',
                                              'campaign', 120, 'no_order', 'market', true, true);
  r := r || chr(10) || case when v_j->>'icon' = 'campaign' and (v_j->>'step_key') like 'custom\_%'
       and v_j->>'voice_gender' = 'male'
    then 'PASS ozel adim eklendi' else 'FAIL ozel adim: ' || left(v_j::text, 200) end;

  begin
    perform public.admin_upsert_new_member_step(null, '', 'x', null, null, 'gift', 1, 'always', null, true, true);
    r := r || chr(10) || 'FAIL bos baslik kabul edildi';
  exception when others then
    r := r || chr(10) || 'PASS bos baslik reddedildi';
  end;

  perform public.admin_set_new_member_step_active(v_profile, false);
  perform public.admin_set_new_member_step_active(v_profile, true);
  perform public.admin_delete_new_member_step((v_j->>'id')::uuid);
  perform public.admin_set_new_member_messages_enabled(false);
  perform public.admin_set_new_member_messages_enabled(true);
  execute 'reset role';

  r := r || chr(10) || case when (select activated_at from public.new_member_message_steps where id = v_profile) = now()
    then 'PASS yeniden acilinca activated_at yenilendi' else 'FAIL activated_at' end;
  r := r || chr(10) || case when not exists (select 1 from public.new_member_message_steps where id = (v_j->>'id')::uuid)
    then 'PASS ozel adim silindi' else 'FAIL ozel adim silinmedi' end;
  r := r || chr(10) || case when private.new_member_enabled_at() = now()
    then 'PASS yeniden acilinca enabled_at yenilendi' else 'FAIL enabled_at' end;
  r := r || chr(10) || case when not exists (select 1 from public.new_member_message_deliveries where status = 'failed')
    then 'PASS basarisiz teslim yok' else 'FAIL basarisiz teslim var' end;

  raise exception 'TESTS_DONE %', r;
end;
$test$;

ROLLBACK;
