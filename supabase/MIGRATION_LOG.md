# Migration Log

**Tarih:** 2026-07-30  
**Amac:** Yerel [`supabase/migrations/`](migrations/) dizinindeki SQL dosyalarinin kronolojik envanteri.
**Format:** `YYYYMMDDHHMMSS_name.sql` (Supabase CLI standardi)

> **Kapsam ve kanit siniri:** 2026-07-30 yerel dosya sistemi sayiminda **314 aktif SQL** vardir: **292** dosya 14 haneli Supabase CLI ad standardina uyar, **22** dosya legacy ada sahiptir. Asagidaki kronoloji yalniz 292 standard dosyayi listeler. Bu belge uzak ortama uygulanma durumunu kanitlamaz; production/staging durumu deploy oncesi `supabase migration list` ile ayrica dogrulanmalidir.

---

**Standard adli toplam:** 292 migration, 2 yil  
**Tum aktif SQL:** 314 (292 standard + 22 legacy adli)

## 2024
**24 migration**

| Tarih | Dosya | Boyut |
|---|---|---|
| 2024-01-01 00:00:09 | `20240101000009_create_follows_table.sql` | 1.6K |
| 2024-01-22 00:00:00 | `20240122000000_add_story_views.sql` | 2.2K |
| 2024-01-23 00:00:00 | `20240123000000_optimize_rls_policies.sql` | 27.1K |
| 2024-01-23 00:00:01 | `20240123000001_fix_rls_auth_uid.sql` | 20.4K |
| 2024-01-23 00:00:02 | `20240123000002_fix_auth_uid_only.sql` | 13.4K |
| 2024-01-23 00:00:03 | `20240123000003_fix_remaining_linter_warnings.sql` | 3.5K |
| 2024-01-23 00:00:04 | `20240123000004_remove_duplicate_policies.sql` | 7.4K |
| 2024-01-23 00:00:05 | `20240123000005_fix_remaining_auth_uid_policies.sql` | 12.1K |
| 2024-01-23 00:00:06 | `20240123000006_fix_campaigns_coupons_reviews.sql` | 4.0K |
| 2024-01-23 00:00:07 | `20240123000007_create_test_shops_and_products.sql` | 11.3K |
| 2024-01-23 00:00:08 | `20240123000008_add_story_thumbnail.sql` | 534B |
| 2024-01-23 00:00:09 | `20240123000009_add_shop_delivery_fees.sql` | 412B |
| 2024-01-24 00:00:10 | `20240124000010_create_product_favorites.sql` | 2.7K |
| 2024-01-24 00:00:11 | `20240124000011_create_post_favorites.sql` | 2.6K |
| 2024-01-24 00:00:12 | `20240124000012_create_story_likes.sql` | 1.8K |
| 2024-01-24 00:00:13 | `20240124000013_fix_function_search_path.sql` | 4.7K |
| 2024-01-24 00:00:14 | `20240124000014_fix_auth_rls_initplan.sql` | 2.4K |
| 2024-01-24 00:00:15 | `20240124000015_create_notifications_table.sql` | 3.0K |
| 2024-01-24 00:00:16 | `20240124000016_alter_notifications_table.sql` | 3.3K |
| 2024-01-24 00:00:17 | `20240124000017_fix_notification_enum.sql` | 790B |
| 2024-01-24 00:00:18 | `20240124000018_fix_notifications_rls.sql` | 958B |
| 2024-01-24 00:00:19 | `20240124000019_add_delete_confirmation_to_profiles.sql` | 680B |
| 2024-01-24 00:00:20 | `20240124000020_fix_follows_performance.sql` | 1003B |
| 2024-01-24 00:00:21 | `20240124000021_fix_story_views_performance.sql` | 1.0K |

## 2026
**268 migration**

