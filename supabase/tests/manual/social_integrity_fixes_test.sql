-- ============================================================================
-- 20261023000001_social_integrity_fixes — canlı davranış testi
-- ----------------------------------------------------------------------------
-- Kendi kendini geri alır: DO bloğu sonunda bilerek RAISE EXCEPTION atar,
-- her şey geri alınır, CLI özet satırlarını hata mesajı olarak yazdırır.
-- Göç uygulanmadan önce denemek için göç gövdesini (BEGIN/COMMIT/NOTIFY
-- hariç) @@MIGRATION@@ satırının yerine koyun; uygulandıktan sonra olduğu
-- gibi çalıştırın:
--   supabase db query --linked --file supabase/tests/manual/social_integrity_fixes_test.sql
-- Beklenen: "TESTS_DONE" mesajında FAIL satırı yok.
-- ============================================================================
BEGIN;

-- @@MIGRATION@@

DO $test$
declare
  v_owner uuid; v_liker uuid; v_stranger uuid;
  v_post uuid; v_story uuid; v_c1 uuid; v_n1 uuid; v_n2 uuid;
  v_row record;
  v_cnt int;
  v_bool boolean;
  r text := '';
begin
  -- ------------------------------------------------------------ fikstürler
  select p.id into v_owner
  from public.profiles p
  where coalesce(p.role::text, 'user') <> 'admin' and not coalesce(p.is_admin, false)
    and not coalesce(p.is_bot, false) and coalesce(p.profile_is_public, true)
    and not coalesce(p.is_ghost_mode, false)
    and coalesce(p.status::text, 'active') = 'active'
    and p.username is not null
  order by p.id limit 1;

  select p.id into v_liker
  from public.profiles p
  where p.id <> v_owner
    and coalesce(p.role::text, 'user') <> 'admin' and not coalesce(p.is_admin, false)
    and not coalesce(p.is_bot, false) and coalesce(p.profile_is_public, true)
    and not coalesce(p.is_ghost_mode, false)
    and coalesce(p.status::text, 'active') = 'active'
    and p.username is not null
    and not exists (select 1 from public.blocked_users b
                    where (b.blocker_id = p.id and b.blocked_id = v_owner)
                       or (b.blocker_id = v_owner and b.blocked_id = p.id))
    and not exists (select 1 from public.follows f
                    where f.follower_id = p.id and f.following_id = v_owner)
  order by p.id limit 1;

  select p.id into v_stranger
  from public.profiles p
  where p.id not in (v_owner, v_liker)
    and coalesce(p.role::text, 'user') <> 'admin' and not coalesce(p.is_admin, false)
    and not coalesce(p.is_bot, false)
    and not exists (select 1 from public.follows f
                    where f.follower_id = p.id and f.following_id = v_owner)
    and not exists (select 1 from public.blocked_users b
                    where (b.blocker_id = p.id and b.blocked_id = v_owner)
                       or (b.blocker_id = v_owner and b.blocked_id = p.id))
  order by p.id limit 1;

  r := r || chr(10) || format('fixtures owner=%s liker=%s stranger=%s',
         v_owner is not null, v_liker is not null, v_stranger is not null);

  -- ------------------------------------------------ gönderi sütun koruması
  perform set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';

  insert into public.posts (user_id, content, admin_pinned, likes_count, comments_count, shares_count, created_at)
  values (v_owner, 'integrity test', true, 500, 40, 30, '2000-01-01')
  returning id into v_post;

  execute 'reset role';
  select * into v_row from public.posts where id = v_post;
  r := r || chr(10) || case when not v_row.admin_pinned and v_row.likes_count = 0
                              and v_row.comments_count = 0 and v_row.shares_count = 0
                              and v_row.created_at > now() - interval '1 minute'
         then 'PASS posts INSERT korumali sutunlar sifirlandi'
         else format('FAIL posts INSERT %s', to_jsonb(v_row)) end;

  execute 'set local role authenticated';
  update public.posts set admin_pinned = true, likes_count = 99999, shares_count = 7,
                          created_at = '2000-01-01', is_pinned = true
  where id = v_post;
  execute 'reset role';
  select * into v_row from public.posts where id = v_post;
  r := r || chr(10) || case when not v_row.admin_pinned and v_row.likes_count = 0
                              and v_row.shares_count = 0
                              and v_row.created_at > now() - interval '1 minute'
         then 'PASS posts UPDATE admin_pinned/sayaclar/created_at eski deger'
         else format('FAIL posts UPDATE %s', to_jsonb(v_row)) end;
  r := r || chr(10) || case when v_row.is_pinned
         then 'PASS posts.is_pinned (profil sabitleme) hala serbest'
         else 'FAIL posts.is_pinned degismedi' end;

  -- ------------------------------------------------- hikâye sütun koruması
  execute 'set local role authenticated';
  insert into public.stories (user_id, image_url, is_pinned, admin_pinned, views_count, likes_count, created_at, expires_at)
  values (v_owner, 'https://example.invalid/x.jpg', true, true, 50, 9, '2000-01-01', '2100-01-01')
  returning id into v_story;
  execute 'reset role';
  select * into v_row from public.stories where id = v_story;
  r := r || chr(10) || case when not v_row.is_pinned and not v_row.admin_pinned
                              and v_row.views_count = 0 and v_row.likes_count = 0
                              and v_row.created_at > now() - interval '1 minute'
                              and v_row.expires_at between now() + interval '23 hours 59 minutes'
                                                       and now() + interval '24 hours 1 minute'
         then 'PASS stories INSERT sunucu saati + korumali sutunlar'
         else format('FAIL stories INSERT %s', to_jsonb(v_row)) end;

  execute 'set local role authenticated';
  update public.stories set expires_at = '2100-01-01', is_pinned = true, views_count = 1000
  where id = v_story;
  execute 'reset role';
  select * into v_row from public.stories where id = v_story;
  r := r || chr(10) || case when v_row.expires_at < now() + interval '25 hours'
                              and not v_row.is_pinned and v_row.views_count = 0
         then 'PASS stories UPDATE expires_at/is_pinned/views_count eski deger'
         else format('FAIL stories UPDATE %s', to_jsonb(v_row)) end;

  -- ------------------------------------- sayaç tetikleyicisi + beğeni tekrarı
  perform set_config('request.jwt.claims', json_build_object('sub', v_liker, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  insert into public.post_likes (post_id, user_id) values (v_post, v_liker);
  execute 'reset role';
  select likes_count into v_cnt from public.posts where id = v_post;
  r := r || chr(10) || case when v_cnt = 1
         then 'PASS begeni sayaci (DEFINER tetikleyici) korumaya takilmadi'
         else format('FAIL likes_count=%s', v_cnt) end;
  select id into v_n1 from public.notifications
  where user_id = v_owner and entity_id = v_post::text and type = 'post_like' and actor_id = v_liker;

  execute 'set local role authenticated';
  delete from public.post_likes where post_id = v_post and user_id = v_liker;
  insert into public.post_likes (post_id, user_id) values (v_post, v_liker);
  execute 'reset role';
  select count(*), max(id::text)::uuid into v_cnt, v_n2 from public.notifications
  where user_id = v_owner and entity_id = v_post::text and type = 'post_like' and actor_id = v_liker;
  r := r || chr(10) || case when v_n1 is not null and v_cnt = 1 and v_n2 = v_n1
         then 'PASS yeniden begeni yeni bildirim uretmedi'
         else format('FAIL yeniden begeni bildirim n1=%s cnt=%s n2=%s', v_n1, v_cnt, v_n2) end;

  -- ------------------------------------------ gönderi sahibinin yorumuna yanıt
  perform set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  insert into public.post_comments (post_id, user_id, content) values (v_post, v_owner, 'sahip yorumu')
  returning id into v_c1;
  perform set_config('request.jwt.claims', json_build_object('sub', v_liker, 'role', 'authenticated')::text, true);
  insert into public.post_comments (post_id, user_id, content, parent_comment_id)
  values (v_post, v_liker, 'yanit', v_c1);
  execute 'reset role';
  select count(*) into v_cnt from public.notifications
  where user_id = v_owner and entity_id = v_post::text and type = 'post_comment' and actor_id = v_liker;
  r := r || chr(10) || case when v_cnt = 0
         then 'PASS sahibin yorumuna yanit cift bildirim uretmedi'
         else format('FAIL post_comment bildirimi=%s', v_cnt) end;
  select count(*) into v_cnt from public.notifications
  where user_id = v_owner and entity_id = v_post::text and type = 'comment_reply' and actor_id = v_liker;
  r := r || chr(10) || case when v_cnt = 1
         then 'PASS comment_reply bildirimi geldi'
         else format('FAIL comment_reply=%s', v_cnt) end;

  execute 'set local role authenticated';
  insert into public.post_comments (post_id, user_id, content) values (v_post, v_liker, 'ust yorum');
  execute 'reset role';
  select count(*) into v_cnt from public.notifications
  where user_id = v_owner and entity_id = v_post::text and type = 'post_comment' and actor_id = v_liker;
  r := r || chr(10) || case when v_cnt = 1
         then 'PASS normal yorum bildirimi hala geliyor'
         else format('FAIL normal post_comment=%s', v_cnt) end;

  -- --------------------------------------------------- görünüm: doğrulama rozeti
  select (w.author_is_verified is not distinct from pr.is_verified) into v_bool
  from public.posts_with_profiles w join public.profiles pr on pr.id = w.user_id
  where w.id = v_post;
  r := r || chr(10) || case when v_bool
         then 'PASS posts_with_profiles.author_is_verified profil degeriyle ayni'
         else 'FAIL author_is_verified' end;

  begin
    execute 'set local role anon';
    perform set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
    perform count(*) from public.posts_with_profiles;
    execute 'reset role';
    r := r || chr(10) || 'PASS anon posts_with_profiles okuyabiliyor';
  exception when others then
    r := r || chr(10) || format('FAIL anon gorunum okuyamadi: %s', sqlerrm);
  end;
  execute 'reset role';

  -- -------------------------------------------- gizli hesap: beğenenler/yorumlar
  update public.profiles set profile_is_public = false where id = v_owner;
  perform set_config('request.jwt.claims', json_build_object('sub', v_stranger, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  select count(*) into v_cnt from public.post_likes where post_id = v_post;
  r := r || chr(10) || case when v_cnt = 0
         then 'PASS gizli hesabin begenenleri yabanciya kapali'
         else format('FAIL yabanci %s begeni gordu', v_cnt) end;
  begin
    insert into public.post_likes (post_id, user_id) values (v_post, v_stranger);
    r := r || chr(10) || 'FAIL yabanci gizli hesabin gonderisini begendi';
  exception when insufficient_privilege then
    r := r || chr(10) || 'PASS yabanci gizli hesabin gonderisini begenemedi';
  end;
  execute 'reset role';
  perform set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  select count(*) into v_cnt from public.post_likes where post_id = v_post;
  r := r || chr(10) || case when v_cnt = 1
         then 'PASS sahip kendi begenenlerini goruyor'
         else format('FAIL sahip %s begeni gordu', v_cnt) end;
  execute 'reset role';
  update public.profiles set profile_is_public = true where id = v_owner;

  -- ----------------------------------------------------- engelleme temizliği
  insert into public.follows (follower_id, following_id) values (v_owner, v_liker) on conflict do nothing;
  insert into public.follows (follower_id, following_id) values (v_liker, v_owner) on conflict do nothing;

  perform set_config('request.jwt.claims', json_build_object('sub', v_owner, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  insert into public.blocked_users (blocker_id, blocked_id) values (v_owner, v_liker);
  execute 'reset role';
  select count(*) into v_cnt from public.follows
  where (follower_id = v_owner and following_id = v_liker) or (follower_id = v_liker and following_id = v_owner);
  r := r || chr(10) || case when v_cnt = 0
         then 'PASS engelde iki yondeki takip silindi'
         else format('FAIL engelden sonra %s takip kaldi', v_cnt) end;

  execute 'set local role authenticated';
  select count(*) into v_cnt from public.post_comments where post_id = v_post and user_id = v_liker;
  r := r || chr(10) || case when v_cnt = 0
         then 'PASS engellenenin yorumlari gizlendi'
         else format('FAIL engellenenin %s yorumu gorunuyor', v_cnt) end;
  select count(*) into v_cnt from public.post_comments where post_id = v_post and user_id = v_owner;
  r := r || chr(10) || case when v_cnt = 1
         then 'PASS kendi yorumu gorunuyor'
         else format('FAIL kendi yorumu=%s', v_cnt) end;
  execute 'reset role';

  perform set_config('request.jwt.claims', json_build_object('sub', v_liker, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  begin
    delete from public.post_likes where post_id = v_post and user_id = v_liker;
    insert into public.post_likes (post_id, user_id) values (v_post, v_liker);
    r := r || chr(10) || 'FAIL engellenen begenebildi';
  exception when insufficient_privilege then
    r := r || chr(10) || 'PASS engellenen begenemedi';
  end;
  begin
    insert into public.post_comments (post_id, user_id, content) values (v_post, v_liker, 'engelli yorum');
    r := r || chr(10) || 'FAIL engellenen yorum yapabildi';
  exception when insufficient_privilege then
    r := r || chr(10) || 'PASS engellenen yorum yapamadi';
  end;
  execute 'reset role';

  raise exception 'TESTS_DONE %', r;
end;
$test$;

ROLLBACK;
