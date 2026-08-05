-- ============================================================================
-- ADIM 1 - CANLI DURUM TESPITI (salt-okunur, hicbir sey degistirmez)
-- Tarih: 2026-08-05
-- Proje: xsbukxkgtmdyickknqzf (CizreApp)
-- ----------------------------------------------------------------------------
-- Amac: 20260802* migration'larinin canliya uygulanip uygulanmadigini ve
--       Flutter'in cagirdigi 66 RPC'nin canli DB'de gercekten var olup
--       olmadigini kesinlestirmek.
--
-- KULLANIM: Supabase Dashboard > SQL Editor'de A/B/C/D/E bloklarini
--           sirayla calistir, her blogun ciktisini kopyala.
-- GUVENLIK: Sadece SELECT. Hicbir DDL/DML yok.
-- ============================================================================


-- ============================================================================
-- BLOK A - MIGRATION DURUMU
-- ============================================================================
SELECT * FROM (
  SELECT 1 AS sira,
    'Uygulanmis 2026-08-01..03 migration surumleri' AS kontrol,
    COALESCE((
      SELECT string_agg(version, ', ' ORDER BY version)
      FROM supabase_migrations.schema_migrations
      WHERE version >= '20260801' AND version < '20260804'
    ), '(hicbiri uygulanmamis)') AS sonuc,
    'Bos ise 20260802* hic push edilmemis demektir' AS yorum

  UNION ALL SELECT 2,
    '20260802000008_revoke_legacy_writes',
    CASE WHEN EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations WHERE version = '20260802000008')
         THEN 'UYGULANDI' ELSE 'uygulanmadi' END,
    'UYGULANDI ise siparis/kupon/flash sale su an KIRIK'

  UNION ALL SELECT 3,
    '20260802000013_coupon_limit_enforcement_strict',
    CASE WHEN EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations WHERE version = '20260802000013')
         THEN 'UYGULANDI' ELSE 'uygulanmadi' END,
    'UYGULANDI ise public.use_coupon/validate_coupon silinmis'

  UNION ALL SELECT 4,
    'En son uygulanan migration',
    COALESCE((SELECT max(version) FROM supabase_migrations.schema_migrations), '(kayit yok)'),
    'Repodaki en son: 20260803000006'

  UNION ALL SELECT 5,
    'Toplam uygulanmis migration sayisi',
    (SELECT count(*)::text FROM supabase_migrations.schema_migrations),
    'Repoda 333 dosya vardi (23 cift prefix grubu / 56 dosya, 22 legacy adli)'
) t ORDER BY sira;


