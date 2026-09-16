-- =============================================================================
-- KUPON AKISI — DAVRANIS testleri (pgTAP)
--
-- NEDEN BU DOSYA:
--   Satici panelinden kupon eklemek calisiyordu; RLS insert politikasi ve
--   tablo yapisi dogruydu. Buna ragmen eklenen kupon HICBIR ISE YARAMIYORDU:
--
--     * private.validate_coupon() her cagrilista 42702 firlatiyordu
--       ("column reference id is ambiguous") — RETURNS TABLE kolonlari ayni
--       zamanda PL/pgSQL degiskeni oldugu icin `WHERE id = p_coupon_id`
--       belirsizdi. Migration sorunsuz uygulanir, katalog/ACL testleri gecer;
--       hata ancak fonksiyon GERCEKTEN CALISTIRILDIGINDA ortaya cikar.
--       (014_payment_rpc_behavior.test.sql ayni sinif hatayi odemelerde
--       yakaliyor; oradaki has_unqualified_out_ref yardimcisi yalniz `public`
--       semasini taradigi icin `private` fonksiyonunu kacirmisti.)
--     * Indirim tipi 'fixed' ile karsilastiriliyordu; enum degeri
--       'fixed_amount'. Satici panelinin varsayilan kupon tipi bu, yani sabit
--       tutarli TUM kuponlar "Bilinmeyen kupon tipi" ile reddediliyordu (hem
--       validate_coupon hem prepare_checkout_session icinde).
--     * shop_coupons SELECT politikasi musteri/misafir dalini kaybetmisti:
--       eklenen kupon hicbir musteriye gorunmuyordu.
--     * coupon_usages SELECT politikasi magaza sahibi dalini kaybetmisti.
--     * usage_count iki kez artiyordu (trigger + RPC).
--
--   Bu dosya kuponu gercek veriyle ucdan uca calistirir; ayni hatalar bir daha
--   canliya cikmadan burada patlar.
--
-- Calistirma:
--   supabase start && supabase test db supabase/tests/database
-- =============================================================================

begin;

create extension if not exists pgtap with schema extensions;

select plan(21);

-- -----------------------------------------------------------------------------
-- YARDIMCILAR
-- -----------------------------------------------------------------------------

-- 42702 korumasi: verilen fonksiyonun govdesinde `where/and/or <kolon> =`
-- seklinde NITELENMEMIS bir OUT kolonu atifi var mi? (sema duyarli)
create or replace function pg_temp.has_unqualified_out_ref(
  p_schema text, p_fn text, p_col text
)
returns boolean language sql stable as $$
  select exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = p_schema
      and p.proname = p_fn
      and p.prolang = (select oid from pg_language where lanname = 'plpgsql')
      and p.prosrc ~* ('(and|where|or)[[:space:]]+'
                       || p_col
                       || '[[:space:]]*(=|is[[:space:]])')
  );
$$;

-- Belirtilen rol/kullanici baglaminda gorunen kupon kodlari (RLS uygulanir).
create or replace function pg_temp.visible_coupon_codes_as(
  p_role text, p_uid uuid, p_shop uuid
)
returns text[] language plpgsql as $$
declare
  v_codes text[];
begin
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', coalesce(p_uid::text, ''), 'role', p_role)::text,
    true
  );
  execute format('set local role %I', p_role);
  begin
    select coalesce(array_agg(sc.code order by sc.code), '{}')
      into v_codes
    from public.shop_coupons sc
    where sc.shop_id = p_shop;
  exception when others then
    reset role;
    return array['ERR:' || sqlstate];
  end;
  reset role;
  return v_codes;
end $$;

-- Kupon eklemeyi verilen satici baglaminda dener; sonucu metin olarak doner:
-- 'OK:<normalize_edilmis_kod>' veya 'ERR:<sqlstate>:<mesaj>'
create or replace function pg_temp.try_insert_coupon(
  p_uid uuid,
  p_shop uuid,
  p_code text,
  p_title text,
  p_type text,
  p_value numeric,
  p_min numeric default 0
)
returns text language plpgsql as $$
declare
  v_code text;
