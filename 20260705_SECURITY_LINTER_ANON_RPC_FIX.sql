-- ============================================================================
-- 20260705_SECURITY_LINTER_ANON_RPC_FIX.sql
-- ============================================================================
-- Supabase Database Linter uyarılarını düzeltir:
--   1) rls_policy_always_true (3 politika)
--   2) public_bucket_allows_listing (2 bucket)
--   3) anon_security_definer_function_executable (~20 fonksiyon)
--
-- KÖK NEDEN (3): 20260621_CREATE_BALANCE_SYSTEM.sql şu satırı içeriyordu:
--   GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO anon, authenticated, service_role;
-- Bu, public şemadaki TÜM fonksiyonları (tüm admin_* fonksiyonları,
-- add_to_balance, deduct_from_balance dahil) anon rolüne açtı.
--
-- Blanket "REVOKE ... FROM anon" YAPILMIYOR çünkü verify_registration_otp,
-- verify_password_reset_otp gibi login-öncesi OTP fonksiyonları kasıtlı
-- olarak anon'a açık olmalı. Bu yüzden fix isim bazlı (hedefli).
--
-- En kritik bulgu: add_to_balance/deduct_from_balance içeride HİÇBİR
-- yetki kontrolü yapmıyor (p_user_id parametresini olduğu gibi güveniyor).
-- anon/authenticated herhangi bir kullanıcı bunları çağırıp keyfi bakiye
-- ekleyebilir/düşürebilirdi. Fix: sadece service_role çağırabilsin;
-- approve/reject_transfer_confirmation SECURITY DEFINER yapılarak admin
-- akışı (owner yetkisiyle nested çağrı) kesintisiz çalışır.
--
-- Idempotent: DROP POLICY IF EXISTS, REVOKE/GRANT tekrar çalıştırılabilir.
-- ============================================================================

BEGIN;

-- ============================================================================
-- A) RLS "always true" politikalarını kaldır
--    service_role RLS'i zaten bypass ediyor; kod taraması doğruladı: bu 3
--    tabloya Flutter client'tan hiç insert/update yapılmıyor (sadece RPC).
-- ============================================================================

DROP POLICY IF EXISTS "Service can insert transactions" ON public.balance_transactions;
DROP POLICY IF EXISTS "Service can manage earnings" ON public.seller_earnings;
DROP POLICY IF EXISTS "Service can update balances" ON public.user_balances;

-- ============================================================================
-- B) Public bucket listing politikalarını kaldır
--    getPublicUrl() bucket public=true olduğu sürece RLS'ten bağımsız
--    çalışır; kod hiçbir yerde storage .list() kullanmıyor.
-- ============================================================================

DROP POLICY IF EXISTS "Anyone can read avatars" ON storage.objects;
DROP POLICY IF EXISTS "Anyone can read covers" ON storage.objects;

-- ============================================================================
-- C) Hedefli REVOKE — admin_* fonksiyonları (içeride admin kontrolü var,
--    ama anon'un çağırıp exception ile reddedilmesi bile linter'ı
--    tetikliyor). authenticated grant'i korunuyor (fonksiyon içi kontrol
--    non-admin authenticated kullanıcıları zaten reddediyor).
-- ============================================================================