-- ============================================================================
-- BLOK B - ESKI (CANLI KULLANILAN) YUZEYLER HALA AYAKTA MI?
-- Flutter su an bunlara bagimli. "YOK" cikan her satir = kirik ozellik.
-- ============================================================================
SELECT * FROM (
  SELECT 1 AS sira, 'public.use_coupon' AS nesne,
    CASE WHEN EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                      WHERE n.nspname='public' AND p.proname='use_coupon')
         THEN 'VAR' ELSE 'YOK -> KIRIK' END AS durum,
    'market/checkout:744,1030 + shop/checkout:408' AS cagiran

  UNION ALL SELECT 2, 'public.validate_coupon',
    CASE WHEN EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                      WHERE n.nspname='public' AND p.proname='validate_coupon')
         THEN 'VAR' ELSE 'YOK -> KIRIK' END,
    'shop/cart_screen:209 + cart_provider:168'

  UNION ALL SELECT 3, 'public.claim_flash_sale',
    CASE WHEN EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                      WHERE n.nspname='public' AND p.proname='claim_flash_sale')
         THEN 'VAR' ELSE 'YOK -> KIRIK' END,
    'market/services/flash_sale_service:76'

  UNION ALL SELECT 4, 'public.release_flash_sale',
    CASE WHEN EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                      WHERE n.nspname='public' AND p.proname='release_flash_sale')
         THEN 'VAR' ELSE 'YOK -> KIRIK' END,
    'market/services/flash_sale_service:94'

  UNION ALL SELECT 5, 'authenticated -> INSERT public.orders',
    CASE WHEN to_regclass('public.orders') IS NULL THEN '(tablo yok)'
         WHEN has_table_privilege('authenticated','public.orders','INSERT')
         THEN 'VAR' ELSE 'YOK -> SIPARIS OLUSTURULAMAZ' END,
    'shop/services/order_service:88,725'

  UNION ALL SELECT 6, 'authenticated -> INSERT public.order_items',
    CASE WHEN to_regclass('public.order_items') IS NULL THEN '(tablo yok)'
         WHEN has_table_privilege('authenticated','public.order_items','INSERT')
         THEN 'VAR' ELSE 'YOK -> SIPARIS KALEMI EKLENEMEZ' END,
    'shop/services/order_service:149,780'

  UNION ALL SELECT 7, 'authenticated -> INSERT public.coupon_usages',
    CASE WHEN to_regclass('public.coupon_usages') IS NULL THEN '(tablo yok)'
         WHEN has_table_privilege('authenticated','public.coupon_usages','INSERT')
         THEN 'VAR' ELSE 'YOK' END,
    'kupon kullanim kaydi'

  UNION ALL SELECT 8, 'authenticated -> UPDATE public.payment_transactions',
    CASE WHEN to_regclass('public.payment_transactions') IS NULL THEN '(tablo yok)'
         WHEN has_table_privilege('authenticated','public.payment_transactions','UPDATE')
         THEN 'VAR' ELSE 'YOK -> KIRIK' END,
    'core/services/payment_service:148'

  UNION ALL SELECT 9, 'authenticated -> UPDATE public.user_balances',
    CASE WHEN to_regclass('public.user_balances') IS NULL THEN '(tablo yok)'
         WHEN has_table_privilege('authenticated','public.user_balances','UPDATE')
         THEN 'VAR' ELSE 'YOK' END,
    'bakiye guncelleme'
) t ORDER BY sira;


-- ============================================================================
-- BLOK C - YENI (private) KATMAN DURUMU
-- ============================================================================
SELECT * FROM (
  SELECT 1 AS sira, 'private semasi mevcut mu?' AS kontrol,
    CASE WHEN to_regnamespace('private') IS NOT NULL THEN 'VAR' ELSE 'YOK' END AS sonuc,
    'Yoksa 20260802000005 hic uygulanmamis' AS yorum

  UNION ALL SELECT 2, 'authenticated -> USAGE ON SCHEMA private',
    CASE WHEN to_regnamespace('private') IS NULL THEN '(sema yok)'
         WHEN has_schema_privilege('authenticated','private','USAGE') THEN 'VAR'
         ELSE 'YOK -> RPC EXECUTE grant''i ise yaramaz' END,
    'Migration bunu bilerek REVOKE ediyor'

  UNION ALL SELECT 3, 'private semasindaki fonksiyonlar',
    COALESCE((SELECT string_agg(p.proname, ', ' ORDER BY p.proname)
              FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
              WHERE n.nspname='private'), '(yok)'),
    'prepare_checkout_session, commit_cod_order, commit_balance_order beklenir'

  UNION ALL SELECT 4, 'PostgREST expose edilen semalar',
    COALESCE((SELECT array_to_string(s.setconfig, ' | ')
              FROM pg_db_role_setting s JOIN pg_roles r ON r.oid = s.setrole
              WHERE r.rolname = 'authenticator'), '(ayar yok = varsayilan public)'),
    'private burada YOKSA .rpc() ile cagrilamaz (PGRST202)'
) t ORDER BY sira;


