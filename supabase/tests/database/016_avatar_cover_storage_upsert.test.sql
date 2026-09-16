-- =============================================================================
-- PROFIL AVATARI / KAPAK YUKLEME — DAVRANIS testleri (pgTAP)
--
-- NEDEN BU DOSYA:
--   Kullanici hazir avatar sectiginde ya da galeriden fotograf yukledginde
--   uygulama "Profil fotografi yuklenemedi" diyordu. Depolama tarafinda
--   INSERT/UPDATE/DELETE politikalari vardi, bucket'lar public'ti, izinli
--   mime listesi image/gif'i bile kapsiyordu — yani her katalog kontrolu
--   geciyordu. Eksik olan tek sey `avatars` / `covers` bucket'lari icin bir
--   SELECT politikasiydi.
--
--   ProfileService tum yuklemeleri `FileOptions(upsert: true)` ile yapiyor.
--   storage-api'nin upsert yolu `INSERT ... ON CONFLICT ... RETURNING`
--   kullanir; RETURNING ile donen satir SELECT politikalarindan da gecmek
--   zorundadir. SELECT politikasi hic olmadigi icin upsert'li her yukleme
--   403 "new row violates row-level security policy" aliyordu; upsert'siz
--   ayni yukleme sorunsuz geciyordu. Bu yuzden testler storage-api'nin
--   gercek deyim seklini (ON CONFLICT + RETURNING) taklit eder.
--
-- Calistirma:
--   supabase start && supabase test db supabase/tests/database
-- =============================================================================

begin;

create extension if not exists pgtap with schema extensions;

select plan(9);

-- -----------------------------------------------------------------------------
-- YARDIMCI: storage-api upsert'ini authenticated rolu baglaminda taklit et
-- -----------------------------------------------------------------------------
create or replace function pg_temp.try_storage_upsert(
  p_uid uuid,
  p_bucket text,
  p_name text,
  p_mime text
)
returns text language plpgsql as $$
declare
  v_name text;
begin
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', p_uid::text, 'role', 'authenticated')::text,
    true
  );
  set local role authenticated;
  begin
    insert into storage.objects (bucket_id, name, owner, owner_id, metadata)
    values (p_bucket, p_name, p_uid, p_uid::text,
            json_build_object('mimetype', p_mime)::jsonb)
    on conflict (bucket_id, name) do update
      set metadata = excluded.metadata
    returning name into v_name;
  exception when others then
    reset role;
    return 'ERR:' || sqlstate || ':' || sqlerrm;
  end;
  reset role;
  return 'OK:' || v_name;
end $$;

-- -----------------------------------------------------------------------------
-- FIXTURE
-- -----------------------------------------------------------------------------
create temporary table t_fix (user_id uuid);

do $$
declare v_user uuid := gen_random_uuid();
begin
  insert into auth.users (id, instance_id, email, aud, role,
                          created_at, updated_at, email_confirmed_at)
  values (v_user, '00000000-0000-0000-0000-000000000000',
          'avatar_test_' || substring(v_user::text from 1 for 8) || '@example.com',
          'authenticated', 'authenticated', now(), now(), now());

  insert into public.profiles (id, email, full_name)
  select v_user, 'avatar_test@example.com', 'Avatar Test'
  where not exists (select 1 from public.profiles p where p.id = v_user);

  insert into t_fix values (v_user);
end $$;

-- -----------------------------------------------------------------------------
-- 1) Avatar upsert (PNG) — hazir/klasik avatar ve galeri akisi
-- -----------------------------------------------------------------------------
select matches(
  pg_temp.try_storage_upsert(
    (select user_id from t_fix), 'avatars',
    'avatar_' || (select user_id from t_fix)::text || '-1.png', 'image/png'
  ),
  '^OK:avatar_',
  'avatars: upsert:true yukleme RLS''e takilmaz (SELECT politikasi var)'
);

-- -----------------------------------------------------------------------------
-- 2) Avatar upsert (GIF) — hareketli hazir avatarlar
-- -----------------------------------------------------------------------------
select matches(
  pg_temp.try_storage_upsert(
    (select user_id from t_fix), 'avatars',
    'avatar_' || (select user_id from t_fix)::text || '-2.gif', 'image/gif'
  ),
  '^OK:avatar_',
  'avatars: hareketli (GIF) avatar upsert ile yuklenebilir'
);

-- -----------------------------------------------------------------------------
-- 3) Ayni ada ikinci upsert — gercek ON CONFLICT yolu
-- -----------------------------------------------------------------------------
select matches(
  pg_temp.try_storage_upsert(
    (select user_id from t_fix), 'avatars',
    'avatar_' || (select user_id from t_fix)::text || '-1.png', 'image/png'
  ),
  '^OK:avatar_',
  'avatars: ayni dosya adina tekrar upsert (uzerine yazma) calisir'
);

-- -----------------------------------------------------------------------------
-- 4) Kapak fotografi upsert
-- -----------------------------------------------------------------------------
select matches(
  pg_temp.try_storage_upsert(
    (select user_id from t_fix), 'covers',
    'cover_' || (select user_id from t_fix)::text || '-1.jpg', 'image/jpeg'
  ),
  '^OK:cover_',
  'covers: upsert:true kapak yuklemesi RLS''e takilmaz'
);

-- -----------------------------------------------------------------------------
-- 5-6) SELECT politikasi katalog kontrolu (regresyon korumasi)
-- -----------------------------------------------------------------------------
select ok(
  exists (
    select 1 from pg_policies
    where schemaname = 'storage' and tablename = 'objects' and cmd = 'SELECT'
      and coalesce(qual, '') like '%avatars%'
  ),
  'storage.objects: avatars bucket icin SELECT politikasi var'
);

select ok(
  exists (
    select 1 from pg_policies
    where schemaname = 'storage' and tablename = 'objects' and cmd = 'SELECT'
      and coalesce(qual, '') like '%covers%'
  ),
  'storage.objects: covers bucket icin SELECT politikasi var'
);

-- -----------------------------------------------------------------------------
-- 7-8) Bucket ayarlari
-- -----------------------------------------------------------------------------
select ok(
  (select bool_and(public) from storage.buckets where id in ('avatars', 'covers')),
  'avatars ve covers bucket''lari public (CDN okumasi RLS''e ugramaz)'
);

select ok(
  (select 'image/gif' = any(allowed_mime_types)
     from storage.buckets where id = 'avatars'),
  'avatars bucket izinli mime listesi image/gif iceriyor (hareketli avatar)'
);

-- -----------------------------------------------------------------------------
-- 9) Profil avatar_url yazimi dar RPC ile yapilabiliyor
-- -----------------------------------------------------------------------------
create or replace function pg_temp.set_avatar_as(p_uid uuid, p_url text)
returns text language plpgsql as $$
begin
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', p_uid::text, 'role', 'authenticated')::text,
    true
  );
  set local role authenticated;
  begin
    perform public.update_my_public_profile(p_avatar_url => p_url);
  exception when others then
    reset role;
    return 'ERR:' || sqlstate || ':' || sqlerrm;
  end;
  reset role;
  return (select coalesce(p.avatar_url, 'NULL') from public.profiles p where p.id = p_uid);
end $$;

select is(
  pg_temp.set_avatar_as((select user_id from t_fix), 'https://example.test/a.png'),
  'https://example.test/a.png',
  'update_my_public_profile: avatar_url kullanicinin kendi profiline yazilir'
);

select * from finish();

rollback;