begin
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', p_uid::text, 'role', 'authenticated')::text,
    true
  );
  set local role authenticated;
  begin
    insert into public.shop_coupons
      (shop_id, code, title, discount_type, discount_value, minimum_order_amount)
    values
      (p_shop, p_code, p_title, p_type::public.coupon_type, p_value, p_min)
    returning code into v_code;
  exception when others then
    reset role;
    return 'ERR:' || sqlstate || ':' || sqlerrm;
  end;
  reset role;
  return 'OK:' || v_code;
end $$;

-- Kupon kullanimlarini verilen kullanici baglaminda sayar (RLS uygulanir).
create or replace function pg_temp.usage_count_seen_by(p_uid uuid, p_coupon uuid)
returns integer language plpgsql as $$
declare v_cnt int;
begin
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', p_uid::text, 'role', 'authenticated')::text,
    true
  );
  set local role authenticated;
  begin
    select count(*) into v_cnt
    from public.coupon_usages cu
    where cu.coupon_id = p_coupon;
  exception when others then
    reset role;
    return -1;
  end;
  reset role;
  return v_cnt;
end $$;

-- -----------------------------------------------------------------------------
-- FIXTURE
-- -----------------------------------------------------------------------------
create temporary table t_fix (
  seller_id        uuid,   -- TEK magazasi olan satici
  other_seller_id  uuid,   -- onaysiz magazanin sahibi
  buyer_id         uuid,
  shop_id          uuid,   -- aktif + onayli magaza
  hidden_shop_id   uuid,   -- onaysiz magaza (kuponu musteriye gorunmemeli)
  coupon_fixed     uuid,   -- 100 TL sabit, min 1500
  coupon_percent   uuid,   -- %25, max 200 TL indirim
  coupon_passive   uuid,   -- is_active = false
  coupon_hidden    uuid,   -- onaysiz magazanin kuponu
  order_id         uuid
);

do $$
declare
  v_seller uuid := gen_random_uuid();
  v_other  uuid := gen_random_uuid();
  v_buyer  uuid := gen_random_uuid();
  v_shop   uuid := gen_random_uuid();
  v_hidden uuid := gen_random_uuid();
  v_fixed  uuid;
  v_pct    uuid;
  v_pass   uuid;
  v_hid    uuid;
  v_order  uuid := gen_random_uuid();
