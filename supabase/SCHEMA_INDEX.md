# Supabase Sema Indeksi

**Tarih:** 2026-07-30  
**Kaynak:** [`supabase/migrations/`](migrations/) altindaki 14 haneli standard ada sahip SQL dosyalarinda tanimlanan objelerin otomatik cikarimi.  
**Taranan standard migration:** 292  
**Yerel aktif SQL toplami:** 314 (292 standard + 22 legacy adli)

> **Kapsam ve kanit siniri:** Bu indeks [`build_schema_index.py`](../plans/scripts/build_schema_index.py:7) regex taramasinin sonucudur; canli veritabani katalog sayimi degildir. Ayni ad bir kez sayilir, `DROP`/supersede sirasi yorumlanmaz ve 22 legacy adli aktif SQL taramaya girmez. Bu nedenle asagidaki 81 tablo, 178 fonksiyon, 9 view, 95 trigger ve 381 benzersiz policy adi yalniz standard dosya kaynak envanteridir; uzak ortam uygulanma durumunu veya nihai canli nesne toplamlarini kanitlamaz.

---

## TABLOLAR (81)

| Tablo | Ilk Tanim |
|---|---|
| `ad_reward_daily_budgets` | (birden fazla migration) |
| `ad_reward_sessions` | (birden fazla migration) |
| `ad_reward_ssv_events` | (birden fazla migration) |
| `ad_reward_views` | (birden fazla migration) |
| `ad_settings` | (birden fazla migration) |
| `ai_conversations` | (birden fazla migration) |
| `ai_messages` | (birden fazla migration) |
| `ai_prompt_images` | (birden fazla migration) |
| `ai_quick_prompts` | (birden fazla migration) |
| `api_settings` | (birden fazla migration) |
| `app_about_settings` | (birden fazla migration) |
| `cancellation_requests` | (birden fazla migration) |
| `conversations` | (birden fazla migration) |
| `coupon_usages` | (birden fazla migration) |
| `courier_requests` | (birden fazla migration) |
| `courier_service_notices` | (birden fazla migration) |
| `courier_service_settings` | (birden fazla migration) |
| `courier_status_changes` | (birden fazla migration) |
| `daily_deals` | (birden fazla migration) |
| `delivery_card_options` | (birden fazla migration) |
| `digital_order_refunds` | (birden fazla migration) |
| `digital_orders` | (birden fazla migration) |
| `email_settings` | (birden fazla migration) |
| `flash_sales` | (birden fazla migration) |
| `follow_requests` | (birden fazla migration) |
| `follows` | (birden fazla migration) |
| `fraud_signals` | (birden fazla migration) |
| `institutions` | (birden fazla migration) |
| `live_messages` | (birden fazla migration) |
| `live_pinned_products` | (birden fazla migration) |
| `live_sessions` | (birden fazla migration) |
| `messages` | (birden fazla migration) |
| `news` | (birden fazla migration) |
| `news_categories` | (birden fazla migration) |
| `news_comment_likes` | (birden fazla migration) |
| `news_comments` | (birden fazla migration) |
| `news_images` | (birden fazla migration) |
| `news_likes` | (birden fazla migration) |
| `news_shares` | (birden fazla migration) |
| `news_views` | (birden fazla migration) |
| `notifications` | (birden fazla migration) |
| `password_reset_otps` | (birden fazla migration) |
| `payment_transactions` | (birden fazla migration) |
| `payout_requests` | (birden fazla migration) |
| `payout_transactions` | (birden fazla migration) |
| `point_ledger_entries` | (birden fazla migration) |
| `post_favorites` | (birden fazla migration) |
| `price_alerts` | (birden fazla migration) |
| `product_favorites` | (birden fazla migration) |
| `product_review_helpful` | (birden fazla migration) |
| `product_reviews` | (birden fazla migration) |
| `product_views` | (birden fazla migration) |
| `push_notifications` | (birden fazla migration) |
| `registration_otps` | (birden fazla migration) |
| `return_requests` | (birden fazla migration) |
| `reward_points_config_audit` | (birden fazla migration) |
| `reward_points_migration_audits` | (birden fazla migration) |
| `sehirici_cities` | (birden fazla migration) |
| `sehirici_drivers` | (birden fazla migration) |
| `sehirici_favorite_stops` | (birden fazla migration) |
| `sehirici_line_stops` | (birden fazla migration) |
| `sehirici_lines` | (birden fazla migration) |
| `sehirici_routes` | (birden fazla migration) |
| `sehirici_stops` | (birden fazla migration) |
| `sehirici_trip_locations` | (birden fazla migration) |
| `sehirici_trips` | (birden fazla migration) |
| `seller_bank_accounts` | (birden fazla migration) |
| `seller_earnings` | (birden fazla migration) |
| `shop_coupons` | (birden fazla migration) |
| `shop_views` | (birden fazla migration) |
| `smm_providers` | (birden fazla migration) |
| `story_likes` | (birden fazla migration) |
| `story_views` | (birden fazla migration) |
| `support_ticket_messages` | (birden fazla migration) |
| `support_tickets` | (birden fazla migration) |
| `system_settings` | (birden fazla migration) |
| `task_categories` | (birden fazla migration) |
| `task_submissions` | (birden fazla migration) |
| `tasks` | (birden fazla migration) |
| `user_point_accounts` | (birden fazla migration) |
| `verification_codes` | (birden fazla migration) |

