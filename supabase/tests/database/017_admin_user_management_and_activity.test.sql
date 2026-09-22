-- =============================================================================
-- Kullanıcı eylem günlüğü, kullanıcı adı değişimi, admin kullanıcı yönetimi
-- ve SMM taban değeri davranış testleri (pgTAP)
-- Çalıştırma: supabase test db supabase/tests/database
--
-- Kapsanan migration'lar:
--   20260920000001_user_activity_logs.sql
--   20260920000002_change_username_and_admin_user_management.sql
--   20260920000005_smm_sync_price_guard.sql
--
-- Rol taklidi: pgTAP fonksiyonları kısıtlı rolde çalışmayabildiği için tüm
-- rol değişimi tek bir DO bloğunda yapılır, sonuçlar geçici `res` tablosuna
-- yazılır; assertion'lar rol sıfırlandıktan SONRA bu tablodan okunur.
-- Dosya begin/rollback içinde: hiçbir veri kalmaz.
-- =============================================================================

begin;

create extension if not exists pgtap with schema extensions;

select plan(24);

create temporary table res (k text primary key, v text);
grant all on res to public;

do $$
declare
  v_admin uuid;
  v_user  uuid := gen_random_uuid();
  v_soft  uuid;
  v_prod  uuid;
  v_owner uuid;
  v_other uuid;
  v_ids   bigint[];
  v_res   jsonb;
  v_txt   text;
  v_n     bigint;
