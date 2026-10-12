-- Supabase Security Advisor: yalnızca davranışı değiştirmediği kanıtlanan
-- düzeltmeler.
--
-- 2026-10-11'de danışman 714 uyarı veriyordu. Büyük kısmı tasarım gereği
-- (istemcinin çağırdığı SECURITY DEFINER RPC'ler, Okey misafirinin anonim
-- oturumu, herkese açık bucket'lar); onlara burada DOKUNULMAZ. Bu göç hiçbir
-- fonksiyon gövdesini, politikayı ya da tabloyu değiştirmez; yalnızca üç küme
-- yetki/ayar düzeltir:
--
-- 1) 14 tetikleyici fonksiyonu. Açık anon/authenticated yetkileri zaten geri
--    alınmış ama PUBLIC yetkisi unutulmuştu ({=X/postgres,...}); yani fiilen
--    herkes çalıştırabiliyordu. Tetikleyici fonksiyonu RPC ile çağrılamaz ve
--    tetikleyici ateşlenirken EXECUTE yetkisine bakılmaz: orders, messages,
--    posts, profiles üzerindeki onlarca tetikleyici fonksiyonu Ağustos'tan beri
--    aynı kilitli hâlde ({postgres,service_role}) çalışıyor. Davranış aynı.
--
-- 2) PUBLIC yetkisi unutulmuş 4 RPC. anon erişimi kapanır, authenticated kalır.
--    Hepsi yalnızca oturum açmış kullanıcının akışından çağrılıyor:
--      * add_product: açık authenticated yetkisi YOKTU, satıcı paneli yalnızca
--        PUBLIC sayesinde çalışıyordu; bu yüzden önce authenticated'a verilir.
--        Gövdedeki `v_owner_id != auth.uid()` denetimi anon için NULL döndüğünden
--        atlanıyordu: anon anahtarıyla herhangi bir mağazaya ürün eklenebiliyordu.
--      * admin_upsert_sehirici_stop: auth_sehirici_is_admin() anon için zaten false.
--      * use_balance_for_order(uuid): auth.uid() NULL ise zaten hata veriyor.
--      * use_coupon: yalnızca ödeme ekranlarından, sipariş sahibi adına çağrılıyor.
--
-- 3) private şemadaki iki saf SQL fonksiyonuna sabit search_path. Gövdeleri
--    yalnızca sabit değer içeriyor, hiçbir nesneye başvurmuyor.

begin;

-- 1) Tetikleyici fonksiyonları ------------------------------------------------
revoke execute on function public.enforce_product_order_quantity_limits() from public, anon, authenticated;
revoke execute on function public.force_default_shop_commission_on_insert() from public, anon, authenticated;
revoke execute on function public.guard_payment_transaction_client_writes() from public, anon, authenticated;
revoke execute on function public.guard_shop_financial_columns() from public, anon, authenticated;
revoke execute on function public.music_attach_guard() from public, anon, authenticated;
revoke execute on function public.notify_admin_new_digital_order() from public, anon, authenticated;
revoke execute on function public.notify_admin_new_order() from public, anon, authenticated;
revoke execute on function public.notify_cart_price_drop() from public, anon, authenticated;
revoke execute on function public.notify_comment_reply() from public, anon, authenticated;
revoke execute on function public.schedule_bot_follows_for_new_user() from public, anon, authenticated;
revoke execute on function public.sync_ilan_favorite_count() from public, anon, authenticated;
revoke execute on function public.unlock_order_milestone_profile_features() from public, anon, authenticated;
revoke execute on function public.validate_ilan_image_write() from public, anon, authenticated;
revoke execute on function public.validate_ilan_write() from public, anon, authenticated;

-- 2) PUBLIC yetkisi unutulmuş RPC'ler -----------------------------------------
-- Önce authenticated/service_role yetkisi garantiye alınır, sonra PUBLIC kalkar;
-- aynı işlem içinde olduğu için oturum açmış kullanıcı hiçbir an yetkisiz kalmaz.
grant execute on function public.add_product(uuid, text, text, numeric, numeric, integer, text, text, text, jsonb, text, jsonb, jsonb, jsonb, text[], integer, integer, numeric, boolean, integer, integer, text) to authenticated, service_role;
grant execute on function public.admin_upsert_sehirici_stop(uuid, uuid, text, text, double precision, double precision, boolean, text) to authenticated, service_role;
grant execute on function public.use_balance_for_order(uuid) to authenticated, service_role;
grant execute on function public.use_coupon(uuid, uuid, uuid, numeric) to authenticated, service_role;

revoke execute on function public.add_product(uuid, text, text, numeric, numeric, integer, text, text, text, jsonb, text, jsonb, jsonb, jsonb, text[], integer, integer, numeric, boolean, integer, integer, text) from public, anon;
revoke execute on function public.admin_upsert_sehirici_stop(uuid, uuid, text, text, double precision, double precision, boolean, text) from public, anon;
revoke execute on function public.use_balance_for_order(uuid) from public, anon;
revoke execute on function public.use_coupon(uuid, uuid, uuid, numeric) from public, anon;