## FONKSIYONLAR / RPC'LER (178)

| Fonksiyon |
|---|
| `add_to_balance` |
| `admin_approve_join_request` |
| `admin_cancel_with_refund` |
| `admin_delete_post` |
| `admin_delete_sehirici_city` |
| `admin_delete_sehirici_driver` |
| `admin_delete_sehirici_line` |
| `admin_delete_sehirici_stop` |
| `admin_get_all_join_requests` |
| `admin_get_task_submissions` |
| `admin_list_fraud_signals` |
| `admin_list_suspicious_users` |
| `admin_reject_join_request` |
| `admin_review_fraud_signal` |
| `admin_scan_fraud_signals` |
| `admin_set_user_suspicious` |
| `admin_update_reward_points_config` |
| `admin_upsert_sehirici_city` |
| `admin_upsert_sehirici_driver` |
| `admin_upsert_sehirici_line` |
| `admin_upsert_sehirici_stop` |
| `ai_quick_prompts_set_updated_at` |
| `apply_campaign_rewards_for_order` |
| `approve_cancellation_request` |
| `approve_task_submission` |
| `atomic_finalize_payment_transaction` |
| `auth_is_admin` |
| `auth_sehirici_is_admin` |
| `auto_calculate_commission` |
| `cache_sehirici_route_polyline` |
| `calculate_order_commission` |
| `can_review_order` |
| `can_review_product` |
| `check_app_version` |
| `claim_flash_sale` |
| `claim_task` |
| `cleanup_old_verification_codes` |
| `cleanup_sehirici_old_locations` |
| `clear_shop_balance` |
| `complete_online_payment` |
| `compute_sehirici_next_stop` |
| `create_ad_reward_session` |
| `create_cancellation_request` |
| `create_digital_order` |
| `create_digital_order_with_points` |
| `create_seller_earnings_on_delivery` |
| `create_verification_code` |
| `current_user_has_role` |
| `current_user_role_in_list` |
| `decrease_product_stock` |
| `decrement_post_likes_count` |
| `decrement_story_likes` |
| `decrement_story_likes_count` |
| `deduct_from_balance` |
| `delete_account_with_code` |
| `dismiss_review_reminder` |
| `end_live_session` |
| `get_active_tasks` |
| `get_admin_commission_report` |
| `get_available_orders_for_courier` |
| `get_categories_with_shop_count` |
| `get_courier_active_orders` |
| `get_email_settings` |
| `get_news_engagement_details` |
| `get_pending_reviews` |
| `get_post_favorite_count` |
| `get_product_favorite_count` |
| `get_sehirici_active_trips` |
| `get_sehirici_lines_with_stops` |
| `get_sehirici_trip_path` |
| `get_sehirici_trips_for_stop` |
| `get_seller_commission_summary` |
| `get_shop_today_views` |
| `get_shop_total_views` |
| `get_task_stats` |
| `get_top_customers` |
| `get_top_viewed_products` |
| `get_user_liked_posts` |
| `get_user_task_history` |
| `grant_ad_reward` |
| `grant_verified_ad_points` |
| `handle_new_user` |
| `increment_post_likes_count` |
| `increment_story_likes` |
| `increment_story_likes_count` |
| `increment_story_views_count` |
| `is_admin` |
| `is_fraud_admin` |
| `is_post_favorited` |
| `is_product_favorited` |
| `mark_messages_as_read` |
| `notify_admin_on_payout_request` |
| `notify_comment_mention` |
| `notify_follow_request_trigger` |
| `notify_new_follower` |
| `notify_new_message` |
| `notify_new_message_push` |
| `notify_new_order` |
| `notify_new_order_email` |
| `notify_news_comment` |
| `notify_news_comment_like` |
| `notify_news_like` |
| `notify_order_status_change` |
| `notify_post_comment` |
| `notify_post_like` |
| `notify_price_drops` |
| `notify_sehirici_favorite_approaching` |
| `notify_seller_on_new_review` |
| `notify_story_like` |
| `notify_user_on_seller_reply` |
| `on_courier_status_change` |
| `prevent_seller_self_grant_smm` |
| `purge_expired_reward_fraud_hashes` |
| `record_coupon_usage` |
| `record_news_view` |
| `refund_digital_order_payment` |
| `reject_cancellation_request` |
| `reject_point_ledger_mutation` |
| `reject_task_submission` |
| `release_flash_sale` |
| `restore_product_stock` |
| `reward_points_apply_entry` |
| `sehirici_set_updated_at` |
| `send_message_direct` |
| `send_push_on_notification` |
| `set_default_working_hours` |
| `set_digital_order_reconciliation` |
| `set_news_published_at` |
| `set_sehirici_trip_status` |
| `set_updated_at` |
| `start_live_session` |
| `start_sehirici_trip` |
| `submit_task_with_proof` |
| `sync_shop_products_availability` |
| `toggle_comment_like` |
| `toggle_news_like` |
| `toggle_post_favorite` |
| `toggle_product_favorite` |
| `trg_flash_sales_set_updated_at` |
| `trg_live_sessions_set_updated_at` |
| `update_app_about_settings_updated_at` |
| `update_comment_like_count` |
| `update_conversation_on_message` |
| `update_courier_location_timestamp` |
| `update_courier_service_notices_timestamp` |
| `update_daily_deals_updated_at` |
| `update_email_settings_updated_at` |
| `update_follow_requests_updated_at` |
| `update_helpful_count_on_vote` |
| `update_last_seen` |
| `update_news_comment_count` |
| `update_news_like_count` |
| `update_news_view_count` |
| `update_notifications_updated_at` |
| `update_payment_transactions_updated_at` |
| `update_payout_requests_updated_at` |
| `update_payout_transactions_updated_at` |
| `update_post_comments_count` |
| `update_product_rating_on_review_change` |
| `update_product_reviews_updated_at` |
| `update_sehirici_trip_location` |
| `update_seller_bank_accounts_updated_at` |
| `update_shop_balance` |
| `update_shop_coupons_updated_at` |
| `update_shop_pending_payout` |
| `update_shop_rating` |
| `update_shop_review_seller_reply` |
| `update_system_settings_updated_at` |
| `update_updated_at_column` |
| `upsert_fraud_signal` |
| `use_coupon` |
| `validate_and_apply_coupon` |
| `validate_coupon` |
| `validate_payout_request` |
| `validate_seller_categories` |
| `verify_code` |
| `verify_password_reset_otp` |
| `verify_registration_otp` |

