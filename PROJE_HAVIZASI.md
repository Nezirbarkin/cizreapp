# PROJE_HAVIZA

Son güncelleme: 2026-06-29  
Supabase Project Ref: `xsbukxkgtmdyickknqzf`

## 1) Şema Özeti

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

## 2) Public Şemasındaki Ana Tablolar

### Kullanıcı / Profil / Sosyal
- `profiles`
- `follows`
- `follow_requests`
- `blocked_users`
- `notifications`
- `notification_preferences`
- `notification_tokens`
- `profile_views`
- `post_views`

### Post / Story / Yorum
- `posts`
- `post_likes`
- `post_comments`
- `post_saves`
- `post_favorites`
- `post_reports`
- `stories`
- `story_views`
- `story_likes`
- `comment_mentions`

### Mağaza / Ürün / Sipariş
- `categories`
- `shops`
- `shop_subscribers`
- `shop_views`
- `products`
- `product_views`
- `product_favorites`
- `cart`
- `cart_items`
- `orders`
- `order_items`
- `addresses`
- `campaigns`
- `daily_deals`

### Kupon / Değerlendirme
- `coupons`
- `shop_coupons`
- `coupon_usages`
- `shop_reviews`
- `product_reviews`
- `product_review_helpful`

### Destek / Raporlama
- `support_tickets`
- `support_ticket_messages`
- `user_reports`
- `report_rate_limit`
- `audit_log`

### Kurye / Ödeme / Bakiye / Finans
- `courier_settings`
- `courier_requests`
- `courier_assignments`
- `courier_earnings`
- `courier_payment_info`
- `courier_payout_requests`
- `courier_status_changes`
- `payment_transactions`
- `seller_bank_accounts`
- `payout_requests`
- `payout_transactions`
- `seller_earnings`
- `seller_withdrawals`
- `user_balances`
- `balance_transactions`
- `bank_accounts`

### Grup Mesajlaşma
- `groups`
- `group_members`
- `group_join_requests`
- `group_messages`
- `group_message_reads`
- `group_message_read_receipts`

### AI Modülü
- `ai_settings`
- `ai_conversations`
- `ai_messages`
- `ai_daily_usage`
- `ai_quick_prompts`
- `ai_prompt_images`

### Sistem / Ayarlar / OTP
- `app_settings`
- `app_about_settings`
- `system_settings`
- `api_settings`
- `email_settings`
- `verification_codes`
- `registration_otps`
- `password_reset_otps`
- `account_deletion_codes`
- `push_notifications`
- `achievements`
- `user_achievements`
- `user_unlocked_achievements`
- `return_requests`

## 3) Auth Şeması (Supabase Yönetilen)

- `auth.users`
- `auth.identities`
- `auth.sessions`
- `auth.refresh_tokens`
- `auth.one_time_tokens`
- `auth.instances`
- `auth.audit_log_entries`
- `auth.schema_migrations`
- `auth.mfa_factors`
- `auth.mfa_challenges`
- `auth.mfa_amr_claims`
- `auth.sso_providers`
- `auth.sso_domains`
- `auth.saml_providers`
- `auth.saml_relay_states`
- `auth.flow_state`
- `auth.oauth_clients`
- `auth.oauth_authorizations`
- `auth.oauth_consents`
- `auth.oauth_client_states`
- `auth.custom_oauth_providers`
- `auth.webauthn_credentials`
- `auth.webauthn_challenges`

## 4) Storage Şeması

- `storage.buckets`
- `storage.objects`
- `storage.migrations`
- `storage.s3_multipart_uploads`
- `storage.s3_multipart_uploads_parts`
- `storage.buckets_analytics`
- `storage.buckets_vectors`
- `storage.vector_indexes`

## 5) Realtime Şeması

- `realtime.messages`
- `realtime.subscription`
- `realtime.schema_migrations`
- Partition tabloları: `realtime.messages_YYYY_MM_DD` (günlük)

## 6) Edge Functions (aktif)

- `send-push-notification`
- `rapid-responder`
- `quick-function`
- `request-account-deletion`
- `delete-account`
- `quick-worker`
- `send-order-email`
- `rapid-service`
- `bright-processor`
- `send-email`
- `iyzico-payment-init`
- `iyzico-payment-callback`
- `send-verification-code`
- `send-registration-otp`
- `send-password-reset-otp`
- `reset-password-with-otp`
- `send-push`
- `ai-chat-proxy`
- `get-balance`
- `create-balance-topup`
- `confirm-balance-topup`
- `use-balance-for-order`
- `refund-to-balance`
- `request-withdrawal`
- `process-withdrawal`
- `get-transaction-history`
- `get-seller-earnings`
- `admin-add-balance`
- `admin-deduct-balance`

## 7) RLS Notu

Projede çok sayıda RLS policy mevcut (public, auth, storage dahil).  
Özellikle `profiles`, `orders`, `products`, `messages`, `groups`, `ai_*` ve `storage.objects` üzerinde detaylı policy’ler tanımlı.

## 8) AI Asistanına Kullanım Talimatı

Bu dosyayı okuyup işlem yaparken:
1. Önce ilgili şemayı/tabloyu tespit et.
2. Varsa RLS etkisini kontrol et.
3. Yazma işlemlerinde (INSERT/UPDATE/DELETE) FK ilişkilerini bozma.
4. Üretilecek migration’larda mevcut tablo/kolon adlarını koru.
5. `auth`, `storage`, `realtime` sistem tablolarına değişiklik önerirken ekstra dikkatli ol.

## 9) Güncelleme Rutini

Her şema değişikliğinden sonra bu dosyayı güncelle:
- Yeni tablo/kolon eklendi mi?
- Yeni policy eklendi mi?
- Yeni edge function deploy edildi mi?
- Deprecated alanlar var mı?