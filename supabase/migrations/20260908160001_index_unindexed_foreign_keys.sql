-- =============================================================================
-- İndekssiz foreign key'lere kapsayıcı indeks ekle
-- =============================================================================
-- Supabase advisor'ın da işaret ettiği klasik eksiklik: bir FK sütununda
-- indeks yoksa,
--   * ON DELETE CASCADE / SET NULL çalışırken çocuk tabloda TAM TARAMA yapılır,
--   * bu sütun üzerinden yapılan join'ler seq scan'e düşer.
--
-- Canlıda 32 FK indekssizdi. Sıcak olanlar özellikle önemli:
--   ilan_favorites.ilan_id, okey_scores_history.user_id,
--   app_analytics_events.user_id, ad_reward_views.reward_session_id
--
-- Hepsi IF NOT EXISTS ile; tekrar çalıştırmak güvenlidir.
-- =============================================================================

CREATE INDEX IF NOT EXISTS idx_ad_reward_views_point_ledger_entry_id ON public.ad_reward_views (point_ledger_entry_id);
CREATE INDEX IF NOT EXISTS idx_ad_reward_views_reward_session_id ON public.ad_reward_views (reward_session_id);
CREATE INDEX IF NOT EXISTS idx_admin_notification_audit_recipient_id ON public.admin_notification_audit (recipient_id);
CREATE INDEX IF NOT EXISTS idx_app_analytics_events_user_id ON public.app_analytics_events (user_id);
CREATE INDEX IF NOT EXISTS idx_bot_post_queue_bot_id ON public.bot_post_queue (bot_id);
CREATE INDEX IF NOT EXISTS idx_courier_assignment_email_outbox_courier_id ON public.courier_assignment_email_outbox (courier_id);
CREATE INDEX IF NOT EXISTS idx_courier_documents_reviewed_by ON public.courier_documents (reviewed_by);
CREATE INDEX IF NOT EXISTS idx_courier_package_email_deliveries_courier_id ON public.courier_package_email_deliveries (courier_id);
CREATE INDEX IF NOT EXISTS idx_courier_payout_requests_approved_by ON public.courier_payout_requests (approved_by);
CREATE INDEX IF NOT EXISTS idx_courier_requests_delivery_confirmed_by ON public.courier_requests (delivery_confirmed_by);
CREATE INDEX IF NOT EXISTS idx_courier_work_offers_assignment_id ON public.courier_work_offers (assignment_id);
CREATE INDEX IF NOT EXISTS idx_digital_order_refunds_cash_balance_transaction_id ON public.digital_order_refunds (cash_balance_transaction_id);
CREATE INDEX IF NOT EXISTS idx_digital_order_refunds_point_ledger_entry_id ON public.digital_order_refunds (point_ledger_entry_id);
CREATE INDEX IF NOT EXISTS idx_digital_orders_point_debit_entry_id ON public.digital_orders (point_debit_entry_id);
CREATE INDEX IF NOT EXISTS idx_ilan_favorites_ilan_id ON public.ilan_favorites (ilan_id);
CREATE INDEX IF NOT EXISTS idx_ilan_images_owner_id ON public.ilan_images (owner_id);
CREATE INDEX IF NOT EXISTS idx_ilan_settings_updated_by ON public.ilan_settings (updated_by);
CREATE INDEX IF NOT EXISTS idx_ilanlar_moderated_by ON public.ilanlar (moderated_by);
CREATE INDEX IF NOT EXISTS idx_okey_bans_banned_by ON public.okey_bans (banned_by);
CREATE INDEX IF NOT EXISTS idx_okey_gifts_sent_recipient_user_id ON public.okey_gifts_sent (recipient_user_id);
CREATE INDEX IF NOT EXISTS idx_okey_gifts_sent_sender_id ON public.okey_gifts_sent (sender_id);
CREATE INDEX IF NOT EXISTS idx_okey_house_revenue_user_id ON public.okey_house_revenue (user_id);
CREATE INDEX IF NOT EXISTS idx_okey_room_players_bot_profile_id ON public.okey_room_players (bot_profile_id);
CREATE INDEX IF NOT EXISTS idx_okey_rooms_created_by ON public.okey_rooms (created_by);
CREATE INDEX IF NOT EXISTS idx_okey_rooms_current_match_id ON public.okey_rooms (current_match_id);
CREATE INDEX IF NOT EXISTS idx_okey_scores_history_user_id ON public.okey_scores_history (user_id);
CREATE INDEX IF NOT EXISTS idx_okey_settings_updated_by ON public.okey_settings (updated_by);
CREATE INDEX IF NOT EXISTS idx_okey_sound_assets_updated_by ON public.okey_sound_assets (updated_by);
CREATE INDEX IF NOT EXISTS idx_okey_table_assets_updated_by ON public.okey_table_assets (updated_by);
CREATE INDEX IF NOT EXISTS idx_reward_points_config_audit_admin_user_id ON public.reward_points_config_audit (admin_user_id);
CREATE INDEX IF NOT EXISTS idx_user_profile_features_feature_id ON public.user_profile_features (feature_id);
CREATE INDEX IF NOT EXISTS idx_user_profile_features_granted_by ON public.user_profile_features (granted_by);

NOTIFY pgrst, 'reload schema';
