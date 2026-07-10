# PROJE_HAVIZA_FUNCTIONS

Son güncelleme: 2026-07-04
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
- `send_message_with_recipient(p_conversation_id, p_content, p_sender_id, p_reply_to_id, p_reply_to_content, p_reply_to_sender_name)` — CHAT mailbox modeli: mesajı HEM gönderenin (is_read=true) HEM alıcının (is_read=false) conversation'ına ekler. RETURNS TABLE created_at/updated_at/is_read(FALSE)/reply alanlarını döndürür. ÖNEMLI: RPC artık conversations'a DOKUNMAZ (unread/last_message tek yetkili = message_insert_trigger). Son sürüm: 20260703_CHAT_UNREAD_BADGE_FIX.sql (20260703_CHAT_SEND_RETURN_FIX.sql'in yerine geçti).
- `update_conversation_on_message()` — `message_insert_trigger` (messages AFTER INSERT). CHAT conversations özeti + unread_count TEK YETKİLİ yöneticisi. Satır-bazlı: NEW.sender_id = conv.user_id → unread=0 (sahip gönderdi); ≠ → unread+=1 (sahip aldı). Yalnızca NEW.conversation_id günceller (çapraz artırım YOK — mailbox'ta her conv'a ayrı satır düşer). Yeni mesaj ilgili taraf için soft-delete'i geri alır. (20260703_CHAT_UNREAD_BADGE_FIX.sql). NOT (2026-07-09): eski `message_replicate_to_recipient` AFTER INSERT trigger (20260701_CHAT_FIX_V2.sql, tek-kopya+çoğaltma modeli) KALDIRILDI — `send_message_with_recipient` RPC zaten iki kopya eklediği için çift kopya + is_read karışıklığı yapıyordu (20260709_NOTIFICATION_FIX.sql Bölüm A).
- `mark_messages_as_read(p_conversation_id)` — CHAT: reader'ın (auth.uid) KENDİ conversation'ında KARŞI tarafın (sender_id=partner) mesajlarını okundu yapar (is_read=true) + KENDİ conv'unun unread_count'unu 0 yapar. PARTNER conversation'ına DOKUNMAZ (eski sürüm partner conv'unu da unread_count=0 yapıyordu → B sohbeti açıkken A'nın rozeti saniyede sönüyordu; ayrıca partner conv'undaki mesajları is_read=true yaparak erken "görüldü" tiki gösteriyordu). Mailbox modeli: her kullanıcı yalnızca KENDİ conv'unda kendi okuma durumunu yönetir; partner mesajı aldıkça trigger +1 yapar, partner sohbeti açınca kendi markMessagesAsRead çağrısı kendi conv'unu sıfırlar. (20260709_MARK_READ_PARTNER_UNREAD_FIX.sql — eski 4-adımlı 20260702_CHAT_READ_RECEIPT_FIX.sql'in YERİNE)

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
- Satıcı bakiye modeli: TEK GERÇEK KAYNAK `shops` kolonları — `admin_credit` (adminden alacak), `commission_debt` (komisyon borcu), `cash_payment_revenue` (kapıda kazanç), `online_payment_revenue` (online kazanç), `total_collected_cash`, `total_paid`, `pending_payout`, `has_own_courier`. Satıcı "Genel Bakış" (PayoutService.getRevenueSummary) bu kolonları hesapsız okur; `create_seller_earnings_on_delivery()` trigger'ı teslimatta artırır.
- `clear_shop_balance()` — payout_requests UPDATE trigger'ı. CANONICAL sürüm (20260703_PAYOUT_TRIGGER_CONSOLIDATE.sql): approved VEYA paid'e İLK geçişte bir kez settle eder (idempotent): tüm kazanç/alacak/borç kolonları 0, pending_payout -= amount, total_paid += amount, paid_at=NOW(). total_paid'e YALNIZCA bu trigger dokunur (Dart _processPayoutRequest artık shops güncellemez → çift sayım yok). ESKİ çakışan sürümler (20260308000001..., FIX_PAYOUT_APPROVED_CLEAR_REVENUE.sql) ARTIK KULLANILMAMALI.
- Admin hızlı butonları (admin_dashboard_screen "Ödeme İşlemleri", payout_requests'ten bağımsız, shops'u doğrudan yazar): "Ödeme Yapıldı" → admin_credit + online_payment_revenue = 0, total_paid += adminCredit; "Ödeme Alındı" → commission_debt + cash_payment_revenue = 0, total_collected_cash += commissionDebt; "Alacak/Verecek Kapat" → hepsi 0. (2026-07-03)

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

### 2.6 CHAT (Sohbet) Mailbox Modeli — KRİTİK MİMARİ NOTU
- Her mantıksal mesaj İKİ satır olarak saklanır (denormalize per-user mailbox):
  - Gönderenin conversation'ında: `is_read=TRUE`
  - Alıcının conversation'ında: `is_read=FALSE`
  - İki satır aynı `sender_id + content + created_at`, **FARKLI `id`** taşır.
- İki yazma tek RPC ile yapılır: `send_message_with_recipient` (trigger `message_insert_trigger` yalnızca conversations özetini günceller).
- SONUÇLARI (client'ta MUTLAKA uyulmalı):
  1. Tekilleştirme id ile YAPILMAZ (id'ler farklı). Anahtar = `sender_id|content|created_at`.
  2. Kendi gönderdiğin mesajın "okundu" bilgisi SADECE partner kopyasından okunur; kendi kopyanın `is_read`'i her zaman TRUE ve anlamsızdır. Partner kopyası yoksa → okunmadı (false) kabul et.
  3. Okundu işaretleme yalnızca ALICI tarafından: `mark_messages_as_read` (sender_id=partner satırlarını YALNIZCA reader'ın kendi conv'unda true yapar — partner conv'a DOKUNMAZ, bkz yukarı).
- İlgili kod: `chat_service.dart` (getMessages/getConversations dedup), `chat_detail_screen.dart` (_addOrMerge, _dupKey), model `message_model.dart` (messageStatus).
- Geçmiş tuzaklar: getConversations'ta reverseConvs mutasyonu partner-conv lookup'ını bozmuştu (2026-07-03 düzeltildi, `reverseConvIdByPartner`).
- PUSH bildirimi: `notify_direct_message()` trigger'ı (messages AFTER INSERT, 20260703_DM_PUSH_TRIGGER.sql) → net.http_post → Edge Function `send-push-notification` → FCM v1 (`profiles.fcm_token`). ÇİFT PUSH KORUMASI: push yalnızca gönderenin conv kopyasında (conversations.user_id = sender_id) üretilir; alıcı mailbox kopyası atlanır. Grup için ayrı `notify_group_message()` (group_messages).
- Uygulama İÇİ mesaj bildirimi (notifications tablosu) BİLİNÇLİ KAPALI: chat unread badge `conversations.unread_count` ile yönetilir; `notification_service.dart` message/chat tiplerini listeden ve unread sayımından filtreler (20260208000005_remove_chat_notifications.sql). Açılmak istenirse hem trigger'a notifications insert hem UI filtre kaldırma gerekir.

## 3) Operasyon Kuralları

- Her function deploy sonrası:
  1. version artışı kontrol et
  2. `verify_jwt` ayarını doğrula
  3. ilgili tablo RLS etkisini test et
  4. hata logları için edge-function log incelemesi yap

## 4) Güvenlik Notları

- Secret değerleri chat/dokümana yazılmaz.
- Sadece secret isimleri belgelenir (ör. `IYZICO_API_KEY`, `OPENAI_API_KEY`).
- İmza doğrulaması gereken callback endpoint'lerinde verify adımı zorunlu olmalı.

## 4.1 Admin Kontrol Fonksiyonları — Güvenlik Notu (2026-07-02)

İki admin kontrol fonksiyonu mevcuttur ve yetki yapıları farklıdır:

- `public.is_admin()` — SECURITY DEFINER, `postgres` rolü ile çalışır. RLS'den etkilenmez. Ancak `CREATE OR REPLACE FUNCTION` sonrası GRANT'ler KORUNMAZ. `authenticated` rolü için EXECUTE yetkisi **manuel eklenmelidir**: `GRANT EXECUTE ON FUNCTION public.is_admin() TO authenticated;`. `anon` rolünden yetki **iptal edilmelidir**: `REVOKE EXECUTE ON FUNCTION public.is_admin() FROM anon;`. Migration'larda bu GRANT/REVOKE ayrıca yazılmalıdır (otomatik değildir).

- `public.auth_is_admin()` — STABLE, `SECURITY DEFINER` değil. `authenticated` ve `anon` için varsayılan GRANT geçerlidir. SECURITY DEFINER olmadığı için RLS'yi bypass etmez — `profiles` sorgularken kendi RLS policy'si devreye girer.

Kullanım: `profiles_update_own` gibi RLS policy'lerde admin kontrolü için `is_admin()` kullanılır (SECURITY DEFINER sayesinde RLS bypass). Ancak orders policy'lerde doğrudan subquery (`EXISTS(SELECT 1 FROM profiles WHERE id=(SELECT auth.uid()) AND role='admin')`) tercih edilir — helper fonksiyon zinciri recursion/permission riskini önler.

Bkz: PROJE_HAVIZA_RLS.md § 4.1.

## 4.2 Grup Sistemi (group_*) — Güvenlik ve RPC Notları (2026-07-04)

- `is_group_admin(p_group_id, p_user_id)` / `is_group_member(p_group_id, p_user_id)` — SECURITY DEFINER, RLS politikaları ve trigger içinde kullanılan yardımcı fonksiyonlar. Sadece dahili kullanım içindir; `20260704_GROUP_LINTER_SECURITY_FIX.sql` ile PUBLIC/anon/authenticated'dan EXECUTE geri alındı (RPC olarak dışarıdan çağrılamazlar, RLS içinde hâlâ çalışırlar).
- `prevent_group_member_role_self_escalation()` — `group_members` üzerinde BEFORE UPDATE trigger fonksiyonu. `NEW.role IS DISTINCT FROM OLD.role` ve çağıran `is_group_admin` değilse `RAISE EXCEPTION`. Bir üyenin kendi rolünü admin yapmasını (RLS'nin kolon bazlı ayırt edemediği açığı) engeller. Bkz. PROJE_HAVIZA_RLS.md § 4.1.5.
- `admin_add_group_member(p_group_id, p_user_id, p_added_by)` — `p_added_by` parametresi artık GÜVENİLMİYOR (istemci sahte bir admin ID'si gönderebilirdi); fonksiyon içinde `auth.uid()` kullanılıyor. `anon`'dan EXECUTE alındı, sadece `authenticated`.
- `mark_group_messages_read_receipts(p_group_id, p_last_message_id DEFAULT NULL)` — TEK imza (2026-07-04'te 1-parametreli eski sürümle overload çakışması — PGRST203 — giderildi, bkz. changelog). `group_message_read_receipts(message_id, group_id, user_id)` tablosuna insert eder, `group_members.unread_count` sıfırlar.
- Grup fotoğrafı: `uploadGroupImage()` (group_chat_service.dart) artık dosya adına zaman damgası ekliyor (`avatar_{groupId}_{timestamp}.jpg`) — sabit ad kullanıldığında public URL değişmediği için istemci tarafı cache eski görseli göstermeye devam ediyordu. Storage: `public` bucket / `group_images` klasörü, politikalar `20260704_GROUP_RPC_AND_STORAGE_FIX.sql`'de `TO authenticated` ile yeniden oluşturuldu.
- Kanonik/güncel migration dosyaları (bu üçü referans alınmalı, eskiler değil): `20260704_GROUP_SYSTEM_SECURITY_FIX_FINAL.sql`, `20260704_GROUP_RPC_AND_STORAGE_FIX.sql`, `20260704_GROUP_LINTER_SECURITY_FIX.sql`.

## 5) Değişiklik Günlüğü Şablonu

- `[Tarih] [Function] [Versiyon] [Değişiklik Özeti]`
- Örnek:
  - `2026-06-29 | iyzico-payment-callback | v18 | callback doğrulama ve order status mapping güncellendi`