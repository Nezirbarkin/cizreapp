-- =============================================================================
-- Admin paneli RPC/sema surukleme (drift) kontrolu — 2026-08-16
-- =============================================================================
-- AMAC
--   Admin panelinin (lib/features/admin/**) cagirdigi her RPC'nin
--   (a) veritabaninda VAR oldugunu,
--   (b) `authenticated` rolunun EXECUTE yetkisi bulundugunu
--   dogrular. Ikisinden biri eksikse ilgili admin ekrani calisma zamaninda
--   42883 (undefined_function) veya 42501 (insufficient_privilege) alir ve
--   -eger varsa- RLS'e takilacak "fallback" dallarina duser ve kullaniciya
--   "Hata: ..." gorunur ya da liste sessizce bos kalir.
--
-- NEDEN GEREKLI
--   Asagidaki 7 grup fonksiyonu CANLI veritabaninda mevcut
--   (supabase/.temp/live_types.ts ile dogrulandi) ama supabase/migrations/
--   altinda TANIMLARI YOK — elle olusturulmuslar:
--     admin_get_all_groups, admin_create_group, admin_update_group,
--     admin_delete_group, admin_get_group_members, admin_remove_group_member,
--     admin_change_member_role
--   Sonuc: `supabase db reset` ile kurulan her ortamda (yerel, CI, staging)
--   admin panelindeki "Gruplar" sekmesi komple calismaz. Prod'da calisiyor
--   olmasi bu riski gizliyor.
--
--   Karsilastirma icin: ayni ailedeki admin_approve_join_request /
--   admin_reject_join_request / admin_get_all_join_requests
--   20260727000004_fix_plpgsql_lint_errors.sql icinde DUZGUN tanimli.
--
-- KULLANIM
--   psql "$DATABASE_URL" -f supabase/diagnostics/20260816_admin_panel_rpc_drift.sql
--   (veya Supabase Studio > SQL Editor'e yapistir)
--
-- BEKLENEN CIKTI
--   0 satir. Donen her satir, o ekranin bozuk oldugu anlamina gelir.
-- =============================================================================

WITH client_rpcs(proname, ekran) AS (
  VALUES
    -- Gruplar sekmesi (groups_management_content.dart)
    ('admin_get_all_groups',        'Gruplar > liste'),
    ('admin_create_group',          'Gruplar > yeni grup'),
    ('admin_update_group',          'Gruplar > düzenle'),
    ('admin_delete_group',          'Gruplar > sil'),
    ('admin_get_group_members',     'Gruplar > üyeler'),
    ('admin_remove_group_member',   'Gruplar > üye çıkar'),
    ('admin_change_member_role',    'Gruplar > rol değiştir'),
    ('admin_get_all_join_requests', 'Gruplar > istekler'),
    ('admin_approve_join_request',  'Gruplar > isteği onayla'),
    ('admin_reject_join_request',   'Gruplar > isteği reddet'),
    ('admin_profiles_minimal',      'Gruplar/Dükkanlar > profil bilgisi'),
    -- Dashboard & kullanicilar
    ('admin_dashboard_counts',      'Dashboard > sayaçlar'),
    ('admin_user_list_with_stats',  'Kullanıcılar > liste (istatistikli)'),
    ('admin_list_users',            'Kullanıcılar > liste (yedek)'),
    ('admin_search_users',          'Kullanıcılar > arama'),
    ('admin_set_user_role',         'Kullanıcılar > rol değiştir'),
    ('admin_update_user_identity',  'Kullanıcılar > düzenle'),
    ('admin_set_user_suspicious',   'Kullanıcılar > şüpheli işaretle'),
    ('admin_get_profile_email',     'Kullanıcılar/Dükkanlar > e-posta'),
    ('admin_get_owner_profile',     'Dükkanlar > sahip bilgisi'),
    -- Icerik moderasyonu
    ('admin_delete_post',           'Gönderiler > sil'),
    ('admin_delete_story',          'Gönderiler > hikaye sil'),
    -- Bildirimler
    ('admin_send_personal_notification', 'Bildirimler > kişisel'),
    ('admin_broadcast_notification',     'Bildirimler > toplu'),
    -- Kurye / odeme
    ('admin_list_couriers',              'Kurye Yönetimi > liste'),
    ('admin_get_courier_profiles',       'Kurye Yönetimi > profiller'),
    ('admin_approve_courier_payout',     'Kurye Yönetimi > ödeme onayla'),
    ('admin_reject_courier_payout',      'Kurye Yönetimi > ödeme reddet'),
    ('admin_cancel_courier_request_with_refund',
                                         'Kurye Yönetimi > paket iptal+iade'),
    -- Guvenlik / raporlama
    ('admin_list_suspicious_users', 'Şüpheli Kullanıcılar'),
    ('admin_list_fraud_signals',    'Dolandırıcılık Sinyalleri > liste'),
    ('admin_scan_fraud_signals',    'Dolandırıcılık Sinyalleri > tara'),
    ('admin_review_fraud_signal',   'Dolandırıcılık Sinyalleri > incele'),
    ('admin_logs_data',             'Loglar'),
    ('get_admin_commission_report', 'Raporlar > komisyon'),
    ('get_seller_commission_summary', 'Raporlar > satıcı komisyonu')
),
resolved AS (
  SELECT
    c.proname,
    c.ekran,
    p.oid,
    p.oid::regprocedure::text AS imza
  FROM client_rpcs AS c
  LEFT JOIN pg_proc AS p
    ON p.proname = c.proname
   AND p.pronamespace = 'public'::regnamespace
)
SELECT
  r.ekran,
  r.proname,
  COALESCE(r.imza, '(yok)') AS imza,
  CASE
    WHEN r.oid IS NULL
      THEN 'EKSIK: fonksiyon veritabaninda yok -> 42883'
    WHEN NOT has_function_privilege('authenticated', r.oid, 'EXECUTE')
      THEN 'YETKI YOK: authenticated EXECUTE alamiyor -> 42501'
  END AS sorun
FROM resolved AS r
WHERE r.oid IS NULL
   OR NOT has_function_privilege('authenticated', r.oid, 'EXECUTE')
ORDER BY r.ekran;

-- -----------------------------------------------------------------------------
-- Ek kontrol: group_join_requests'te `reviewed_at` kolonu VAR MI?
-- -----------------------------------------------------------------------------
-- Dart tarafindaki fallback dallari bir donem bu kolona yaziyordu ve
-- PGRST204 aliyordu (kolon yok). Sunucu tarafi `updated_at` kullaniyor,
-- admin_get_all_join_requests da `updated_at AS reviewed_at` diye sunuyor.
-- Asagidaki sorgu 0 satir dondurmelidir. Satir donerse Dart tarafindaki
-- yorumlar guncellenmelidir.
SELECT
  'group_join_requests.reviewed_at artik VAR — Dart yorumlari guncellensin'
    AS not_edildi
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'group_join_requests'
  AND column_name = 'reviewed_at';

-- -----------------------------------------------------------------------------
-- Ek kontrol: group_members(group_id, user_id) tekilligi
-- -----------------------------------------------------------------------------
-- Hem admin_approve_join_request'in ON CONFLICT (group_id, user_id) dali hem de
-- Dart fallback'indeki upsert(onConflict: 'group_id,user_id') bu kisita bagli.
-- Kisit yoksa mukerrer uyelik satirlari olusur ve member_count sisirilir.
SELECT 'EKSIK: group_members(group_id, user_id) UNIQUE kisiti yok' AS sorun
WHERE NOT EXISTS (
  SELECT 1
  FROM pg_constraint AS con
  JOIN pg_class AS rel ON rel.oid = con.conrelid
  WHERE rel.relname = 'group_members'
    AND rel.relnamespace = 'public'::regnamespace
    AND con.contype IN ('u', 'p')
    AND (
      SELECT array_agg(att.attname::text ORDER BY att.attname)
      FROM unnest(con.conkey) AS k(attnum)
      JOIN pg_attribute AS att
        ON att.attrelid = rel.oid AND att.attnum = k.attnum
    ) = ARRAY['group_id', 'user_id']
);

-- -----------------------------------------------------------------------------
-- Ek kontrol: member_count kaymasi
-- -----------------------------------------------------------------------------
-- Denormalize `groups.member_count`, gercek group_members satir sayisindan
-- sapmis gruplari listeler. Sapma varsa gecmiste elle +1/-1 yapan (artik
-- kaldirilmis) istemci kodunun izidir. Dosya sonundaki UPDATE ile duzeltilir.
SELECT
  g.id,
  g.name,
  g.member_count AS kayitli,
  count(m.id)    AS gercek
FROM public.groups AS g
LEFT JOIN public.group_members AS m ON m.group_id = g.id
GROUP BY g.id, g.name, g.member_count
HAVING COALESCE(g.member_count, 0) <> count(m.id)
ORDER BY abs(COALESCE(g.member_count, 0) - count(m.id)) DESC;

-- Duzeltme (once yukaridaki listeyi inceleyin, sonra elle calistirin):
--   UPDATE public.groups AS g
--   SET member_count = s.gercek, updated_at = now()
--   FROM (
--     SELECT g2.id, count(m.id) AS gercek
--     FROM public.goups AS g2
--     LEFT JOIN purblic.group_members AS m ON m.group_id = g2.id
--     GROUP BY g2.id
--   ) AS s
--   WHERE s.id = g.id
--     AND COALESCE(g.member_count, 0) <> s.gercek
