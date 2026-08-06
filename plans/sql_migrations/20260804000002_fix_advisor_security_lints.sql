-- =============================================================================
-- SUPABASE SECURITY ADVISOR: search_path, extension_in_public, bucket listing,
--                            anon SECURITY DEFINER erisimi
-- =============================================================================
-- Bu migration Security Advisor'in bildirdigi lint'lerden GUVENLE ve
-- KANITA DAYALI olarak kapatilabilenleri kapatir:
--
--   1) function_search_path_mutable            (0011)
--   2) extension_in_public: cube, earthdistance (0014)
--   3) public_bucket_allows_listing: news-images (0025)
--   4) anon_security_definer_function_executable -> verify_password_reset_otp (0028)
--
-- Kapsam disi birakilanlar dosyanin sonunda gerekcesiyle birlikte NOTICE olarak
-- raporlanir; korlemesine REVOKE uygulamak bu projede uygulamayi ve RLS'i
-- kirardi (ayrintili gerekce asagida, 5. bolum).
--
-- ONEMLI: MIGRATION/CANLI SAPMASI
-- --------------------------------
-- Advisor ciktisi, bu depodaki bazi migration'larin canliya UYGULANMADIGINI
-- gosteriyor. Ornekler:
--   * verify_password_reset_otp: [`20260802000002`](20260802000002_remove_insecure_password_reset_otp.sql:1)
--     bu fonksiyonu tamamen DROP ediyor, ama Advisor hala canlida goruyor.
--   * update_courier_location_timestamp: [`20260727000002`](20260727000002_fix_advisor_security_performance.sql:26)
--     search_path'i pinliyor, ama Advisor hala "mutable" diyor.
--   * cube/earthdistance: [`20260725000001`](20260725000001_sehirici_services.sql:754)
--     bunlari `WITH SCHEMA extensions` ile kuruyor, ama canlida public'teler.
-- Bu yuzden migration dosyalara degil, calisma anindaki KATALOGA bakar ve
-- tekrar calistirilabilir (idempotent) yazilmistir.
-- =============================================================================

-- =============================================================================
-- 1) function_search_path_mutable
-- =============================================================================
-- search_path'i sabitlenmemis her public fonksiyona pinler.
-- `extensions` bilincli olarak listeye dahildir: 2. bolumde cube/earthdistance
-- public'ten extensions'a tasiniyor ve bazi fonksiyonlar earth_distance() /
-- ll_to_earth() cagrilarini SEMASIZ yapiyor. extensions search_path'te
-- olmazsa tasima sonrasi bu fonksiyonlar "function does not exist" ile patlar.
-- =============================================================================
DO $search_path$
DECLARE
  fn    record;
  fixed integer := 0;
BEGIN
  FOR fn IN
    SELECT p.oid::regprocedure AS ident
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prokind IN ('f', 'p')          -- fonksiyon + prosedur (agregat/window haric)
      -- Bir extension'a ait fonksiyonlar HARIC. cube/earthdistance kendi
      -- fonksiyonlarini (ll_to_earth, earth_distance, cube_in, ...) public'e
      -- kurmus durumda; bunlari ALTER etmek extension sahipligini bozar,
      -- pg_dump/extension upgrade davranisini etkiler ve Advisor'in istedigi
      -- sey de degildir. Lint yalnizca projeye ait fonksiyonlari hedefler.
      AND NOT EXISTS (
        SELECT 1 FROM pg_depend d
        WHERE d.classid = 'pg_proc'::regclass
          AND d.objid   = p.oid
          AND d.deptype = 'e'
      )
      AND NOT EXISTS (
        SELECT 1
        FROM unnest(coalesce(p.proconfig, ARRAY[]::text[])) AS cfg
        WHERE cfg LIKE 'search\_path=%'
      )
    ORDER BY 1
  LOOP
    EXECUTE format('ALTER FUNCTION %s SET search_path = public, extensions, pg_temp', fn.ident);
    fixed := fixed + 1;
    RAISE NOTICE 'search_path pinlendi: %', fn.ident;
  END LOOP;

  RAISE NOTICE 'function_search_path_mutable: % fonksiyon duzeltildi.', fixed;
