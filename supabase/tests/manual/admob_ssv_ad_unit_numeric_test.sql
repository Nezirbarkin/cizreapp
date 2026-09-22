-- =============================================================================
-- Elle çalıştırılan test: Google SSV `ad_unit` biçimi (sayısal) grant_verified_ad_points
-- tarafından kabul ediliyor mu?
-- =============================================================================
-- Google, callback'te `ad_unit` olarak YALNIZ sayısal kimliği yollar; ad_settings
-- ise tam kimliği (ca-app-pub-.../...) saklar. Fonksiyon ikisini de kabul etmeli,
-- yanlış birimi / başka yayıncıyı reddetmelidir. (Geçmişte yalnız tam kimlik
-- kabul ediliyordu → gerçek her ödül AD_UNIT_NOT_ALLOWED ile düşecekti.)
--
-- Tek DO bloğudur; sonunda bilerek RAISE EXCEPTION ile HER ŞEYİ geri alır, sonucu
-- hata mesajında yazdırır ("failures=0" beklenir). Canlı veriye dokunmaz.
-- Çalıştırma:
--   supabase db query --linked --file supabase/tests/manual/admob_ssv_ad_unit_numeric_test.sql
-- =============================================================================
do $test$
declare
  u uuid[];
  full_a text; full_i text; num_a text; num_i text;
  log text := ''; failures int := 0; got text;
begin

  execute $h$
    create or replace function pg_temp.try_grant(p_uid uuid, p_tag text, p_unit text)
    returns text language plpgsql as $f$
    declare
      v_nonce text := md5(p_tag) || md5(p_tag || ':n');
      v_tx    text := md5(p_tag || ':t') || md5(p_tag || ':u');
      v_sess  jsonb;
      v_res   jsonb;
      v_err   text;
    begin
      perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
      v_sess := public.create_ad_reward_session(p_uid, v_nonce, 'sim-' || p_tag || '-idem', null, null);
      v_res := public.grant_verified_ad_points(
        (v_sess ->> 'reward_session_id')::uuid, v_tx, v_tx, p_unit, 'key1', now(), v_nonce, null);
      select e.verification_error_code into v_err
        from public.ad_reward_ssv_events e
       where e.session_id = (v_sess ->> 'reward_session_id')::uuid;
      return (v_res ->> 'status') || '/' || coalesce(v_err, '-');
    exception when others then
      return 'error/' || sqlstate || ' ' || sqlerrm;
    end
    $f$;
  $h$;

  select array_agg(id) into u from (select id from public.profiles order by created_at limit 8) s;
  if coalesce(array_length(u, 1), 0) < 4 then
    raise exception 'TEST_SETUP: en az 4 profil gerekli (bulunan: %)', coalesce(array_length(u, 1), 0);
  end if;
  select admob_rewarded_unit_id_android, admob_rewarded_unit_id_ios
    into full_a, full_i from public.ad_settings where id = 1;
  num_a := split_part(full_a, '/', 2);
  num_i := split_part(full_i, '/', 2);
  log := 'android tam=' || full_a || ' sayisal=' || num_a || E'\nios tam=' || full_i || ' sayisal=' || num_i || E'\n';

  -- Beklenen kabuller (her biri ayrı kullanıcı: bekleme/saatlik limit karışmasın)
  got := pg_temp.try_grant(u[1], 'num_android',  num_a);
  log := log || rpad('GOOGLE sayisal android', 34) || ' -> ' || got || E'\n';
  if got <> 'credited/-' then failures := failures + 1; end if;

  got := pg_temp.try_grant(u[2], 'num_ios',      num_i);
  log := log || rpad('GOOGLE sayisal ios', 34) || ' -> ' || got || E'\n';
  if got <> 'credited/-' then failures := failures + 1; end if;

  got := pg_temp.try_grant(u[3], 'full_android', full_a);
  log := log || rpad('tam kimlik android (eski davranis)', 34) || ' -> ' || got || E'\n';
  if got <> 'credited/-' then failures := failures + 1; end if;

  got := pg_temp.try_grant(u[4], 'full_ios',     full_i);
  log := log || rpad('tam kimlik ios (eski davranis)', 34) || ' -> ' || got || E'\n';
  if got <> 'credited/-' then failures := failures + 1; end if;

  -- Beklenen retler
  got := pg_temp.try_grant(u[1], 'wrong_numeric', '1111111111');
  log := log || rpad('yanlis sayisal birim', 34) || ' -> ' || got || E'\n';
  if got <> 'rejected/AD_UNIT_NOT_ALLOWED' then failures := failures + 1; end if;

  got := pg_temp.try_grant(u[1], 'other_publisher', 'ca-app-pub-9999999999999999/' || num_a);
  log := log || rpad('baska yayinci + ayni sayisal', 34) || ' -> ' || got || E'\n';
  if got <> 'rejected/AD_UNIT_NOT_ALLOWED' then failures := failures + 1; end if;

  got := pg_temp.try_grant(u[1], 'prefix_only', '3604161523594294');
  log := log || rpad('yalniz yayinci kismi', 34) || ' -> ' || got || E'\n';
  if got <> 'rejected/AD_UNIT_NOT_ALLOWED' then failures := failures + 1; end if;

  -- Yetkiler ve sahip degismemeli
  log := log || 'sahip=' || (select pg_get_userbyid(proowner) from pg_proc
        where oid = 'public.grant_verified_ad_points(uuid,text,text,text,text,timestamptz,text,text)'::regprocedure)
    || ' service_role_exec=' || has_function_privilege('service_role',
        'public.grant_verified_ad_points(uuid,text,text,text,text,timestamptz,text,text)', 'EXECUTE')
    || ' anon_exec=' || has_function_privilege('anon',
        'public.grant_verified_ad_points(uuid,text,text,text,text,timestamptz,text,text)', 'EXECUTE')
    || ' authenticated_exec=' || has_function_privilege('authenticated',
        'public.grant_verified_ad_points(uuid,text,text,text,text,timestamptz,text,text)', 'EXECUTE') || E'\n';
  if not has_function_privilege('service_role', 'public.grant_verified_ad_points(uuid,text,text,text,text,timestamptz,text,text)', 'EXECUTE')
     or has_function_privilege('anon', 'public.grant_verified_ad_points(uuid,text,text,text,text,timestamptz,text,text)', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.grant_verified_ad_points(uuid,text,text,text,text,timestamptz,text,text)', 'EXECUTE') then
    failures := failures + 1;
  end if;

  raise exception E'SSV_AD_UNIT_TEST failures=% (geri alindi)\n%', failures, log;
end
$test$;