begin
  insert into auth.users (id, instance_id, email, aud, role,
                          created_at, updated_at, email_confirmed_at)
  values
    (v_seller, '00000000-0000-0000-0000-000000000000',
     'coupon_seller_' || substring(v_seller::text from 1 for 8) || '@example.com',
     'authenticated', 'authenticated', now(), now(), now()),
    (v_other, '00000000-0000-0000-0000-000000000000',
     'coupon_other_' || substring(v_other::text from 1 for 8) || '@example.com',
     'authenticated', 'authenticated', now(), now(), now()),
    (v_buyer, '00000000-0000-0000-0000-000000000000',
     'coupon_buyer_' || substring(v_buyer::text from 1 for 8) || '@example.com',
     'authenticated', 'authenticated', now(), now(), now());

  -- on_auth_user_created profili olusturur; olusturmadiysa yedek.
  insert into public.profiles (id, email, full_name)
  select v_seller, 'coupon_seller@example.com', 'Kupon Satici'
  where not exists (select 1 from public.profiles p where p.id = v_seller);
  insert into public.profiles (id, email, full_name)
  select v_other, 'coupon_other@example.com', 'Diger Satici'
  where not exists (select 1 from public.profiles p where p.id = v_other);
  insert into public.profiles (id, email, full_name)
  select v_buyer, 'coupon_buyer@example.com', 'Kupon Musteri'
  where not exists (select 1 from public.profiles p where p.id = v_buyer);

  insert into public.shops (id, owner_id, name, slug, is_active, is_approved)
  values
    (v_shop, v_seller, 'Kupon Test Magazasi',
     'kupon-test-' || substring(v_shop::text from 1 for 8), true, true),
    (v_hidden, v_other, 'Onaysiz Kupon Magazasi',
     'kupon-onaysiz-' || substring(v_hidden::text from 1 for 8), true, false);

  insert into public.shop_coupons
    (shop_id, code, title, discount_type, discount_value,
     minimum_order_amount, maximum_discount_amount, usage_limit, usage_per_user,
     is_active)
  values (v_shop, 'SABIT100', '100 TL Indirim', 'fixed_amount', 100,
          1500, null, 10, 1, true)
  returning id into v_fixed;

  insert into public.shop_coupons
    (shop_id, code, title, discount_type, discount_value,
     minimum_order_amount, maximum_discount_amount, usage_per_user, is_active)
  values (v_shop, 'YUZDE25', 'Yuzde 25', 'percentage', 25, 0, 200, 1, true)
  returning id into v_pct;

  insert into public.shop_coupons
    (shop_id, code, title, discount_type, discount_value,
     minimum_order_amount, is_active)
  values (v_shop, 'PASIF', 'Pasif kupon', 'fixed_amount', 50, 0, false)
  returning id into v_pass;

  insert into public.shop_coupons
    (shop_id, code, title, discount_type, discount_value,
     minimum_order_amount, is_active)
  values (v_hidden, 'GIZLI', 'Onaysiz magaza kuponu', 'fixed_amount', 50, 0, true)
  returning id into v_hid;

  insert into public.orders
    (id, user_id, shop_id, order_number, delivery_address_text,
     payment_method, subtotal, total)
  values
    (v_order, v_buyer, v_shop,
     'KUPON-TEST-' || substring(v_order::text from 1 for 8),
     'Test adresi', 'cash', 2000, 2000);

  insert into t_fix values
    (v_seller, v_other, v_buyer, v_shop, v_hidden,
     v_fixed, v_pct, v_pass, v_hid, v_order);
end $$;

-- -----------------------------------------------------------------------------
-- 1) private.validate_coupon — sabit tutarli kupon
--    (42702 VE 'fixed' sabiti regresyonlarinin ikisini birden yakalar)
-- -----------------------------------------------------------------------------
select results_eq(
  $$ select code, discount_type, computed_discount
     from private.validate_coupon(
       (select coupon_fixed from t_fix), 2000, (select buyer_id from t_fix)
     ) $$,
  $$ values ('SABIT100'::text, 'fixed_amount'::text, 100::numeric) $$,
  'private.validate_coupon: sabit tutarli kupon 100 TL indirim doner'
);

-- -----------------------------------------------------------------------------
-- 2) Yuzdelik kupon maksimum indirimle sinirlanir
-- -----------------------------------------------------------------------------
select results_eq(
  $$ select computed_discount
     from private.validate_coupon(
       (select coupon_percent from t_fix), 2000, (select buyer_id from t_fix)
     ) $$,
  $$ values (200::numeric) $$,
  'private.validate_coupon: yuzdelik indirim maximum_discount_amount ile kesilir'
);

-- -----------------------------------------------------------------------------
-- 3) Minimum sepet tutari asilmadiysa hata
-- -----------------------------------------------------------------------------
select throws_ok(
  $$ select * from private.validate_coupon(
       (select coupon_fixed from t_fix), 1000, (select buyer_id from t_fix)
     ) $$,
  'P0001',
  'Minimum siparis tutari asilmadi',
  'private.validate_coupon: minimum tutar altinda reddedilir'
);