END
$search_path$;

-- =============================================================================
-- 2) extension_in_public: cube + earthdistance
-- =============================================================================
-- cube ve earthdistance PostgreSQL 16'da relocatable=true oldugu icin
-- ALTER EXTENSION ... SET SCHEMA ile tasinabilir. Sira onemlidir:
-- earthdistance cube'e bagimlidir, once cube tasinir.
--
-- Tasima oncesi, bu extension'lari SEMASIZ cagiran fonksiyonlarin
-- search_path'ine `extensions` eklenir. 1. bolum search_path'i HIC olmayanlari
-- hallediyor; burada ise search_path'i VAR ama icinde extensions OLMAYAN
-- fonksiyonlar da duzeltilir (ornegin compute_sehirici_next_stop).
-- =============================================================================
DO $extensions$
DECLARE
  fn        record;
  ext       record;
  cfg       text;
  new_cfg   text;
  patched   integer := 0;
  moved     integer := 0;
BEGIN
  -- Hedef sema yoksa olustur (Supabase'de normalde vardir).
  IF NOT EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'extensions') THEN
    CREATE SCHEMA extensions;
    RAISE NOTICE 'extensions semasi olusturuldu.';
  END IF;

  -- 2a) cube/earthdistance fonksiyonlarini semasiz cagiran public fonksiyonlarin
  --     search_path'ine extensions ekle.
  FOR fn IN
    SELECT
      p.oid::regprocedure AS ident,
      (SELECT c FROM unnest(p.proconfig) AS c WHERE c LIKE 'search\_path=%') AS sp
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prokind IN ('f', 'p')
      AND p.prosrc ~* '\m(ll_to_earth|earth_distance|earth_box|geo_distance)\s*\('
      AND p.proconfig IS NOT NULL
      -- Extension'in kendi fonksiyonlari haric (yukaridaki gerekce).
      AND NOT EXISTS (
        SELECT 1 FROM pg_depend d
        WHERE d.classid = 'pg_proc'::regclass
          AND d.objid   = p.oid
          AND d.deptype = 'e'
      )
    ORDER BY 1
  LOOP
    cfg := fn.sp;
    CONTINUE WHEN cfg IS NULL;
    -- Zaten extensions varsa dokunma.
    CONTINUE WHEN cfg ~ '(^|=|,\s*)extensions(\s*,|$)';

    new_cfg := cfg || ', extensions';
    EXECUTE format(
      'ALTER FUNCTION %s SET search_path = %s',
      fn.ident,
      substring(new_cfg from 'search\_path=(.*)$')
    );
    patched := patched + 1;
    RAISE NOTICE 'extensions search_path''e eklendi: %', fn.ident;
  END LOOP;

  -- 2b) Extension'lari tasi. cube once, earthdistance sonra.
  FOR ext IN
    SELECT e.extname
    FROM pg_extension e
    JOIN pg_namespace n ON n.oid = e.extnamespace
    WHERE n.nspname = 'public'
      AND e.extname IN ('cube', 'earthdistance')
    ORDER BY CASE e.extname WHEN 'cube' THEN 0 ELSE 1 END
  LOOP
    EXECUTE format('ALTER EXTENSION %I SET SCHEMA extensions', ext.extname);
    moved := moved + 1;
    RAISE NOTICE 'extension tasindi: public.% -> extensions.%', ext.extname, ext.extname;
  END LOOP;

  RAISE NOTICE 'extension_in_public: % fonksiyon yamandi, % extension tasindi.', patched, moved;
END
$extensions$;

-- =============================================================================
-- 3) public_bucket_allows_listing: news-images
-- =============================================================================
-- Public bucket'ta getPublicUrl() / dogrudan obje URL erisimi storage.objects
-- uzerinde SELECT policy'si GEREKTIRMEZ. Genis SELECT policy'si yalnizca
-- istemcinin bucket icerigini LISTELEMESINE izin verir.
-- Flutter tarafinda news-images icin .list() cagrisi yok (dogrulandi), bu yuzden
-- listeleme policy'sini dusurmek gorunur davranisi degistirmez.
-- Upload/update/delete policy'lerine DOKUNULMAZ.
-- =============================================================================
DROP POLICY IF EXISTS "Public can access news images by name" ON storage.objects;
DROP POLICY IF EXISTS "Public can access news images"         ON storage.objects;

