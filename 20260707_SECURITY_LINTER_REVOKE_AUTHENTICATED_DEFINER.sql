-- Plan: plans/security_linter_fixes_plan.md — Adım 3 (Yüksek Risk, fonksiyon bazlı analiz sonrası)
-- Amaç: authenticated_security_definer_function_executable uyarılarını, Flutter tarafından
-- doğrudan .rpc() ile çağrılmadığı doğrulanmış (trigger fonksiyonları + hiç kullanılmayan
-- yardımcı fonksiyonlar) 59 fonksiyon için REVOKE ile kapatmak.
--
-- Analiz yöntemi: lib/ altında her fonksiyon adı için `.rpc('ad')` çağrısı grep edildi,
-- ayrıca RLS policy tanımları (pg_policies) fonksiyonun USING/WITH CHECK içinde kullanılıp
-- kullanılmadığı kontrol edildi. is_admin/is_group_admin/is_group_member RLS policy'lerinde
-- kullanıldığı için KEEP edildi, bu listeye dahil EDİLMEDİ.
--
-- NOT: Bu fonksiyonlar trigger olarak veya SECURITY DEFINER içinden (add_to_balance vb.) veya
-- service_role ile (edge functions) çağrılmaya devam edecek — REVOKE sadece `authenticated`
-- rolünün REST/RPC üzerinden DOĞRUDAN çağırmasını engeller, trigger/iç çağrı zincirini bozmaz.

BEGIN;

-- Trigger fonksiyonları (hiçbiri .rpc() ile çağrılamaz, sadece trigger context'inde çalışır)
REVOKE EXECUTE ON FUNCTION public.update_addresses_updated_at() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.update_app_about_settings_updated_at() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.update_daily_deals_updated_at() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.update_email_settings_updated_at() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.update_follow_requests_updated_at() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.update_notifications_updated_at() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.update_payment_transactions_updated_at() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.update_payout_requests_updated_at() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.update_payout_transactions_updated_at() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.update_seller_bank_accounts_updated_at() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.update_shop_coupons_updated_at() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.update_group_last_message() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.update_group_member_count() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.update_post_comments_count() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.update_post_likes_count() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.update_shop_rating() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.update_shop_review_seller_reply() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.update_shop_pending_payout() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.update_story_views_count() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.decrement_story_likes(uuid) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.on_courier_status_change() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.sync_assigned_courier_to_order() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.sync_shop_products_availability() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.update_order_on_courier_assignment() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.update_order_status_on_courier_delivery() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.replicate_message_to_recipient() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.restore_product_stock() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.prevent_group_member_role_self_escalation() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.validate_follow_data_integrity() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.notify_post_comment() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.notify_post_like() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.notify_seller_on_new_review() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.notify_story_like() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.notify_user_on_seller_reply() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.send_new_order_emails(uuid) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.send_new_order_push_notifications(uuid) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.send_push_on_notification() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.update_profile_fields() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.validate_payout_request() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.record_coupon_usage() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.update_user_heartbeat() FROM authenticated;

-- İç yardımcı fonksiyonlar (Flutter'da .rpc() ile hiç çağrılmıyor; trigger/başka
-- SECURITY DEFINER fonksiyon/edge function (service_role) üzerinden çağrılıyor)
REVOKE EXECUTE ON FUNCTION public.send_fcm_push_notification(uuid, text, text, jsonb) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.send_push_notification_safe(uuid, text, text, jsonb) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.send_email(text, text, text, text) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.ai_increment_usage(uuid, integer, boolean) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.cleanup_old_verification_codes() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.atomic_add_balance_topup(uuid, numeric, uuid, character varying, numeric) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.atomic_finalize_payment_transaction(uuid, text, numeric, text, text, text, text, text, integer, text, text, text, text, timestamptz, jsonb) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.complete_online_payment(uuid) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.delete_conversation_with_partner(uuid) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.mark_all_messages_read(uuid) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.mark_sender_messages_read(uuid, uuid) FROM authenticated;

-- Kodda hiçbir yerde (Flutter lib/ veya supabase/functions) çağrılmadığı doğrulanan,
-- kullanılmayan/legacy RPC'ler
REVOKE EXECUTE ON FUNCTION public.check_app_version() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.check_app_version(text, integer) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.get_categories_with_shop_count() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.get_available_orders_for_courier(uuid) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.get_courier_active_orders(uuid) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_delete_order(uuid) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_get_all_join_requests() FROM authenticated;

COMMIT;
