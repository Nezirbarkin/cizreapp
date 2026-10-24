-- ============================================================================
-- 20261023000003_social_share_links — canlı davranış testi
-- ----------------------------------------------------------------------------
-- Kendi kendini geri alır (DO bloğu sonunda RAISE EXCEPTION). Göçten önce
-- denemek için göç gövdesini (BEGIN/COMMIT/NOTIFY hariç) @@MIGRATION@@
-- satırının yerine koyun; uygulandıktan sonra olduğu gibi çalıştırın:
--   supabase db query --linked --file supabase/tests/manual/social_share_links_test.sql
-- Beklenen: "TESTS_DONE" mesajında FAIL satırı yok.
-- ============================================================================
BEGIN;

-- @@MIGRATION@@

DO $test$
declare
  v_owner uuid; v_owner_name text; v_viewer uuid; v_middle uuid; v_target uuid;
  v_post uuid;
  v_cnt int; v_before int; v_after int;
  v_json jsonb;
  r text := '';
begin
  -- ------------------------------------------------------------ fikstürler
  select p.id, p.username into v_owner, v_owner_name
  from public.profiles p
  where coalesce(p.role::text, 'user') <> 'admin' and not coalesce(p.is_admin, false)
    and coalesce(p.profile_is_public, true) and not coalesce(p.is_ghost_mode, false)
    and coalesce(p.status::text, 'active') = 'active' and p.username is not null
  order by p.id limit 1;

  select p.id into v_viewer from public.profiles p
  where p.id <> v_owner and coalesce(p.role::text, 'user') <> 'admin'
    and not coalesce(p.is_admin, false) and not coalesce(p.is_ghost_mode, false)
    and coalesce(p.status::text, 'active') = 'active'
    and not exists (select 1 from public.blocked_users b
                    where (b.blocker_id = p.id and b.blocked_id = v_owner)
                       or (b.blocker_id = v_owner and b.blocked_id = p.id))
  order by p.id limit 1;

  select p.id into v_middle from public.profiles p
  where p.id not in (v_owner, v_viewer) and not coalesce(p.is_ghost_mode, false)
    and coalesce(p.status::text, 'active') = 'active'
    and not exists (select 1 from public.blocked_users b
                    where b.blocker_id in (p.id, v_viewer) and b.blocked_id in (p.id, v_viewer))
  order by p.id limit 1;

  select p.id into v_target from public.profiles p
  where p.id not in (v_owner, v_viewer, v_middle)
    and coalesce(p.status::text, 'active') = 'active'
  order by p.id limit 1;

  insert into public.posts (user_id, content) values (v_owner, 'paylaşım testi')
  returning id into v_post;

  r := r || chr(10) || format('fixtures owner=%s viewer=%s middle=%s target=%s',
         v_owner is not null, v_viewer is not null, v_middle is not null, v_target is not null);

  -- ------------------------------------------------------ paylaşım sayacı
  perform set_config('request.jwt.claims', json_build_object('sub', v_viewer, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  v_before := public.record_post_share(v_post, 'external');
  v_after := public.record_post_share(v_post, 'chat');
  execute 'reset role';
  select count(*) into v_cnt from public.post_shares where post_id = v_post;
  r := r || chr(10) || case when v_before = 1 and v_after = 1 and v_cnt = 1
         then 'PASS paylaşım kişi başına bir kez sayıldı'
         else format('FAIL paylaşım before=%s after=%s rows=%s', v_before, v_after, v_cnt) end;

  execute 'set local role authenticated';
  begin
    perform count(*) from public.post_shares;
    r := r || chr(10) || 'FAIL post_shares istemciye açık';
  exception when insufficient_privilege then
    r := r || chr(10) || 'PASS post_shares istemciye kapalı';
  end;
  execute 'reset role';

  -- ---------------------------------------------- misafir gönderi önizlemesi
  update public.app_settings set value = '"true"'::jsonb where key = 'explore_public_access';
  execute 'set local role anon';
  perform set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
  select count(*) into v_cnt from public.public_post_by_id(v_post);
  execute 'reset role';
  r := r || chr(10) || case when v_cnt = 1
         then 'PASS misafir açık hesabın gönderisini görüyor (Keşfet açık)'
         else format('FAIL misafir önizleme=%s', v_cnt) end;

  update public.app_settings set value = '"false"'::jsonb where key = 'explore_public_access';
  execute 'set local role anon';
  select count(*) into v_cnt from public.public_post_by_id(v_post);
  execute 'reset role';
  r := r || chr(10) || case when v_cnt = 0
         then 'PASS Keşfet misafire kapalıyken önizleme de kapalı'
         else format('FAIL kapalı anahtarda önizleme=%s', v_cnt) end;

  update public.app_settings set value = '"true"'::jsonb where key = 'explore_public_access';
  update public.profiles set profile_is_public = false where id = v_owner;
  execute 'set local role anon';
  select count(*) into v_cnt from public.public_post_by_id(v_post);
  execute 'reset role';
  r := r || chr(10) || case when v_cnt = 0
         then 'PASS gizli hesabın gönderisi misafire kapalı'
         else format('FAIL gizli hesap önizleme=%s', v_cnt) end;
  update public.profiles set profile_is_public = true where id = v_owner;

  -- ------------------------------------------------ kullanıcı adıyla profil
  execute 'set local role anon';
  v_json := public.public_profile_by_username('@' || upper(v_owner_name));
  execute 'reset role';
  r := r || chr(10) || case when (v_json->>'id')::uuid = v_owner and v_json ? 'followers'
         then 'PASS profil kartı (büyük/küçük harf ve @ duyarsız)'
         else format('FAIL profil kartı %s', v_json) end;

  update public.profiles set is_ghost_mode = true where id = v_owner;
  execute 'set local role anon';
  v_json := public.public_profile_by_username(v_owner_name);
  execute 'reset role';
  r := r || chr(10) || case when v_json is null
         then 'PASS hayalet hesap bulunamadı sayılır'
         else 'FAIL hayalet hesap döndü' end;
  update public.profiles set is_ghost_mode = false where id = v_owner;

  -- ------------------------------------------------------- ortak takipçiler
  insert into public.follows (follower_id, following_id) values (v_viewer, v_middle) on conflict do nothing;
  insert into public.follows (follower_id, following_id) values (v_middle, v_target) on conflict do nothing;

  perform set_config('request.jwt.claims', json_build_object('sub', v_viewer, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  v_json := public.get_mutual_followers(v_target, 3);
  execute 'reset role';
  r := r || chr(10) || case when (v_json->>'count')::int >= 1
                              and v_json->'users' @> jsonb_build_array(jsonb_build_object('id', v_middle))
         then 'PASS ortak takipçi bulundu'
         else format('FAIL ortak takipçi %s', v_json) end;

  insert into public.blocked_users (blocker_id, blocked_id) values (v_viewer, v_middle);
  execute 'set local role authenticated';
  v_json := public.get_mutual_followers(v_target, 50);
  execute 'reset role';
  r := r || chr(10) || case when not (v_json->'users' @> jsonb_build_array(jsonb_build_object('id', v_middle)))
         then 'PASS engellenen kişi ortak takipçide görünmüyor'
         else 'FAIL engellenen ortak takipçide' end;

  execute 'set local role anon';
  begin
    perform public.get_mutual_followers(v_target, 3);
    r := r || chr(10) || 'FAIL anon ortak takipçi çağırabildi';
  exception when insufficient_privilege then
    r := r || chr(10) || 'PASS anon ortak takipçiye kapalı';
  end;
  begin
    perform public.record_post_share(v_post, 'external');
    r := r || chr(10) || 'FAIL anon paylaşım kaydedebildi';
  exception when insufficient_privilege then
    r := r || chr(10) || 'PASS anon paylaşım kaydına kapalı';
  end;
  execute 'reset role';

  raise exception 'TESTS_DONE %', r;
end;
$test$;

ROLLBACK;