-- 3) Sabit search_path ---------------------------------------------------------
alter function private.admin_notification_icon(text) set search_path = '';
alter function private.bot_seed_personas() set search_path = '';

-- Son durum denetimi: beklenmeyen bir yetki kaybı varsa göç tümüyle geri alınır.
do $$
declare
  v_bad text;
begin
  select string_agg(p.oid::regprocedure::text, ', ')
    into v_bad
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.proname in ('add_product', 'admin_upsert_sehirici_stop', 'use_coupon', 'use_balance_for_order')
     and (not has_function_privilege('authenticated', p.oid, 'EXECUTE')
          or not has_function_privilege('service_role', p.oid, 'EXECUTE')
          or has_function_privilege('anon', p.oid, 'EXECUTE'));
  if v_bad is not null then
    raise exception 'security_advisor_safe_fixes: beklenmeyen RPC yetkisi: %', v_bad;
  end if;

  select string_agg(p.oid::regprocedure::text, ', ')
    into v_bad
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.prorettype = 'trigger'::regtype
     and p.proname in (
       'enforce_product_order_quantity_limits', 'force_default_shop_commission_on_insert',
       'guard_payment_transaction_client_writes', 'guard_shop_financial_columns',
       'music_attach_guard', 'notify_admin_new_digital_order', 'notify_admin_new_order',
       'notify_cart_price_drop', 'notify_comment_reply', 'schedule_bot_follows_for_new_user',
       'sync_ilan_favorite_count', 'unlock_order_milestone_profile_features',
       'validate_ilan_image_write', 'validate_ilan_write')
     and (has_function_privilege('anon', p.oid, 'EXECUTE')
          or has_function_privilege('authenticated', p.oid, 'EXECUTE')
          or not has_function_privilege('service_role', p.oid, 'EXECUTE'));
  if v_bad is not null then
    raise exception 'security_advisor_safe_fixes: beklenmeyen tetikleyici fonksiyon yetkisi: %', v_bad;
  end if;
end;
$$;

-- Ağustos'taki yetki kısma turuyla aynı kayıt defteri.
insert into private.client_execute_revocations (function_signature, revoked_from, migration)
select v.sig, v.revoked_from, '20261011000001'
  from (values
    ('enforce_product_order_quantity_limits()', 'anon'),
    ('enforce_product_order_quantity_limits()', 'authenticated'),
    ('force_default_shop_commission_on_insert()', 'anon'),
    ('force_default_shop_commission_on_insert()', 'authenticated'),
    ('guard_payment_transaction_client_writes()', 'anon'),
    ('guard_payment_transaction_client_writes()', 'authenticated'),
    ('guard_shop_financial_columns()', 'anon'),
    ('guard_shop_financial_columns()', 'authenticated'),
    ('music_attach_guard()', 'anon'),
    ('music_attach_guard()', 'authenticated'),
    ('notify_admin_new_digital_order()', 'anon'),
    ('notify_admin_new_digital_order()', 'authenticated'),
    ('notify_admin_new_order()', 'anon'),
    ('notify_admin_new_order()', 'authenticated'),
    ('notify_cart_price_drop()', 'anon'),
    ('notify_cart_price_drop()', 'authenticated'),
    ('notify_comment_reply()', 'anon'),
    ('notify_comment_reply()', 'authenticated'),
    ('schedule_bot_follows_for_new_user()', 'anon'),
    ('schedule_bot_follows_for_new_user()', 'authenticated'),
    ('sync_ilan_favorite_count()', 'anon'),
    ('sync_ilan_favorite_count()', 'authenticated'),
    ('unlock_order_milestone_profile_features()', 'anon'),
    ('unlock_order_milestone_profile_features()', 'authenticated'),
    ('validate_ilan_image_write()', 'anon'),
    ('validate_ilan_image_write()', 'authenticated'),
    ('validate_ilan_write()', 'anon'),
    ('validate_ilan_write()', 'authenticated'),
    ('add_product(uuid,text,text,numeric,numeric,integer,text,text,text,jsonb,text,jsonb,jsonb,jsonb,text[],integer,integer,numeric,boolean,integer,integer,text)', 'anon'),
    ('admin_upsert_sehirici_stop(uuid,uuid,text,text,double precision,double precision,boolean,text)', 'anon'),
    ('use_balance_for_order(uuid)', 'anon'),
    ('use_coupon(uuid,uuid,uuid,numeric)', 'anon')
  ) as v(sig, revoked_from)
 where not exists (
   select 1
     from private.client_execute_revocations r
    where r.function_signature = v.sig
      and r.revoked_from = v.revoked_from
      and r.migration = '20261011000001'
 );

commit;

notify pgrst, 'reload schema';
