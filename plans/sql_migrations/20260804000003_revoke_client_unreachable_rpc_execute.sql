-- =============================================================================
-- SECURITY ADVISOR 0028/0029: istemciden erisilemeyen SECURITY DEFINER
-- fonksiyonlarindan anon/authenticated EXECUTE yetkisini kaldir
-- =============================================================================
-- Advisor'in "Signed-In Users / Public Can Execute SECURITY DEFINER Function"
-- uyarilari, istemciye acilan her RPC icin tetiklenir. Bu projede bu
-- fonksiyonlarin bir kismi GERCEKTEN istemciden cagriliyor (tasarim geregi),
-- bir kismi ise yalnizca sunucu tarafindan (Edge Function / trigger / baska
-- RPC icinden) kullaniliyor ama yine de anon/authenticated'a acik durumda.
--
-- Bu migration YALNIZ ikinci grubu kapatir.
--
-- KALIP (repo standardi, bkz. [`20260727000008`](20260727000008_harden_balance_rpc_permissions.sql:1)):
--   REVOKE EXECUTE ... FROM PUBLIC, anon, authenticated
--   GRANT  EXECUTE ... TO service_role
-- service_role'e ACIK grant sarttir: fonksiyonlarda EXECUTE varsayilani
-- PUBLIC'tir, yalnizca PUBLIC'ten alinirsa Edge Function'lar da yetkisini
-- kaybederdi.
--
-- ---------------------------------------------------------------------------
-- BIR FONKSIYON SU DURUMLARDA KORUNUR (revoke EDILMEZ):
-- ---------------------------------------------------------------------------
--   1. Istemci (Flutter/web) dogrudan cagiriyor  -> app_rpcs listesi.
--      Liste kaynak koddan cikarildi; istemcideki TUM .rpc() cagrilari sabit
--      string oldugu icin liste eksiksizdir (dinamik cagri yok, dogrulandi).
--   2. RLS policy, CHECK constraint, kolon DEFAULT, index ifadesi veya trigger
--      tarafindan kullaniliyor -> pg_depend uzerinden KATALOGDAN tespit edilir.
--      Sabit liste kullanilmaz; boylece gozden kacan yardimci fonksiyonlar da
--      korunur. Bu kritik: RLS ifadeleri ve CHECK/DEFAULT ifadeleri sorguyu
--      yapan rolun yetkisiyle calisir, EXECUTE alinirsa SELECT/INSERT patlar.
--   3. Korunan bir fonksiyonun govdesinde adi geciyor -> ic ice cagrilar.
--      (SECURITY INVOKER bir RPC baska bir fonksiyonu cagiriyorsa, ic
--      fonksiyon icin de cagiranin yetkisi gerekir.)
--   4. Bir extension'a ait.
--
-- ---------------------------------------------------------------------------
-- GERI ALMA
-- ---------------------------------------------------------------------------
-- Kaldirilan her yetki private.client_execute_revocations tablosuna yazilir.
-- Bir sey kirilirsa tek tek veya toplu geri alinabilir:
--
--   -- tek fonksiyon:
--   GRANT EXECUTE ON FUNCTION public.<imza> TO authenticated;
--
--   -- tamamini geri al:
--   DO $$
--   DECLARE r record;
--   BEGIN
--     FOR r IN SELECT function_signature, revoked_from FROM private.client_execute_revocations
--     LOOP
--       EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO %s', r.function_signature, r.revoked_from);
--     END LOOP;
--   END $$;
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS private;

CREATE TABLE IF NOT EXISTS private.client_execute_revocations (
  id                 bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  function_signature text        NOT NULL,
  revoked_from       text        NOT NULL,
  revoked_at         timestamptz NOT NULL DEFAULT now(),
  migration          text        NOT NULL
);

COMMENT ON TABLE private.client_execute_revocations IS
  'Advisor 0028/0029 sertlestirmesinde istemci rollerinden alinan EXECUTE yetkilerinin kaydi. Geri alma icin kullanilir.';

DO $revoke$
DECLARE
  fn         record;
  revoked_ct integer := 0;
  kept_ct    integer := 0;
  kept_list  text;

  -- Flutter/web istemcisinin DOGRUDAN cagirdigi RPC'ler (kaynak koddan cikarildi).
  -- Yeni bir istemci RPC'si eklendiginde BURAYA da eklenmelidir.
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

  -- Yetkilendirme/RLS yardimcilari: KOSULSUZ korunur.
  -- Bunlar normalde asagidaki pg_depend taramasiyla da yakalanir (policy
  -- ifadeleri fonksiyona bagimlilik kaydi olusturur). Liste ikinci bir emniyet
  -- katmani: bir yardimci gecici olarak hicbir policy'de kullanilmiyorsa bile
  -- istemci rollerine kapatilmamalidir, cunku ilk kullanildigi anda o tablodaki
  -- TUM sorgular yetki hatasi verir. Yanlis pozitif maliyeti (bir uyari daha)
  -- yanlis negatif maliyetinin (uretimde RLS cokmesi) yaninda onemsizdir.
  always_keep text[] := ARRAY[
    'is_admin','auth_is_admin','auth_sehirici_is_admin','is_fraud_admin',
    'current_user_has_role','current_user_role_in_list','is_group_member','is_group_admin'
  ];
  added integer;
