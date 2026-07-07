-- ============================================================================
-- 20260706_SECURITY_LINTER_ANON_RPC_FIX_PART2.sql
-- ============================================================================
-- 20260705_SECURITY_LINTER_ANON_RPC_FIX.sql sadece ~19 admin_* fonksiyonunu
-- ve add_to_balance/deduct_from_balance'ı elle hedefledi. Linter'ı yeniden
-- çalıştırınca 225 uyarı çıktı — hepsi anon_security_definer_function_executable
-- kategorisinden ve ~100+ ek fonksiyonu kapsıyor (ai_*, atomic_*, tüm
-- notify_*/increment_*/decrement_* trigger fonksiyonları, handle_new_user,
-- is_admin, is_group_admin, is_group_member, mesajlaşma fonksiyonları vb.).
--
-- Kök neden aynı: 20260621_CREATE_BALANCE_SYSTEM.sql'deki blanket
--   GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO anon, authenticated, service_role;
--
-- Bu ölçekte (100+) elle REVOKE/GRANT yazmak yerine pg_proc'u tarayan
-- programatik bir DO bloğu kullanılıyor.
--
-- Kod taramasıyla doğrulanan 2 liste:
-- 1) ALLOWLIST — login-öncesi gerçekten anon'a açık kalması gereken
--    fonksiyonlar (verify_registration_otp: kayıt OTP, register_screen_v2.dart:178;
--    verify_password_reset_otp: şifre sıfırlama OTP, reset_password_screen.dart:142;
--    verify_code: aynı serviste yaşayan genel doğrulayıcı, temkinli olarak dahil).
-- 2) TRIGGER-ONLY — lib/'de hiçbir yerde .rpc() ile çağrılmayan, sadece
--    CREATE TRIGGER ... EXECUTE FUNCTION ile bağlı 26 fonksiyon. Postgres
--    trigger'ları çalıştırıcının EXECUTE yetkisinden bağımsız çalışır
--    (definer semantiği), bu yüzden bunlardan anon+authenticated+PUBLIC
--    güvenle kaldırılabilir.
--
-- Diğer her şeyden (is_admin, is_group_admin/member, mesajlaşma/grup RPC'leri,
-- atomic_* vb.) PUBLIC'ten kaldırılıp authenticated'e açıkça yeniden
-- veriliyor (bkz. DÜZELTME notu altta) — client bunları doğrudan .rpc() ile
-- çağırıyor.
--
-- DÜZELTME (ilk versiyondan sonra bulundu): Bazı fonksiyonlar (delete_conversation_for_user,
-- delete_conversation_with_partner, get_online_users, mark_all_messages_read,
-- send_message_with_recipient, update_user_heartbeat) chat migration'larında
-- `DROP FUNCTION` + `CREATE FUNCTION` ile yeniden oluşturulmuş; Postgres yeni
-- oluşturulan fonksiyona varsayılan olarak PUBLIC'e (yani anon dahil herkese)
-- EXECUTE veriyor. Bu dosyalar sadece `GRANT ... TO authenticated` eklemiş,
-- PUBLIC'ten hiç REVOKE etmemiş. "REVOKE ... FROM anon" bu durumda no-op'tur
-- (anon'a özel bir grant yoktur ki kaldırılsın) — asıl kaldırılması gereken
-- PUBLIC grant'idir. Bu yüzden aşağıdaki 1. döngü artık "FROM anon" değil
-- "FROM PUBLIC" + "TO authenticated yeniden grant" yapıyor.
--
-- Idempotent: has_function_privilege kontrolü + Postgres'te var olmayan
-- bir grant'i REVOKE etmek hataya değil no-op'a yol açar.
-- ============================================================================

BEGIN;

DO $$
DECLARE
  r RECORD;
  v_allowlist TEXT[] := ARRAY['verify_registration_otp', 'verify_password_reset_otp', 'verify_code'];
  v_trigger_only TEXT[] := ARRAY[
    'ai_on_message_insert','calculate_order_commission',
    'create_seller_earnings_on_delivery','create_user_balance_on_signup','decrease_product_stock',
    'decrement_post_comments_count','decrement_post_likes_count','decrement_story_likes_count',
    'ensure_online_status','handle_follow_request_status_change','handle_new_user',
    'increment_post_comments_count','increment_post_likes_count','increment_story_likes_count',
    'notify_admin_payout_request','notify_comment_mention','notify_direct_message',
    'notify_follow_request','notify_follow_request_accepted','notify_group_join_request',
    'notify_group_member_joined','notify_group_message','notify_new_follower','notify_new_message',
    'notify_new_message_push','notify_new_order_email','create_notification_preferences',
    'notify_transfer_confirmation_resolved','update_conversation_on_message'
  ];
BEGIN
  -- 1) Tüm public.SECURITY DEFINER fonksiyonlardan anon'u kaldır (allowlist hariç)
  FOR r IN
    SELECT p.oid, p.proname, pg_get_function_identity_arguments(p.oid) AS args
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prosecdef = true
      AND has_function_privilege('anon', p.oid, 'EXECUTE')
      AND p.proname <> ALL(v_allowlist)
  LOOP
    -- NOT: bazı fonksiyonlar DROP FUNCTION + CREATE FUNCTION ile yeniden
    -- oluşturulduğu için (örn. chat fix migration'ları) yetki PUBLIC'e
    -- (Postgres varsayılanı) düşmüş olabilir — "REVOKE ... FROM anon" bu
    -- durumda no-op'tur (anon'a özel bir grant yoktur ki kaldırılsın).
    -- PUBLIC'ten kaldırıp authenticated'e açıkça yeniden veriyoruz, böylece
    -- anon (PUBLIC üzerinden gelen dolaylı erişim dahil) kesin olarak düşer.
    EXECUTE format('REVOKE EXECUTE ON FUNCTION public.%I(%s) FROM PUBLIC', r.proname, r.args);
    EXECUTE format('GRANT EXECUTE ON FUNCTION public.%I(%s) TO authenticated', r.proname, r.args);
    RAISE NOTICE 'PUBLIC/anon EXECUTE kaldırıldı, authenticated korundu: %(%)', r.proname, r.args;
  END LOOP;

  -- 2) Saf trigger fonksiyonlarından anon + authenticated + PUBLIC'i de kaldır
  FOR r IN
    SELECT p.oid, p.proname, pg_get_function_identity_arguments(p.oid) AS args
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = ANY(v_trigger_only)
  LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION public.%I(%s) FROM PUBLIC, anon, authenticated', r.proname, r.args);
    RAISE NOTICE 'trigger-only, tüm client grant''ları kaldırıldı: %(%)', r.proname, r.args;
  END LOOP;
END $$;

NOTIFY pgrst, 'reload schema';

COMMIT;

-- ============================================================================
-- DOĞRULAMA
-- ============================================================================
-- 1) anon hâlâ EXECUTE yetkisi olan SECURITY DEFINER fonksiyonlar (sadece
--    allowlist'teki 3 tanesi kalmalı):
-- SELECT p.proname, pg_get_function_identity_arguments(p.oid) AS args
-- FROM pg_proc p
-- JOIN pg_namespace n ON n.oid = p.pronamespace
-- WHERE n.nspname = 'public' AND p.prosecdef = true
--   AND has_function_privilege('anon', p.oid, 'EXECUTE');
--
-- 2) authenticated hâlâ çağırabiliyor mu (örnek):
-- SELECT has_function_privilege('authenticated', 'public.is_admin()', 'EXECUTE');
-- SELECT has_function_privilege('authenticated', 'public.notify_new_message()', 'EXECUTE');
-- (ilki true, ikincisi false dönmeli — notify_new_message artık sadece trigger üzerinden çalışır)
-- ============================================================================
