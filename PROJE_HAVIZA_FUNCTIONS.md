# PROJE_HAVIZA_FUNCTIONS

Son güncelleme: 2026-07-30
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

### 1.3a AdMob SSV / Ödül Puanı — 2026-07-30

- [`admob-reward-session`](supabase/functions/admob-reward-session/index.ts:1) — `POST`, JWT zorunlu. Body yalnız 8–200 karakterlik `idempotency_key` alır; `user_id`, reward, price veya amount istemciden gelirse reddeder. JWT kullanıcı kimliğinden deterministik, dışarıdan tahmin edilemeyen nonce üretir; DB'ye nonce HMAC'ını yazar, SDK'ya `v1.<session>.<nonce>.<MAC>` biçimindeki opaque custom data'yı döndürür. Cihaz/ağ hash alanlarına mevcut uygulamada `null` gönderir.
- [`admob-ssv-callback`](supabase/functions/admob-ssv-callback/index.ts:1) — Google'ın çağırdığı public `GET`; yalnız bu AdMob endpoint'inde [`verify_jwt=false`](supabase/config.toml:13). Public olması doğrulamasız olduğu anlamına gelmez: raw signed query ECDSA P-256/SHA-256 ile doğrulanır; AdMob network id, production/test ad-unit allowlist, timestamp penceresi, key-id ve custom-data MAC zorunludur. Bilinmeyen key veya ilk imza hatasında key cache bir kez refetch edilir; başarısızlıkta kredi yoktur.
- Callback production modunda ham provider transaction id'yi ve varsa provider user id'yi [`hmacSha256Hex()`](supabase/functions/admob-ssv-callback/index.ts:43) ile takma değere çevirir. Ham query, imza, custom data, provider kimliği, JWT veya secret loglanmaz. Test modu protokolü doğrular fakat [`204`](supabase/functions/admob-ssv-callback/index.ts:40) dönerek ekonomik kredi oluşturmaz.
- [`grant-ad-reward`](supabase/functions/grant-ad-reward/index.ts:1) — legacy endpoint; her `POST` için HTTP `410`, `LEGACY_AD_REWARD_ENDPOINT_RETIRED`, `credit_created:false`. İstemci callback'inden TL veya puan üretme yolu yoktur.
- Flutter akışı: [`RewardedAdService.showAndVerify()`](lib/core/services/rewarded_ad_service.dart:244) önce JWT'li session açar, custom data'yı reklam nesnesine bağlar ve SDK callback'ini yalnız “SSV bekleniyor” sinyali sayar. [`RewardVerificationPoller.waitForTerminal()`](lib/core/services/reward_points_service.dart:96) güvenli session view'ını poll eder; ağ hatası/timeout başarı sayılmaz, yalnız server status `credited` ise puan gösterilir.

**Çift fail-closed kapısı:** Edge katmanındaki Google doğrulaması geçmeden DB RPC çağrısı yoktur. [`grant_verified_ad_points(...)`](supabase/migrations/20260730000002_admob_reward_points_system.sql:440) ayrıca service-role claim'i, session/expiry, callback zamanı, ad-unit, user limit/cooldown, günlük bütçe ve earn+SSV+legacy-disable+mode flag'lerini doğrular. Herhangi bir kapı kapanırsa ledger/TL mutasyonu yoktur.