BEGIN
  -- ---------------------------------------------------------------------------
  -- Adim 1: KORUNACAK fonksiyonlar kumesi.
  -- ---------------------------------------------------------------------------
  CREATE TEMP TABLE _keep ON COMMIT DROP AS
  SELECT DISTINCT p.oid, p.proname::text
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND (
      -- 1) istemci dogrudan cagiriyor
      p.proname = ANY (app_rpcs)
      -- 2) yetkilendirme/RLS yardimcisi (kosulsuz emniyet listesi)
      OR p.proname = ANY (always_keep)
      -- 3) policy / constraint / default / index / trigger tarafindan kullaniliyor
      OR EXISTS (
        SELECT 1 FROM pg_depend d
        WHERE d.refclassid = 'pg_proc'::regclass
          AND d.refobjid   = p.oid
          AND d.classid IN (
            'pg_policy'::regclass, 'pg_constraint'::regclass,
            'pg_attrdef'::regclass, 'pg_class'::regclass, 'pg_trigger'::regclass
          )
      )
    );

  -- ---------------------------------------------------------------------------
  -- Adim 2: Korunan fonksiyonlarin govdesinde adi gecenleri de koru (ic ice
  -- cagrilar). Kelime siniri ile eslesir; supheli durumda KORUR (guvenli taraf).
  --
  -- SABIT NOKTAYA kadar tekrarlanir: zincir policy -> A -> B -> C seklinde
  -- uzayabilir. Tek gecis yapilsaydi yalnizca A ve B korunur, C acikta kalirdi
  -- ve zincir ilk calistiginda yetki hatasi verirdi.
  -- ---------------------------------------------------------------------------
  LOOP
    INSERT INTO _keep (oid, proname)
    SELECT DISTINCT p.oid, p.proname::text
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.oid NOT IN (SELECT oid FROM _keep)
      AND EXISTS (
        SELECT 1
        FROM _keep k
        JOIN pg_proc kp ON kp.oid = k.oid
        WHERE kp.oid <> p.oid
          AND kp.prosrc ~ ('\m' || p.proname || '\M')
      );

    GET DIAGNOSTICS added = ROW_COUNT;
    EXIT WHEN added = 0;
  END LOOP;

  -- ---------------------------------------------------------------------------
  -- Adim 3: Adaylar -> REVOKE + kayit.
  -- ---------------------------------------------------------------------------
  FOR fn IN
    SELECT p.oid::regprocedure AS ident, p.oid::regprocedure::text AS sig
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prokind IN ('f', 'p')
      AND p.prosecdef                                      -- yalniz SECURITY DEFINER
      AND p.oid NOT IN (SELECT oid FROM _keep)
      AND NOT EXISTS (                                     -- extension fonksiyonlari haric
        SELECT 1 FROM pg_depend d
        WHERE d.classid = 'pg_proc'::regclass
          AND d.objid   = p.oid
          AND d.deptype = 'e'
      )
      AND (
        has_function_privilege('anon',          p.oid, 'EXECUTE')
        OR has_function_privilege('authenticated', p.oid, 'EXECUTE')
      )
    ORDER BY 2
  LOOP
    EXECUTE format(
      'REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon, authenticated',
      fn.ident
    );
    -- service_role'e ACIK grant: EXECUTE varsayilani PUBLIC oldugu icin
    -- PUBLIC'ten alinca Edge Function'lar da yetkisini kaybederdi.
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', fn.ident);

    INSERT INTO private.client_execute_revocations (function_signature, revoked_from, migration)
    VALUES (fn.sig, 'authenticated', '20260804000003'),
           (fn.sig, 'anon',          '20260804000003');

    revoked_ct := revoked_ct + 1;
    RAISE NOTICE 'revoke: %', fn.sig;
  END LOOP;

  SELECT count(*), string_agg(DISTINCT proname, ', ' ORDER BY proname)
  INTO kept_ct, kept_list
  FROM _keep;

  RAISE NOTICE '---------------------------------------------------------------';
  RAISE NOTICE 'REVOKE edilen: %  |  korunan: %', revoked_ct, kept_ct;
  RAISE NOTICE 'Geri alma: private.client_execute_revocations tablosuna bakin.';
  RAISE NOTICE '---------------------------------------------------------------';
END
$revoke$;

-- =============================================================================
-- Kalan Advisor uyarilari hakkinda
-- =============================================================================
-- Bu migration sonrasi 0028/0029 altinda kalanlar, istemcinin GERCEKTEN
-- cagirdigi RPC'ler ve RLS/CHECK/DEFAULT tarafindan kullanilan yardimcilardir.
-- Bunlar Supabase mimarisinde SECURITY DEFINER olmak ZORUNDADIR; uyari
-- "niyetli mi?" sorusudur, otomatik bir hata degildir. Guvenlik bu noktadan
-- sonra EXECUTE yetkisiyle degil, fonksiyon govdesindeki yetki kontrolleriyle
-- saglanir (ornegin admin_* fonksiyonlarindaki is_admin() dogrulamasi).
--
-- auth_leaked_password_protection ayri kalir: Dashboard > Authentication
-- altindan acilmalidir, SQL ile degistirilemez.
-- =============================================================================
