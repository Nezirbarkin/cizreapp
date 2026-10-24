-- ============================================================================
-- 20261024000002_post_insights_and_edits — canlı davranış testi
-- ----------------------------------------------------------------------------
-- Kendi kendini geri alır: DO bloğu sonunda bilerek RAISE EXCEPTION atar,
-- her şey geri alınır, CLI özet satırlarını hata mesajı olarak yazdırır.
-- Göç uygulanmadan önce denemek için göç gövdesini (BEGIN/COMMIT/NOTIFY
-- hariç) @@MIGRATION@@ satırının yerine koyun; uygulandıktan sonra olduğu
-- gibi çalıştırın:
--   supabase db query --linked --file supabase/tests/manual/post_insights_and_edits_test.sql
-- Beklenen: "TESTS_DONE" mesajında FAIL satırı yok.
-- ============================================================================
BEGIN;

-- @@MIGRATION@@

DO $test$
declare
  v_owner uuid; v_viewer uuid; v_private uuid;
  v_post uuid; v_post2 uuid; v_own uuid; v_hidden uuid;
  v_n int;
  v_j jsonb;
  v_ts timestamptz;
  v_row record;
  r text := '';
begin
  -- ------------------------------------------------------------ fikstürler
  select p.id into v_owner
  from public.profiles p
  where coalesce(p.role::text, 'user') <> 'admin' and not coalesce(p.is_admin, false)
    and not coalesce(p.is_bot, false) and coalesce(p.profile_is_public, true)
    and not coalesce(p.is_ghost_mode, false) and coalesce(p.status::text, 'active') = 'active'
  order by p.id limit 1;

  select p.id into v_viewer
  from public.profiles p
  where p.id <> v_owner
    and coalesce(p.role::text, 'user') <> 'admin' and not coalesce(p.is_admin, false)
    and not coalesce(p.is_bot, false) and coalesce(p.status::text, 'active') = 'active'
    and not exists (select 1 from public.blocked_users b
                    where (b.blocker_id = p.id and b.blocked_id = v_owner)
                       or (b.blocker_id = v_owner and b.blocked_id = p.id))
  order by p.id limit 1;

  select p.id into v_private
  from public.profiles p
  where p.id not in (v_owner, v_viewer)
    and coalesce(p.role::text, 'user') <> 'admin' and not coalesce(p.is_admin, false)
    and not coalesce(p.is_bot, false)
    and not exists (select 1 from public.follows f where f.follower_id = v_viewer and f.following_id = p.id)
  order by p.id limit 1;

  update public.profiles set profile_is_public = false where id = v_private;

  insert into public.posts (user_id, content) values (v_owner, 'insights test') returning id into v_post;
  insert into public.posts (user_id, content) values (v_owner, 'insights test 2') returning id into v_post2;
  insert into public.posts (user_id, content) values (v_viewer, 'own post') returning id into v_own;
  insert into public.posts (user_id, content) values (v_private, 'private post') returning id into v_hidden;

  r := r || chr(10) || format('fixtures owner=%s viewer=%s private=%s',
         v_owner is not null, v_viewer is not null, v_private is not null);

  -- ------------------------------------------------------------ gösterim kaydı
  perform set_config('request.jwt.claims', json_build_object('sub', v_viewer, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';

  v_n := public.record_post_impressions(array[v_post, v_post, v_post2, v_own, v_hidden, null]);
  r := r || chr(10) || case when v_n = 2 then 'PASS ilk kayit 2 (tekrar/kendi/gizli/null haric)'
                             else 'FAIL ilk kayit n=' || v_n end;

  v_n := public.record_post_impressions(array[v_post, v_post2]);
  r := r || chr(10) || case when v_n = 0 then 'PASS ayni gun ikinci kez sayilmadi'
                             else 'FAIL ikinci kez sayildi n=' || v_n end;

  select views_count, edited_at into v_row from public.posts_with_profiles where id = v_post;
  r := r || chr(10) || case when v_row.views_count = 1 and v_row.edited_at is null
    then 'PASS gorunumde views_count=1' else 'FAIL gorunum views=' || coalesce(v_row.views_count::text, 'null') end;

  begin
    perform 1 from public.post_impressions limit 1;
    r := r || chr(10) || 'FAIL gosterim tablosu istemciye acik';
  exception when insufficient_privilege then
    r := r || chr(10) || 'PASS gosterim tablosu istemciye kapali';
  end;

  begin
    update public.post_stats set views_count = 999 where post_id = v_post;
    r := r || chr(10) || 'FAIL sayac istemciden yazildi';
  exception when insufficient_privilege then
    r := r || chr(10) || 'PASS sayac istemciden yazilamaz';
  end;

  begin
    perform public.get_post_insights(v_post);
    r := r || chr(10) || 'FAIL yabanci istatistigi gordu';
  exception when insufficient_privilege then
    r := r || chr(10) || 'PASS yabanci istatistigi goremedi';
  end;

  insert into public.post_favorites (user_id, post_id) values (v_viewer, v_post);
  execute 'reset role';

  -- Ertesi gün aynı kişi yeniden sayılır.
  update public.post_impressions set day = day - 1 where post_id = v_post and viewer_id = v_viewer;
  perform set_config('request.jwt.claims', json_build_object('sub', v_viewer, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  v_n := public.record_post_impressions(array[v_post]);
  execute 'reset role';
  r := r || chr(10) || case when v_n = 1 and (select views_count from public.post_stats where post_id = v_post) = 2
    then 'PASS ertesi gun yeniden sayildi' else 'FAIL ertesi gun n=' || v_n end;

  -- ------------------------------------------------------------ misafir
  execute 'set local role anon';
  begin
    perform public.record_post_impressions(array[v_post]);
    r := r || chr(10) || 'FAIL misafir gosterim yazdi';
  exception when insufficient_privilege then
    r := r || chr(10) || 'PASS misafir gosterim yazamaz';
  end;
  execute 'reset role';

  -- ------------------------------------------------------------ sahip istatistiği
  perform set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  v_j := public.get_post_insights(v_post);
  r := r || chr(10) || case when (v_j->>'views')::int = 2 and (v_j->>'unique_viewers')::int = 1
       and (v_j->>'saves')::int = 1 and jsonb_array_length(v_j->'daily') = 7
       and (v_j->>'engagement_rate')::numeric = 100
    then 'PASS sahip istatistigi' else 'FAIL sahip istatistigi: ' || left(v_j::text, 300) end;

  v_n := public.record_post_impressions(array[v_post]);
  r := r || chr(10) || case when v_n = 0 then 'PASS kendi gonderisi sayilmadi' else 'FAIL kendi gonderisi sayildi' end;

  -- ------------------------------------------------------------ düzenleme işareti
  update public.posts set edited_at = '2000-01-01', location = 'Cizre' where id = v_post;
  execute 'reset role';
  select edited_at into v_ts from public.posts where id = v_post;
  r := r || chr(10) || case when v_ts is null then 'PASS edited_at istemciden yazilamaz' else 'FAIL edited_at yazildi' end;

  perform set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  update public.posts set content = 'insights test (duzenlendi)' where id = v_post;
  execute 'reset role';
  select edited_at into v_ts from public.posts where id = v_post;
  r := r || chr(10) || case when v_ts = now() then 'PASS icerik degisince edited_at' else 'FAIL edited_at=' || coalesce(v_ts::text, 'null') end;

  insert into public.posts (user_id, content, edited_at) values (v_owner, 'x', now()) returning id into v_post2;
  -- postgres olarak eklendi → koruma uygulanmaz; istemci ekleme yolu:
  perform set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  insert into public.posts (user_id, content, edited_at) values (v_owner, 'y', '2000-01-01') returning id into v_post2;
  execute 'reset role';
  r := r || chr(10) || case when (select edited_at from public.posts where id = v_post2) is null
    then 'PASS yeni gonderide edited_at bos' else 'FAIL yeni gonderide edited_at' end;

  -- ------------------------------------------------------------ şema
  r := r || chr(10) || case when (
       select count(*) from information_schema.columns
       where table_schema = 'public' and table_name = 'posts_with_profiles'
         and column_name in ('views_count', 'edited_at')) = 2
    then 'PASS gorunum sutunlari' else 'FAIL gorunum sutunlari' end;
  r := r || chr(10) || case when pg_get_function_result('public.public_explore_feed(integer,integer)'::regprocedure) like '%views_count integer, edited_at timestamp with time zone)'
       and pg_get_function_result('public.public_post_by_id(uuid)'::regprocedure) like '%views_count integer, edited_at timestamp with time zone)'
    then 'PASS misafir RPC sutunlari' else 'FAIL misafir RPC sutunlari' end;
  r := r || chr(10) || case when to_regprocedure('public.increment_post_view(uuid)') is null
    then 'PASS increment_post_view kaldirildi' else 'FAIL increment_post_view duruyor' end;
  r := r || chr(10) || case when has_function_privilege('anon', 'public.public_explore_feed(integer,integer)', 'execute')
       and not has_function_privilege('anon', 'public.get_post_insights(uuid)', 'execute')
    then 'PASS yetkiler' else 'FAIL yetkiler' end;

  raise exception 'TESTS_DONE %', r;
end;
$test$;

ROLLBACK;
