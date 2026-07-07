# PROJE_HAVIZA_SCHEMA

Son güncelleme: 2026-07-02
Project Ref: `xsbukxkgtmdyickknqzf`

## 1) Şemalar

- `public`
- `auth`
- `storage`
- `realtime`
- `vault`
- `extensions`
- `supabase_migrations`
- `net`
- `graphql`
- `graphql_public`
- `pgbouncer`

## 2) Domain Blokları (public)

### 2.1 Kullanıcı / Profil
- `profiles`
- `notification_preferences`
- `notification_tokens`
- `blocked_users`
- `profile_views`
- `notifications`

### 2.2 Sosyal İçerik
- `posts`, `post_likes`, `post_comments`, `post_saves`, `post_favorites`, `post_views`, `post_reports`
- `stories`, `story_views`, `story_likes`
- `follows`, `follow_requests`
- `comment_mentions`

### 2.3 Mesajlaşma
- 1-1: `conversations`, `messages`, `conversation_participants`
- Grup: `groups`, `group_members`, `group_join_requests`, `group_messages`, `group_message_reads`, `group_message_read_receipts`
- MAILBOX MODELİ (KRİTİK): Her kullanıcının kendi `conversations` satırı vardır (`user_id` = sahip, `other_user_id` = karşı taraf). Her mantıksal mesaj İKİ `messages` satırı olarak saklanır — her iki tarafın conv'unda birer kopya (aynı `sender_id|content|created_at`, farklı `id`). Detay: PROJE_HAVIZA_FUNCTIONS.md §2.6.
  - `conversations.unread_count`: o conv sahibinin okumadığı (sender_id != user_id, is_read=false) mesaj sayısı. TEK YETKİLİ yöneticisi `message_insert_trigger` (satır-bazlı). Sohbet listesi rozeti + yüzen mesaj ikonu bu değerden beslenir. Yeniden hesap: 20260703_CHAT_UNREAD_RECOUNT.sql.
  - `conversations.deleted_for_user_id`: soft-delete; yeni mesaj gelince ilgili taraf için NULL'a döner (sohbet geri gelir).
  - `messages.is_read`: alıcı kopyasında karşı taraf okuyunca true olur (okundu tiki). Gönderenin kendi kopyasında hep true (anlamsız) — okundu bilgisi partner kopyasından okunur.
  - `app_about_settings` banka/bakiye/animasyon kolonları: bkz. §2.10 notu + toJson eşleşmesi.

### 2.4 Ticaret / Katalog
- `categories`, `shops`, `products`
- `campaigns`, `daily_deals`
- `shop_subscribers`, `shop_views`, `product_views`, `product_favorites`

### 2.5 Sepet / Sipariş
- `cart`, `cart_items`
- `orders`, `order_items`
- `addresses`
- `return_requests`

### 2.6 Kupon / İnceleme
- `coupons`, `shop_coupons`, `coupon_usages`
- `shop_reviews`, `product_reviews`, `product_review_helpful`

### 2.7 Ödeme / Finans
- `payment_transactions`
- `user_balances`, `balance_transactions`
- `seller_bank_accounts`, `payout_requests`, `payout_transactions`, `seller_earnings`, `seller_withdrawals`
- `bank_accounts`
- `transfer_confirmations` (20260705 — havale onay akışı: pending/approved/rejected + admin_id + admin_note + balance_added + user_notified)

### 2.8 Kurye
- `courier_settings`, `courier_requests`, `courier_assignments`, `courier_earnings`, `courier_payment_info`, `courier_payout_requests`, `courier_status_changes`

### 2.9 AI
- `ai_settings`, `ai_conversations`, `ai_messages`, `ai_daily_usage`, `ai_quick_prompts`, `ai_prompt_images`

