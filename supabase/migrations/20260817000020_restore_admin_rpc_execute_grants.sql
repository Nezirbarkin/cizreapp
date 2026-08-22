-- =============================================================================
-- Admin paneli RPC'lerinde kaybolan EXECUTE yetkilerini geri ver
-- =============================================================================
-- TESPIT (2026-08-16, canli veritabani —
--   supabase/diagnostics/20260816_admin_panel_rpc_drift.sql ciktisi):
--
--   | ekran                | proname                     | sorun            |
--   |----------------------|-----------------------------|------------------|
--   | Şüpheli Kullanıcılar | admin_list_suspicious_users | 42501 yetki yok  |
--
--   Fonksiyon canlida MEVCUT ama `authenticated` rolu EXECUTE alamiyor.
--   Sonuc: admin panelindeki "Şüpheli Kullanıcılar" ekrani her acilista
--   42501 insufficient_privilege aliyor ve komple bos kaliyor.
--
--   Ilginc olan: ayni ailedeki admin_set_user_suspicious(uuid,boolean,text)
--   yetkisini KORUMUS. Ikisi de 20260720000006_suspicious_users.sql sonunda
--   birlikte GRANT edilmis, 20260727000002 de ikisini birlikte yeniden
--   GRANT ediyor. Yani yetki, migration zincirinin disinda (elle mudahale
--   veya uygulanmamis migration) kaybolmus.
--
-- NEDEN LISTE ILE COZULUYOR
--   Bu repoda RPC yetkileri surekli DROP/REVOKE/GRANT turbulansinda
--   (bkz. 20260727000002, 20260727000008, 20260803000006, 20260804000003
--   plani, 20260810000008). Tek bir fonksiyonu duzeltmek ayni sinifin
--   tekrarlamasini engellemiyor. Bu migration, Flutter admin panelinin
--   GERCEKTEN cagirdigi RPC listesini kaynak koddan cikarip hepsinin
--   yetkisini garantiye alir. Halihazirda yetkili olanlar icin no-op'tur,
--   yalniz eksik olani duzeltir ve NOTICE ile raporlar.
--
-- GUVENLIK NOTU
--   Buradaki her fonksiyon SECURITY DEFINER'dir ve GOVDESINDE is_admin() /
--   auth_sehirici_is_admin() kontrolu yapar. Yani EXECUTE yetkisi guvenlik
--   siniri degildir; sinir fonksiyonun icindedir. anon ve PUBLIC yine de
--   kapatilir (repo standardi, bkz. 20260727000008).
--
-- KAPSAM DISI
--   admin_cancel_courier_request_with_refund ayni teshiste "EKSIK" cikti
--   ama o bir YETKI sorunu degil: fonksiyon hic olusturulmamis. Tanimi
--   20260802000001_secure_add_to_balance_and_courier_refund.sql icinde
--   duruyor ve o migration canliya uygulanmamis. 280 satirlik, para hareketi
--   yapan bir fonksiyonu burada yeniden yazmak iki ayri gercek kaynagi
--   dogurur; dogru cozum o migration'i uygulamaktir. Asagidaki son blok
--   uygulanmadiysa NOTICE ile uyarir.
-- =============================================================================

SET search_path = public, pg_temp;

