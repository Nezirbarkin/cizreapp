-- ============================================================================
-- 20261024000003_comment_likes_and_hashtags — canlı davranış testi
-- ----------------------------------------------------------------------------
-- Kendi kendini geri alır: DO bloğu sonunda bilerek RAISE EXCEPTION atar,
-- her şey geri alınır, CLI özet satırlarını hata mesajı olarak yazdırır.
-- Göç uygulanmadan önce denemek için göç gövdesini (BEGIN/COMMIT/NOTIFY
-- hariç) @@MIGRATION@@ satırının yerine koyun; uygulandıktan sonra olduğu
-- gibi çalıştırın:
--   supabase db query --linked --file supabase/tests/manual/comment_likes_hashtags_test.sql
-- Beklenen: "TESTS_DONE" mesajında FAIL satırı yok.
-- ============================================================================
BEGIN;

-- @@MIGRATION@@

DO $test$
declare
  v_owner uuid; v_liker uuid; v_blocked uuid;
  v_post uuid; v_c1 uuid; v_c2 uuid;
  v_n int;
  v_j jsonb;
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

  select p.id into v_liker
  from public.profiles p
  where p.id <> v_owner
    and coalesce(p.role::text, 'user') <> 'admin' and not coalesce(p.is_admin, false)
    and not coalesce(p.is_bot, false) and coalesce(p.status::text, 'active') = 'active'
    and not exists (select 1 from public.blocked_users b
                    where (b.blocker_id = p.id and b.blocked_id = v_owner)
                       or (b.blocker_id = v_owner and b.blocked_id = p.id))
  order by p.id limit 1;

  select p.id into v_blocked
  from public.profiles p
  where p.id not in (v_owner, v_liker)
    and coalesce(p.role::text, 'user') <> 'admin' and not coalesce(p.is_admin, false)
    and not coalesce(p.is_bot, false)
  order by p.id limit 1;

  delete from public.notification_preferences where user_id = v_owner;
  insert into public.posts (user_id, content)
  values (v_owner, 'Akşam #Cizre yürüyüşü #ıĞdır_gezisi http://x.com/a#cizre #c')
  returning id into v_post;
  insert into public.post_comments (post_id, user_id, content) values (v_post, v_owner, 'sahip yorumu')
  returning id into v_c1;

  r := r || chr(10) || format('fixtures owner=%s liker=%s blocked=%s',
         v_owner is not null, v_liker is not null, v_blocked is not null);

  -- ------------------------------------------------------------ beğeni + sayaç + bildirim
  perform set_config('request.jwt.claims', json_build_object('sub', v_liker, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  insert into public.post_comment_likes (comment_id, user_id) values (v_c1, v_liker);
  select likes_count into v_n from public.post_comments where id = v_c1;
  r := r || chr(10) || case when v_n = 1 then 'PASS sayac 1' else 'FAIL sayac=' || v_n end;

  insert into public.post_comment_likes (comment_id, user_id) values (v_c1, v_liker)
  on conflict do nothing;
  select likes_count into v_n from public.post_comments where id = v_c1;
  r := r || chr(10) || case when v_n = 1 then 'PASS ikinci begeni yok sayildi' else 'FAIL sayac=' || v_n end;

  begin
    insert into public.post_comment_likes (comment_id, user_id) values (v_c1, v_owner);
    r := r || chr(10) || 'FAIL baskasi adina begeni';
  exception when insufficient_privilege then
    r := r || chr(10) || 'PASS baskasi adina begeni yok';
  end;

  -- Kendi yorumunu yazarken sayaç yazamaz.
  insert into public.post_comments (post_id, user_id, content, likes_count) values (v_post, v_liker, 'begenen yorumu', 99)
  returning id into v_c2;
  update public.post_comments set likes_count = 500, user_id = v_owner, content = 'duzeltildi' where id = v_c2;
  execute 'reset role';
  select likes_count, user_id, content into v_row from public.post_comments where id = v_c2;
  r := r || chr(10) || case when v_row.likes_count = 0 and v_row.user_id = v_liker and v_row.content = 'duzeltildi'
    then 'PASS yorum korumasi' else 'FAIL yorum korumasi ' || v_row::text end;

  select count(*) into v_n from public.notifications
  where user_id = v_owner and type = 'comment_like' and actor_id = v_liker and entity_id = v_post::text
    and metadata ->> 'comment_id' = v_c1::text;
  r := r || chr(10) || case when v_n = 1 then 'PASS bildirim gitti' else 'FAIL bildirim n=' || v_n end;

  -- Geri al → yeniden beğen: sayaç doğru, ikinci bildirim yok.
  perform set_config('request.jwt.claims', json_build_object('sub', v_liker, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  delete from public.post_comment_likes where comment_id = v_c1 and user_id = v_liker;
  select likes_count into v_n from public.post_comments where id = v_c1;
  r := r || chr(10) || case when v_n = 0 then 'PASS geri alinca 0' else 'FAIL geri alinca ' || v_n end;
  insert into public.post_comment_likes (comment_id, user_id) values (v_c1, v_liker);
  execute 'reset role';
  select count(*) into v_n from public.notifications
  where user_id = v_owner and type = 'comment_like' and actor_id = v_liker;
  r := r || chr(10) || case when v_n = 1 then 'PASS 24 saatte tek bildirim' else 'FAIL bildirim n=' || v_n end;

  -- Kendi yorumunu beğenince bildirim yok; tercih kapalıysa yok.
  perform set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  insert into public.post_comment_likes (comment_id, user_id) values (v_c1, v_owner);
  execute 'reset role';
  r := r || chr(10) || case when not exists (select 1 from public.notifications
       where user_id = v_owner and type = 'comment_like' and actor_id = v_owner)
    then 'PASS kendine bildirim yok' else 'FAIL kendine bildirim' end;

  insert into public.notification_preferences (user_id, likes_enabled) values (v_liker, false)
  on conflict (user_id) do update set likes_enabled = false;
  perform set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  insert into public.post_comment_likes (comment_id, user_id) values (v_c2, v_owner);
  execute 'reset role';
  r := r || chr(10) || case when not exists (select 1 from public.notifications
       where user_id = v_liker and type = 'comment_like' and actor_id = v_owner)
    then 'PASS tercih kapaliyken bildirim yok' else 'FAIL tercih yok sayildi' end;

  -- Engelli kişi beğenemez.
  insert into public.blocked_users (blocker_id, blocked_id) values (v_owner, v_blocked)
  on conflict do nothing;
  perform set_config('request.jwt.claims', json_build_object('sub', v_blocked, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  begin
    insert into public.post_comment_likes (comment_id, user_id) values (v_c1, v_blocked);
    r := r || chr(10) || 'FAIL engelli begendi';
  exception when insufficient_privilege then
    r := r || chr(10) || 'PASS engelli begenemedi';
  end;
  execute 'reset role';

  -- ------------------------------------------------------------ etiketler
  r := r || chr(10) || case when public.social_fold_tr('IĞDIR İzmir ıslak Çay') = 'iğdir izmir islak çay'
    then 'PASS turkce katlama' else 'FAIL katlama: ' || public.social_fold_tr('IĞDIR İzmir ıslak Çay') end;

  perform set_config('request.jwt.claims', json_build_object('sub', v_liker, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  v_j := public.posts_by_hashtag('#cizre');
  r := r || chr(10) || case when exists (select 1 from jsonb_array_elements(v_j) e where e->>'id' = v_post::text)
       and (v_j->0) ? 'views_count'
    then 'PASS etiket akisi' else 'FAIL etiket akisi' end;
  v_j := public.posts_by_hashtag('IĞDIR_GEZİSİ');
  r := r || chr(10) || case when exists (select 1 from jsonb_array_elements(v_j) e where e->>'id' = v_post::text)
    then 'PASS buyuk harf + Turkce etiket' else 'FAIL Turkce etiket' end;
  v_j := public.posts_by_hashtag('cizr');
  r := r || chr(10) || case when not exists (select 1 from jsonb_array_elements(v_j) e where e->>'id' = v_post::text)
    then 'PASS kismi etiket eslesmez' else 'FAIL kismi etiket eslesti' end;
  r := r || chr(10) || case when public.posts_by_hashtag('a.*') = '[]'::jsonb and public.posts_by_hashtag('c') = '[]'::jsonb
    then 'PASS gecersiz etiket bos' else 'FAIL gecersiz etiket' end;
  v_j := public.trending_hashtags(7, 30);
  r := r || chr(10) || case when exists (select 1 from jsonb_array_elements(v_j) e where e->>'tag' = 'cizre')
       and exists (select 1 from jsonb_array_elements(v_j) e where e->>'tag' = 'iğdir_gezisi')
       and not exists (select 1 from jsonb_array_elements(v_j) e where e->>'tag' = 'c')
    then 'PASS gundem etiketleri' else 'FAIL gundem: ' || left(v_j::text, 200) end;
  execute 'reset role';

  r := r || chr(10) || case when not has_function_privilege('anon', 'public.posts_by_hashtag(text,integer,integer)', 'execute')
    then 'PASS misafir etiket rpc kapali' else 'FAIL misafir etiket rpc acik' end;

  raise exception 'TESTS_DONE %', r;
end;
$test$;

ROLLBACK;