DO $bucket$
DECLARE
  remaining text;
BEGIN
  SELECT string_agg(policyname, ', ' ORDER BY policyname)
  INTO remaining
  FROM pg_policies
  WHERE schemaname = 'storage'
    AND tablename  = 'objects'
    AND cmd IN ('SELECT', 'ALL')
    AND coalesce(qual, '') LIKE '%news-images%';

  IF remaining IS NULL THEN
    RAISE NOTICE 'public_bucket_allows_listing: news-images listeleme policy''si kalmadi.';
  ELSE
    RAISE NOTICE 'public_bucket_allows_listing: news-images uzerinde hala SELECT policy(ler)i var: %', remaining;
  END IF;
END
$bucket$;

-- =============================================================================
-- 4) anon_security_definer_function_executable -> verify_password_reset_otp
-- =============================================================================
-- Bu fonksiyon [`20260802000002`](20260802000002_remove_insecure_password_reset_otp.sql:1)
-- ile kaldirilmisti (acik metin OTP + brute-force korumasiz anon RPC).
-- Advisor hala canlida gordugu icin kaldirma burada yeniden uygulanir.
-- Uygulama artik Supabase Auth'un yerlesik recovery OTP akisini kullaniyor;
-- Flutter kodunda bu RPC'ye cagri yok (dogrulandi).
-- =============================================================================
DO $reset_otp$
DECLARE
  fn      record;
  dropped integer := 0;
BEGIN
  FOR fn IN
    -- Imzayi metin olarak simdi al: DROP sonrasi regprocedure cozulemez ve
    -- NOTICE ciktisinda imza yerine ham OID gorunur.
    SELECT p.oid::regprocedure AS ident, p.oid::regprocedure::text AS sig
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'verify_password_reset_otp'
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon, authenticated', fn.ident);
    EXECUTE format('DROP FUNCTION IF EXISTS %s', fn.ident);
    dropped := dropped + 1;
    RAISE NOTICE 'kaldirildi: %', fn.sig;
  END LOOP;

  IF dropped = 0 THEN
    RAISE NOTICE 'verify_password_reset_otp: zaten yok.';
  END IF;
END
$reset_otp$;

