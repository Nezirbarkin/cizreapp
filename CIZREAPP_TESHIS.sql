-- =============================================================================
-- CIZREAPP — SUPABASE TESHIS SCRIPTI  (SALT OKUNUR, hicbir sey degistirmez)
-- =============================================================================
-- Nasil calistirilir:
--   Supabase Dashboard > SQL Editor > yeni sorgu > bu dosyanin TAMAMINI yapistir
--   > Run. Cikan tabloyu bana gonderin.
--
-- Ne yapar: Flutter kaynak kodundan cikarilan
--   66 RPC, 110 tablo/view ve 8 storage bucket'ini
-- canli veritabaniyla karsilastirir ve uygulamanin neden calismadigini gosterir.
--
-- Sonuc sutunlari:
--   onem   : 1 = KRITIK (uygulama kirilir), 2 = UYARI, 3 = bilgi
--   kategori / nesne / sorun
-- =============================================================================

WITH
app_rpcs(name) AS (VALUES
  ('add_notification'), ('admin_add_group_member'), ('admin_approve_join_request'),
  ('admin_change_member_role'), ('admin_create_group'), ('admin_delete_group'),
  ('admin_delete_sehirici_city'), ('admin_delete_sehirici_stop'), ('admin_get_all_groups'),
  ('admin_get_group_members'), ('admin_list_suspicious_users'), ('admin_reject_join_request'),
  ('admin_remove_group_member'), ('admin_reward_points_overview'), ('admin_scan_fraud_signals'),
  ('admin_set_user_suspicious'), ('admin_update_group'), ('admin_upsert_sehirici_city'),
  ('admin_upsert_sehirici_line'), ('admin_upsert_sehirici_stop'),
  ('apply_campaign_rewards_for_order'), ('approve_group_join_request'), ('can_review_order'),
  ('cancel_order'), ('claim_flash_sale'), ('commit_balance_order'), ('commit_cod_order'),
  ('compute_sehirici_next_stop'), ('dismiss_review_reminder'), ('end_live_session'),
  ('ensure_my_profile'), ('get_admin_commission_report'),
  ('get_group_messages_with_read_count'), ('get_message_read_count'),
  ('get_message_read_receipts'), ('get_pending_reviews'), ('get_sehirici_active_trips'),
  ('get_sehirici_lines_with_stops'), ('get_sehirici_trip_path'),
  ('get_sehirici_trips_for_stop'), ('get_seller_commission_summary'), ('get_shop_today_views'),
  ('get_shop_total_views'), ('get_task_stats'), ('get_top_customers'),
  ('get_top_viewed_products'), ('get_user_groups'), ('increment_story_likes'),
  ('join_open_group'), ('mark_group_messages_as_read'), ('mark_group_messages_read_receipts'),
  ('mark_messages_as_read'), ('prepare_checkout_session'), ('reject_group_join_request'),
  ('release_flash_sale'), ('search_groups'), ('set_my_presence'), ('set_sehirici_trip_status'),
  ('start_live_session'), ('start_sehirici_trip'), ('update_sehirici_trip_location'),
  ('upsert_follow_request'), ('use_coupon'), ('validate_coupon'), ('verify_code'),
  ('verify_registration_otp')
),
app_tables(name) AS (VALUES
  ('addresses'), ('admin_broadcasts'), ('admin_user_spending_summary'),
  ('admin_users_with_balance'), ('api_keys'), ('api_settings'), ('app_about_settings'),
  ('app_settings'), ('avatars'), ('balance_transactions'), ('bank_accounts'), ('blocked_users'),
  ('cancellation_requests'), ('cart'), ('cart_items'), ('categories'), ('comment_mentions'),
  ('conversations'), ('coupon_usages'), ('courier_assignments'), ('courier_earnings'),
  ('courier_payment_info'), ('courier_payout_requests'), ('courier_requests'),
  ('courier_service_notices'), ('courier_service_settings'), ('courier_settings'),
  ('courier_status_changes'), ('covers'), ('daily_deals'), ('deals'), ('digital_orders'),
  ('faqs'), ('flash_sales'), ('follow_requests'), ('follows'), ('group_join_requests'),
  ('group_members'), ('group_message_read_receipts'), ('group_messages'), ('groups'),
  ('institutions'), ('live_messages'), ('live_pinned_products'), ('live_sessions'),
  ('messages'), ('my_ad_reward_sessions'), ('my_point_ledger_entries'), ('news'),
  ('news_categories'), ('news_comment_likes'), ('news_comments'), ('news_images'),
  ('news_likes'), ('news_views'), ('notification_preferences'), ('notifications'),
  ('order_items'), ('orders'), ('payment_transactions'), ('payout_requests'), ('post_comments'),
  ('post_favorites'), ('post_likes'), ('post_reports'), ('post_views'), ('posts'),
  ('price_alerts'), ('product_favorites'), ('product_review_helpful'), ('product_reviews'),
  ('product_views'), ('products'), ('profile_views'), ('profiles'), ('public'),
  ('public_profiles_safe'), ('push_notifications'), ('return_requests'),
  ('reward_points_public_config'), ('sehirici_cities'), ('sehirici_drivers'),
  ('sehirici_favorite_stops'), ('sehirici_line_stops'), ('sehirici_lines'), ('sehirici_routes'),
  ('sehirici_stops'), ('sehirici_trips'), ('seller_withdrawals'), ('shop_coupons'),
  ('shop_reviews'), ('shop_views'), ('shops'), ('smm_providers'), ('stories'), ('story_likes'),
  ('story_views'), ('support_ticket_messages'), ('support_tickets'), ('system_settings'),
  ('task_categories'), ('task_images'), ('task_screenshots'), ('tasks'),
  ('transfer_confirmations'), ('user_point_accounts'), ('user_reports'),
  ('user_unlocked_achievements'), ('v_admin_commission_dashboard'), ('v_debt_orders')
),
app_buckets(name) AS (VALUES
  ('avatars'), ('covers'), ('news-images'), ('public'), ('shop-images'), ('stories'),
  ('task_images'), ('task_screenshots')
),