-- ============================================================================
-- BLOK D - FLUTTER'IN CAGIRDIGI 66 RPC CANLI DB'DE VAR MI?
-- "EKSIK" cikan her satir = uygulamada kirik ozellik.
-- ============================================================================
WITH dart_rpc(ad) AS (
  VALUES
    ('add_notification'),
    ('admin_add_group_member'),
    ('admin_approve_join_request'),
    ('admin_change_member_role'),
    ('admin_create_group'),
    ('admin_delete_group'),
    ('admin_delete_sehirici_city'),
    ('admin_delete_sehirici_stop'),
    ('admin_get_all_groups'),
    ('admin_get_group_members'),
    ('admin_list_suspicious_users'),
    ('admin_reject_join_request'),
    ('admin_remove_group_member'),
    ('admin_reward_points_overview'),
    ('admin_scan_fraud_signals'),
    ('admin_set_user_suspicious'),
    ('admin_update_group'),
    ('admin_upsert_sehirici_city'),
    ('admin_upsert_sehirici_line'),
    ('admin_upsert_sehirici_stop'),
    ('apply_campaign_rewards_for_order'),
    ('approve_group_join_request'),
    ('can_review_order'),
    ('cancel_order'),
    ('claim_flash_sale'),
    ('commit_balance_order'),
    ('commit_cod_order'),
    ('compute_sehirici_next_stop'),
    ('dismiss_review_reminder'),
    ('end_live_session'),
    ('ensure_my_profile'),
    ('get_admin_commission_report'),
    ('get_group_messages_with_read_count'),
    ('get_message_read_count'),
    ('get_message_read_receipts'),
    ('get_pending_reviews'),
    ('get_sehirici_active_trips'),
    ('get_sehirici_lines_with_stops'),
    ('get_sehirici_trip_path'),
    ('get_sehirici_trips_for_stop'),
    ('get_seller_commission_summary'),
    ('get_shop_today_views'),
    ('get_shop_total_views'),
    ('get_task_stats'),
    ('get_top_customers'),
    ('get_top_viewed_products'),
    ('get_user_groups'),
    ('increment_story_likes'),
    ('join_open_group'),
    ('mark_group_messages_as_read'),
    ('mark_group_messages_read_receipts'),
    ('mark_messages_as_read'),
    ('prepare_checkout_session'),
    ('reject_group_join_request'),
    ('release_flash_sale'),
    ('search_groups'),
    ('set_my_presence'),
    ('set_sehirici_trip_status'),
    ('start_live_session'),
    ('start_sehirici_trip'),
    ('update_sehirici_trip_location'),
    ('upsert_follow_request'),
    ('use_coupon'),
    ('validate_coupon'),
    ('verify_code'),
    ('verify_registration_otp')
)
SELECT
  d.ad AS rpc_adi,
  CASE WHEN p.proname IS NULL THEN 'EKSIK' ELSE 'var' END AS durum,
  COALESCE(n.nspname, '-') AS sema,
  -- Etkin cagrilabilirlik: PostgREST sadece public'i expose eder VE
  -- fonksiyon EXECUTE + sema USAGE'in ikisi birden gerekir.
  CASE
    WHEN p.proname IS NULL THEN 'RPC YOK'
    WHEN n.nspname <> 'public' THEN 'HAYIR - ' || n.nspname || ' semasi PostgREST''e acik degil'
    WHEN NOT has_schema_privilege('authenticated', n.nspname, 'USAGE') THEN 'HAYIR - sema USAGE yok'
    WHEN NOT has_function_privilege('authenticated', p.oid, 'EXECUTE') THEN 'HAYIR - EXECUTE yok'
    ELSE 'evet'
  END AS flutter_cagirabilir_mi
FROM dart_rpc d
LEFT JOIN LATERAL (
  SELECT pp.oid, pp.proname, pp.pronamespace
  FROM pg_proc pp JOIN pg_namespace nn ON nn.oid = pp.pronamespace
  WHERE pp.proname = d.ad AND nn.nspname IN ('public','private')
  ORDER BY CASE WHEN nn.nspname = 'public' THEN 0 ELSE 1 END
  LIMIT 1
) p ON TRUE
LEFT JOIN pg_namespace n ON n.oid = p.pronamespace
ORDER BY (p.proname IS NOT NULL), d.ad;


