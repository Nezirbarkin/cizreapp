-- ============================================================================
-- 20261024000004_mute_hide_search — canlı davranış testi
-- ----------------------------------------------------------------------------
-- Kendi kendini geri alır: DO bloğu sonunda bilerek RAISE EXCEPTION atar,
-- her şey geri alınır, CLI özet satırlarını hata mesajı olarak yazdırır.
-- Göç uygulanmadan önce denemek için göç gövdesini (BEGIN/COMMIT/NOTIFY
-- hariç) @@MIGRATION@@ satırının yerine koyun; uygulandıktan sonra olduğu
-- gibi çalıştırın:
--   supabase db query --linked --file supabase/tests/manual/mute_hide_search_test.sql
-- Beklenen: "TESTS_DONE" mesajında FAIL satırı yok.
-- ============================================================================
BEGIN;

-- @@MIGRATION@@

DO $test$
declare
  v_me uuid; v_author uuid; v_other uuid;
  v_p1 uuid; v_p2 uuid; v_p3 uuid;
  v_n int;
  v_j jsonb;
  r text := '';
begin
  -- ------------------------------------------------------------ fikstürler
  select p.id into v_me
  from public.profiles p
  where coalesce(p.role::text, 'user') <> 'admin' and not coalesce(p.is_admin, false)
    and not coalesce(p.is_bot, false) and coalesce(p.status::text, 'active') = 'active'
  order by p.id limit 1;

  select p.id into v_author
  from public.profiles p
  where p.id <> v_me and coalesce(p.profile_is_public, true) and not coalesce(p.is_ghost_mode, false)
    and not coalesce(p.is_bot, false) and coalesce(p.status::text, 'active') = 'active'
    and not exists (select 1 from public.blocked_users b
                    where (b.blocker_id = p.id and b.blocked_id = v_me)
                       or (b.blocker_id = v_me and b.blocked_id = p.id))
  order by p.id limit 1;

  select p.id into v_other
  from public.profiles p
  where p.id not in (v_me, v_author) and coalesce(p.profile_is_public, true)
    and not coalesce(p.is_ghost_mode, false) and not coalesce(p.is_bot, false)
    and coalesce(p.status::text, 'active') = 'active'
    and not exists (select 1 from public.blocked_users b
                    where (b.blocker_id = p.id and b.blocked_id = v_me)
                       or (b.blocker_id = v_me and b.blocked_id = p.id))
  order by p.id limit 1;

  insert into public.posts (user_id, content) values (v_author, 'Zıpzıp ARAMA_testi 100% kahve') returning id into v_p1;
  insert into public.posts (user_id, content) values (v_other, 'diğer arama_testi gönderisi') returning id into v_p2;
  insert into public.posts (user_id, content) values (v_other, 'gizlenecek arama_testi') returning id into v_p3;

  r := r || chr(10) || format('fixtures me=%s author=%s other=%s',
         v_me is not null, v_author is not null, v_other is not null);

  perform set_config('request.jwt.claims', json_build_object('sub', v_me, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';

  select count(*) into v_n from public.feed_posts_with_profiles where id in (v_p1, v_p2, v_p3);
  r := r || chr(10) || case when v_n = 3 then 'PASS akista uc gonderi' else 'FAIL akis n=' || v_n end;

  -- Sessize al: yazarın gönderisi akıştan çıkar, profil görünümünde kalır.
  insert into public.muted_users (muter_id, muted_id) values (v_me, v_author);
  select count(*) into v_n from public.feed_posts_with_profiles where id = v_p1;
  r := r || chr(10) || case when v_n = 0 then 'PASS sessize alinan akista yok' else 'FAIL sessize alinan gorundu' end;
  select count(*) into v_n from public.posts_with_profiles where id = v_p1;
  r := r || chr(10) || case when v_n = 1 then 'PASS profilde gorunur' else 'FAIL profilde yok' end;

  -- Gizle: yalnız o gönderi çıkar.
  insert into public.hidden_posts (user_id, post_id, reason) values (v_me, v_p3, 'not_interested');
  select count(*) into v_n from public.feed_posts_with_profiles where id in (v_p2, v_p3);
  r := r || chr(10) || case when v_n = 1 then 'PASS gizlenen akista yok' else 'FAIL gizleme n=' || v_n end;

  begin
    insert into public.muted_users (muter_id, muted_id) values (v_other, v_me);
    r := r || chr(10) || 'FAIL baskasi adina sessize alma';
  exception when insufficient_privilege then
    r := r || chr(10) || 'PASS baskasi adina sessize alma yok';
  end;
  begin
    insert into public.muted_users (muter_id, muted_id) values (v_me, v_me);
    r := r || chr(10) || 'FAIL kendini sessize aldi';
  exception when check_violation then
    r := r || chr(10) || 'PASS kendini sessize alamaz';
  end;

  -- Arama: Türkçe katlama ve joker kaçışı.
  v_j := public.search_posts('zipzip arama');
  r := r || chr(10) || case when exists (select 1 from jsonb_array_elements(v_j) e where e->>'id' = v_p1::text)
    then 'PASS arama turkce katlama' else 'FAIL arama: ' || left(v_j::text, 120) end;
  v_j := public.search_posts('100%');
  r := r || chr(10) || case when jsonb_array_length(v_j) >= 1
       and not exists (select 1 from jsonb_array_elements(v_j) e where e->>'id' = v_p2::text)
    then 'PASS yuzde isareti metin olarak aranir' else 'FAIL joker kacisi' end;
  r := r || chr(10) || case when public.search_posts('a') = '[]'::jsonb
    then 'PASS tek harf aranmaz' else 'FAIL tek harf' end;

  execute 'reset role';

  perform set_config('request.jwt.claims', json_build_object('sub', v_other, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  select count(*) into v_n from public.muted_users where muter_id = v_me;
  r := r || chr(10) || case when v_n = 0 then 'PASS sessize alma listesi gizli' else 'FAIL liste gorundu' end;
  select count(*) into v_n from public.feed_posts_with_profiles where id = v_p1;
  r := r || chr(10) || case when v_n = 1 then 'PASS baskasinin akisi etkilenmez' else 'FAIL baskasinin akisi' end;
  execute 'reset role';

  r := r || chr(10) || case when not has_table_privilege('anon', 'public.feed_posts_with_profiles', 'select')
       and not has_function_privilege('anon', 'public.search_posts(text,integer)', 'execute')
    then 'PASS misafir kapali' else 'FAIL misafir yetkisi' end;

  raise exception 'TESTS_DONE %', r;
end;
$test$;

ROLLBACK;