-- ---------------------------------------------------------------------------
-- 1) Uygulamanin cagirdigi ama VERITABANINDA OLMAYAN RPC'ler
--    Bu en olasi kirilma sebebi: PostgREST 404 / "function does not exist"
-- ---------------------------------------------------------------------------
eksik_rpc AS (
  SELECT 1 AS onem, 'EKSIK RPC' AS kategori, r.name AS nesne,
         'Uygulama bu RPC yi cagiriyor ama veritabaninda YOK. Ilgili migration uygulanmamis.' AS sorun
  FROM app_rpcs r
  WHERE NOT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = r.name
  )
),

-- ---------------------------------------------------------------------------
-- 2) Var olan ama istemcinin CAGIRAMADIGI RPC'ler (EXECUTE yetkisi yok)
-- ---------------------------------------------------------------------------
yetkisiz_rpc AS (
  SELECT 2 AS onem, 'RPC YETKI YOK' AS kategori,
         p.oid::regprocedure::text AS nesne,
         'Fonksiyon var ama authenticated EXECUTE yetkisi yok -> 403 permission denied' AS sorun
  FROM app_rpcs r
  JOIN pg_proc p ON p.proname = r.name
  JOIN pg_namespace n ON n.oid = p.pronamespace AND n.nspname = 'public'
  WHERE NOT has_function_privilege('authenticated', p.oid, 'EXECUTE')
),

-- ---------------------------------------------------------------------------
-- 3) Uygulamanin sorguladigi ama OLMAYAN tablo/view'lar
-- ---------------------------------------------------------------------------
eksik_tablo AS (
  SELECT 1 AS onem, 'EKSIK TABLO/VIEW' AS kategori, t.name AS nesne,
         'Uygulama bu tabloyu sorguluyor ama veritabaninda YOK.' AS sorun
  FROM app_tables t
  WHERE to_regclass('public.' || quote_ident(t.name)) IS NULL
),

-- ---------------------------------------------------------------------------
-- 4) Tablo var ama istemcinin SELECT yetkisi yok (GRANT eksik)
-- ---------------------------------------------------------------------------
yetkisiz_tablo AS (
  SELECT 2 AS onem, 'TABLO YETKI YOK' AS kategori, t.name AS nesne,
         'authenticated icin SELECT GRANT yok -> 403 permission denied' AS sorun
  FROM app_tables t
  WHERE to_regclass('public.' || quote_ident(t.name)) IS NOT NULL
    AND NOT has_table_privilege('authenticated', to_regclass('public.' || quote_ident(t.name)), 'SELECT')
),

-- ---------------------------------------------------------------------------
-- 5) RLS acik ama HIC SELECT POLICY'si yok
--    En sinsi hata: 403 vermez, sessizce BOS LISTE doner. Uygulama "veri yok"
--    gibi gorunur, hata da alamazsiniz.
-- ---------------------------------------------------------------------------
rls_bos AS (
  SELECT 1 AS onem, 'RLS VAR POLICY YOK' AS kategori, t.name AS nesne,
         'RLS acik ama SELECT policy yok -> sorgu hata vermez, HER ZAMAN BOS doner' AS sorun
  FROM app_tables t
  JOIN pg_class c ON c.oid = to_regclass('public.' || quote_ident(t.name))
  WHERE c.relkind = 'r'
    AND c.relrowsecurity
    AND NOT EXISTS (
      SELECT 1 FROM pg_policy p
      WHERE p.polrelid = c.oid AND p.polcmd IN ('r', '*') AND p.polpermissive
    )
),