-- -----------------------------------------------------------------------------
-- 4) Pasif kupon reddedilir
-- -----------------------------------------------------------------------------
select throws_ok(
  $$ select * from private.validate_coupon(
       (select coupon_passive from t_fix), 2000, (select buyer_id from t_fix)
     ) $$,
  'P0001',
  'Kupon aktif degil',
  'private.validate_coupon: pasif kupon reddedilir'
);

-- public.validate_coupon auth.uid() ister; musteri baglamini kur.
do $$
declare v_buyer uuid;
begin
  select buyer_id into v_buyer from t_fix;
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', v_buyer::text, 'role', 'authenticated')::text,
    true
  );
end $$;

-- -----------------------------------------------------------------------------
-- 5) public.validate_coupon — bosluklu/kucuk harfli kod da eslesir
-- -----------------------------------------------------------------------------
select results_eq(
  $$ select code, computed_discount
     from public.validate_coupon(
       (select shop_id from t_fix), '  sabit100 ', 2000,
       (select buyer_id from t_fix)
     ) $$,
  $$ values ('SABIT100'::text, 100::numeric) $$,
  'public.validate_coupon: kod trim/buyuk-kucuk harf duyarsiz eslesir'
);

-- -----------------------------------------------------------------------------
-- 6) Yanlis kod net mesajla reddedilir
-- -----------------------------------------------------------------------------
select throws_ok(
  $$ select * from public.validate_coupon(
       (select shop_id from t_fix), 'OLMAYANKOD', 2000,
       (select buyer_id from t_fix)
     ) $$,
  'P0001',
  'Geçersiz kupon kodu',
  'public.validate_coupon: bilinmeyen kod icin net mesaj'
);

-- -----------------------------------------------------------------------------
-- 7-8) 42702 statik korumasi (sema duyarli)
-- -----------------------------------------------------------------------------
select ok(
  not pg_temp.has_unqualified_out_ref('private', 'validate_coupon', 'id'),
  'private.validate_coupon: "id" atiflari nitelenmis (42702 korumasi)'
);

select ok(
  not pg_temp.has_unqualified_out_ref('public', 'validate_coupon', 'id'),
  'public.validate_coupon: "id" atiflari nitelenmis (42702 korumasi)'
);

-- -----------------------------------------------------------------------------
-- 9-10) 'fixed' sabiti hicbir kupon hesabinda kalmamali
-- -----------------------------------------------------------------------------
select ok(
  position('discount_type = ''fixed''' in
    pg_get_functiondef('private.validate_coupon(uuid,numeric,uuid)'::regprocedure)) = 0,
  'private.validate_coupon: hatali ''fixed'' karsilastirmasi kalmadi'
);

select ok(
  position('discount_type = ''fixed''' in
    pg_get_functiondef(
      'private.prepare_checkout_session(jsonb,uuid,text,text,uuid,text,jsonb,uuid)'::regprocedure
    )) = 0,
  'private.prepare_checkout_session: hatali ''fixed'' karsilastirmasi kalmadi'
);

-- -----------------------------------------------------------------------------
-- 11-13) Musteri / misafir gorunurlugu (RLS)
-- -----------------------------------------------------------------------------
select is(
  pg_temp.visible_coupon_codes_as('authenticated',
    (select buyer_id from t_fix), (select shop_id from t_fix)),
  array['SABIT100', 'YUZDE25'],
  'musteri: yayinda magazanin AKTIF kuponlarini gorur (pasif kupon gorunmez)'
);

select is(
  pg_temp.visible_coupon_codes_as('anon', null, (select shop_id from t_fix)),
  array['SABIT100', 'YUZDE25'],
  'misafir: aktif kuponlari gorur (anon politikasi auth_is_admin cagirmadan calisir)'
);

select is(
  pg_temp.visible_coupon_codes_as('anon', null, (select hidden_shop_id from t_fix)),
  '{}'::text[],
  'misafir: onaysiz magazanin kuponunu GORMEZ'
);

