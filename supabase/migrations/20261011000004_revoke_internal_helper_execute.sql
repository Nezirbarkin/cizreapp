-- Yalnızca başka SECURITY DEFINER fonksiyonların içinden çağrılan altı yardımcı
-- fonksiyonun istemci (authenticated) EXECUTE yetkisi kaldırılır.
--
-- Security Advisor bunları "authenticated SECURITY DEFINER fonksiyonu
-- çalıştırabiliyor" diye işaretliyordu. Kanıt (2026-10-11, canlı):
--   * Hiçbiri RLS politikasında, view'de, sütun varsayılanında, kısıtta,
--     tetikleyici WHEN koşulunda ya da cron işinde geçmiyor.
--   * Çağıranlarının tamamı postgres sahipli SECURITY DEFINER fonksiyonlar
--     (can_view_okey_room/match, okey_watch_room, okey_invite_to_room,
--     okey_invitable_friends, okey_match_barajs, okey_internal_finalize_hand,
--     okey_auto_play_absent, okey_cron_advance_stalled_matches,
--     admin_*_fraud_signal*). DEFINER gövdesindeki çağrılar fonksiyon sahibinin
--     yetkisiyle denetlenir; postgres ve service_role yetkisi aynen kalır.
--   * Hepsi depo geçmişi başladıktan sonra (2026-07-29 … 2026-09-06) yaratıldı
--     ve adları lib/ altında hiçbir commit'te geçmedi: hiçbir istemci sürümü
--     bunları doğrudan çağırmadı.
--
-- Güncel kodda geçmeyen diğer RPC'lere (get_my_*, toggle_*_like, migration'sız
-- eski fonksiyonlar…) bilerek DOKUNULMADI: istemci API'si olarak yazılmışlar ya
-- da depo geçmişinden eski sürümler çağırıyor olabilir.

begin;

revoke execute on function public.is_fraud_admin() from public, anon, authenticated;
revoke execute on function public.is_seated_in_okey_match(uuid) from public, anon, authenticated;
revoke execute on function public.is_seated_in_okey_room(uuid) from public, anon, authenticated;
revoke execute on function public.okey_baraj_kind(uuid, smallint) from public, anon, authenticated;
revoke execute on function public.okey_internal_baraj_adjustments(uuid, smallint) from public, anon, authenticated;
revoke execute on function public.okey_seat_is_absent(uuid, smallint, integer) from public, anon, authenticated;

-- Son durum denetimi: bu fonksiyonları çağıran her fonksiyon DEFINER olmalı ve
-- sahibi hâlâ çalıştırabilmeli; aksi hâlde göç tümüyle geri alınır.
do $$
declare
  v_bad text;
begin
  select string_agg(c.oid::regprocedure::text || ' -> ' || t.proname, ', ')
    into v_bad
    from pg_proc t
    join pg_proc c
      on c.oid <> t.oid
     and c.prosrc ~ ('(^|[^A-Za-z0-9_])' || t.proname || '([^A-Za-z0-9_]|$)')
     -- oturuma özel geçici fonksiyonlar (ör. test yardımcıları) sayılmaz
     and c.pronamespace not in (select n.oid from pg_namespace n where n.nspname ~ '^pg_(toast_)?temp')
   where t.pronamespace = 'public'::regnamespace
     and t.proname in ('is_fraud_admin', 'is_seated_in_okey_match', 'is_seated_in_okey_room',
                       'okey_baraj_kind', 'okey_internal_baraj_adjustments', 'okey_seat_is_absent')
     and (not c.prosecdef or not has_function_privilege(c.proowner, t.oid, 'EXECUTE'));
  if v_bad is not null then
    raise exception 'revoke_internal_helper_execute: yetkisiz kalacak çağıran var: %', v_bad;
  end if;

  select string_agg(pol.schemaname || '.' || pol.tablename || ':' || pol.policyname, ', ')
    into v_bad
    from pg_policies pol
   where (coalesce(pol.qual, '') || ' ' || coalesce(pol.with_check, ''))
         ~ '(is_fraud_admin|is_seated_in_okey_match|is_seated_in_okey_room|okey_baraj_kind|okey_internal_baraj_adjustments|okey_seat_is_absent)';
  if v_bad is not null then
    raise exception 'revoke_internal_helper_execute: politikada kullanılıyor: %', v_bad;
  end if;
end;
$$;

insert into private.client_execute_revocations (function_signature, revoked_from, migration)
select v.sig, 'authenticated', '20261011000004'
  from (values
    ('is_fraud_admin()'),
    ('is_seated_in_okey_match(uuid)'),
    ('is_seated_in_okey_room(uuid)'),
    ('okey_baraj_kind(uuid,smallint)'),
    ('okey_internal_baraj_adjustments(uuid,smallint)'),
    ('okey_seat_is_absent(uuid,smallint,integer)')
  ) as v(sig)
 where not exists (
   select 1
     from private.client_execute_revocations r
    where r.function_signature = v.sig
      and r.revoked_from = 'authenticated'
      and r.migration = '20261011000004'
 );

commit;

notify pgrst, 'reload schema';