-- ---------------------------------------------------------------------------
-- 6) Eksik storage bucket'lari
-- ---------------------------------------------------------------------------
eksik_bucket AS (
  SELECT 1 AS onem, 'EKSIK BUCKET' AS kategori, b.name AS nesne,
         'Uygulama bu bucket i kullaniyor ama storage.buckets icinde YOK.' AS sorun
  FROM app_buckets b
  WHERE NOT EXISTS (SELECT 1 FROM storage.buckets sb WHERE sb.id = b.name)
),

-- ---------------------------------------------------------------------------
-- 7) Bozuk search_path: cube/earthdistance tasinmis ama fonksiyon semasiz cagiriyor
-- ---------------------------------------------------------------------------
bozuk_earth AS (
  SELECT 1 AS onem, 'BOZUK search_path' AS kategori,
         p.oid::regprocedure::text AS nesne,
         'earth_distance/ll_to_earth semasiz cagriliyor ama search_path te extensions yok -> calisma aninda hata' AS sorun
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.prosrc ~* '\m(ll_to_earth|earth_distance|earth_box)\s*\('
    AND NOT EXISTS (
      SELECT 1 FROM pg_depend d
      WHERE d.classid = 'pg_proc'::regclass AND d.objid = p.oid AND d.deptype = 'e'
    )
    AND EXISTS (  -- extension public disinda
      SELECT 1 FROM pg_extension e JOIN pg_namespace en ON en.oid = e.extnamespace
      WHERE e.extname = 'earthdistance' AND en.nspname <> 'public'
    )
    AND NOT EXISTS (
      SELECT 1 FROM unnest(coalesce(p.proconfig, ARRAY[]::text[])) cfg
      WHERE cfg LIKE 'search\_path=%' AND cfg ~ '(^|=|,\s*)extensions(\s*,|$)'
    )
),

-- ---------------------------------------------------------------------------
-- 8) Hangi migration'larim uygulanmis? (parmak izi)
-- ---------------------------------------------------------------------------
migration_durumu AS (
  SELECT 3 AS onem, 'MIGRATION DURUMU' AS kategori, m.nesne, m.sorun
  FROM (
    VALUES
      ('20260804000001 performans',
       CASE WHEN EXISTS (SELECT 1 FROM pg_policy WHERE polname LIKE '%\_merged' OR polname LIKE '%\_merged\_%')
            THEN 'UYGULANMIS' ELSE 'uygulanmamis' END),
      ('20260804000002 guvenlik',
       CASE WHEN EXISTS (SELECT 1 FROM pg_extension e JOIN pg_namespace n ON n.oid=e.extnamespace
                         WHERE e.extname='earthdistance' AND n.nspname='extensions')
            THEN 'UYGULANMIS' ELSE 'uygulanmamis' END),
      ('20260804000003 EXECUTE sertlestirme',
       CASE WHEN to_regclass('private.client_execute_revocations') IS NOT NULL
            THEN 'UYGULANMIS' ELSE 'uygulanmamis' END)
  ) AS m(nesne, sorun)
),

-- ---------------------------------------------------------------------------
-- 9) Genel ozet
-- ---------------------------------------------------------------------------
ozet AS (
  SELECT 3 AS onem, 'OZET' AS kategori, x.nesne, x.sorun
  FROM (
    VALUES
      ('public tablo sayisi',   (SELECT count(*)::text FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind='r')),
      ('public fonksiyon sayisi',(SELECT count(*)::text FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public')),
      ('policy sayisi',          (SELECT count(*)::text FROM pg_policy p JOIN pg_class c ON c.oid=p.polrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public')),
      ('storage bucket sayisi',  (SELECT count(*)::text FROM storage.buckets)),
      -- Bu tablo dogrudan yazilamaz: yoksa PostgreSQL sorguyu PLAN asamasinda
      -- reddeder ve tum teshis patlar. query_to_xml sorguyu metin olarak alir,
      -- CASE de tablo yokken hic calistirmaz.
      ('uygulanmis migration',
       CASE WHEN to_regclass('supabase_migrations.schema_migrations') IS NOT NULL
            THEN (xpath('/row/c/text()',
                        query_to_xml('SELECT count(*) AS c FROM supabase_migrations.schema_migrations',
                                     false, true, '')))[1]::text
            ELSE 'tablo yok (Supabase CLI hic kullanilmamis olabilir)' END)
  ) AS x(nesne, sorun)
)

SELECT onem, kategori, nesne, sorun FROM eksik_rpc
UNION ALL SELECT * FROM yetkisiz_rpc
UNION ALL SELECT * FROM eksik_tablo
UNION ALL SELECT * FROM yetkisiz_tablo
UNION ALL SELECT * FROM rls_bos
UNION ALL SELECT * FROM eksik_bucket
UNION ALL SELECT * FROM bozuk_earth
UNION ALL SELECT * FROM migration_durumu
UNION ALL SELECT * FROM ozet
ORDER BY onem, kategori, nesne;