**Secret/env adları:** Değerler repoya yazılmaz. Kesin sözleşme [`supabase/functions/README.md`](supabase/functions/README.md:34) içindedir: Edge runtime tarafından sağlanan `SUPABASE_URL` ve `SUPABASE_SERVICE_ROLE_KEY`; custom secret olarak tanımlanan `ADMOB_SSV_MODE`, `ADMOB_SSV_HASH_SECRET`, `ADMOB_SSV_PUBLIC_KEY_URL`, `ADMOB_SSV_KEY_CACHE_TTL_SECONDS`, `ADMOB_SSV_MAX_AGE_SECONDS`, `ADMOB_SSV_FUTURE_SKEW_SECONDS`, `ADMOB_SSV_PRODUCTION_AD_UNITS`, `ADMOB_SSV_TEST_AD_UNITS` ve `CRON_SECRET`. Flutter production ad-unit define adları [`ADMOB_REWARDED_UNIT_ID_ANDROID`](lib/core/models/ad_settings_model.dart:144) ve [`ADMOB_REWARDED_UNIT_ID_IOS`](lib/core/models/ad_settings_model.dart:147)'tur; boş production değerinde reklam servisi fail-closed davranır.

### 1.4 SQL RPC Fonksiyonları (Database)
- `add_to_balance` — bakiye ekleme (topup, refund, commission, adjustment tipleri için)
- `deduct_from_balance` — bakiye düşürme (FOR UPDATE lock, RETURNS TABLE)
- `atomic_add_balance_topup` — atomik bakiye yükleme (HATA-1 düzeltmesi: FOR UPDATE lock + pending kayıt silme + completed kayıt oluşturma)
- `atomic_finalize_payment_transaction` — iyzico callback için atomik ödeme tamamlama (HATA-2 REGRESYON çözümü: SELECT FOR UPDATE + UPDATE WHERE payment_status='pending' + GET DIAGNOSTICS)
- `complete_online_payment` — iyzico callback sonrası sipariş oluşturma
- `send_message_with_recipient(p_conversation_id, p_content, p_sender_id, p_reply_to_id, p_reply_to_content, p_reply_to_sender_name)` — CHAT mailbox modeli: mesajı HEM gönderenin (is_read=true) HEM alıcının (is_read=false) conversation'ına ekler. RETURNS TABLE created_at/updated_at/is_read(FALSE)/reply alanlarını döndürür. ÖNEMLI: RPC artık conversations'a DOKUNMAZ (unread/last_message tek yetkili = message_insert_trigger). Son sürüm: 20260703_CHAT_UNREAD_BADGE_FIX.sql (20260703_CHAT_SEND_RETURN_FIX.sql'in yerine geçti).
- `update_conversation_on_message()` — `message_insert_trigger` (messages AFTER INSERT). CHAT conversations özeti + unread_count TEK YETKİLİ yöneticisi. Satır-bazlı: NEW.sender_id = conv.user_id → unread=0 (sahip gönderdi); ≠ → unread+=1 (sahip aldı). Yalnızca NEW.conversation_id günceller (çapraz artırım YOK — mailbox'ta her conv'a ayrı satır düşer). Yeni mesaj ilgili taraf için soft-delete'i geri alır. (20260703_CHAT_UNREAD_BADGE_FIX.sql). NOT (2026-07-09): eski `message_replicate_to_recipient` AFTER INSERT trigger (20260701_CHAT_FIX_V2.sql, tek-kopya+çoğaltma modeli) KALDIRILDI — `send_message_with_recipient` RPC zaten iki kopya eklediği için çift kopya + is_read karışıklığı yapıyordu (20260709_NOTIFICATION_FIX.sql Bölüm A).
- `mark_messages_as_read(p_conversation_id)` — CHAT: reader'ın (auth.uid) KENDİ conversation'ında KARŞI tarafın (sender_id=partner) mesajlarını okundu yapar (is_read=true) + KENDİ conv'unun unread_count'unu 0 yapar. PARTNER conversation'ına DOKUNMAZ (eski sürüm partner conv'unu da unread_count=0 yapıyordu → B sohbeti açıkken A'nın rozeti saniyede sönüyordu; ayrıca partner conv'undaki mesajları is_read=true yaparak erken "görüldü" tiki gösteriyordu). Mailbox modeli: her kullanıcı yalnızca KENDİ conv'unda kendi okuma durumunu yönetir; partner mesajı aldıkça trigger +1 yapar, partner sohbeti açınca kendi markMessagesAsRead çağrısı kendi conv'unu sıfırlar. (20260709_MARK_READ_PARTNER_UNREAD_FIX.sql — eski 4-adımlı 20260702_CHAT_READ_RECEIPT_FIX.sql'in YERİNE)

### 1.5 SMM (Dijital Ürün Paneli) — 2026-07-30 composition güncellemesi
- [`smm-order-create`](supabase/functions/smm-order-create/index.ts:1) — JWT auth. İstemciden `price`, `total_price`, `composition` veya `user_id` kabul etmez. `x-idempotency-key`/body anahtarını `smm-create:<jwt-user>:<key>` biçiminde server anahtarına çevirip [`create_digital_order_with_points(...)`](supabase/migrations/20260730000002_admob_reward_points_system.sql:576) çağırır. Ürün/fiyat/uygunluk, önce puan sonra TL dağılımı ve iki bakiye kilidi DB transaction'ındadır.
- Duplicate rezervasyonda mevcut `external_order_id` varsa aynı başarı/composition döner; yoksa sağlayıcıya ikinci belirsiz `add` isteği göndermez ve `reconciliation_pending` döner. Pasif/eksik provider veya sağlayıcının kesin reddi tam composition iadesi oluşturur. Network timeout, parse hatası veya belirsiz HTTP sonucu **hemen iade edilmez**; `reconciliation_pending` olur.
- [`smm-order-manual-status`](supabase/functions/smm-order-manual-status/index.ts:1) — JWT auth; yalnız admin veya provider sahibi satıcı. İstemci fiyat/iade tutarı/composition veremez. Yetkili kesin `canceled|refunded|failed` kararı tam kümülatif iade; `partial` kararı teslim edilmeyen brüt oran kadar kümülatif iade + teslim edilen brüt oran kadar tek satıcı kredisi; `completed` tam satıcı kredisi üretir.
- [`smm-order-status-check`](supabase/functions/smm-order-status-check/index.ts:1) — cron için [`CRON_SECRET`](supabase/functions/README.md:26) veya kullanıcı JWT; cron en fazla 200 pending/in-progress, kullanıcı yalnız kendi siparişlerini kontrol eder. Provider kapalı, timeout, parse/non-OK/error veya statüsüz yanıtta `reconciliation_pending`; yalnız kesin canceled/refunded/partial sonucunda kaynak-koruyan iade, completed/partial sonucunda idempotent satıcı kredisi uygulanır.
- `smm-provider-services` — JWT auth, yetki: admin veya provider sahibi satıcı. Provider `action=services` çağırır, `api_key`'i temizler, `{service, name, category, rate, min, max}` döner.
- `smm-sync-products` — SADECE cron (`x-cron-secret`), önerilen saatlik. Her aktif provider için `action=services` ile mevcut servis ID'lerini alır; `products.smm_provider_id` eşleşen ve `product_type='digital'` ürünleri karşılaştırır. Servis kalkmışsa ve ürün `is_available=true` ise `is_available=false` + `smm_disabled_reason` yazar. Servis geri gelmişse VE ürün bu mekanizmayla kapatılmışsa (`smm_disabled_reason` dolu) otomatik yeniden açar — satıcının manuel kapattığı ürünlere (`smm_disabled_reason` boş) dokunmaz. Aynı turda servisin `min`/`max` değerleri ürünün `min_quantity`/`max_quantity` alanlarıyla karşılaştırılır; fark varsa aralık sağlayıcıya göre güncellenir (aynı aralığa düşen ürünler tek UPDATE'te toplanır, geçersiz/eksik veya `max < min` aralıklar atlanır). Fiyat (`price_per_1000`) satıcının kâr marjını içerdiği için senkronize **edilmez**. Yanıt `rangeUpdated` sayacını da döner.
- Ortak [`refundComposition()`](supabase/functions/_shared/digital_orders.ts:27), [`setReconciliation()`](supabase/functions/_shared/digital_orders.ts:46) ve [`creditSellerOnce()`](supabase/functions/_shared/digital_orders.ts:54) üç function tarafından paylaşılır. İade event anahtarı `provider-outcome:<order>:<status>:<cents>` biçimindedir. İade kümülatif hedeflidir ve puanı puana/TL'yi TL'ye döndürür.
- Satıcı hakedişi puan transferi değildir: immutable `gross_total_try * deliveredRatio` üzerinden komisyon/net TL hesaplanır. Puan indirimi platform promosyon bileşenidir; müşteri puanı satıcı bakiyesine, çekime veya `balance_transactions` reklam geliri olarak aktarılmaz. `seller_credited` optimistic claim'i ikinci worker'ın çift TL kredisi vermesini engeller.
- Eski [`create_digital_order(uuid,uuid,text,integer)`](supabase/migrations/20260730000002_admob_reward_points_system.sql:973) tüm rollerden kapalıdır. Tek güncel rezervasyon imzası service-role-only [`create_digital_order_with_points(...)`](supabase/migrations/20260730000002_admob_reward_points_system.sql:576)'tır.
- Dart: [`SmmService.createDigitalOrder()`](lib/core/services/smm_service.dart:39) response'ta `grossTotalTry`, `pointsSpent`, `pointsDiscountTry`, `cashPaidTry` ayrımını parse eder. [`DigitalOrder`](lib/core/models/digital_order_model.dart:104) brüt/puan/TL snapshot'ları ile kümülatif puan/TL iadelerini ayrı taşır.