-- -----------------------------------------------------------------------------
-- 14) Magaza sahibi kendi pasif kuponunu da gorur
-- -----------------------------------------------------------------------------
select is(
  pg_temp.visible_coupon_codes_as('authenticated',
    (select seller_id from t_fix), (select shop_id from t_fix)),
  array['PASIF', 'SABIT100', 'YUZDE25'],
  'satici: kendi magazasinin pasif kuponunu da gorur'
);

-- -----------------------------------------------------------------------------
-- 15) anon politikasi auth_is_admin() cagirmaz (42501 tuzagi)
-- -----------------------------------------------------------------------------
select ok(
  (select count(*) = 1
   from pg_policies
   where schemaname = 'public'
     and tablename = 'shop_coupons'
     and policyname = 'shop_coupons_select_anon'
     and roles::text = '{anon}'
     and coalesce(qual, '') not like '%auth_is_admin%'),
  'shop_coupons_select_anon: anon politikasi auth_is_admin() icermez'
);

-- Kuponu gercekten kullan (satici istatistigi + sayac testleri icin).
do $$
declare v_c uuid; v_o uuid; v_b uuid;
begin
  select coupon_fixed, order_id, buyer_id into v_c, v_o, v_b from t_fix;
  perform public.use_coupon(v_c, v_o, v_b, 100);
end $$;

-- -----------------------------------------------------------------------------
-- 16) Satici kendi kuponunun kullanimlarini gorur
-- -----------------------------------------------------------------------------
select is(
  pg_temp.usage_count_seen_by(
    (select seller_id from t_fix), (select coupon_fixed from t_fix)),
  1,
  'satici: kendi kuponunun kullanim kaydini gorur (istatistik 0 kalmaz)'
);

-- -----------------------------------------------------------------------------
-- 17-18) usage_count TEK artar (cift sayac regresyonu)
-- -----------------------------------------------------------------------------
select is(
  (select usage_count from public.shop_coupons
    where id = (select coupon_fixed from t_fix)),
  1,
  'usage_count: bir kullanim = bir artis (trigger + RPC cift saymiyor)'
);

select ok(
  not exists (
    select 1
    from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    where c.relname = 'coupon_usages'
      and t.tgname = 'trigger_record_coupon_usage'
      and not t.tgisinternal
  ),
  'trigger_record_coupon_usage kaldirildi (cift artisin kaynagi)'
);

-- -----------------------------------------------------------------------------
-- 19) Kupon ekleme: kod trim + buyuk harf
-- -----------------------------------------------------------------------------
select is(
  pg_temp.try_insert_coupon(
    (select seller_id from t_fix), (select shop_id from t_fix),
    '  bahar25 ', 'Bahar', 'percentage', 25
  ),
  'OK:BAHAR25',
  'kupon ekleme: kod trim edilip buyuk harfe cevrilir'
);

-- -----------------------------------------------------------------------------
-- 20) Ayni kod ikinci kez: anlasilir Turkce mesaj (teknik constraint degil)
-- -----------------------------------------------------------------------------
select matches(
  pg_temp.try_insert_coupon(
    (select seller_id from t_fix), (select shop_id from t_fix),
    'sabit100', 'Kopya', 'fixed_amount', 10
  ),
  '^ERR:23505:Bu kupon kodu magazanizda zaten kayitli',
  'kupon ekleme: ayni kod anlasilir mesajla reddedilir'
);

-- -----------------------------------------------------------------------------
-- 21) shop_id gonderilmezse sunucu cagiranin magazasini kullanir
--     (istemci "Magaza bulunamadi" durumuna dusse bile kupon kaybolmaz)
-- -----------------------------------------------------------------------------
select is(
  pg_temp.try_insert_coupon(
    (select seller_id from t_fix), null,
    'otomatik10', 'Otomatik', 'fixed_amount', 10
  ),
  'OK:OTOMATIK10',
  'kupon ekleme: shop_id yoksa sunucu saticinin magazasini kullanir'
);

select * from finish();

rollback;
