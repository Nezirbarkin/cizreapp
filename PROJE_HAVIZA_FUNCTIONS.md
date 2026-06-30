# PROJE_HAVIZA_FUNCTIONS

Son güncelleme: 2026-06-29  
Project Ref: `xsbukxkgtmdyickknqzf`

## 1) Aktif Edge Functions

### 1.1 Bildirim / Email
- `send-push-notification`
- `send-push`
- `send-email`
- `send-order-email`

### 1.2 Auth / OTP / Hesap
- `request-account-deletion`
- `delete-account`
- `send-verification-code`
- `send-registration-otp`
- `send-password-reset-otp`
- `reset-password-with-otp`

### 1.3 Ödeme / Bakiye / Çekim
- `iyzico-payment-init`
- `iyzico-payment-callback`
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

### 1.4 SQL RPC Fonksiyonları (Database)
- `add_to_balance` — bakiye ekleme (topup, refund, commission, adjustment tipleri için)
- `deduct_from_balance` — bakiye düşürme (FOR UPDATE lock, RETURNS TABLE)
- `atomic_add_balance_topup` — atomik bakiye yükleme (HATA-1 düzeltmesi: FOR UPDATE lock + pending kayıt silme + completed kayıt oluşturma)
- `atomic_finalize_payment_transaction` — iyzico callback için atomik ödeme tamamlama (HATA-2 REGRESYON çözümü: SELECT FOR UPDATE + UPDATE WHERE payment_status='pending' + GET DIAGNOSTICS)
- `complete_online_payment` — iyzico callback sonrası sipariş oluşturma

### 1.4 AI / Utility
- `ai-chat-proxy`
- `rapid-responder`
- `rapid-service`
- `quick-function`
- `quick-worker`
- `bright-processor`

## 2) Fonksiyon Grupları ve Bağlı Tablolar (özet)

### 2.1 Iyzico Ödeme Akışı
- init/callback fonksiyonları
- ilişkili tablolar:
  - `payment_transactions`
  - `orders`
  - (opsiyonel) `balance_transactions`

### 2.2 Bakiye Akışı
- topup, confirm, spend, refund, withdraw fonksiyonları
- ilişkili tablolar:
  - `user_balances`
  - `balance_transactions`
  - `orders`
  - `payment_transactions`

### 2.3 Satıcı/Kurye Finans
- earnings, payout, withdrawal süreçleri
- ilişkili tablolar:
  - `seller_earnings`, `payout_requests`, `payout_transactions`, `seller_bank_accounts`
  - `courier_earnings`, `courier_payout_requests`, `courier_payment_info`

### 2.4 Bildirim Akışı
- push/email fonksiyonları
- ilişkili tablolar:
  - `notifications`
  - `push_notifications`
  - `notification_tokens`
  - `support_tickets` / `orders` olayları

### 2.5 AI Akışı
- `ai-chat-proxy`
- ilişkili tablolar:
  - `ai_settings`
  - `ai_conversations`
  - `ai_messages`
  - `ai_daily_usage`

## 3) Operasyon Kuralları

- Her function deploy sonrası:
  1. version artışı kontrol et
  2. `verify_jwt` ayarını doğrula
  3. ilgili tablo RLS etkisini test et
  4. hata logları için edge-function log incelemesi yap

## 4) Güvenlik Notları

- Secret değerleri chat/dokümana yazılmaz.
- Sadece secret isimleri belgelenir (ör. `IYZICO_API_KEY`, `OPENAI_API_KEY`).
- İmza doğrulaması gereken callback endpoint’lerinde verify adımı zorunlu olmalı.

## 5) Değişiklik Günlüğü Şablonu

- `[Tarih] [Function] [Versiyon] [Değişiklik Özeti]`
- Örnek:
  - `2026-06-29 | iyzico-payment-callback | v18 | callback doğrulama ve order status mapping güncellendi`