DO $grants$
DECLARE
  v_name      text;
  v_function  regprocedure;
  v_restored  integer := 0;
  v_ok        integer := 0;
  v_missing   text[] := ARRAY[]::text[];
  v_found     boolean;

  -- Flutter admin panelinin dogrudan cagirdigi RPC'ler.
  -- Kaynak: lib/features/admin/**, lib/sehirici/admin/**,
  --         lib/kullaniciozellikler/admin/**, lib/ilanlar/admin/**
  -- Yeni bir admin RPC'si eklenirse BURAYA da eklenmelidir.
  admin_rpcs text[] := ARRAY[
    -- Gruplar
    'admin_get_all_groups', 'admin_create_group', 'admin_update_group',
    'admin_delete_group', 'admin_get_group_members', 'admin_add_group_member',
    'admin_remove_group_member', 'admin_change_member_role',
    'admin_get_all_join_requests', 'admin_approve_join_request',
    'admin_reject_join_request',
    -- Dashboard & kullanicilar
    'admin_dashboard_counts', 'admin_user_list_with_stats', 'admin_list_users',
    'admin_search_users', 'admin_set_user_role', 'admin_update_user_identity',
    'admin_set_user_suspicious', 'admin_profiles_minimal',
    'admin_get_profile_email', 'admin_get_owner_profile',
    'admin_recent_active_users',
    -- Icerik moderasyonu
    'admin_delete_post', 'admin_delete_story', 'admin_delete_order',
    'admin_pin_post', 'admin_pin_product', 'admin_pin_shop', 'admin_pin_story',
    -- Bildirimler
    'admin_send_personal_notification', 'admin_broadcast_notification',
    -- Kurye / odeme
    'admin_list_couriers', 'admin_get_courier_profiles',
    'admin_approve_courier_payout', 'admin_reject_courier_payout',
    'admin_cancel_courier_request_with_refund', 'admin_cancel_with_refund',
    -- Guvenlik / raporlama
    'admin_list_suspicious_users', 'admin_list_fraud_signals',
    'admin_scan_fraud_signals', 'admin_review_fraud_signal',
    'admin_logs_data', 'admin_logs_counts',
    'get_admin_commission_report', 'get_seller_commission_summary',
    -- Sehirici admin
    'admin_upsert_sehirici_city', 'admin_delete_sehirici_city',
    'admin_upsert_sehirici_line', 'admin_delete_sehirici_line',
    'admin_upsert_sehirici_stop', 'admin_delete_sehirici_stop',
    'admin_upsert_sehirici_driver', 'admin_delete_sehirici_driver',
    'admin_clear_sehirici_route_cache',
    -- Gorev / odul
    'admin_get_task_submissions', 'admin_reward_points_overview',
    'admin_update_reward_points_config'
  ];
BEGIN
  FOREACH v_name IN ARRAY admin_rpcs
  LOOP
    v_found := false;

    -- Ayni ada sahip TUM overload'lar icin dongu: imza tahmin edilmez,
    -- katalogdan okunur (gecmiste imza degisiklikleri yetki kaybina yol acti).
    FOR v_function IN
      SELECT p.oid::regprocedure
      FROM pg_catalog.pg_proc AS p
      JOIN pg_catalog.pg_namespace AS n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public'
        AND p.proname = v_name
    LOOP
      v_found := true;

      IF has_function_privilege('authenticated', v_function::oid, 'EXECUTE') THEN
        v_ok := v_ok + 1;
      ELSE
        v_restored := v_restored + 1;
        RAISE NOTICE 'YETKI GERI VERILDI: %', v_function::text;
      END IF;

      -- Repo standardi: PUBLIC/anon kapali, authenticated acik.
      -- Zaten yetkili olanlar icin GRANT no-op'tur.
      EXECUTE format(
        'REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon', v_function
      );
      EXECUTE format(
        'GRANT EXECUTE ON FUNCTION %s TO authenticated', v_function
      );
    END LOOP;

    IF NOT v_found THEN
      v_missing := v_missing || v_name;
    END IF;
  END LOOP;

  RAISE NOTICE '---------------------------------------------------------------';
  RAISE NOTICE 'Zaten yetkili: %  |  geri verilen: %', v_ok, v_restored;

  IF array_length(v_missing, 1) IS NOT NULL THEN
    RAISE NOTICE 'Veritabaninda BULUNAMAYAN admin RPC''leri (%): %',
      array_length(v_missing, 1), array_to_string(v_missing, ', ');
    RAISE NOTICE 'Bunlar 42883 undefined_function uretir; ilgili admin ekrani calismaz.';
  END IF;
  RAISE NOTICE '---------------------------------------------------------------';
END
$grants$;

-- -----------------------------------------------------------------------------
-- Uygulanmamis migration uyarisi
-- -----------------------------------------------------------------------------
-- 20260802000001 iki is yapiyordu:
--   A) add_to_balance'i authenticated'a kapatmak (KRITIK: acikken herhangi bir
--      oturumlu kullanici istedigi user_id'ye sinirsiz bakiye ekleyebilir),
--   B) admin_cancel_courier_request_with_refund fonksiyonunu olusturmak.
-- (B) canlida yok, yani o migration uygulanmamis. (A)'yi 20260810000008 de
-- yapiyor; ikisinden en az biri uygulanmis olmali. Asagidaki blok ikisini de
-- kontrol eder.
DO $verify$
DECLARE
  v_function regprocedure;
  v_leak     boolean := false;
BEGIN
  IF to_regprocedure('public.admin_cancel_courier_request_with_refund(uuid)')
     IS NULL THEN
    RAISE WARNING
      'EKSIK: admin_cancel_courier_request_with_refund yok. '
      'Kurye Yonetimi > Paketler > "Iptal Et" butonu 42883 verir. '
      'Cozum: 20260802000001_secure_add_to_balance_and_courier_refund.sql '
      'uygulanmali (supabase db push --include-all).';
  END IF;

  FOR v_function IN
    SELECT p.oid::regprocedure
    FROM pg_catalog.pg_proc AS p
    JOIN pg_catalog.pg_namespace AS n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'add_to_balance'
      AND p.prosecdef
  LOOP
    IF has_function_privilege('authenticated', v_function::oid, 'EXECUTE')
       OR has_function_privilege('anon', v_function::oid, 'EXECUTE') THEN
      v_leak := true;
      RAISE WARNING
        'KRITIK GUVENLIK: % istemci rolunden cagrilabiliyor. '
        'SECURITY DEFINER olup p_user_id/p_amount''i istemciden aldigi icin '
        'herhangi bir oturumlu kullanici istedigi hesaba sinirsiz bakiye '
        'ekleyebilir.', v_function::text;
    END IF;
  END LOOP;

  IF NOT v_leak THEN
    RAISE NOTICE 'add_to_balance yetkileri kapali — sorun yok.';
  END IF;
END
$verify$;

NOTIFY pgrst, 'reload schema';