| Tarih | Dosya | Boyut |
|---|---|---|
| 2026-01-28 00:00:00 | `20260128000000_test_sellers_and_products.sql` | 10.1K |
| 2026-01-29 00:00:00 | `20260129000000_enable_user_reports_realtime.sql` | 502B |
| 2026-01-29 00:00:01 | `20260129000001_fix_rls_performance.sql` | 8.6K |
| 2026-01-29 00:00:02 | `20260129000002_fix_profiles_insert_policy.sql` | 1.6K |
| 2026-01-29 00:00:03 | `20260129000003_enable_support_tickets_realtime.sql` | 339B |
| 2026-01-29 00:00:04 | `20260129000004_add_support_tickets_category.sql` | 3.7K |
| 2026-01-29 00:00:05 | `20260129000005_support_ticket_messages.sql` | 4.6K |
| 2026-01-30 00:00:00 | `20260130000000_add_support_notification_types.sql` | 722B |
| 2026-01-30 00:00:01 | `20260130000001_payout_requests.sql` | 5.4K |
| 2026-01-30 00:00:02 | `20260130000002_fix_posts_admin_policies.sql` | 1012B |
| 2026-01-30 00:00:03 | `20260130000003_add_shop_settings.sql` | 4.2K |
| 2026-01-30 00:00:04 | `20260130000004_create_shop_images_bucket.sql` | 2.5K |
| 2026-01-30 00:00:05 | `20260130000005_rls_performance_optimization.sql` | 7.6K |
| 2026-01-30 00:00:06 | `20260130000006_fix_function_search_path.sql` | 4.0K |
| 2026-01-30 00:00:07 | `20260130000007_seller_product_images_rls.sql` | 1.9K |
| 2026-01-30 00:00:08 | `20260130000008_add_has_own_courier.sql` | 838B |
| 2026-01-30 00:00:09 | `20260130000009_one_shop_per_seller.sql` | 2.0K |
| 2026-01-30 00:00:10 | `20260130000010_shop_cascade_delete.sql` | 1.8K |
| 2026-01-30 00:00:11 | `20260130000011_add_product_variants.sql` | 1.4K |
| 2026-01-30 00:00:12 | `20260130000012_fix_shop_images_rls.sql` | 1.5K |
| 2026-01-30 00:00:13 | `20260130000013_reset_shop_images_policies.sql` | 1.8K |
| 2026-01-30 00:00:14 | `20260130000014_fix_shop_images_path.sql` | 1.9K |
| 2026-01-31 00:00:00 | `20260131000000_fix_product_images_and_limit.sql` | 1.6K |
| 2026-01-31 00:00:01 | `20260131000001_add_cart_variant_data.sql` | 414B |
| 2026-01-31 00:00:02 | `20260131000002_commission_system.sql` | 13.8K |
| 2026-01-31 00:00:03 | `20260131000003_fix_shops_rls_policy.sql` | 1.8K |
| 2026-01-31 00:00:04 | `20260131000004_fix_rls_linter_warnings.sql` | 7.8K |
| 2026-01-31 00:00:05 | `20260131000005_fix_function_search_path.sql` | 1.7K |
| 2026-01-31 00:00:06 | `20260131000006_fix_orders_update_policy.sql` | 2.0K |
| 2026-01-31 00:00:07 | `20260131000007_fix_orders_delete_policy.sql` | 978B |
| 2026-01-31 00:00:08 | `20260131000008_add_is_verified_to_shops.sql` | 1.9K |
| 2026-01-31 00:00:09 | `20260131000009_add_shop_approval_system.sql` | 1.6K |
| 2026-02-02 00:00:00 | `20260202000000_create_daily_deals.sql` | 4.2K |
| 2026-02-02 00:00:01 | `20260202000001_create_posts_bucket.sql` | 1.9K |
| 2026-02-02 00:00:02 | `20260202000002_fix_commission_trigger.sql` | 4.8K |
| 2026-02-02 00:00:03 | `20260202000003_fix_order_status_enum.sql` | 1.5K |
| 2026-02-03 00:00:00 | `20260203000000_fix_linter_warnings.sql` | 3.5K |
| 2026-02-03 00:00:01 | `20260203000001_fix_seller_orders_update.sql` | 1.5K |
| 2026-02-03 00:00:02 | `20260203000002_remove_conflicting_triggers.sql` | 7.4K |
| 2026-02-03 00:00:03 | `20260203000003_sellers_can_view_order_addresses.sql` | 1.2K |
| 2026-02-04 00:00:00 | `20260204000000_order_email_notification_trigger.sql` | 2.9K |
| 2026-02-04 00:00:01 | `20260204000001_email_settings_table.sql` | 3.3K |
| 2026-02-05 00:00:00 | `20260205000000_add_card_on_delivery_payment_method.sql` | 1.2K |
| 2026-02-05 00:00:01 | `20260205000001_multi_shop_order_system.sql` | 6.4K |
| 2026-02-05 00:00:02 | `20260205000002_fix_order_group_id_type.sql` | 468B |
| 2026-02-05 00:00:03 | `20260205000003_fix_notification_types.sql` | 517B |
| 2026-02-05 00:00:04 | `20260205000004_fix_existing_notifications.sql` | 707B |
| 2026-02-05 00:00:05 | `20260205000005_order_review_system.sql` | 8.4K |
| 2026-02-05 00:00:06 | `20260205000006_notification_types_update.sql` | 849B |
| 2026-02-06 00:00:01 | `20260206000001_create_avatar_cover_buckets.sql` | 4.5K |
| 2026-02-06 00:00:02 | `20260206000002_optimize_rls_performance.sql` | 6.5K |
| 2026-02-06 00:00:03 | `20260206000003_shop_analytics_tables.sql` | 5.8K |
| 2026-02-06 00:00:04 | `20260206000004_seller_categories.sql` | 1.4K |
| 2026-02-07 00:00:01 | `20260207000001_courier_commission_system.sql` | 7.9K |
| 2026-02-07 00:00:02 | `20260207000002_fix_search_path.sql` | 388B |
| 2026-02-07 00:00:03 | `20260207000003_fix_commission_triggers_search_path.sql` | 5.8K |
| 2026-02-07 00:00:04 | `20260207000004_cleanup_duplicate_triggers.sql` | 5.5K |
| 2026-02-07 00:00:05 | `20260207000005_fix_admin_delete_orders.sql` | 2.3K |
| 2026-02-07 00:00:06 | `20260207000006_fix_shop_reviews_unique_constraint.sql` | 1.1K |
| 2026-02-07 00:00:07 | `20260207000007_create_chat_system.sql` | 6.7K |
| 2026-02-07 00:00:08 | `20260207000008_fix_conversation_create.sql` | 3.1K |
| 2026-02-07 00:00:08 | `20260207000009_fix_linter_warnings.sql` | 4.9K |
| 2026-02-07 00:00:09 | `20260207000010_fix_chat_push_and_conversation.sql` | 7.0K |
| 2026-02-07 00:00:09 | `20260207000011_fix_rls_performance.sql` | 5.0K |
| 2026-02-07 00:00:10 | `20260207000012_fix_chat_safe.sql` | 2.9K |
| 2026-02-07 00:00:10 | `20260207000013_fix_missing_indexes.sql` | 2.4K |
| 2026-02-07 00:00:11 | `20260207000014_add_privacy_status_to_profiles.sql` | 1.7K |
| 2026-02-07 00:00:11 | `20260207000015_fix_chat_safe_check.sql` | 3.4K |
| 2026-02-07 00:00:12 | `20260207000016_fix_chat_urgent.sql` | 3.3K |
| 2026-02-07 00:00:13 | `20260207000017_fix_chat_no_notification_insert.sql` | 3.6K |
| 2026-02-07 00:00:14 | `20260207000018_fix_chat_complete.sql` | 4.9K |
| 2026-02-07 00:00:15 | `20260207000019_add_message_push_notification.sql` | 2.7K |
| 2026-02-08 00:00:01 | `20260208000001_fix_chat_foreign_keys.sql` | 3.4K |
| 2026-02-08 00:00:02 | `20260208000002_chat_push_notification_trigger.sql` | 4.6K |
| 2026-02-08 00:00:03 | `20260208000003_chat_delete_policy.sql` | 1.4K |
| 2026-02-08 00:00:04 | `20260208000004_fix_chat_notification_trigger.sql` | 2.7K |
| 2026-02-08 00:00:05 | `20260208000005_remove_chat_notifications.sql` | 1.6K |
| 2026-02-08 00:00:06 | `20260208000006_fix_conversation_system.sql` | 2.5K |
| 2026-02-08 00:00:07 | `20260208000007_simple_message_trigger.sql` | 2.5K |
| 2026-02-08 00:00:08 | `20260208000008_drop_old_conversation_index.sql` | 2.5K |
| 2026-02-08 00:00:09 | `20260208000009_fix_mark_as_read_function.sql` | 1.4K |
| 2026-02-08 00:00:10 | `20260208000010_all_chat_fixes.sql` | 3.1K |
| 2026-02-08 00:00:11 | `20260208000011_admin_dashboard_rls.sql` | 3.0K |
| 2026-02-08 00:00:11 | `20260208000012_fix_admin_rls_policies.sql` | 4.5K |
| 2026-02-09 00:00:01 | `20260209000001_fix_orders_rls.sql` | 1.5K |
| 2026-02-09 00:00:01 | `20260209000002_free_delivery_settings.sql` | 451B |
| 2026-02-09 00:00:02 | `20260209000003_fix_rls_infinite_recursion.sql` | 4.4K |
| 2026-02-09 00:00:03 | `20260209000004_comprehensive_rls_optimization.sql` | 11.3K |
| 2026-02-09 00:00:04 | `20260209000005_security_fixes.sql` | 4.6K |
| 2026-02-09 00:00:05 | `20260209000006_add_performance_indexes.sql` | 1.8K |
| 2026-02-09 00:00:06 | `20260209000007_fix_post_feed_n_plus_one.sql` | 541B |
| 2026-02-09 00:00:07 | `20260209000008_fix_comments_count_trigger.sql` | 1.7K |
| 2026-02-09 00:00:10 | `20260209000010_admin_crud_policies.sql` | 7.7K |
| 2026-02-09 00:00:11 | `20260209000011_fix_all_rls_performance.sql` | 3.9K |
| 2026-02-09 00:00:12 | `20260209000012_fix_orders_products_rls.sql` | 6.2K |
| 2026-02-10 00:00:00 | `20260210000000_app_about_settings.sql` | 4.8K |
| 2026-02-10 00:00:01 | `20260210000001_fix_chat_conversation_rls.sql` | 3.1K |
| 2026-02-10 00:00:02 | `20260210000002_fix_post_likes_count_trigger.sql` | 2.2K |
| 2026-02-10 00:00:03 | `20260210000003_create_notification_triggers.sql` | 10.5K |
| 2026-02-10 00:00:04 | `20260210000004_fix_linter_warnings.sql` | 6.8K |
| 2026-02-10 00:00:05 | `20260210000005_redesign_seller_payment_system.sql` | 13.6K |
| 2026-02-10 00:00:06 | `20260210000006_fix_commission_status_constraint.sql` | 985B |
| 2026-02-10 00:00:07 | `20260210000007_create_analytics_functions.sql` | 3.1K |
| 2026-02-10 00:00:07 | `20260210000008_fix_comment_mentions_column.sql` | 697B |
| 2026-02-10 00:00:08 | `20260210000009_hide_inactive_shop_products.sql` | 2.1K |
| 2026-02-10 00:00:09 | `20260210000010_fix_orders_seller_access.sql` | 4.1K |
| 2026-02-10 00:00:10 | `20260210000011_fix_notification_and_email_issues.sql` | 5.5K |
| 2026-02-10 00:00:11 | `20260210000012_fix_order_payment_to_seller.sql` | 11.6K |
| 2026-02-10 00:00:12 | `20260210000013_fix_shop_reviews_order_id_nullable.sql` | 539B |
| 2026-02-10 00:00:13 | `20260210000014_fix_linter_warnings.sql` | 6.0K |
| 2026-02-10 00:00:14 | `20260210000015_fix_linter_warnings_part2.sql` | 5.5K |
| 2026-02-10 00:00:15 | `20260210000016_fix_cash_payment_revenue_for_non_courier.sql` | 5.7K |
| 2026-02-10 00:00:16 | `20260210000017_create_shop_coupons_system.sql` | 7.9K |
| 2026-02-11 00:00:00 | `20260211000000_add_test_coupons.sql` | 1.5K |
| 2026-02-11 00:00:01 | `20260211000001_stock_management_trigger.sql` | 2.7K |
| 2026-02-11 00:00:02 | `20260211000002_fix_admin_products_rls.sql` | 3.3K |
| 2026-02-11 00:00:03 | `20260211000003_fix_courier_status_changes_rls.sql` | 2.8K |
| 2026-02-12 00:00:00 | `20260212000000_add_phone_to_addresses.sql` | 419B |
| 2026-02-12 00:00:01 | `20260212000001_add_customer_phone_to_orders.sql` | 593B |
| 2026-02-12 00:00:02 | `20260212000002_remove_duplicate_order_notification_triggers.sql` | 1.4K |
| 2026-02-12 00:00:03 | `20260212000003_add_is_ghost_mode_to_profiles.sql` | 1.2K |
| 2026-02-12 00:00:04 | `20260212000004_fix_supabase_linter_issues.sql` | 10.5K |
| 2026-02-12 00:00:05 | `20260212000005_merge_multiple_permissive_policies.sql` | 3.5K |
| 2026-02-12 00:00:06 | `20260212000006_fix_indexes_and_foreign_keys.sql` | 8.5K |
| 2026-02-12 00:00:07 | `20260212000007_online_payment_system.sql` | 12.5K |
| 2026-02-12 00:00:08 | `20260212000008_fix_complete_online_payment.sql` | 5.0K |
| 2026-02-12 00:00:09 | `20260212000009_add_online_payment_settings.sql` | 2.0K |
| 2026-02-13 00:00:00 | `20260213000000_order_control_and_startup_announcement.sql` | 3.5K |
| 2026-02-13 00:00:01 | `20260213000001_create_category_images_bucket.sql` | 1.9K |
| 2026-02-13 00:00:02 | `20260213000002_add_is_pinned_columns.sql` | 968B |
| 2026-02-21 00:00:01 | `20260221000001_follow_requests_and_private_accounts.sql` | 4.6K |
| 2026-02-22 00:00:00 | `20260222000000_add_s3_storage_settings.sql` | 4.0K |
| 2026-02-27 00:00:00 | `20260227000000_verification_codes.sql` | 4.7K |
| 2026-02-27 00:00:01 | `20260227000001_add_verification_code_notification_type.sql` | 2.0K |
| 2026-02-27 00:00:02 | `20260227000002_fix_comment_mention_trigger.sql` | 723B |
| 2026-02-27 00:00:03 | `20260227000003_update_pending_reviews_with_product.sql` | 1.9K |
| 2026-02-27 00:00:04 | `20260227000004_story_like_notification_trigger.sql` | 1.9K |
| 2026-02-27 00:00:05 | `20260227000005_disable_email_notifications.sql` | 2.1K |
| 2026-02-27 00:00:06 | `20260227000006_fix_pending_reviews_product_check.sql` | 1.8K |
| 2026-02-27 00:00:07 | `20260227000007_fix_verification_code_type.sql` | 768B |
| 2026-02-28 00:00:01 | `20260228000001_force_update_system.sql` | 4.7K |
| 2026-02-28 00:00:02 | `20260228000002_courier_orders_update.sql` | 2.5K |
| 2026-02-28 00:00:02 | `20260228000003_fix_shop_views_rls.sql` | 2.0K |
| 2026-02-28 00:00:03 | `20260228000004_add_post_share_notification_type.sql` | 1.2K |
| 2026-02-28 00:00:04 | `20260228000005_add_html_support_to_daily_deals.sql` | 837B |
| 2026-03-01 00:00:01 | `20260301000001_create_push_notifications_tracking.sql` | 3.6K |
| 2026-03-01 00:00:02 | `20260301000002_create_posts_with_profiles_view.sql` | 1.4K |
| 2026-03-01 00:00:03 | `20260301000003_create_shops_with_products_view.sql` | 2.0K |
| 2026-03-08 00:00:01 | `20260308000001_payout_paid_status_clear_balance.sql` | 9.0K |
| 2026-03-14 00:00:01 | `20260314000001_add_seller_pinned_column.sql` | 557B |
| 2026-03-19 00:00:00 | `20260319000000_registration_otp_system.sql` | 3.3K |
| 2026-04-05 00:00:01 | `20260405000001_fix_complete_online_payment_columns.sql` | 5.1K |
| 2026-04-06 00:00:01 | `20260406000001_add_admin_notification_support.sql` | 1.7K |
| 2026-04-06 00:00:02 | `20260406000002_add_paid_at_to_shops.sql` | 841B |
| 2026-04-11 00:00:00 | `20260411000000_add_is_pinned_columns.sql` | 1.1K |
| 2026-04-11 00:00:00 | `20260411000001_add_messages_enabled_column.sql` | 398B |
| 2026-04-11 00:00:00 | `20260411000002_create_return_requests_table.sql` | 4.0K |
| 2026-04-11 12:00:01 | `20260411120001_courier_status_change.sql` | 3.6K |
| 2026-04-11 12:00:02 | `20260411120002_guest_access_support_about.sql` | 1.5K |
| 2026-04-11 12:00:03 | `20260411120003_new_features.sql` | 2.9K |
| 2026-04-11 12:00:04 | `20260411120004_push_notification_trigger.sql` | 2.4K |
| 2026-04-11 12:00:05 | `20260411120005_product_reviews_clean_install.sql` | 6.9K |
| 2026-04-11 12:00:06 | `20260411120006_product_reviews_complete.sql` | 8.7K |
| 2026-04-11 12:00:07 | `20260411120007_product_reviews_minimal.sql` | 5.8K |
| 2026-04-11 12:00:08 | `20260411120008_product_reviews_setup.sql` | 10.0K |
| 2026-04-11 12:00:09 | `20260411120009_step1_create_reviews_table.sql` | 939B |
| 2026-04-11 12:00:10 | `20260411120010_step2_create_helpful_table.sql` | 522B |
| 2026-04-11 12:00:11 | `20260411120011_step3_add_rating_columns.sql` | 310B |
| 2026-04-11 12:00:12 | `20260411120012_step4_triggers.sql` | 3.7K |
| 2026-05-25 12:00:00 | `20260525120000_add_post_report_notification_type.sql` | 2.4K |
| 2026-05-28 00:00:01 | `20260528000001_fix_story_likes_count_trigger.sql` | 2.9K |
| 2026-05-29 00:00:00 | `20260529000000_fix_story_likes_count.sql` | 2.4K |
| 2026-05-29 00:00:00 | `20260529000001_fix_story_likes_security.sql` | 1.6K |
| 2026-06-02 00:00:01 | `20260602000001_add_courier_notification_types.sql` | 1.4K |
| 2026-06-02 00:00:02 | `20260602000002_fix_duplicate_notifications.sql` | 923B |
| 2026-06-14 00:00:01 | `20260614000001_add_admin_pinned_column.sql` | 1.6K |
| 2026-06-19 00:00:00 | `20260619000000_ai_quick_prompts.sql` | 4.3K |
| 2026-06-19 00:00:01 | `20260619000001_ai_conversations_preview.sql` | 735B |
| 2026-06-21 00:00:00 | `20260621000000_add_image_to_ai_quick_prompts.sql` | 1.3K |
| 2026-06-21 00:00:00 | `20260621000001_ai_chat_fix_permissions.sql` | 6.2K |
| 2026-06-21 00:00:00 | `20260621000002_create_ai_chat_tables.sql` | 4.3K |
| 2026-06-21 00:00:00 | `20260621000003_create_ai_prompt_images.sql` | 2.7K |
| 2026-06-21 00:00:00 | `20260621000004_fix_ai_settings_rls.sql` | 843B |
| 2026-06-21 00:00:00 | `20260621000005_fix_provider_constraint.sql` | 405B |
| 2026-06-21 12:00:01 | `20260621120001_add_delivered_courier_columns.sql` | 1.8K |
| 2026-06-21 12:00:02 | `20260621120002_add_online_enabled_column.sql` | 1.2K |
| 2026-06-21 12:00:03 | `20260621120003_fix_duplicate_order_notifications_final.sql` | 2.9K |
| 2026-06-24 00:00:00 | `20260624000000_fix_admin_order_courier_info.sql` | 1.3K |
| 2026-06-24 00:00:00 | `20260624000001_fix_all_rls_and_data.sql` | 6.4K |
| 2026-06-24 00:00:00 | `20260624000002_fix_commission_trigger.sql` | 3.6K |
| 2026-06-24 00:00:00 | `20260624000003_fix_courier_order_assignment.sql` | 1.3K |
| 2026-07-02 00:00:00 | `20260702000000_app_animation_settings.sql` | 1.8K |
| 2026-07-09 00:00:01 | `20260709000001_CREATE_CANCELLATION_REQUESTS.sql` | 7.2K |
| 2026-07-09 00:00:02 | `20260709000002_CANCELLATION_RPCS.sql` | 14.5K |
| 2026-07-09 00:00:04 | `20260709000004_ADMIN_CANCEL_WITH_REFUND_RPC.sql` | 7.4K |
| 2026-07-09 00:00:05 | `20260709000005_BALANCE_REFUND_FIX.sql` | 6.5K |
| 2026-07-09 00:00:05 | `20260709000006_TRANSFER_SENDER_NAME.sql` | 1.7K |
| 2026-07-09 00:00:06 | `20260709000007_TRANSFER_RPC_REVOKE_PUBLIC.sql` | 2.8K |
| 2026-07-10 00:00:01 | `20260710000001_add_invoice_info.sql` | 2.9K |
| 2026-07-10 00:00:02 | `20260710000002_FIX_ADMIN_VIEW_SECURITY_INVOKER.sql` | 1.6K |
| 2026-07-10 00:00:03 | `20260710000003_smm_integration.sql` | 8.5K |
| 2026-07-10 00:00:04 | `20260710000004_smm_fixes.sql` | 766B |
| 2026-07-10 12:00:01 | `20260710120001_fix_admin_view_security.sql` | 1.8K |
| 2026-07-13 00:00:01 | `20260713000001_smm_earnings.sql` | 668B |
| 2026-07-13 00:00:02 | `20260713000002_smm_digital_commission.sql` | 249B |
| 2026-07-14 00:00:01 | `20260714000001_fix_balance_transactions_check.sql` | 1.9K |
| 2026-07-15 00:00:01 | `20260715000001_restrict_balance_rls_to_service_role.sql` | 783B |
| 2026-07-15 00:00:02 | `20260715000002_add_shop_digital_warning_note.sql` | 324B |
| 2026-07-15 00:00:03 | `20260715000003_bump_force_update_min_version.sql` | 296B |
| 2026-07-15 00:00:04 | `20260715000004_digital_max_orders_per_user.sql` | 3.0K |
| 2026-07-15 00:00:05 | `20260715000005_digital_order_reviews.sql` | 3.0K |
| 2026-07-15 00:00:06 | `20260715000006_ad_reward_system.sql` | 3.9K |
| 2026-07-15 00:00:07 | `20260715000007_ad_reward_random_range.sql` | 938B |
| 2026-07-15 00:00:08 | `20260715000008_ad_settings_card_description.sql` | 190B |
| 2026-07-19 00:00:01 | `20260719000001_task_earning_system.sql` | 10.3K |
| 2026-07-19 00:00:02 | `20260719000002_task_earning_rls_rpc.sql` | 27.9K |
| 2026-07-19 00:00:03 | `20260719000003_fix_get_active_tasks_signature.sql` | 3.1K |
| 2026-07-19 00:00:04 | `20260719000004_task_images.sql` | 3.0K |
| 2026-07-19 00:00:05 | `20260719000005_add_image_url_to_get_active_tasks.sql` | 2.8K |
| 2026-07-20 00:00:01 | `20260720000001_fix_screenshot_url_nullable.sql` | 387B |
| 2026-07-20 00:00:02 | `20260720000002_task_multi_images.sql` | 2.9K |
| 2026-07-20 00:00:03 | `20260720000003_fix_admin_get_task_submissions_ambiguous_id.sql` | 2.5K |
| 2026-07-20 00:00:03 | `20260720000004_grant_ad_reward_atomic_rpc.sql` | 5.8K |
| 2026-07-20 00:00:04 | `20260720000005_add_task_notification_types.sql` | 1.8K |
| 2026-07-20 00:00:05 | `20260720000006_suspicious_users.sql` | 1.6K |
| 2026-07-22 00:00:01 | `20260722000001_review_reminder_dismiss_db.sql` | 3.5K |
| 2026-07-22 00:00:02 | `20260722000002_approve_existing_shops.sql` | 450B |
| 2026-07-22 00:00:03 | `20260722000003_fix_coupon_validation.sql` | 3.7K |
| 2026-07-22 00:00:04 | `20260722000004_buy2_get1_balance_campaign.sql` | 1.9K |
| 2026-07-22 00:00:05 | `20260722000005_courier_delivery_cards.sql` | 2.8K |
| 2026-07-22 00:00:06 | `20260722000006_courier_requests_fix.sql` | 1.2K |
| 2026-07-22 00:00:07 | `20260722000007_courier_complete.sql` | 2.9K |
| 2026-07-23 00:00:00 | `20260723000000_courier_package_pricing.sql` | 982B |
| 2026-07-23 00:01:00 | `20260723000100_courier_extras.sql` | 240B |
| 2026-07-23 00:01:01 | `20260723000101_courier_balance_type.sql` | 146B |
| 2026-07-23 00:02:00 | `20260723000200_courier_settings_admin_update.sql` | 343B |
| 2026-07-23 00:03:00 | `20260723000300_add_package_notification_types.sql` | 1.4K |
| 2026-07-23 00:04:00 | `20260723000400_add_courier_location_tracking.sql` | 796B |
| 2026-07-23 00:05:00 | `20260723000500_courier_earnings_package_support.sql` | 637B |
| 2026-07-24 00:00:00 | `20260724000000_fix_linter_warnings.sql` | 4.3K |
| 2026-07-24 00:00:01 | `20260724000001_notify_admin_on_task_claim.sql` | 3.3K |
| 2026-07-24 00:00:02 | `20260724000002_show_paused_completed_tasks.sql` | 3.0K |
| 2026-07-24 00:00:03 | `20260724000003_add_courier_realtime_tracking.sql` | 2.0K |
| 2026-07-24 00:00:04 | `20260724000004_courier_service_notices.sql` | 2.8K |
| 2026-07-25 00:00:01 | `20260725000001_sehirici_services.sql` | 32.9K |
| 2026-07-25 00:00:02 | `20260725000002_add_driver_role.sql` | 3.3K |
| 2026-07-25 00:00:03 | `20260725000003_sehirici_admin_crud.sql` | 9.7K |
| 2026-07-25 00:00:04 | `20260725000004_sehirici_route_and_settings_fix.sql` | 3.3K |
| 2026-07-25 00:00:05 | `20260725000005_sehirici_road_route_cache.sql` | 3.8K |
| 2026-07-26 00:00:01 | `20260726000001_news_system.sql` | 20.9K |
| 2026-07-26 00:00:02 | `20260726000002_fix_news_rls_auth_users.sql` | 7.6K |
| 2026-07-26 12:00:01 | `20260726120001_flash_sale_and_price_alert_setup.sql` | 13.4K |
| 2026-07-26 12:00:02 | `20260726120002_live_shopping_setup.sql` | 10.5K |
| 2026-07-27 00:00:01 | `20260727000001_news_published_at_trigger.sql` | 2.4K |
| 2026-07-27 00:00:02 | `20260727000002_fix_advisor_security_performance.sql` | 11.7K |
| 2026-07-27 00:00:03 | `20260727000003_optimize_rls_auth_initplan.sql` | 13.0K |
| 2026-07-27 00:00:04 | `20260727000004_fix_plpgsql_lint_errors.sql` | 17.8K |
| 2026-07-27 00:00:05 | `20260727000005_fix_news_images_storage_rls.sql` | 2.1K |
| 2026-07-27 00:00:06 | `20260727000006_fix_news_comments_insert_rls.sql` | 986B |
| 2026-07-27 00:00:07 | `20260727000007_add_home_news_limit.sql` | 1.1K |
| 2026-07-27 00:00:08 | `20260727000008_harden_balance_rpc_permissions.sql` | 5.5K |
| 2026-07-27 00:00:09 | `20260727000009_secure_iyzico_credentials.sql` | 468B |
| 2026-07-29 00:00:01 | [`20260729000001_secure_ai_api_keys.sql`](migrations/20260729000001_secure_ai_api_keys.sql) | 3.4K |
| 2026-07-29 00:00:03 | [`20260729000003_get_sehirici_trip_path.sql`](migrations/20260729000003_get_sehirici_trip_path.sql) | 1.2K |
| 2026-07-29 00:00:04 | [`20260729000004_fraud_detection_system.sql`](migrations/20260729000004_fraud_detection_system.sql) | 12.4K |
| 2026-07-29 00:00:04 | [`20260729000005_news_engagement_notifications_and_analytics.sql`](migrations/20260729000005_news_engagement_notifications_and_analytics.sql) | 8.4K |
| 2026-07-30 00:00:01 | [`20260730000001_cart_flash_sale_columns.sql`](migrations/20260730000001_cart_flash_sale_columns.sql) | 1.5K |
| 2026-07-30 00:00:02 | [`20260730000002_admob_reward_points_system.sql`](migrations/20260730000002_admob_reward_points_system.sql) | 51.3K |

