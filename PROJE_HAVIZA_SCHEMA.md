# PROJE_HAVIZA_SCHEMA

Son güncelleme: 2026-07-30
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
  - `mark_messages_as_read` (2026-07-09 FIX): reader yalnızca KENDİ conv'unda partner mesajlarını is_read=true yapar + KENDİ conv'unun unread_count=0 yapar. PARTNER conv'una DOKUNMAZ. (Eski sürüm partner conv'unu da unread_count=0 yapıyordu → B sohbeti açıkken A'nın rozeti saniyede sönüyordu; asıl kök neden 2026-07-09). Detay: PROJE_HAVIZA_FUNCTIONS.md §2.6.
  - `message_replicate_to_recipient` trigger KALDIRILDI (2026-07-09): `send_message_with_recipient` RPC zaten iki kopya eklediği için çift kopya + is_read karışıklığı yapıyordu.
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
- 2026-07-15: `orders.total` için DB seviyesinde CHECK yok (zaten 0'a izin veriyordu). Uygulama tarafında kullanıcı başı ücretsiz (0 TL) sipariş limiti eklendi — `OrderService.freeOrderLimitPerUser` (varsayılan 1), `order_service.dart::createOrder` içinde `total <= 0` ise mevcut 0 TL sipariş sayısı kontrol edilir. DB'de ayrı bir constraint/trigger yok, kontrol tamamen Dart tarafında.

### 2.6 Kupon / İnceleme
- `coupons`, `shop_coupons`, `coupon_usages`
- `shop_reviews`, `product_reviews`, `product_review_helpful`

### 2.7 Ödeme / Finans
- `payment_transactions`
- `user_balances`, `balance_transactions`
  - 2026-07-15: `balance_transactions_amount_check` gevşetildi (`amount > 0` → `amount >= 0`) — checkout akışında 0 TL bakiye işlemlerine izin verir (bkz. §2.5 not, madde 5 "0 TL sipariş" özelliği). `fee >= 0` constraint'i de teyit edildi. Migration: `20260714000001_fix_balance_transactions_check.sql`.
- `seller_bank_accounts`, `payout_requests`, `payout_transactions`, `seller_earnings`, `seller_withdrawals`
- `bank_accounts`
- `transfer_confirmations` (20260705 — havale onay akışı: pending/approved/rejected + admin_id + admin_note + balance_added + user_notified)
- [`ad_settings`](supabase/migrations/20260730000002_admob_reward_points_system.sql:17) (2026-07-30 güncel sözleşme): 2026-07-15 tarihli TL reklam kolonları tarihsel uyumluluk/audit için şemada kalır; yeni ödül yolu tam sayı puan alanlarını ve rollout flag'lerini kullanır. Eklenen alanlar: `reward_min_points`, `reward_max_points`, `max_daily_reward_points`, `points_per_try`, `reward_policy_version`, `reward_feature_mode`, `reward_points_schema_ready`, `reward_points_earn_enabled`, `reward_points_ssv_required`, `reward_points_ssv_enabled`, `reward_points_spend_enabled`, `reward_points_eligible_products_enabled`, `reward_points_admin_reporting_enabled`, `legacy_ad_tl_grant_disabled`, `migration_cutover_at`, `fraud_hash_retention_days`. Migration başlangıçta `is_enabled=false`, earn/spend kapalı ve `legacy_ad_tl_grant_disabled=true` yazar.
- [`ad_reward_views`](supabase/migrations/20260730000002_admob_reward_points_system.sql:230) artık yeni kredi kaynağı değildir. `reward_points`, `point_ledger_entry_id`, `reward_session_id`, `legacy_grandfathered` alanları eklenmiştir; cutover öncesi başarılı ve pozitif TL kayıtları `legacy_grandfathered=true` olarak işaretlenir. Eski TL değeri kullanıcıdan geri alınmaz, fakat puana kopyalanmaz ve yeni puan yaratmaz.

#### 2.7a AdMob SSV / Puan Defteri — 2026-07-30

Tek kaynak additive migration: [`20260730000002_admob_reward_points_system.sql`](supabase/migrations/20260730000002_admob_reward_points_system.sql:1). Yeni nesneler:

- [`reward_points_config_audit`](supabase/migrations/20260730000002_admob_reward_points_system.sql:61): admin ayar değişikliğinin eski/yeni JSON snapshot'ı, gerekçesi ve admin kimliği.
- [`user_point_accounts`](supabase/migrations/20260730000002_admob_reward_points_system.sql:73): kullanıcı başına tam sayı bakiye projection'ı; `balance_points`, yaşam boyu kazanılan/harcanan/iade edilen toplamlar ve `version`. Bakiye negatif olamaz.
- [`point_ledger_entries`](supabase/migrations/20260730000002_admob_reward_points_system.sql:84): unique `idempotency_key` taşıyan append-only puan defteri. Tip/yön ve önce-sonra bakiye matematiği CHECK ile korunur; metadata içinde ham IP, cihaz kimliği, imza, raw query veya ham provider kullanıcı kimliği yasaktır. [`point_ledger_reject_update_delete`](supabase/migrations/20260730000002_admob_reward_points_system.sql:135) ve [`point_ledger_reject_truncate`](supabase/migrations/20260730000002_admob_reward_points_system.sql:139) trigger'ları UPDATE/DELETE/TRUNCATE işlemlerini reddeder.
- [`ad_reward_sessions`](supabase/migrations/20260730000002_admob_reward_points_system.sql:148): kullanıcı + client idempotency anahtarıyla 30 dakikalık SSV oturumu; nonce yalnız 64 haneli hash olarak, opsiyonel cihaz/ağ sinyalleri yalnız 64 haneli HMAC takma değer olarak tutulabilir. Durumlar: `initiated`, `pending_ssv`, `verified`, `credited`, `blocked`, `rejected`, `duplicate`, `expired`.
- [`ad_reward_ssv_events`](supabase/migrations/20260730000002_admob_reward_points_system.sql:173): bir oturuma bir doğrulanmış AdMob olayı. Edge Function ham transaction id yerine deterministik HMAC'ı hem `provider_transaction_id` hem `provider_transaction_hash` girdisi olarak verir. Kalıcı metadata; HMAC provider kimlikleri, ad-unit, key-id, callback zamanı, doğrulama durumu ve retention zamanıdır; ham query/imza/IP/cihaz kolonu yoktur.
- [`ad_reward_daily_budgets`](supabase/migrations/20260730000002_admob_reward_points_system.sql:195): UTC gününe göre atomik `granted_points` ve `grant_count` bütçe bucket'ı.
- [`reward_points_migration_audits`](supabase/migrations/20260730000002_admob_reward_points_system.sql:202): cutover anındaki tarihsel TL reklam sayısı/tutarı ve bağlı/bağsız bakiye işlem sayılarını kaydeder. Varsayılan not açıkça “Grandfathered TL retained; no point backfill performed.” der.
- [`digital_order_refunds`](supabase/migrations/20260730000002_admob_reward_points_system.sql:306): sipariş + idempotency anahtarına göre tekil, kümülatif brüt hedefli kaynak-koruyan iade olayı; puan ve TL transaction bağlantıları ayrıdır.
- Güvenli okuma view'ları: [`reward_points_public_config`](supabase/migrations/20260730000002_admob_reward_points_system.sql:904) yalnız istemcinin ihtiyaç duyduğu puan config alanlarını; [`my_ad_reward_sessions`](supabase/migrations/20260730000002_admob_reward_points_system.sql:911) ise `security_invoker=true` ile kullanıcının RLS kapsamındaki session durumunu açar.

**Puan → nakit izolasyonu:** Çekirdek [`user_point_accounts`](supabase/migrations/20260730000002_admob_reward_points_system.sql:73) ve [`point_ledger_entries`](supabase/migrations/20260730000002_admob_reward_points_system.sql:84) depolamasından [`user_balances`](supabase/migrations/20260730000002_admob_reward_points_system.sql:646) veya [`balance_transactions`](supabase/migrations/20260730000002_admob_reward_points_system.sql:671) depolamasına FK yoktur. Composition audit tablosu [`digital_order_refunds`](supabase/migrations/20260730000002_admob_reward_points_system.sql:306), puan iadesini ledger FK'siyle ve TL iadesini balance-transaction FK'siyle ayrı kolonlarda izler; bu bağlantılar kaynak muhafazası içindir ve puanı nakde çevirmez. Puan için çekim, IBAN, transfer, fiziksel sipariş veya satıcıya puan aktarma nesnesi/RPC'si yoktur. TL tablosuna yalnız dijital siparişin kalan `cash_balance_paid_try` bileşeni ve bu bileşenin iadesi yazılır.
- `task_categories` (2026-07-19, YENİ): Görev kategorileri — Instagram/YouTube/TikTok/X/Facebook/Uygulama/Anket/Diğer. RLS: public SELECT, yalnız admin INSERT/UPDATE/DELETE.
- `tasks` (2026-07-19, YENİ): Admin tarafından oluşturulan görevler — başlık, açıklama, uyarı metni, link, ödül tutarı (NUMERIC 12,2, CHECK > 0), katılımcı limiti (INT CHECK > 0), başlangıç/süre sonu tarihi, durum (`task_status` enum: draft/active/paused/completed/archived). `current_participants` sayacı RPC ile atomik artır/azalt (trigger yok). RLS: kullanıcı yalnız aktif+başlamış+süresi geçmemiş görür; admin hepsini.
- `task_submissions` (2026-07-19, YENİ): Kullanıcı başvuruları — `task_id`, `user_id`, `screenshot_url` (TEXT NOT NULL), `user_note`, durum (`task_submission_status` enum: pending/approved/rejected), `reward_amount`, `balance_txn_id` (FK balance_transactions), `reviewed_by/at`, `rejection_reason`. **KRİTİK**: partial unique index `(task_id, user_id) WHERE status IN ('pending','approved')` — aynı kullanıcı aynı göreve yalnız 1 kez katılabilir (rejected sonrası tekrar). RLS: kullanıcı yalnız kendininkini görür (admin hepsini); INSERT yalnız kendi `user_id` ile pending; UPDATE pending aşamasında kullanıcı kendi ekran görüntüsünü değiştirebilir. Migration: `20260719000001_task_earning_system.sql` + `20260719000002_task_earning_rls_rpc.sql`.
- `task_screenshots` Storage bucket (2026-07-19): 5 MB limit, jpeg/png/webp. Dosya yolu `user_id/submissionId_timestamp.ext` (cache-bust). RLS: SELECT public, INSERT/UPDATE yalnız `(storage.foldername(name))[1] = auth.uid()` klasörü, DELETE sahibi veya admin.
- `task_images` Storage bucket (2026-07-19, YENİ): 5 MB limit, public, jpeg/png/webp — admin tarafından yüklenen görev açıklama görselleri. RLS: SELECT public (kullanıcılar görüntüler), INSERT/UPDATE/DELETE yalnız admin (`profiles.role='admin'` kontrolü ile). Migration: `20260719000004_task_images.sql`.
- `tasks.image_url` (2026-07-19, YENİ): Admin tarafından yüklenen görev görseli public URL'si. NULL olabilir. `get_active_tasks` RPC'si migration 5 ile genişletildi (image_url döner). Migration: `20260719000005_add_image_url_to_get_active_tasks.sql`.
- `balance_transaction_type` enum'una `task_reward` (Görev ödülü) eklendi (2026-07-19). `ad_reward` zaten mevcuttu.
- Realtime: `task_submissions` ve `tasks` `supabase_realtime` publication'a eklendi — admin dashboard canlı güncellenir.

### 2.8 Kurye
- `courier_settings`, `courier_requests`, `courier_assignments`, `courier_earnings`, `courier_payment_info`, `courier_payout_requests`, `courier_status_changes`

### 2.9 AI
- `ai_settings`, `ai_conversations`, `ai_messages`, `ai_daily_usage`, `ai_quick_prompts`, `ai_prompt_images`

### 2.9b SMM (Dijital Ürün / Sosyal Medya Panel) — 2026-07-10/13
- `smm_providers`: `id`, `owner_type` (enum `smm_owner_type`: admin|seller), `owner_id` (admin→profiles.id, seller→shops.id), `name`, `api_url` (varsayılan `https://smmget.com/api/v2`), `api_key` (SADECE service_role okur, client'a hiç dönmez), `is_active`. Admin kendi panelini veya satıcı kendi panelini tanımlayabilir (satıcı için `shops.can_use_own_smm_api=true` şartı).
- [`digital_orders`](supabase/migrations/20260730000002_admob_reward_points_system.sql:253): bağımsız SMM sipariş kaydının mevcut alanlarına `request_idempotency_key`, `gross_total_try`, `points_spent`, `points_per_try_snapshot`, `points_discount_try`, `cash_balance_paid_try`, `point_debit_entry_id`, `payment_composition_version`, `refund_points_total`, `refund_cash_total_try`, `refund_gross_total_try`, `reconciliation_status` eklenmiştir. Eski siparişler `gross_total_try=total_price`, `cash_balance_paid_try=total_price`, `points_spent=0`, oran snapshot'ı `100` ile backfill edilir. [`digital_orders_payment_composition_check`](supabase/migrations/20260730000002_admob_reward_points_system.sql:286) migration'da `NOT VALID` eklenmiştir; yeni/değişen satırlarda brüt = puan indirimi + TL, puan/FK tutarlılığı ve kümülatif iade üst sınırlarını uygular, fakat migration tarihsel satırlar için ayrıca `VALIDATE CONSTRAINT` çalıştırmaz.
- [`products`](supabase/migrations/20260730000002_admob_reward_points_system.sql:248) mevcut SMM alanlarına ek olarak `is_points_eligible` (varsayılan `false`) ve `max_points_coverage_percent` (`0..100`, varsayılan `100`) taşır. Puan uygunluğu istemci fiyat/composition beyanından değil bu sunucu satırından belirlenir.
- Ödeme composition değişmezi: uygunluk ve spend flag'leri açıksa sunucu mevcut tam sayı puanın dijital indirimini hesaplar, `max_points_coverage_percent` ile sınırlar, önce puanı düşer ve yalnız kalanı TL bakiyeden düşer. Siparişte kullanılan `points_per_try_snapshot` sonraki ayar değişimlerinden bağımsızdır.
- İade composition değişmezi: kümülatif brüt iade hedefinin önce orijinal puan katkısı, sonra orijinal TL katkısı kadar olan bölümü kaynağına döner; `refund_points_total <= points_spent`, `refund_cash_total_try <= cash_balance_paid_try`, `refund_gross_total_try <= gross_total_try`.
- `shops` tablosu genişletildi: `can_use_own_smm_api` BOOLEAN (varsayılan false, sadece admin verebilir — bkz. RLS §4.1.6), `digital_commission_rate` NUMERIC(5,2) (nullable, fiziksel `commission_rate`'den ayrı; NULL ise Edge Function'da %10 varsayılan).
- 2026-07-15: `shops.digital_warning_note` TEXT eklendi (nullable) — satıcının dijital ürünleri için yazdığı, mağazadaki TÜM dijital ürünlerde sabit gösterilen uyarı metni (ürün bazlı değil, mağaza bazlı). `manage_product_screen.dart` yazar, `product_detail_screen.dart` dijital ürün sayfasında turuncu uyarı kutusu olarak gösterir. Migration: `20260715000002_add_shop_digital_warning_note.sql`.

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
- `admin_broadcasts` (20260709 — admin TOPLU duyuruları): id UUID PK, title TEXT, content TEXT, icon_type TEXT (announcement|discount|campaign|news|event|update|warning|gift|info), target_audience TEXT (all/customers/sellers), is_active BOOLEAN, created_by UUID FK auth.users, created_at, expires_at. RLS ON; aktif broadcast'leri her authenticated okur (SELECT is_active=TRUE), sadece admin INSERT/UPDATE/DELETE. Index: (is_active, created_at DESC) WHERE is_active=TRUE. Frontend (`notifications_screen.dart` + `notifications_content_v2.dart`) toplu duyuruları bu tablodan "Duyurular" bölümünde gösterir; kişiye özel admin bildirimleri ayrı `notifications` tablosunda kalır. Migration: `20260709_NOTIFICATION_FIX.sql` Bölüm B.

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
- [`user_point_accounts.user_id -> profiles.id`](supabase/migrations/20260730000002_admob_reward_points_system.sql:73)
- [`point_ledger_entries.user_id -> profiles.id`](supabase/migrations/20260730000002_admob_reward_points_system.sql:84)
- [`ad_reward_sessions.user_id -> profiles.id`](supabase/migrations/20260730000002_admob_reward_points_system.sql:148)
- [`ad_reward_ssv_events.session_id -> ad_reward_sessions.id`](supabase/migrations/20260730000002_admob_reward_points_system.sql:173)
- [`digital_order_refunds.digital_order_id -> digital_orders.id`](supabase/migrations/20260730000002_admob_reward_points_system.sql:306)

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
- [`reward_points_apply_entry(uuid,text,text,bigint,text,uuid,text,jsonb) -> point_ledger_entries`](supabase/migrations/20260730000002_admob_reward_points_system.sql:326) — yalnız owner fonksiyon zincirinin çağırabildiği iç ledger mutasyonu; dış roller ve `service_role` için EXECUTE kapalıdır.
- [`create_ad_reward_session(uuid,text,text,text,text) -> jsonb`](supabase/migrations/20260730000002_admob_reward_points_system.sql:402) — service-role-only SSV oturumu.
- [`grant_verified_ad_points(uuid,text,text,text,text,timestamptz,text,text) -> jsonb`](supabase/migrations/20260730000002_admob_reward_points_system.sql:446) — service-role-only, custom-data nonce bağlı ve idempotent doğrulanmış SSV puan kredisi.
- [`create_digital_order_with_points(uuid,uuid,text,integer,text,boolean) -> jsonb`](supabase/migrations/20260730000002_admob_reward_points_system.sql:576) — service-role-only, önce puan sonra TL composition'lı sipariş rezervasyonu.
- [`refund_digital_order_payment(uuid,numeric,text,text,boolean) -> jsonb`](supabase/migrations/20260730000002_admob_reward_points_system.sql:697) — service-role-only, kümülatif hedef üzerinden puanı puana/TL'yi TL'ye idempotent iade.
- [`set_digital_order_reconciliation(uuid,text) -> void`](supabase/migrations/20260730000002_admob_reward_points_system.sql:798) — service-role-only reconciliation state geçişi.
- [`admin_update_reward_points_config(integer,integer,bigint,integer,text,boolean,boolean,boolean,boolean,text) -> jsonb`](supabase/migrations/20260730000002_admob_reward_points_system.sql:816) — authenticated EXECUTE; içeride admin rol kontrolü, SSV gate'i ve audit insert'i.
- [`purge_expired_reward_fraud_hashes(integer) -> integer`](supabase/migrations/20260730000002_admob_reward_points_system.sql:865) — service-role-only; süresi dolan provider-user/device/network HMAC alanlarını boşaltır.
- Eski [`grant_ad_reward(uuid,text,text,integer)`](supabase/migrations/20260730000002_admob_reward_points_system.sql:964) uyumluluk imzası kredi vermez ve tüm rollerden REVOKE edilmiştir. Eski [`create_digital_order(uuid,uuid,text,integer)`](supabase/migrations/20260730000002_admob_reward_points_system.sql:973) imzasının da tüm rollerden EXECUTE yetkisi kaldırılmıştır.
- `prevent_seller_self_grant_smm()` — satıcının kendi `shops.can_use_own_smm_api` alanını admin onayı olmadan açmasını engelleyen trigger (SECURITY DEFINER; bkz. PROJE_HAVIZA_RLS.md §4.1.6)

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