### 1.4 AI / Utility
- `ai-chat-proxy`
- `rapid-responder`
- `rapid-service`
- `quick-function`
- `quick-worker`
- `bright-processor`

### 1.6 Görev Yaparak Kazan (Task Earning) — 2026-07-19
- `claim_task(p_task_id UUID) → UUID` (SQL RPC, SECURITY DEFINER): Kullanıcı görevi alır. FOR UPDATE ile görev satırı kilitlenir, current_participants atomik artırılır, max_participants eşitse status otomatik 'completed' olur, pending submission INSERT. Kontroller: status='active', starts_at <= NOW(), expires_at NULL veya > NOW(), aynı kullanıcı pending/approved başvuru YAPMAMIŞ olmalı. Aynı kullanıcı aynı göreve 1 kez katılabilir (partial unique index). RPC REVOKE ALL FROM PUBLIC + GRANT EXECUTE TO authenticated.
- `submit_task_with_proof(p_submission_id UUID, p_screenshot_url TEXT, p_user_note TEXT DEFAULT NULL) → VOID`: Kullanıcı ekran görüntüsünü yükler. UPDATE WHERE user_id=auth.uid() AND status='pending' atomik; FOUND değilse hata. RPC authenticated only.
- `approve_task_submission(p_submission_id UUID, p_admin_note TEXT DEFAULT NULL) → JSONB`: Admin onayı. Önce admin mi kontrol (profiles.role='admin'). Idempotent: status='approved' ise no-op. `add_to_balance(task_reward, reference_type='task')` ile atomik bakiye ekleme. Submission'a reward_amount, balance_txn_id, reviewed_by/at yazılır. Notifications trigger ile kullanıcıya 'task_approved' bildirimi. RPC authenticated + service_role.
- `reject_task_submission(p_submission_id UUID, p_rejection_reason TEXT) → JSONB`: Admin red. Bakiye iade YOK. tasks.current_participants-- (limit geri açılır, status='completed' ise tekrar 'active'). Notifications trigger ile kullanıcıya 'task_rejected' bildirimi. RPC authenticated + service_role.
- `admin_get_task_submissions(p_status, p_task_id, p_limit, p_offset) → TABLE`: Admin için başvuru listesi. profiles JOIN ile full_name/avatar_url/phone, tasks JOIN ile title/reward döner. RPC authenticated + service_role.
- `get_active_tasks(p_category_id, p_limit, p_offset) → TABLE`: Kullanıcı için aktif görevler. user_already_claimed, user_submission_id, user_submission_status kolonlarını da döner. RPC authenticated only.
- `get_user_task_history(p_status, p_limit, p_offset) → TABLE`: Kullanıcının kendi başvuru geçmişi. task_title, reward_amount, rejection_reason, total_earned döner. RPC authenticated only.
- `get_task_stats() → JSONB`: Admin dashboard istatistikleri — total_tasks/active_tasks/completed_tasks/paused_tasks + pending/approved/rejected_submissions + total_paid_today/total_paid_all_time. RPC authenticated + service_role.
- **Idempotency**: (1) Partial unique index çift katılımı engeller; (2) approve_task_submission status='approved' guard → ikinci çağrı no-op; (3) balance_transactions task_reward tekil.
- **Race condition**: claim_task FOR UPDATE ile görev satırı kilitlenir.
- **PROJE_HAVIZA öğrenmeleri**: §4.1.7 (bakiye mutasyonu yalnız service_role üzerinden, RPC SECURITY DEFINER), §4.1.1 (admin kontrolü profiles subquery ile RLS recursion yok), §4.1.5 (trigger fonksiyonu SECURITY DEFINER ama auth.uid() kullanmıyor).
- Dart: `TaskEarningService` (`lib/core/services/task_earning_service.dart`). Modeller: Task, TaskCategory, TaskSubmission, TaskStats. Realtime: subscribeUserSubmissions, subscribeAllSubmissions, subscribeAllTasks.
- UI: `tasks_screen.dart` (TasksScreen + TaskDetailScreen + TaskHistoryScreen), `task_management_content.dart` (3 sekme: Görevler/Başvurular/İstatistikler + görev oluşturma formu), `wallet_screen.dart` mor kart.
- Test: (1) çift claim → 'zaten katıldınız', (2) limit doldu → 'limit dolmuş' + status='completed', (3) approve + tekrar approve → 'already_approved', (4) reject → current_participants azalır, (5) admin realtime badge.

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