-- ============================================================================
-- BLOK E - OZET SAYIM (tek satir, hizli bakis)
-- ============================================================================
WITH dart_rpc(ad) AS (
  VALUES
    ('add_notification'),
    ('admin_add_group_member'),
    ('admin_approve_join_request'),
    ('admin_change_member_role'),
    ('admin_create_group'),
    ('admin_delete_group'),
    ('admin_delete_sehirici_city'),
    ('admin_delete_sehirici_stop'),
    ('admin_get_all_groups'),
    ('admin_get_group_members'),
    ('admin_list_suspicious_users'),
    ('admin_reject_join_request'),
    ('admin_remove_group_member'),
    ('admin_reward_points_overview'),
    ('admin_scan_fraud_signals'),
    ('admin_set_user_suspicious'),
    ('admin_update_group'),
    ('admin_upsert_sehirici_city'),
    ('admin_upsert_sehirici_line'),
    ('admin_upsert_sehirici_stop'),
    ('apply_campaign_rewards_for_order'),
    ('approve_group_join_request'),
    ('can_review_order'),
    ('cancel_order'),
    ('claim_flash_sale'),
    ('commit_balance_order'),
    ('commit_cod_order'),
    ('compute_sehirici_next_stop'),
    ('dismiss_review_reminder'),
    ('end_live_session'),
    ('ensure_my_profile'),
    ('get_admin_commission_report'),
    ('get_group_messages_with_read_count'),
    ('get_message_read_count'),
    ('get_message_read_receipts'),
    ('get_pending_reviews'),
    ('get_sehirici_active_trips'),
    ('get_sehirici_lines_with_stops'),
    ('get_sehirici_trip_path'),
    ('get_sehirici_trips_for_stop'),
    ('get_seller_commission_summary'),
    ('get_shop_today_views'),
    ('get_shop_total_views'),
    ('get_task_stats'),
    ('get_top_customers'),
    ('get_top_viewed_products'),
    ('get_user_groups'),
    ('increment_story_likes'),
    ('join_open_group'),
    ('mark_group_messages_as_read'),
    ('mark_group_messages_read_receipts'),
    ('mark_messages_as_read'),
    ('prepare_checkout_session'),
    ('reject_group_join_request'),
    ('release_flash_sale'),
    ('search_groups'),
    ('set_my_presence'),
    ('set_sehirici_trip_status'),
    ('start_live_session'),
    ('start_sehirici_trip'),
    ('update_sehirici_trip_location'),
    ('upsert_follow_request'),
    ('use_coupon'),
    ('validate_coupon'),
    ('verify_code'),
    ('verify_registration_otp')
)
SELECT
  count(*) AS toplam_rpc,
  count(*) FILTER (WHERE p.proname IS NOT NULL) AS canlida_var,
  count(*) FILTER (WHERE p.proname IS NULL) AS eksik,
  count(*) FILTER (
    WHERE p.proname IS NOT NULL
      AND NOT (
        p.nspname = 'public'
        AND has_schema_privilege('authenticated', p.nspname, 'USAGE')
        AND has_function_privilege('authenticated', p.oid, 'EXECUTE')
      )
  ) AS var_ama_cagrilamaz
FROM dart_rpc d
LEFT JOIN LATERAL (
  SELECT pp.oid, pp.proname, nn.nspname
  FROM pg_proc pp JOIN pg_namespace nn ON nn.oid = pp.pronamespace
  WHERE pp.proname = d.ad AND nn.nspname IN ('public','private')
  ORDER BY CASE WHEN nn.nspname = 'public' THEN 0 ELSE 1 END
  LIMIT 1
) p ON TRUE;