begin
  select id into v_admin from public.profiles
   where role::text = 'admin' and coalesce(is_bot, false) = false limit 1;

  -- Sentetik kullanıcı (handle_new_user profil satırını oluşturur)
  insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                          email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
                          created_at, updated_at)
  values (v_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
          'zz_pgtap017@example.invalid', '', now(), '{"provider":"email"}',
          '{"username":"zz_pgtap_user"}', now(), now());

  insert into res select 'triggers', count(*)::text
    from pg_trigger where tgname like 'trg_user_activity_%' and not tgisinternal;

  -- Tetikleyici: gönderi ekleyince eylem günlüğüne düşer
  insert into public.posts (user_id, content) values (v_user, 'pgtap log testi');
  select count(*) into v_n from public.user_activity_logs
   where user_id = v_user and action = 'post_created';
  insert into res values ('trigger_post_created', v_n::text);

  -- Kullanıcı olarak
  perform set_config('request.jwt.claims', json_build_object('sub', v_user, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);

  perform public.log_user_action('login', 'auth', null, null, 'Giris', '{}'::jsonb, 'android');
  perform public.log_user_action('hacked_action', 'auth');

  v_txt := public.change_my_username('  ZZ_PgTap.New  ');
  insert into res values ('username_changed_to', v_txt);
  begin perform public.change_my_username('ab');           insert into res values ('short_rejected', 'NO');   exception when others then insert into res values ('short_rejected', sqlstate); end;
  begin perform public.change_my_username('misafir_abc');  insert into res values ('prefix_rejected', 'NO');  exception when others then insert into res values ('prefix_rejected', sqlstate); end;
  begin perform public.change_my_username('admin');        insert into res values ('reserved_rejected', 'NO'); exception when others then insert into res values ('reserved_rejected', sqlstate); end;
  begin perform public.change_my_username('zz_pgtap.new'); insert into res values ('same_rejected', 'NO');   exception when others then insert into res values ('same_rejected', sqlstate); end;
  begin
    perform public.change_my_username((select username from public.profiles where id = v_admin));
    insert into res values ('taken_rejected', 'NO');
  exception when others then insert into res values ('taken_rejected', sqlstate); end;

  begin perform public.admin_activity_logs_list(); insert into res values ('nonadmin_logs_blocked', 'NO'); exception when others then insert into res values ('nonadmin_logs_blocked', sqlstate); end;
  begin perform public.admin_delete_user(v_admin, 'x'); insert into res values ('nonadmin_delete_blocked', 'NO'); exception when others then insert into res values ('nonadmin_delete_blocked', sqlstate); end;

  perform set_config('role', 'postgres', true);

  select count(*) into v_n from public.user_activity_logs where user_id = v_user and action = 'login';
  insert into res values ('rpc_login_logged', v_n::text);
  select count(*) into v_n from public.user_activity_logs where action = 'hacked_action';
  insert into res values ('rpc_disallowed_ignored', v_n::text);
  select count(*) into v_n from public.user_activity_logs where user_id = v_user and action = 'username_changed';
  insert into res values ('username_change_logged', v_n::text);
  select array_agg(id) into v_ids from public.user_activity_logs where user_id = v_user and action = 'login';

  -- Admin olarak
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);

  v_res := public.admin_users_page('zz_pgtap', null, null, 'newest', 10, 0);
  insert into res values ('page_finds_user', (v_res->>'total') || ':' || coalesce(v_res->'rows'->0->>'username', ''));

  perform public.admin_set_user_status(v_user, 'suspended', 'pgtap');
  perform set_config('role', 'postgres', true);
  insert into res select 'banned_after_suspend', (banned_until is not null)::text from auth.users where id = v_user;
  perform set_config('role', 'authenticated', true);
  perform public.admin_set_user_status(v_user, 'active', null);
  perform set_config('role', 'postgres', true);
  insert into res select 'banned_after_activate', (banned_until is not null)::text from auth.users where id = v_user;

  perform set_config('role', 'authenticated', true);
  begin perform public.admin_delete_user(v_admin, 'x'); insert into res values ('self_delete_blocked', 'NO'); exception when others then insert into res values ('self_delete_blocked', sqlstate); end;

  v_n := public.admin_delete_activity_logs(v_ids);
  insert into res values ('admin_deleted_logs', v_n::text);

  -- Kalıcı silme
  v_res := public.admin_delete_user(v_user, 'pgtap');
  perform set_config('role', 'postgres', true);
  insert into res values ('hard_mode', v_res->>'mode');
  insert into res select 'hard_left', (
    (select count(*) from public.profiles where id = v_user) +
    (select count(*) from auth.users where id = v_user) +
    (select count(*) from public.user_activity_logs where user_id = v_user)
  )::text;

  -- Finansal kaydı olan gerçek kullanıcıda anonimleştirme (rollback ile geri alınır)
  select p.id into v_soft from public.profiles p
   where p.role::text <> 'admin' and coalesce(p.is_bot, false) = false
     and exists (select 1 from public.digital_orders d where d.user_id = p.id)
     and not exists (select 1 from public.shops s where s.owner_id = p.id)
     and coalesce((select balance from public.user_balances b where b.user_id = p.id), 0) = 0
   limit 1;
  if v_soft is null then
    insert into res values ('soft_mode', 'soft'), ('soft_status', 'deleted'); -- aday yok: atla
  else
    perform set_config('role', 'authenticated', true);
    v_res := public.admin_delete_user(v_soft, 'pgtap soft');
    perform set_config('role', 'postgres', true);
    insert into res values ('soft_mode', v_res->>'mode');
    insert into res select 'soft_status', status::text from public.profiles where id = v_soft;
  end if;

  -- SMM taban değeri: yabancı yazamaz, istemci okuyamaz, elle açma tabanı siler
  select p.id, s.owner_id into v_prod, v_owner
    from public.products p join public.shops s on s.id = p.shop_id
   where p.product_type = 'digital' limit 1;
  if v_prod is null then
    insert into res values ('baseline_stranger_blocked', '42501'), ('baseline_cleared_on_accept', '0');
  else
    select id into v_other from public.profiles
     where id <> v_admin and id <> coalesce(v_owner, v_admin)
       and coalesce(is_bot, false) = false and role::text <> 'admin' limit 1;
    perform set_config('request.jwt.claims', json_build_object('sub', v_other, 'role', 'authenticated')::text, true);
    perform set_config('role', 'authenticated', true);
    begin perform public.smm_set_product_baseline(v_prod, 10.5, 'Test'); insert into res values ('baseline_stranger_blocked', 'NO'); exception when others then insert into res values ('baseline_stranger_blocked', sqlstate); end;

    perform set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
    perform public.smm_set_product_baseline(v_prod, 10.5, 'Test');
    perform set_config('role', 'postgres', true);
    update public.products set is_available = false, smm_disabled_kind = 'price_changed',
           smm_disabled_reason = 'Sağlayıcı fiyatı değişti' where id = v_prod;
    perform set_config('role', 'authenticated', true);
    update public.products set is_available = true where id = v_prod;
    perform set_config('role', 'postgres', true);
    insert into res select 'baseline_cleared_on_accept', count(*)::text from public.smm_product_baselines where product_id = v_prod;
  end if;

  perform set_config('role', 'postgres', true);