### 3.1 AdMob deploy sırası ve callback istisnası

1. Önce additive migration [`20260730000002_admob_reward_points_system.sql`](supabase/migrations/20260730000002_admob_reward_points_system.sql:1) uygulanır; migration earn/spend ve eski TL reklam yolunu güvenli kapalı durumda bırakır.
2. Secret adları, allowlist'ler ve Google key URL'si tanımlanır; gerçek değer dokümana/repoya girmez.
3. JWT'li [`admob-reward-session`](supabase/functions/admob-reward-session/index.ts:1), public fakat Google ECDSA doğrulamalı [`admob-ssv-callback`](supabase/functions/admob-ssv-callback/index.ts:1), daima 410 dönen [`grant-ad-reward`](supabase/functions/grant-ad-reward/index.ts:1), ardından composition-aware [`smm-order-create`](supabase/functions/smm-order-create/index.ts:1), [`smm-order-manual-status`](supabase/functions/smm-order-manual-status/index.ts:1), [`smm-order-status-check`](supabase/functions/smm-order-status-check/index.ts:1) deploy edilir.
4. Yalnız [`admob-ssv-callback`](supabase/config.toml:13) AdMob kapsamında `verify_jwt=false` kalır; session ve diğer kullanıcı endpoint'leri JWT doğrulamayı korur.
5. Observe/test doğrulamasından sonra admin RPC ile sırasıyla SSV, cohort earn, eligible products ve spend açılır. Legacy TL grant rollback sırasında dahi yeniden açılmaz.

Tam komutlar, kill-switch/cutover ve no-backfill runbook'u [`supabase/README.md`](supabase/README.md:1) ile function özel sözleşmesi [`supabase/functions/README.md`](supabase/functions/README.md:1) içinde tutulur.

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