-- Grup yönetimi
REVOKE EXECUTE ON FUNCTION public.admin_delete_group(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_delete_group(UUID) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.admin_update_group(UUID, TEXT, TEXT, BOOLEAN, BOOLEAN, TEXT, INTEGER) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_update_group(UUID, TEXT, TEXT, BOOLEAN, BOOLEAN, TEXT, INTEGER) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.admin_create_group(TEXT, TEXT, BOOLEAN, BOOLEAN, TEXT, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_create_group(TEXT, TEXT, BOOLEAN, BOOLEAN, TEXT, UUID) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.admin_remove_group_member(UUID, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_remove_group_member(UUID, UUID) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.admin_change_member_role(UUID, UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_change_member_role(UUID, UUID, TEXT) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.admin_approve_join_request(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_approve_join_request(UUID) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.admin_reject_join_request(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_reject_join_request(UUID) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.admin_get_all_groups() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_get_all_groups() TO authenticated;

REVOKE EXECUTE ON FUNCTION public.admin_get_all_join_requests() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_get_all_join_requests() TO authenticated;

REVOKE EXECUTE ON FUNCTION public.admin_get_group_members(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_get_group_members(UUID) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.admin_add_group_member(UUID, UUID, UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_add_group_member(UUID, UUID, UUID) TO authenticated;

-- Gönderi / hikaye / ürün / dükkan yönetimi
REVOKE EXECUTE ON FUNCTION public.admin_delete_post(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_delete_post(UUID) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.admin_delete_story(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_delete_story(UUID) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.admin_pin_post(UUID, BOOLEAN) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_pin_post(UUID, BOOLEAN) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.admin_pin_story(UUID, BOOLEAN) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_pin_story(UUID, BOOLEAN) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.admin_pin_product(UUID, BOOLEAN) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_pin_product(UUID, BOOLEAN) TO authenticated;

REVOKE EXECUTE ON FUNCTION public.admin_pin_shop(UUID, BOOLEAN) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_pin_shop(UUID, BOOLEAN) TO authenticated;

-- Sipariş yönetimi
REVOKE EXECUTE ON FUNCTION public.admin_delete_order(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_delete_order(UUID) TO authenticated;

-- ============================================================================
-- D) add_to_balance / deduct_from_balance — en kritik düzeltme.
--    İçeride hiçbir yetki kontrolü yok; authenticated grant'i de yetersiz
--    (herhangi bir login'li kullanıcı kendine bakiye ekleyebilir/başkasınınkini
--    düşürebilir). Sadece service_role çağırabilsin.
-- ============================================================================

REVOKE EXECUTE ON FUNCTION public.add_to_balance(
  UUID, NUMERIC, balance_transaction_type, VARCHAR, UUID, TEXT, VARCHAR, VARCHAR, JSONB
) FROM PUBLIC, anon, authenticated;

REVOKE EXECUTE ON FUNCTION public.deduct_from_balance(
  UUID, NUMERIC, balance_transaction_type, VARCHAR, UUID, TEXT, JSONB
) FROM PUBLIC, anon, authenticated;

-- approve/reject_transfer_confirmation admin'in kendi authenticated
-- oturumuyla çağırdığı RPC'ler ve içeride PERFORM add_to_balance(...) var.
-- SECURITY DEFINER yaparak nested çağrı fonksiyon sahibinin (postgres)
-- yetkisiyle çalışır — admin'in artık kaldırılan add_to_balance grant'ine
-- bağımlı kalmaz. İçeride zaten auth.uid() + admin rol kontrolü var,
-- bu yüzden ek yetki riski oluşturmaz.
ALTER FUNCTION public.approve_transfer_confirmation(UUID, TEXT) SECURITY DEFINER;
ALTER FUNCTION public.reject_transfer_confirmation(UUID, TEXT) SECURITY DEFINER;

-- Defensive: bu ikisi zaten sadece authenticated'e grant edilmişti
-- (20260705_TRANSFER_CONFIRMATIONS.sql), anon grant'i yoktu — blanket
-- grant'ten etkilenmemeleri için temizlik.
REVOKE EXECUTE ON FUNCTION public.approve_transfer_confirmation(UUID, TEXT) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.reject_transfer_confirmation(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.approve_transfer_confirmation(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reject_transfer_confirmation(UUID, TEXT) TO authenticated;

-- ============================================================================
-- E) Gelecekte yeni fonksiyonların otomatik anon'a açılmasını önle.
--    NOT: yalnızca bundan sonra oluşturulacak fonksiyonları etkiler.
-- ============================================================================

ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE EXECUTE ON FUNCTIONS FROM anon;

NOTIFY pgrst, 'reload schema';

COMMIT;

-- ============================================================================
-- DOĞRULAMA
-- ============================================================================
-- 1) RLS politikaları kalktı mı:
-- SELECT policyname FROM pg_policies
-- WHERE tablename IN ('balance_transactions','seller_earnings','user_balances')
--   AND policyname IN ('Service can insert transactions','Service can manage earnings','Service can update balances');
-- (0 satır dönmeli)
--
-- 2) Bucket listing politikaları kalktı mı:
-- SELECT policyname FROM pg_policies
-- WHERE tablename = 'objects' AND schemaname = 'storage'
--   AND policyname IN ('Anyone can read avatars','Anyone can read covers');
-- (0 satır dönmeli)
--
-- 3) anon artık çağıramıyor mu (örnek):
-- SELECT has_function_privilege('anon', 'public.add_to_balance(uuid, numeric, balance_transaction_type, varchar, uuid, text, varchar, varchar, jsonb)', 'EXECUTE');
-- SELECT has_function_privilege('anon', 'public.admin_delete_post(uuid)', 'EXECUTE');
-- (her ikisi de false dönmeli)
--
-- 4) authenticated hâlâ çağırabiliyor mu (admin fonksiyonları için):
-- SELECT has_function_privilege('authenticated', 'public.admin_delete_post(uuid)', 'EXECUTE');
-- (true dönmeli)
-- ============================================================================