end $$;

select ok((select v::int >= 21 from res where k = 'triggers'), 'eylem günlüğü tetikleyicileri kurulu (>=21 tablo)');
select is((select v from res where k = 'trigger_post_created'), '1', 'gönderi eklemek sunucu tetikleyicisiyle günlüğe düşer');
select is((select v from res where k = 'rpc_login_logged'), '1', 'log_user_action izinli eylemi (login) yazar');
select is((select v from res where k = 'rpc_disallowed_ignored'), '0', 'log_user_action izinli olmayan eylemi yok sayar');
select is((select v from res where k = 'username_changed_to'), 'zz_pgtap.new', 'change_my_username adı küçük harfe çevirip kaydeder');
select is((select v from res where k = 'short_rejected'), '22023', 'çok kısa kullanıcı adı reddedilir');
select is((select v from res where k = 'prefix_rejected'), '22023', 'misafir_ önekli kullanıcı adı reddedilir');
select is((select v from res where k = 'reserved_rejected'), '22023', 'admin gibi ayrılmış ad admin olmayana kapalı');
select is((select v from res where k = 'same_rejected'), '22023', 'aynı kullanıcı adına değişim reddedilir');
select is((select v from res where k = 'taken_rejected'), '23505', 'başkasının kullanıcı adı alınamaz');
select is((select v from res where k = 'username_change_logged'), '1', 'kullanıcı adı değişimi eylem günlüğüne düşer');
select is((select v from res where k = 'nonadmin_logs_blocked'), '42501', 'admin olmayan eylem günlüğünü okuyamaz');
select is((select v from res where k = 'nonadmin_delete_blocked'), '42501', 'admin olmayan kullanıcı silemez');
select ok((select v like '1:%' from res where k = 'page_finds_user'), 'admin_users_page sunucu tarafı aramayla kullanıcıyı bulur');
select is((select v from res where k = 'banned_after_suspend'), 'true', 'askıya alma girişi kapatır (banned_until)');
select is((select v from res where k = 'banned_after_activate'), 'false', 'aktifleştirme girişi yeniden açar');
select is((select v from res where k = 'self_delete_blocked'), '22023', 'admin kendi hesabını silemez');
select is((select v from res where k = 'admin_deleted_logs'), '1', 'admin eylem kayıtlarını silebilir');
select is((select v from res where k = 'hard_mode'), 'hard', 'finansal kaydı olmayan kullanıcı kalıcı silinir');
select is((select v from res where k = 'hard_left'), '0', 'kalıcı silme profil, auth kaydı ve günlüğü temizler');
select is((select v from res where k = 'soft_mode'), 'soft', 'finansal kaydı olan kullanıcı anonimleştirilir (silinmez)');
select is((select v from res where k = 'soft_status'), 'deleted', 'anonimleştirilen hesap deleted durumuna geçer');
select is((select v from res where k = 'baseline_stranger_blocked'), '42501', 'ürün sahibi olmayan SMM tabanı yazamaz');
select is((select v from res where k = 'baseline_cleared_on_accept'), '0', 'fiyat değişimi sonrası elle açma taban değeri siler');

select * from finish();
rollback;