### 2.10 Destek / Sistem
- `support_tickets`, `support_ticket_messages`, `faqs`
- `user_reports`, `report_rate_limit`, `audit_log`
- `app_settings`, `app_about_settings`, `system_settings`, `api_settings`, `email_settings`
  - `app_about_settings` kolonları (Dart `AppAboutSettings.toJson()` ile birebir eşleşmeli):
    temel: `app_name`, `app_slogan`, `app_description`, `app_features`, `contact_email`, `website_url`, `support_phone`, `terms_of_service`, `privacy_policy`, `version_number`, `build_number`, `social_media_links`
    ödeme/iyzico: `online_payment_enabled`, `iyzico_api_key`, `iyzico_secret_key`, `iyzico_api_url`, `global_orders_enabled`
    banka/bakiye: `company_bank_name`, `company_iban`, `company_account_holder`, `balance_enabled`, `card_topup_enabled`, `min_topup_amount`, `max_topup_amount`, `withdrawal_fee_percent`, `min_withdrawal_amount`
    sipariş ödeme yöntemi toggle'ları (20260705): `order_cod_enabled`, `order_card_on_delivery_enabled`, `order_balance_enabled` (`online` için `online_payment_enabled` kolonu kullanılır — tek gerçek kaynak prensibi)
    duyuru: `startup_announcement_enabled`, `startup_announcement_title`, `startup_announcement_message`, `startup_announcement_type`, `startup_announcement_button_text`, `startup_announcement_updated_at`
    diğer: `google_maps_api_key`, `animation_primary_duration_ms`, `animation_secondary_duration_ms`, `animation_transition_duration_ms`
    - NOT: 2026-07-03 tarihinde `company_account_holder` ve banka/bakiye kolonları eksikti (PGRST204). Migration: `20260703_ABOUT_SETTINGS_MISSING_COLUMNS.sql`
- `verification_codes`, `registration_otps`, `password_reset_otps`, `account_deletion_codes`
- `achievements`, `user_achievements`, `user_unlocked_achievements`
- `push_notifications`

## 3) Kritik FK Notları

- `profiles.id -> auth.users.id`
- `shops.owner_id -> profiles.id`
- `products.shop_id -> shops.id`
- `products.category_id -> categories.id`
- `orders.user_id -> profiles.id`
- `orders.shop_id -> shops.id`
- `order_items.order_id -> orders.id`
- `order_items.product_id -> products.id`
- `messages.conversation_id -> conversations.id`
- `group_members.group_id -> groups.id`

### 2.11 SQL Fonksiyonlar (Database)
- `add_to_balance(p_user_id, p_amount, ...)` — bakiye ekleme (topup, refund, commission, adjustment)
- `deduct_from_balance(p_user_id, p_amount, ...)` — bakiye düşürme (FOR UPDATE lock, atomik)
- `atomic_add_balance_topup(p_user_id, p_amount, p_pending_txn_id, ...)` — atomik bakiye yükleme (HATA-1, FOR UPDATE + pending silme + completed insert tek transaction)
- `atomic_finalize_payment_transaction(p_transaction_id, p_payment_id, p_paid_price, ...)` — iyzico callback sonrası atomik ödeme kaydı güncelleme (HATA-2 REGRESYON çözümü: SELECT FOR UPDATE + UPDATE WHERE status='pending' + GET DIAGNOSTICS, RETURNS TABLE)
- `complete_online_payment(p_payment_transaction_id)` — iyzico callback sonrası sipariş oluşturma
- `create_seller_earnings_on_delivery()` — sipariş teslim edildiğinde satıcı kazancı oluşturma (trigger)
- `is_admin()` — admin kontrolü (SECURITY DEFINER, authenticated EXECUTE gerektirir; bkz. PROJE_HAVIZA_RLS.md § 4.1.1)
- `auth_is_admin()` — admin kontrolü (STABLE, SECURITY DEFINER değil; bkz. PROJE_HAVIZA_RLS.md § 4.1.1)
- `sync_assigned_courier_to_order()` — courier ataması yapıldığında orders.assigned_courier_id'yi senkronize eder (trigger, SECURITY DEFINER)

## 4) Sistem Şemaları (özet)

### auth
- Kullanıcı kimlik/session/mfa/oauth/sso/webAuthn tabloları

### storage
- `storage.buckets`, `storage.objects`, multipart ve vector tabloları

### realtime
- `realtime.messages`, `realtime.subscription`, günlük partition tabloları (`realtime.messages_YYYY_MM_DD`)

### net
- `net.http_request_queue`, `net._http_response`

## 5) Asistan Çalışma Notu

- İşlem öncesi tablo + FK + RLS birlikte değerlendirilmeli.
- `auth/storage/realtime` değişiklikleri için migration yaklaşımı tercih edilmeli.