-- =============================================================================
-- 5) KAPSAM DISI BIRAKILANLAR + inceleme listesi
-- =============================================================================
-- Asagidakiler BILEREK duzeltilmedi. Gerekceler:
--
-- (a) anon_security_definer_function_executable — kalan 6 fonksiyon
--     * verify_registration_otp: kayit akisinin kendisi. anon cagiramazsa
--       hic kimse kayit olamaz.
--     * get_sehirici_* / compute_sehirici_next_stop: sehir ici ulasim haritasi.
--       Uygulamada misafir (guest) modu var (currentUser == null) ve
--       [`20260725000001`](20260725000001_sehirici_services.sql:752) bu
--       fonksiyonlara anon icin acikca GRANT veriyor. Tasarim geregi publiktir.
--     Bunlar SECURITY DEFINER olarak kalmali; risk fonksiyon govdesindeki
--     yetki kontrolleriyle yonetilir, EXECUTE'u kaldirarak degil.
--
-- (b) authenticated_security_definer_function_executable — ~100 uyari
--     Supabase uygulamalarinda istemciye acilan hemen her RPC SECURITY DEFINER
--     ve `authenticated` tarafindan cagrilabilir olmak zorundadir; bu lint
--     "niyetli mi?" diye sorar, otomatik bir hata degildir.
--     Toplu REVOKE bu projede iki sekilde yikici olurdu:
--       1. Uygulama 66 RPC'yi dogrudan istemciden cagiriyor (Flutter kodundan
--          cikarildi); bunlar calismaz olurdu.
--       2. is_admin() 73, auth_sehirici_is_admin() 21, current_user_role_in_list()
--          16 kez RLS POLICY ifadeleri icinde kullaniliyor. RLS ifadeleri sorguyu
--          yapan rolun yetkisiyle degerlendirilir; bu yardimcilardan EXECUTE
--          alinirsa authenticated icin TUM RLS degerlendirmesi hata verir.
--     Asagidaki rapor, "uygulama cagirmiyor VE RLS yardimcisi degil" olan
--     fonksiyonlari listeler. Bunlar guvenli bir sekilde REVOKE edilebilecek
--     ADAYLARDIR; her biri admin paneli/Edge Function kullanimina karsi tek tek
--     dogrulanmadan kaldirilmamalidir.
--
-- (c) auth_leaked_password_protection
--     Bu bir SQL ayari degil; Supabase Dashboard > Authentication > Policies
--     altindan "Leaked password protection" acilmalidir. Migration ile
--     degistirilemez.
-- =============================================================================
DO $review$
DECLARE
  candidates text;
  -- Flutter/web istemcisinin dogrudan cagirdigi RPC'ler (kaynak koddan cikarildi).
  app_rpcs text[] := ARRAY[
    'add_notification','admin_add_group_member','admin_approve_join_request',
    'admin_change_member_role','admin_create_group','admin_delete_group',
    'admin_delete_sehirici_city','admin_delete_sehirici_stop','admin_get_all_groups',
    'admin_get_group_members','admin_list_suspicious_users','admin_reject_join_request',
    'admin_remove_group_member','admin_reward_points_overview','admin_scan_fraud_signals',
    'admin_set_user_suspicious','admin_update_group','admin_upsert_sehirici_city',
    'admin_upsert_sehirici_line','admin_upsert_sehirici_stop','apply_campaign_rewards_for_order',
    'approve_group_join_request','can_review_order','cancel_order','claim_flash_sale',
    'commit_balance_order','commit_cod_order','compute_sehirici_next_stop',
    'dismiss_review_reminder','end_live_session','ensure_my_profile',
    'get_admin_commission_report','get_group_messages_with_read_count',
    'get_message_read_count','get_message_read_receipts','get_pending_reviews',
    'get_sehirici_active_trips','get_sehirici_lines_with_stops','get_sehirici_trip_path',
    'get_sehirici_trips_for_stop','get_seller_commission_summary','get_shop_today_views',
    'get_shop_total_views','get_task_stats','get_top_customers','get_top_viewed_products',
    'get_user_groups','increment_story_likes','join_open_group','mark_group_messages_as_read',
    'mark_group_messages_read_receipts','mark_messages_as_read','prepare_checkout_session',
    'reject_group_join_request','release_flash_sale','search_groups','set_my_presence',
    'set_sehirici_trip_status','start_live_session','start_sehirici_trip',
    'update_sehirici_trip_location','upsert_follow_request','use_coupon','validate_coupon',
    'verify_code','verify_registration_otp'
  ];
  -- RLS policy ifadelerinde kullanilan yardimcilar: EXECUTE ASLA kaldirilmamali.
  rls_helpers text[] := ARRAY[
    'is_admin','auth_is_admin','auth_sehirici_is_admin','is_fraud_admin',
    'current_user_has_role','current_user_role_in_list','is_group_member','is_group_admin'
  ];
BEGIN
  SELECT string_agg('  ' || sig, E'\n' ORDER BY sig)
  INTO candidates
  FROM (
    SELECT p.oid::regprocedure::text AS sig
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prosecdef                                   -- SECURITY DEFINER
      AND has_function_privilege('authenticated', p.oid, 'EXECUTE')
      AND NOT (p.proname = ANY (app_rpcs))
      AND NOT (p.proname = ANY (rls_helpers))
  ) s;

  IF candidates IS NULL THEN
    RAISE NOTICE 'authenticated SECURITY DEFINER: inceleme adayi yok.';
  ELSE
    RAISE NOTICE E'authenticated SECURITY DEFINER — uygulama cagirmayan ve RLS yardimcisi olmayan\nREVOKE ADAYLARI (otomatik kaldirilmadi, tek tek dogrulayin):\n%', candidates;
  END IF;

  RAISE NOTICE 'auth_leaked_password_protection: Dashboard > Authentication ayari, SQL ile kapatilamaz.';
END
$review$;
