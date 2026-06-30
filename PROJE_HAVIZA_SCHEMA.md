# PROJE_HAVIZA_SCHEMA

Son güncelleme: 2026-06-29  
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

### 2.8 Kurye
- `courier_settings`, `courier_requests`, `courier_assignments`, `courier_earnings`, `courier_payment_info`, `courier_payout_requests`, `courier_status_changes`

### 2.9 AI
- `ai_settings`, `ai_conversations`, `ai_messages`, `ai_daily_usage`, `ai_quick_prompts`, `ai_prompt_images`

### 2.10 Destek / Sistem
- `support_tickets`, `support_ticket_messages`, `faqs`
- `user_reports`, `report_rate_limit`, `audit_log`
- `app_settings`, `app_about_settings`, `system_settings`, `api_settings`, `email_settings`
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