## VIEW'LAR (9)

- `admin_user_spending_summary`
- `ai_conversations_with_preview`
- `my_ad_reward_sessions`
- `posts_with_profiles`
- `posts_with_user`
- `reward_points_public_config`
- `shops_with_products_stats`
- `v_admin_commission_dashboard`
- `v_debt_orders`

## TRIGGER'LAR (95)

- `app_about_settings_updated_at`
- `calculate_order_commission`
- `clear_shop_balance`
- `comment_like_count_trigger`
- `conversations_updated_at`
- `daily_deals_updated_at`
- `email_settings_updated_at`
- `flash_sales_set_updated_at`
- `for`
- `function`
- `live_sessions_set_updated_at`
- `message_insert_trigger`
- `messages_updated_at`
- `news_comment_count_trigger`
- `news_like_count_trigger`
- `news_view_count_trigger`
- `notifications_push_trigger`
- `notifications_updated_at`
- `notify_admin_on_payout_request`
- `notify_comment_mention_trigger`
- `notify_follow_request`
- `notify_new_follower_trigger`
- `notify_new_message_push_trigger`
- `notify_new_order_trigger`
- `notify_news_comment_like_trigger`
- `notify_news_comment_trigger`
- `notify_news_like_trigger`
- `notify_order_status_trigger`
- `notify_post_comment_trigger`
- `notify_post_like_trigger`
- `notify_seller_new_review_trigger`
- `notify_story_like_trigger`
- `notify_user_seller_reply_trigger`
- `on_auth_user_created`
- `on_courier_status_change`
- `on_new_message_notify`
- `on_order_created_send_email`
- `orders_auto_calculate_commission`
- `orders_update_shop_pending_payout`
- `payout_requests_updated_at`
- `point_ledger_reject_truncate`
- `point_ledger_reject_update_delete`
- `post_likes_delete_trigger`
- `post_likes_insert_trigger`
- `product_review_helpful_delete_trigger`
- `product_review_helpful_insert_trigger`
- `product_reviews_delete_trigger`
- `product_reviews_insert_trigger`
- `product_reviews_update_trigger`
- `product_reviews_updated_at`
- `products_price_drop_alert`
- `push_notifications_updated_at`
- `set_default_working_hours_trigger`
- `set_news_published_at_on_insert`
- `set_news_published_at_trigger`
- `shop_review_seller_reply_trigger`
- `sync_shop_products_availability_trigger`
- `system_settings_updated_at`
- `trg_ai_quick_prompts_updated`
- `trg_cancellation_requests_updated_at`
- `trg_prevent_seller_self_grant_smm`
- `trg_sehirici_cities_updated_at`
- `trg_sehirici_drivers_updated_at`
- `trg_sehirici_lines_updated_at`
- `trg_sehirici_stops_updated_at`
- `trg_sehirici_trips_updated_at`
- `trg_task_submissions_updated_at`
- `trg_tasks_updated_at`
- `trigger_create_seller_earnings`
- `trigger_decrease_stock_on_order_confirm`
- `trigger_decrement_story_likes_count`
- `trigger_follow_requests_updated_at`
- `trigger_increment_story_likes_count`
- `trigger_increment_story_views_count`
- `trigger_record_coupon_usage`
- `trigger_restore_stock_on_order_cancel`
- `trigger_update_courier_location_timestamp`
- `trigger_update_courier_service_notices_timestamp`
- `trigger_update_shop_coupons_updated_at`
- `update_ai_conversations_updated_at`
- `update_ai_prompt_images_updated_at`
- `update_comments_count_on_delete`
- `update_comments_count_on_insert`
- `update_institutions_updated_at`
- `update_news_categories_updated_at`
- `update_news_comments_updated_at`
- `update_news_updated_at`
- `update_payment_transactions_updated_at`
- `update_payout_transactions_updated_at`
- `update_profiles_last_seen`
- `update_seller_bank_accounts_updated_at`
- `update_shop_balance`
- `update_shop_coupons_updated_at_trigger`
- `update_shop_rating_trigger`
- `validate_payout_request`

## RLS POLICY'LER (381)

**Toplam:** 381 policy

Not: Policy'ler tablo bazinda migration dosyalarinda tanimli. Detay icin ilgili migration dosyasina bakin.

---

**Guncelleme:** Bu dosyanin nesne listeleri [`build_schema_index.py`](../plans/scripts/build_schema_index.py:1) ile otomatik uretilmistir. Betik yalniz `^\d{14}_` adlarini tarar; yeniden uretimden sonra 314/292/22 kapsam notu korunmali ve uzak ortam ayrica dogrulanmalidir.