## Legacy adli aktif SQL dosyalari (22)

Bu dosyalar [`supabase/migrations/`](migrations/) altinda aktiftir ancak adlari `^\d{14}_` kuralina uymadigi icin yukaridaki 292 standard migration sayimina ve mevcut manifest uretici betiklerine dahil degildir. Yeniden adlandirma veya uygulama durumu bu dokumantasyon gorevinin disindadir.

- `20260101000000_ai_chat_provider_update.sql`
- `20260101000001_ai_chat_security_fix.sql`
- `20260101000002_ai_chat_system.sql`
- `20260126000000_account_deletion_rpc.sql`
- `20260621000006_ADD_BALANCE_NOTIFICATION.sql`
- `20260621000007_CREATE_BALANCE_SYSTEM.sql`
- `20260623000000_ADD_PAYMENT_METHOD_BALANCE.sql`
- `20260624000004_ADD_ADMIN_BALANCE_BANK_SETTINGS.sql`
- `20260624000005_CREATE_BANK_ACCOUNTS_TABLE.sql`
- `20260625000000_ADD_CARD_TOPUP_ENABLED_SETTING.sql`
- `20260626000000_FIX_BALANCE_NOTIFICATION_TRIGGER.sql`
- `20260626000001_REMOVE_BALANCE_NOTIFICATION_TRIGGER.sql`
- `20260628000000_enrich_deduct_from_balance_rpc.sql`
- `20260629000000_FIX_BALANCE_TOPUP_RACE_CONDITION.sql`
- `20260630000000_FIX_CALLBACK_IDEMPOTENCY_RPC.sql`
- `20260630000001_FIX_COMPLETE_ONLINE_PAYMENT_IDEMPOTENT.sql`
- `20260630000002_PREVENT_DUPLICATE_TOKEN.sql`
- `20260707000000_DEDUCT_FROM_BALANCE_ENRICHED.sql`
- `20260707000001_FIX_ADMIN_VIEWS_SECURITY_DEFINER.sql`
- `20260707000002_NOTIFICATIONS_AND_BALANCE_FIX.sql`
- `20260708000000_FIX_SELLER_EARNINGS_TRIGGER.sql`
- `20260710000000_BALANCE_TOPUP_SECURITY_FIX.sql`
