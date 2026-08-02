# PROJE_HAVIZA_RPCS

Son güncelleme: 2026-07-30
Project Ref: `xsbukxkgtmdyickknqzf`

> Bu dosya, **Flutter istemcisinin** Supabase'e yaptığı tüm `.rpc(...)` çağrılarının
> envanteridir. Her RPC için: dosya:satır, kullanım yeri (anon/auth/admin),
> tanımlandığı migration, SECURITY DEFINER durumu, GRANT/REVOKE ve kısa açıklama yer alır.
>
> **Kapsam:** Yalnızca `lib/` altındaki Dart kodundan çağrılan RPC'ler. `Edge Functions`
> (supabase/functions/*) içindeki RPC çağrıları ve REST URL'leri (rest/v1/rpc/*) dahil
> **değildir** — kod taramasında 0 REST URL tespit edildi.
>
> **30 Temmuz 2026 tam-dosya statik taraması:** [`lib`](lib/) altında 108 literal `.rpc(...)` çağrı yeri ve 96 farklı literal RPC adı. Dinamik isim üretimi bu ölçüme dahil değildir. Edge Function içi backend RPC'leri aşağıdaki ayrı bölümde yer alır.

---

## 0) Okuma Rehberi

| Sütun | Anlam |
|------|------|
| **Kullanım** | Kodda çağrılmış mı? (✅ Evet / ⚠️ Tanımlı ama çağrılmıyor) |
| **Auth** | 🟢 Anon (giriş öncesi) · 🔵 Authenticated · 🟣 Admin (SECURITY DEFINER + is_admin) · ⚪ Auth + sınırlı |
| **SEC** | SECURITY tanımı: SD = SECURITY DEFINER · SI = SECURITY INVOKER |
| **GRANT** | EXECUTE verilen roller (anon / authenticated / service_role) |
| **Migration** | Tanımlandığı ana migration dosyası (en son geçerli olan) |

**Renkler (özet):**
- 🟢 **Anon (giriş öncesi)** — 3 RPC
- 🔵 **Authenticated (normal kullanıcı)** — 50+ RPC
- 🟣 **Admin-only (is_admin kontrolü ile)** — 25+ RPC
- ⚪ **Karma (admin veya kullanıcı duruma göre)** — birkaç RPC

---

## 1) Bakiye & Ödeme (Balance / Wallet)

| # | RPC | Kullanım | Çağrı yeri (lib) | Auth | Migration | SEC | GRANT | Açıklama |
|---|-----|----------|-------------------|------|-----------|-----|-------|---------|
| 1 | `add_to_balance` | ✅ | `admin_package_requests_tab.dart:170` | 🟣 Admin | `20260621_CREATE_BALANCE_SYSTEM.sql` → `20260709000005_BALANCE_REFUND_FIX.sql` → `20260727000008_harden_balance_rpc_permissions.sql` | SD | **service_role only** (anon/authenticated REVOKE) | Atomik bakiye ekleme (topup, refund, commission, adjustment). Client'tan çağrılmaz; service_role/admin trigger üzerinden çalışır. `20260727`'den sonra istemciden doğrudan çağrılamaz. |
| 2 | `deduct_from_balance` | ✅ | `send_package_screen.dart:216` (kullanıcı) + `admin_package_requests_tab.dart:170` (admin paket iade, add_to_balance olarak) | 🔵 Auth | `20260621_CREATE_BALANCE_SYSTEM.sql` → `20260628_enrich_deduct_from_balance_rpc.sql` → `20260707_DEDUCT_FROM_BALANCE_ENRICHED.sql` → [`20260727000008_harden_balance_rpc_permissions.sql`](supabase/migrations/20260727000008_harden_balance_rpc_permissions.sql:157) | SD | `authenticated`, `service_role`; PUBLIC/anon REVOKE | FOR UPDATE kilidi ile atomik düşme. Yetersiz bakiyede exception. Client → sadece kurye ödemesi. |

### 1.1 Puan Ayarı — Flutter'dan Çağrılan Yeni RPC

| RPC | Kullanım | Çağrı yeri | Auth | Migration | SEC | GRANT | Açıklama |
|---|---|---|---|---|---|---|---|
| [`admin_update_reward_points_config(integer,integer,bigint,integer,text,boolean,boolean,boolean,boolean,text)`](supabase/migrations/20260730000002_admob_reward_points_system.sql:816) | ✅ | [`AdSettingsService.updateRewardPointsConfig()`](lib/core/services/ad_settings_service.dart:87) | 🟣 Admin | [`20260730000002_admob_reward_points_system.sql`](supabase/migrations/20260730000002_admob_reward_points_system.sql:816) | SD, `search_path=''` | `authenticated` only; PUBLIC/anon/service_role REVOKE | Min/max puan, günlük puan bütçesi, oran, mode ve earn/SSV/spend/uygun ürün flag'lerini doğrular. Earn yalnız SSV açık + mode `cohort|enabled` iken açılır; legacy TL grant'i daima kapalı tutar, policy version artırır ve gerekçeli config audit yazar. |

### 1.2 Edge Function / Backend-Only Puan ve Dijital Sipariş RPC'leri

Bu bölüm ana Flutter envanterinin sayımına dahil değildir. İstemci bu RPC'leri doğrudan çağıramaz; ilgili Edge Function doğrulamasından sonra `service_role` çağırır.

| Kesin imza | Dış çağıran | EXECUTE | Uygulanmış davranış |
|---|---|---|---|
| [`reward_points_apply_entry(uuid,text,text,bigint,text,uuid,text,jsonb) -> point_ledger_entries`](supabase/migrations/20260730000002_admob_reward_points_system.sql:326) | Yalnız owner RPC zinciri | PUBLIC/anon/authenticated/service_role REVOKE | Tekil idempotency anahtarı, hesap satırı kilidi, negatif bakiye reddi, ledger insert ve projection/lifetime güncellemesini tek transaction'da yapar. |
| [`create_ad_reward_session(uuid,text,text,text,text) -> jsonb`](supabase/migrations/20260730000002_admob_reward_points_system.sql:402) | [`admob-reward-session`](supabase/functions/admob-reward-session/index.ts:35) | `service_role` only | Feature disabled değilse user + client key için idempotent, `pending_ssv`, 30 dakika ömürlü session döndürür. |
| [`grant_verified_ad_points(uuid,text,text,text,text,timestamptz,text,text) -> jsonb`](supabase/migrations/20260730000002_admob_reward_points_system.sql:446) | [`admob-ssv-callback`](supabase/functions/admob-ssv-callback/index.ts:87) | `service_role` only | Duplicate provider transaction için aynı sonucu döndürür; service claim, zaman, session, custom-data nonce HMAC bağı, feature/SSV/legacy flag, ad-unit, user limit, cooldown ve günlük bütçe kontrolünden sonra atomik puan kredi eder. Edge raw provider id yerine deterministik HMAC gönderir. |
| [`create_digital_order_with_points(uuid,uuid,text,integer,text,boolean) -> jsonb`](supabase/migrations/20260730000002_admob_reward_points_system.sql:576) | [`smm-order-create`](supabase/functions/smm-order-create/index.ts:25) | `service_role` only | İstemci fiyat/composition gönderemez. Ürün/fiyat/uygunluğu server-side doğrular; kilit sırası puan hesabı sonra TL hesabıdır; uygun siparişte önce puan, sonra kalan TL düşer ve immutable composition snapshot'ı yazar. |
| [`refund_digital_order_payment(uuid,numeric,text,text,boolean) -> jsonb`](supabase/migrations/20260730000002_admob_reward_points_system.sql:697) | Ortak [`refundComposition()`](supabase/functions/_shared/digital_orders.ts:27) | `service_role` only | Sipariş + event key için idempotent; artan kümülatif brüt hedef zorunlu. Hedefin puan bileşenini puan ledger'a, TL bileşenini balance transaction'a döndürür; `reconciliation_pending` siparişi reddeder ve asıl kaynak üst sınırlarını aşmaz. |
| [`set_digital_order_reconciliation(uuid,text) -> void`](supabase/migrations/20260730000002_admob_reward_points_system.sql:798) | Üç güncel `smm-order-*` function'ı | `service_role` only | Yalnız `pending_provider`, `reconciliation_pending`, `settled` durumlarını kabul eder. Belirsiz provider sonucunu yanlışlıkla iade saymamak için kullanılır. |
| [`purge_expired_reward_fraud_hashes(integer) -> integer`](supabase/migrations/20260730000002_admob_reward_points_system.sql:865) | Planlı service job | `service_role` only | Retention süresi dolan `provider_user_id_hash`, `device_pseudonym_hash`, `network_pseudonym_hash` alanlarını batch halinde NULL yapar. Provider transaction HMAC/ledger satırını silmez. |

Kapatılan imzalar:

- [`grant_ad_reward(uuid,text,text,integer)`](supabase/migrations/20260730000002_admob_reward_points_system.sql:964) yalnız `{status:410,error_code:'LEGACY_AD_TL_GRANT_DISABLED'}` üretir ve hiçbir role açık değildir.
- [`create_digital_order(uuid,uuid,text,integer)`](supabase/migrations/20260730000002_admob_reward_points_system.sql:973) tüm rollerden REVOKE edilmiştir; puansız eski checkout cutover sonrasında çağrılamaz.

---

## 2) Görev Kazanımı (Task Earning)

| # | RPC | Kullanım | Çağrı yeri (lib) | Auth | Migration | SEC | GRANT | Açıklama |
|---|-----|----------|-------------------|------|-----------|-----|-------|---------|
| 3 | `get_active_tasks` | ✅ | `task_earning_service.dart:59` | 🔵 Auth | `20260719000002_task_earning_rls_rpc.sql` → `20260719000003_fix_get_active_tasks_signature.sql` → `20260719000005_add_image_url_to_get_active_tasks.sql` | SD | authenticated | Kullanıcının görebileceği aktif görevler (user_already_claimed dahil). |
| 4 | `claim_task` | ✅ | `task_earning_service.dart:80` | 🔵 Auth | `20260719000002_task_earning_rls_rpc.sql` | SD | authenticated | Atomik katılımcı artırma + pending submission INSERT. |
| 5 | `submit_task_with_proof` | ✅ | `task_earning_service.dart:144` | 🔵 Auth | `20260719000002_task_earning_rls_rpc.sql` | SD | authenticated | Ekran görüntüsünü submission'a bağla. |
| 6 | `get_user_task_history` | ✅ | `task_earning_service.dart:164, 184, 207` (3 kez) | 🔵 Auth | `20260719000002_task_earning_rls_rpc.sql` | SD | authenticated | Kullanıcının kendi başvuru geçmişi (status/limit/offset). |
| 7 | `admin_get_task_submissions` | ✅ | `task_earning_service.dart:443` | 🟣 Admin | `20260719000002_task_earning_rls_rpc.sql` → `20260720000003_fix_admin_get_task_submissions_ambiguous_id.sql` | SD | authenticated + service_role | Admin için başvuru listesi (profiles + tasks JOIN). |
| 8 | `approve_task_submission` | ✅ | `task_earning_service.dart:468` | 🟣 Admin | `20260719000002_task_earning_rls_rpc.sql` | SD | authenticated + service_role | Admin onayı → atomik bakiye ekleme + idempotent. |
| 9 | `reject_task_submission` | ✅ | `task_earning_service.dart:488` | 🟣 Admin | `20260719000002_task_earning_rls_rpc.sql` | SD | authenticated + service_role | Admin red → current_participants geri alınır. |
| 10 | `get_task_stats` | ✅ | `task_earning_service.dart:504` | 🟣 Admin | `20260719000002_task_earning_rls_rpc.sql` | SD | authenticated + service_role | Admin dashboard istatistikleri. |

---

## 3) Versiyon, OTP, Hesap (Auth / Misc)

| # | RPC | Kullanım | Çağrı yeri (lib) | Auth | Migration | SEC | GRANT | Açıklama |
|---|-----|----------|-------------------|------|-----------|-----|-------|---------|
| 11 | `check_app_version` | ✅ | `version_check_service.dart:28` | 🟢 Anon | `20260228000001_force_update_system.sql` | SD | anon + authenticated | Uygulama açılışında versiyon kontrolü (giriş öncesi). |
| 12 | `verify_registration_otp` | ✅ | `verification_service.dart:135` | 🟢 Anon | `20260319000000_registration_otp_system.sql` | SD | anon + authenticated | Kayıt OTP doğrulama. |
| 13 | `verify_password_reset_otp` | ✅ | `verification_service.dart:275` | 🟢 Anon | `20260319000000_registration_otp_system.sql` | SD | anon + authenticated | Şifre sıfırlama OTP doğrulama. |
| 14 | `verify_code` | ✅ | `verification_service.dart:428` | 🔵 Auth | `20260227000000_verification_codes.sql` | SD | authenticated | Giriş sonrası ek doğrulama kodu (2FA benzeri). |
| 15 | `request_account_deletion` | ✅ | `account_settings_screen.dart:242` | 🔵 Auth | `20260126_account_deletion_rpc.sql` → `20260727000002_fix_advisor_security_performance.sql` (REVOKE/GRANT harden) | SD | authenticated (anon REVOKE) | Hesap silme onay kodu üretir + email gönderir. |
| 16 | `delete_account_with_code` | ✅ | `account_settings_screen.dart:382` | 🔵 Auth | `20260126_account_deletion_rpc.sql` → `20260724000000_fix_linter_warnings.sql` (REVOKE/GRANT) | SD | authenticated (anon REVOKE) | Onay kodunu doğrular ve tüm kullanıcı verisini siler. |

---

## 4) Bildirimler (Notifications)

| # | RPC | Kullanım | Çağrı yeri (lib) | Auth | Migration | SEC | GRANT | Açıklama |
|---|-----|----------|-------------------|------|-----------|-----|-------|---------|
| 17 | `add_notification` | ✅ | `notification_service.dart:219` + `courier_notification_service.dart:130` + `seller_orders_screen.dart:2493` (3 ayrı çağrı) | 🔵 Auth | `20260707_NOTIFICATIONS_AND_BALANCE_FIX.sql` | SD | authenticated (anon REVOKE) | Başka bir kullanıcıya bildirim yazmak için SECURITY DEFINER RPC (RLS 42501 sorunu çözümü). |

---

## 5) Havale / Transfer (Admin Onay)

| # | RPC | Kullanım | Çağrı yeri (lib) | Auth | Migration | SEC | GRANT | Açıklama |
|---|-----|----------|-------------------|------|-----------|-----|-------|---------|
| 18 | `approve_transfer_confirmation` | ✅ | `transfer_service.dart:115` | 🟣 Admin | `20260621_CREATE_BALANCE_SYSTEM.sql` → `20260709000006_TRANSFER_RPC_REVOKE_PUBLIC.sql` (anon REVOKE) | SD | authenticated (anon REVOKE) | Admin onayı → atomik bakiye ekleme + kullanıcıya notification. |
| 19 | `reject_transfer_confirmation` | ✅ | `transfer_service.dart:149` | 🟣 Admin | `20260621_CREATE_BALANCE_SYSTEM.sql` → `20260709000006_TRANSFER_RPC_REVOKE_PUBLIC.sql` (anon REVOKE) | SD | authenticated (anon REVOKE) | Admin red → bakiye eklenmez, kullanıcıya notification. |

---

## 6) Sipariş İptal (Cancellation)

| # | RPC | Kullanım | Çağrı yeri (lib) | Auth | Migration | SEC | GRANT | Açıklama |
|---|-----|----------|-------------------|------|-----------|-----|-------|---------|
| 20 | `create_cancellation_request` | ✅ | `cancellation_request_service.dart:189` | 🔵 Auth | `20260709000002_CANCELLATION_RPCS.sql` | SD | authenticated | Müşteri iptal talebi açar. |
| 21 | `approve_cancellation_request` | ✅ | `cancellation_request_service.dart:328` | 🟣 Admin | `20260709000002_CANCELLATION_RPCS.sql` | SD | authenticated (admin kontrolü içeride) | Admin onayı + atomik iade + notification. |
| 22 | `reject_cancellation_request` | ✅ | `cancellation_request_service.dart:352` | 🟣 Admin | `20260709000002_CANCELLATION_RPCS.sql` | SD | authenticated (admin kontrolü içeride) | Admin red. |
| 23 | `admin_cancel_with_refund` | ✅ | `cancellation_request_service.dart:386` | 🟣 Admin | `20260709000004_ADMIN_CANCEL_WITH_REFUND_RPC.sql` | SD | authenticated (admin kontrolü içeride) | Tek adım admin iptal + iade + stok restore. |

---

## 7) Kupon & Kampanya (Coupon / Campaign)

| # | RPC | Kullanım | Çağrı yeri (lib) | Auth | Migration | SEC | GRANT | Açıklama |
|---|-----|----------|-------------------|------|-----------|-----|-------|---------|
| 24 | `validate_coupon` | ✅ | `cart_screen.dart:206` | 🔵 Auth | `20260722000003_fix_coupon_validation.sql` (önce: `20260205000005_order_review_system.sql` veya benzer) | SD | authenticated | Sepette kupon doğrulama (süre, limit, kullanıcı başına). |
| 25 | `use_coupon` | ✅ | `checkout_screen.dart:400` | 🔵 Auth | `20260722000003_fix_coupon_validation.sql` | SD | authenticated | Sipariş oluşturulunca kupon kullanım kaydı. |
| 26 | `apply_campaign_rewards_for_order` | ✅ | `checkout_screen.dart:389` | 🔵 Auth | `20260722000004_buy2_get1_balance_campaign.sql` | SD | authenticated | 2-al-1 kampanya ödülünü bakiyeye yansıt. |

---

## 8) Mağaza Analitik (Satıcı Paneli)

| # | RPC | Kullanım | Çağrı yeri (lib) | Auth | Migration | SEC | GRANT | Açıklama |
|---|-----|----------|-------------------|------|-----------|-----|-------|---------|
| 27 | `get_shop_total_views` | ✅ | `shop_analytics_service.dart:73` | 🔵 Auth (satıcı) | `20260206000003_shop_analytics_tables.sql` | SD | authenticated | Mağaza toplam görüntüleme. |
| 28 | `get_shop_today_views` | ✅ | `shop_analytics_service.dart:107` | 🔵 Auth (satıcı) | `20260206000003_shop_analytics_tables.sql` | SD | authenticated | Bugünkü görüntüleme. |
| 29 | `get_top_viewed_products` | ✅ | `shop_analytics_service.dart:140` | 🔵 Auth (satıcı) | `20260206000003_shop_analytics_tables.sql` | SD | authenticated | En çok görüntülenen ürünler. |
| 30 | `get_top_customers` | ✅ | `shop_analytics_service.dart:265` | 🔵 Auth (satıcı) | `20260206000003_shop_analytics_tables.sql` | SD | authenticated | En çok sipariş veren müşteriler. |

---

## 9) Profil & Post Görüntüleme (Analytics)

| # | RPC | Kullanım | Çağrı yeri (lib) | Auth | Migration | SEC | GRANT | Açıklama |
|---|-----|----------|-------------------|------|-----------|-----|-------|---------|
| 31 | `track_profile_view` | ✅ | `profile_view_service.dart:41` | 🔵 Auth | `20260210000007_create_analytics_functions.sql` | SD | authenticated | Profil ziyaret kaydı (günde 1, viewer=auth.uid). |
| 32 | `get_profile_current_month_views` | ✅ | `profile_view_service.dart:59` | 🔵 Auth | `20260210000007_create_analytics_functions.sql` | SD | authenticated | Aylık profil istatistikleri. |
| 33 | `get_profile_monthly_stats` | ✅ | `profile_view_service.dart:89` | 🔵 Auth | `20260210000007_create_analytics_functions.sql` | SD | authenticated | Aylık geçmiş (varsayılan 6 ay). |
| 34 | `track_post_view` | ✅ | `post_view_service.dart:53` | 🔵 Auth | `20260210000007_create_analytics_functions.sql` | SD | authenticated | Post görüntüleme kaydı. |
| 35 | `get_user_current_month_post_views` | ✅ | `post_view_service.dart:71` | 🔵 Auth | `20260210000007_create_analytics_functions.sql` | SD | authenticated | Kullanıcının postlarının aylık toplam görüntülenmesi. |
| 36 | `get_post_monthly_stats` | ✅ | `post_view_service.dart:101` | 🔵 Auth | `20260210000007_create_analytics_functions.sql` | SD | authenticated | Aylık geçmiş. |
| 37 | `get_user_top_posts_by_views` | ✅ | `post_view_service.dart:241` | 🔵 Auth | `20260210000007_create_analytics_functions.sql` | SD | authenticated | Kullanıcının en çok görüntülenen postları. |

---

## 10) Story, Post, Başarım (Social)

| # | RPC | Kullanım | Çağrı yeri (lib) | Auth | Migration | SEC | GRANT | Açıklama |
|---|-----|----------|-------------------|------|-----------|-----|-------|---------|
| 38 | `increment_story_likes` | ✅ | `story_service.dart:583` | 🔵 Auth | `20240124000012_create_story_likes.sql` → `20260529000000_fix_story_likes_security.sql` (anon REVOKE) | SD | authenticated (anon REVOKE) | Story beğeni sayacı (trigger destekli). |
| 39 | `add_user_xp` | ✅ | `achievement_service.dart:221` | 🔵 Auth | `20260727000002_fix_advisor_security_performance.sql` (anon REVOKE) | SD | authenticated (anon REVOKE) | Başarım XP ekleme. |
| 40 | `toggle_post_favorite` | ✅ | `profile_screen.dart:2537` + `user_profile_screen.dart:2951` (2 kez) | 🔵 Auth | `20240124000011_create_post_favorites.sql` → `20260727000002_fix_advisor_security_performance.sql` (anon REVOKE) | SD | authenticated (anon REVOKE) | Gönderiyi kaydet/kaldır. |

---

## 11) Takip & Profil (Profile)

| # | RPC | Kullanım | Çağrı yeri (lib) | Auth | Migration | SEC | GRANT | Açıklama |
|---|-----|----------|-------------------|------|-----------|-----|-------|---------|
| 41 | `upsert_follow_request` | ✅ | `follow_request_service.dart:31` + `followers_screen.dart:212` + `profile_screen.dart:387` (3 kez) | 🔵 Auth | `20260208000010_all_chat_fixes.sql` (veya önceki) → `20260727000002_fix_advisor_security_performance.sql` (anon REVOKE) | SD | authenticated (anon REVOKE) | Gizli hesap için takip isteği (duplicate önleme). |

---

## 12) Chat — Birebir (1:1 Messaging — Mailbox Model)

| # | RPC | Kullanım | Çağrı yeri (lib) | Auth | Migration | SEC | GRANT | Açıklama |
|---|-----|----------|-------------------|------|-----------|-----|-------|---------|
| 42 | `send_message_with_recipient` | ✅ | `chat_service.dart:471` | 🔵 Auth | `20260207000007_create_chat_system.sql` → `20260208000010_all_chat_fixes.sql` (son sürüm: `20260703_CHAT_UNREAD_BADGE_FIX.sql` veya sonrası) | SD | authenticated | Mesajı HEM gönderenin HEM alıcının conversation'ına ekler. V2: trigger tetiklemez. |
| 43 | `mark_messages_as_read` | ✅ | `chat_service.dart:582` | 🔵 Auth | `20260208000009_fix_mark_as_read_function.sql` → `20260208000010_all_chat_fixes.sql` (son: `20260709_MARK_READ_PARTNER_UNREAD_FIX.sql`) | SD | authenticated | Okundu işaretle (yalnız reader'ın kendi conv'unda). |
| 44 | `delete_conversation_for_user` | ✅ | `chat_service.dart:628` | 🔵 Auth | `20260208000010_all_chat_fixes.sql` | SD | authenticated | Soft-delete konuşma. |
| 45 | `get_online_users` | ✅ | `chat_list_screen.dart:109` | 🔵 Auth | `20260208000010_all_chat_fixes.sql` | SD | authenticated | Aktif kullanıcı listesi. |

---

## 13) Chat — Gruplar (Group Messaging)

| # | RPC | Kullanım | Çağrı yeri (lib) | Auth | Migration | SEC | GRANT | Açıklama |
|---|-----|----------|-------------------|------|-----------|-----|-------|---------|
| 46 | `get_user_groups` | ✅ | `group_chat_service.dart:66` | 🔵 Auth | `20260207000007_create_chat_system.sql` → `20260208000010_all_chat_fixes.sql` | SD | authenticated | Kullanıcının grupları. |
| 47 | `search_groups` | ✅ | `group_chat_service.dart:277` | 🔵 Auth | `20260207000007_create_chat_system.sql` | SD | authenticated | Grup arama. |
| 48 | `join_open_group` | ✅ | `group_chat_service.dart:339` | 🔵 Auth | `20260207000007_create_chat_system.sql` → `20260208000010_all_chat_fixes.sql` | SD | authenticated (RLS bypass) | Açık gruba katıl. |
| 49 | `admin_add_group_member` | ✅ | `group_chat_service.dart:411` | 🟣 Grup admini | `20260208000010_all_chat_fixes.sql` (son: `20260704_GROUP_SYSTEM_SECURITY_FIX_FINAL.sql`) | SD | authenticated (p_added_by artık güvenilmiyor, auth.uid() kullanılıyor) | Gruba üye ekle. |
| 50 | `approve_group_join_request` | ✅ | `group_chat_service.dart:581` | 🟣 Grup admini | `20260208000010_all_chat_fixes.sql` → `20260724000000_fix_linter_warnings.sql` (anon REVOKE) | SD | authenticated (anon REVOKE) | Katılma isteğini onayla. |
| 51 | `reject_group_join_request` | ✅ | `group_chat_service.dart:644` | 🟣 Grup admini | `20260208000010_all_chat_fixes.sql` → `20260724000000_fix_linter_warnings.sql` (anon REVOKE) | SD | authenticated (anon REVOKE) | Katılma isteğini reddet. |
| 52 | `get_group_messages_with_read_count` | ✅ | `group_chat_service.dart:691` | 🔵 Auth | `20260208000010_all_chat_fixes.sql` | SD | authenticated | Mesaj listesi + read_by_count. |
| 53 | `mark_group_messages_as_read` | ✅ | `group_chat_service.dart:854` | 🔵 Auth | `20260208000010_all_chat_fixes.sql` | SD | authenticated | Grup okundu. |
| 54 | `mark_group_messages_read_receipts` | ✅ | `group_chat_service.dart:1065` | 🔵 Auth | `20260208000010_all_chat_fixes.sql` (son: `20260704_GROUP_RPC_AND_STORAGE_FIX.sql`) | SD | authenticated | Detaylı read receipts. |
| 55 | `get_message_read_receipts` | ✅ | `group_chat_service.dart:1088` | 🔵 Auth | `20260208000010_all_chat_fixes.sql` | SD | authenticated | Kim okudu listesi. |
| 56 | `get_message_read_count` | ✅ | `group_chat_service.dart:1143` | 🔵 Auth | `20260208000010_all_chat_fixes.sql` | SD | authenticated | Okunma sayısı. |

---

## 14) Şehir İçi Toplu Taşıma (Şoför & Admin)

| # | RPC | Kullanım | Çağrı yeri (lib) | Auth | Migration | SEC | GRANT | Açıklama |
|---|-----|----------|-------------------|------|-----------|-----|-------|---------|
| 57 | `get_sehirici_lines_with_stops` | ✅ | `sehirici_line_service.dart:32` | 🔵 Auth (anon da açık) | `20260725000001_sehirici_services.sql` | SD | authenticated + **anon** | Hat + duraklar (public bilgi). |
| 58 | `get_sehirici_active_trips` | ✅ | `sehirici_line_service.dart:51` | 🔵 Auth (anon da açık) | `20260725000001_sehirici_services.sql` | SD | authenticated + **anon** | Aktif seferler. |
| 59 | `get_sehirici_trips_for_stop` | ✅ | `sehirici_line_service.dart:67` | 🔵 Auth (anon da açık) | `20260725000001_sehirici_services.sql` | SD | authenticated + **anon** | Durağa gelen seferler. |
| 60 | `start_sehirici_trip` | ✅ | `sehirici_trip_service.dart:24` | 🔵 Auth (şoför) | `20260725000001_sehirici_services.sql` | SD | authenticated (PUBLIC REVOKE) | Sefer başlat. |
| 61 | `update_sehirici_trip_location` | ✅ | `sehirici_trip_service.dart:47` | 🔵 Auth (şoför) | `20260725000001_sehirici_services.sql` | SD | authenticated (PUBLIC REVOKE) | Konum güncelle (10 sn). |
| 62 | `set_sehirici_trip_status` | ✅ | `sehirici_trip_service.dart:64` | 🔵 Auth (şoför) | `20260725000001_sehirici_services.sql` | SD | authenticated (PUBLIC REVOKE) | Durum değiştir. |
| 63 | `compute_sehirici_next_stop` | ✅ | `sehirici_trip_service.dart:97` | 🔵 Auth (anon da açık) | `20260725000001_sehirici_services.sql` | SD | authenticated + **anon** | Sıradaki durak (ETA hesabı). |
| 64 | `get_sehirici_trip_path` | ✅ | `sehirici_trip_service.dart:184` | 🔵 Auth (anon da açık) | `20260729000003_get_sehirici_trip_path.sql` | SD | authenticated + **anon** | Polyline için geçmiş konum noktaları. |
| 65 | `admin_upsert_sehirici_line` | ✅ | `sehirici_line_service.dart:118` | 🟣 Admin | `20260725000003_sehirici_admin_crud.sql` | SD | authenticated (PUBLIC REVOKE, admin check inside) | Hat ekle/güncelle. |
| 66 | `admin_upsert_sehirici_stop` | ✅ | `sehirici_line_service.dart:194` | 🟣 Admin | `20260725000003_sehirici_admin_crud.sql` | SD | authenticated (PUBLIC REVOKE) | Durak ekle/güncelle. |
| 67 | `admin_delete_sehirici_stop` | ✅ | `sehirici_line_service.dart:213` | 🟣 Admin | `20260725000003_sehirici_admin_crud.sql` | SD | authenticated (PUBLIC REVOKE) | Durak sil. |
| 68 | `admin_upsert_sehirici_city` | ✅ | `sehirici_city_service.dart:87` | 🟣 Admin | `20260725000003_sehirici_admin_crud.sql` | SD | authenticated (PUBLIC REVOKE) | Şehir ekle/güncelle. |
| 69 | `admin_delete_sehirici_city` | ✅ | `sehirici_city_service.dart:106` | 🟣 Admin | `20260725000003_sehirici_admin_crud.sql` | SD | authenticated (PUBLIC REVOKE) | Şehir sil. |

---

## 15) Admin — Şüpheli Hesaplar (Suspicious Users)

| # | RPC | Kullanım | Çağrı yeri (lib) | Auth | Migration | SEC | GRANT | Açıklama |
|---|-----|----------|-------------------|------|-----------|-----|-------|---------|
| 70 | `admin_list_suspicious_users` | ✅ | `suspicious_users_content.dart:32` | 🟣 Admin | `20260720000005_suspicious_users.sql` | SD | authenticated | Şüpheli hesapları listele. |
| 71 | `admin_set_user_suspicious` | ✅ | `suspicious_users_content.dart:46, 95` (2 kez) | 🟣 Admin | `20260720000005_suspicious_users.sql` | SD | authenticated | Şüpheli işaretle/kaldır. |

---

## 16) Admin — Fraud Tespiti (Fraud Detection)

| # | RPC | Kullanım | Çağrı yeri (lib) | Auth | Migration | SEC | GRANT | Açıklama |
|---|-----|----------|-------------------|------|-----------|-----|-------|---------|
| 72 | `admin_list_fraud_signals` | ✅ | `fraud_detection_service.dart:24` | 🟣 Admin | `20260729000004_fraud_detection_system.sql` | SD | authenticated (PUBLIC REVOKE) | Fraud sinyalleri listesi. |
| 73 | `admin_scan_fraud_signals` | ✅ | `fraud_detection_service.dart:43` | 🟣 Admin | `20260729000004_fraud_detection_system.sql` | SD | authenticated (PUBLIC REVOKE) | Tarama başlat. |
| 74 | `admin_review_fraud_signal` | ✅ | `fraud_detection_service.dart:56` | 🟣 Admin | `20260729000004_fraud_detection_system.sql` | SD | authenticated (PUBLIC REVOKE) | Sinyal inceleme (approve/reject). |

---

## 17) Admin — Komisyon (Commission)

| # | RPC | Kullanım | Çağrı yeri (lib) | Auth | Migration | SEC | GRANT | Açıklama |
|---|-----|----------|-------------------|------|-----------|-----|-------|---------|
| 75 | `get_admin_commission_report` | ✅ | `commission_service.dart:249` | 🟣 Admin | `20260131000002_commission_system.sql` | SD | authenticated (admin kontrolü içeride) | Tarih aralığı komisyon raporu. |
| 76 | `get_seller_commission_summary` | ✅ | `commission_service.dart:294` | ⚪ Admin/Satıcı | `20260131000002_commission_system.sql` | SD | authenticated | Satıcı komisyon özeti (sahiplik kontrolü içeride). |

---

## 18) Admin — Grup Yönetimi (Group Management)

| # | RPC | Kullanım | Çağrı yeri (lib) | Auth | Migration | SEC | GRANT | Açıklama |
|---|-----|----------|-------------------|------|-----------|-----|-------|---------|
| 77 | `admin_get_all_groups` | ✅ | `groups_management_content.dart:48` | 🟣 Admin | `20260207000007_create_chat_system.sql` → `20260208000010_all_chat_fixes.sql` | SD | authenticated | Tüm grupları listele. |
| 78 | `admin_approve_join_request` | ✅ | `groups_management_content.dart:235, 579` (2 kez) | 🟣 Admin | `20260208000010_all_chat_fixes.sql` → `20260724000000_fix_linter_warnings.sql` (anon REVOKE) | SD | authenticated (anon REVOKE) | Herhangi bir grubun katılma isteğini onayla. |
| 79 | `admin_reject_join_request` | ✅ | `groups_management_content.dart:238, 581` (2 kez) | 🟣 Admin | `20260208000010_all_chat_fixes.sql` → `20260724000000_fix_linter_warnings.sql` (anon REVOKE) | SD | authenticated (anon REVOKE) | Herhangi bir grubun katılma isteğini reddet. |
| 80 | `admin_create_group` | ✅ | `groups_management_content.dart:282` | 🟣 Admin | `20260208000010_all_chat_fixes.sql` | SD | authenticated | Grup oluştur. |
| 81 | `admin_update_group` | ✅ | `groups_management_content.dart:322` | 🟣 Admin | `20260208000010_all_chat_fixes.sql` | SD | authenticated | Grup güncelle. |
| 82 | `admin_delete_group` | ✅ | `groups_management_content.dart:355` | 🟣 Admin | `20260208000010_all_chat_fixes.sql` | SD | authenticated | Grup sil. |
| 83 | `admin_get_group_members` | ✅ | `groups_management_content.dart:432` | 🟣 Admin | `20260208000010_all_chat_fixes.sql` | SD | authenticated | Üye listesi. |
| 84 | `admin_remove_group_member` | ✅ | `groups_management_content.dart:473` | 🟣 Admin | `20260208000010_all_chat_fixes.sql` | SD | authenticated | Üye çıkar. |
| 85 | `admin_change_member_role` | ✅ | `groups_management_content.dart:497` | 🟣 Admin | `20260208000010_all_chat_fixes.sql` | SD | authenticated | Rol değiştir. |

---

## 19) Admin — İçerik Sabitleme / Silme (Pin & Delete)

| # | RPC | Kullanım | Çağrı yeri (lib) | Auth | Migration | SEC | GRANT | Açıklama |
|---|-----|----------|-------------------|------|-----------|-----|-------|---------|
| 86 | `admin_pin_post` | ✅ | `_part_reports.dart:968` (dinamik) | 🟣 Admin | `20260724000000_fix_linter_warnings.sql` → `20260209000004_security_fixes.sql` | SD | authenticated (anon REVOKE) | Gönderi sabitle. |
| 87 | `admin_pin_story` | ✅ | `_part_reports.dart:968` (dinamik) | 🟣 Admin | `20260724000000_fix_linter_warnings.sql` | SD | authenticated (anon REVOKE) | Hikaye sabitle. |
| 88 | `admin_pin_product` | ✅ | `_part_reports.dart:968` (dinamik) | 🟣 Admin | `20260724000000_fix_linter_warnings.sql` | SD | authenticated (anon REVOKE) | Ürün sabitle. |
| 89 | `admin_pin_shop` | ✅ | `_part_reports.dart:968` (dinamik) | 🟣 Admin | `20260724000000_fix_linter_warnings.sql` | SD | authenticated (anon REVOKE) | Mağaza sabitle. |
| 90 | `admin_delete_post` | ✅ | `_part_posts.dart:772` | 🟣 Admin | `20260724000000_fix_linter_warnings.sql` | SD | authenticated (anon REVOKE) | Gönderi sil (ilişkili likes/views/comments/favorites/reports dahil). |
| 91 | `admin_delete_story` | ✅ | `_part_posts.dart:903` | 🟣 Admin | `20260209000004_security_fixes.sql` → `20260724000000_fix_linter_warnings.sql` | SD | authenticated (anon REVOKE) | Hikaye sil. |

---

## 20) Canlı Yayın & Flash Sale (Live Shopping)

| # | RPC | Kullanım | Çağrı yeri (lib) | Auth | Migration | SEC | GRANT | Açıklama |
|---|-----|----------|-------------------|------|-----------|-----|-------|---------|
| 92 | `start_live_session` | ✅ | `live_shopping_service.dart:121` | 🔵 Auth (satıcı) | `20260726120002_live_shopping_setup.sql` → `20260727000002_fix_advisor_security_performance.sql` (anon REVOKE) | SD | authenticated (anon REVOKE) | Canlı yayın başlat. |
| 93 | `end_live_session` | ✅ | `live_shopping_service.dart:128` | 🔵 Auth (satıcı) | `20260726120002_live_shopping_setup.sql` → `20260727000002_fix_advisor_security_performance.sql` (anon REVOKE) | SD | authenticated (anon REVOKE) | Canlı yayın bitir. |
| 94 | `claim_flash_sale` | ✅ | `flash_sale_service.dart:76` | 🔵 Auth | `20260726120001_flash_sale_and_price_alert_setup.sql` → `20260724000000_fix_linter_warnings.sql` (anon REVOKE) | SD | authenticated (anon REVOKE) | Atomik stok düşme. |
| 95 | `release_flash_sale` | ✅ | `flash_sale_service.dart:94` | 🔵 Auth | `20260726120001_flash_sale_and_price_alert_setup.sql` → `20260724000000_fix_linter_warnings.sql` (anon REVOKE) | SD | authenticated (anon REVOKE) | Stok geri verme. |

---

## 21) Değerlendirme (Reviews)

| # | RPC | Kullanım | Çağrı yeri (lib) | Auth | Migration | SEC | GRANT | Açıklama |
|---|-----|----------|-------------------|------|-----------|-----|-------|---------|
| 96 | `get_pending_reviews` | ✅ | `shop_review_service.dart:384` | 🔵 Auth | `20260205000005_order_review_system.sql` → `20260227000003_update_pending_reviews_with_product.sql` → `20260227000006_fix_pending_reviews_product_check.sql` | SD | authenticated | Bekleyen değerlendirmeler. |
| 97 | `can_review_order` | ✅ | `shop_review_service.dart:452` | 🔵 Auth | `20260205000005_order_review_system.sql` | SD | authenticated | Değerlendirme uygunluk kontrolü. |
| 98 | `dismiss_review_reminder` | ✅ | `pending_review_dialog.dart:445` | 🔵 Auth | `20260722000001_review_reminder_dismiss_db.sql` | SD | authenticated | Hatırlatıcıyı atla (kalıcı). |

---

## 22) Haberler (News)

| # | RPC | Kullanım | Çağrı yeri (lib) | Auth | Migration | SEC | GRANT | Açıklama |
|---|-----|----------|-------------------|------|-----------|-----|-------|---------|
| 99 | `get_news_engagement_details` | ✅ | `news_service.dart:506` | 🔵 Auth (yazar/admin) | `20260729000004_news_engagement_notifications_and_analytics.sql` | SD | authenticated (PUBLIC REVOKE) | Haber etkileşim detayları (viewers/likes/comments). |

---

## 23) Çağrı Sıklığı Sıralaması (Kod Tarafında)

Birden fazla yerde çağrılan RPC'ler:

| RPC | Çağrı sayısı | Yerler |
|-----|--------------|--------|
| `add_notification` | 3 | notification_service, courier_notification_service, seller_orders_screen |
| `upsert_follow_request` | 3 | follow_request_service, followers_screen, profile_screen |
| `admin_set_user_suspicious` | 2 | suspicious_users_content (unflag + flag) |
| `admin_approve_join_request` | 2 | groups_management_content (ana + dialog) |
| `admin_reject_join_request` | 2 | groups_management_content (ana + dialog) |
| `get_user_task_history` | 3 | task_earning_service (3 farklı filtre ile) |
| `toggle_post_favorite` | 2 | profile_screen, user_profile_screen |
| `admin_pin_*` (4 farklı) | 1 (dinamik) | _part_reports.dart |
| `admin_delete_post` | 1 | _part_posts.dart |
| `admin_delete_story` | 1 | _part_posts.dart |

---

## 24) İstemci Çağrı Envanteri Ölçümü

| Ölçüm | 2026-07-30 sonucu |
|---|---:|
| [`lib`](lib/) altında literal `.rpc(...)` çağrı yeri | 108 |
| Farklı literal RPC adı | 96 |

Rol dağılımı yalnız isim öneklerinden güvenilir biçimde türetilemeyeceği için eski yaklaşık yüzde tablosu kaldırılmıştır. Yetki gerçeği her satırın migration `GRANT/REVOKE` sözleşmesidir. Dinamik `admin_pin_*` çağrıları ayrıca ilgili satırlarda belgelenir.

---

## 25) SECURITY DEFINER vs INVOKER

Tarihsel 96 istemci RPC adı bu alt görevde çalışan veritabanı kataloğuyla topluca karşılaştırılmamıştır. Bu nedenle SECURITY DEFINER/INVOKER için toplam veya yüzde verilmez; her RPC'nin en son migration imzası ile canlı katalogdaki `prosecdef`, `proconfig` ve `proacl` değerleri ayrı ayrı doğrulanmalıdır.

Doğrulanan yeni kapsam: puan sisteminin dışa açık ve iç RPC'leri [`20260730000002_admob_reward_points_system.sql`](supabase/migrations/20260730000002_admob_reward_points_system.sql:326) içinde `SECURITY DEFINER` ve `SET search_path=''` ile tanımlıdır. Bu migration'a ait GRANT/REVOKE matrisi §1.1–1.2'de imza bazında verilmiştir.

Mevcut istemci envanterindeki bilinen sınırlar:
- **anon** yetkili olduğu önceki migration envanterinde belgelenenler: `check_app_version`, `verify_registration_otp`, `verify_password_reset_otp`, `get_sehirici_lines_with_stops`, `get_sehirici_active_trips`, `get_sehirici_trips_for_stop`, `compute_sehirici_next_stop`, `get_sehirici_trip_path`. Bu liste canlı katalog için eksiksizlik iddiası taşımaz.
- Diğer tarihsel RPC'ler için blanket anon-REVOKE varsayımı yapılmaz; en son migration ve canlı `proacl` doğrulanır.
- **service_role only**: `add_to_balance` (`20260727`'den sonra)

---

## 26) Migration Tarih Sırasına Göre Kronoloji

| Tarih | Migration | RPC'ler |
|-------|-----------|---------|
| 2024-01-24 | `20240124000011_create_post_favorites.sql` | `toggle_post_favorite` |
| 2024-01-24 | `20240124000012_create_story_likes.sql` | `increment_story_likes` (orijinal) |
| 2026-01-26 | `20260126_account_deletion_rpc.sql` | `request_account_deletion`, `delete_account_with_code` |
| 2026-01-31 | `20260131000002_commission_system.sql` | `get_admin_commission_report`, `get_seller_commission_summary` |
| 2026-02-05 | `20260205000005_order_review_system.sql` | `get_pending_reviews`, `can_review_order` |
| 2026-02-06 | `20260206000003_shop_analytics_tables.sql` | `get_shop_total_views`, `get_shop_today_views`, `get_top_viewed_products`, `get_top_customers` |
| 2026-02-07 | `20260207000007_create_chat_system.sql` | `send_message_with_recipient`, `get_user_groups`, `search_groups`, `join_open_group` (orijinaller) |
| 2026-02-08 | `20260208000009_fix_mark_as_read_function.sql` | `mark_messages_as_read` |
| 2026-02-08 | `20260208000010_all_chat_fixes.sql` | Tüm chat RPC'lerinin final halleri + grup admin RPC'leri |
| 2026-02-09 | `20260209000004_security_fixes.sql` | `admin_delete_story` |
| 2026-02-10 | `20260210000007_create_analytics_functions.sql` | 7 profil/post analytics RPC'si |
| 2026-02-27 | `20260227000000_verification_codes.sql` | `verify_code` |
| 2026-02-28 | `20260228000001_force_update_system.sql` | `check_app_version` |
| 2026-03-19 | `20260319000000_registration_otp_system.sql` | `verify_registration_otp`, `verify_password_reset_otp` |
| 2026-05-29 | `20260529000000_fix_story_likes_security.sql` | `increment_story_likes` (anon REVOKE) |
| 2026-06-21 | `20260621_CREATE_BALANCE_SYSTEM.sql` | `add_to_balance`, `deduct_from_balance`, `approve_transfer_confirmation`, `reject_transfer_confirmation` (orijinaller) |
| 2026-06-28 | `20260628_enrich_deduct_from_balance_rpc.sql` | `deduct_from_balance` (zenginleştirme) |
| 2026-07-07 | `20260707_DEDUCT_FROM_BALANCE_ENRICHED.sql` | `deduct_from_balance` (final GRANT) |
| 2026-07-07 | `20260707_NOTIFICATIONS_AND_BALANCE_FIX.sql` | `add_notification` |
| 2026-07-09 | `20260709000002_CANCELLATION_RPCS.sql` | 3 cancellation RPC'si |
| 2026-07-09 | `20260709000004_ADMIN_CANCEL_WITH_REFUND_RPC.sql` | `admin_cancel_with_refund` |
| 2026-07-09 | `20260709000005_BALANCE_REFUND_FIX.sql` | `add_to_balance` (refund fix) |
| 2026-07-09 | `20260709000006_TRANSFER_RPC_REVOKE_PUBLIC.sql` | transfer RPC'lerinden anon REVOKE |
| 2026-07-19 | `20260719000002_task_earning_rls_rpc.sql` | 7 task RPC'si |
| 2026-07-20 | `20260720000005_suspicious_users.sql` | `admin_list_suspicious_users`, `admin_set_user_suspicious` |
| 2026-07-22 | `20260722000001_review_reminder_dismiss_db.sql` | `dismiss_review_reminder` |
| 2026-07-22 | `20260722000003_fix_coupon_validation.sql` | `validate_coupon`, `use_coupon` |
| 2026-07-22 | `20260722000004_buy2_get1_balance_campaign.sql` | `apply_campaign_rewards_for_order` |
| 2026-07-24 | `20260724000000_fix_linter_warnings.sql` | `admin_pin_*` (4), `admin_delete_post`, `admin_approve_join_request`, `admin_reject_join_request` (anon REVOKE) |
| 2026-07-25 | `20260725000001_sehirici_services.sql` | 5 şehir içi okuma RPC + 3 şoför RPC |
| 2026-07-25 | `20260725000003_sehirici_admin_crud.sql` | 5 şehir içi admin RPC |
| 2026-07-26 | `20260726120001_flash_sale_and_price_alert_setup.sql` | `claim_flash_sale`, `release_flash_sale` |
| 2026-07-26 | `20260726120002_live_shopping_setup.sql` | `start_live_session`, `end_live_session` |
| 2026-07-27 | `20260727000002_fix_advisor_security_performance.sql` | 12+ RPC'de anon REVOKE hardened (`upsert_follow_request`, `toggle_post_favorite`, `add_user_xp`, `start_live_session`, `end_live_session`, `get_top_customers`, `get_top_viewed_products` vb.) |
| 2026-07-27 | `20260727000008_harden_balance_rpc_permissions.sql` | `add_to_balance` → service_role only, `deduct_from_balance` authenticated only |
| 2026-07-29 | `20260729000003_get_sehirici_trip_path.sql` | `get_sehirici_trip_path` |
| 2026-07-29 | `20260729000004_fraud_detection_system.sql` | 3 fraud RPC |
| 2026-07-29 | `20260729000004_news_engagement_notifications_and_analytics.sql` | `get_news_engagement_details` |
| 2026-07-30 | [`20260730000002_admob_reward_points_system.sql`](supabase/migrations/20260730000002_admob_reward_points_system.sql:1) | [`admin_update_reward_points_config(...)`](supabase/migrations/20260730000002_admob_reward_points_system.sql:816) istemci-admin RPC'si; §1.2'deki service-only SSV/puan/composition/iade RPC'leri; legacy reklam ve checkout imzalarının kapatılması |

---

## 27) Güvenlik Notları (Audit Checklist)

- ✅ **Yeni puan RPC ACL'leri**: [`20260730000002_admob_reward_points_system.sql`](supabase/migrations/20260730000002_admob_reward_points_system.sql:326) her yeni imza için önce PUBLIC/anon/authenticated/service_role yetkilerini geri alır; yalnız §1.1–1.2'de belirtilen rolleri geri verir.
- ✅ **service_role only**: `add_to_balance` artık yalnızca service_role (Edge Function ve trigger) üzerinden çağrılabilir. Client'tan doğrudan çağrılamaz.
- ⚠️ **Admin RPC denetimi**: `admin_*` öneki tek başına yetki kanıtı değildir. Her imzada iç admin kontrolü ve GRANT/REVOKE ayrı doğrulanır. Yeni [`admin_update_reward_points_config(...)`](supabase/migrations/20260730000002_admob_reward_points_system.sql:816) çağrısı içeride admin kontrolü yapar ve yalnız `authenticated` rolüne verilir.
- ✅ **Idempotency**: Transactional RPC'ler (`approve_task_submission`, `approve_cancellation_request`, `deduct_from_balance`) tekrar çağrıya karşı korumalı.
- ✅ **Puan RPC search path'i**: Yeni ödül/puan/composition RPC'lerinin tamamı `SET search_path = ''` kullanır ve nesne adlarını şema nitelikli çağırır.
- ✅ **SSV fail-closed**: İstemcideki SDK callback'i RPC çağırmaz. [`admob-ssv-callback`](supabase/functions/admob-ssv-callback/index.ts:21) ECDSA/key/timestamp/ad-unit/custom-data doğrulamasını bitirmeden [`grant_verified_ad_points(...)`](supabase/migrations/20260730000002_admob_reward_points_system.sql:440) çağrılmaz; SQL ayrıca rollout/legacy flag'lerini zorunlu kılar.
- ✅ **Puan–nakit izolasyonu**: Puan kredisi `user_balances`/`balance_transactions` yazmaz. Yalnız uygun dijital siparişin kalan TL bileşeni TL ledger'a gider; iade her kaynağa kendi türünde döner.
- ⚠️ **Önceki envanterde anon GRANT'ı görülen RPC'ler**: Aşağıdaki sekiz imza public bilgi (şehir içi hat/durak) veya kayıt akışı (OTP) amacıyla belgelenmiştir; canlı katalog doğrulaması olmadan liste eksiksiz kabul edilmez:
  - `check_app_version`, `verify_registration_otp`, `verify_password_reset_otp`
  - `get_sehirici_lines_with_stops`, `get_sehirici_active_trips`, `get_sehirici_trips_for_stop`
  - `compute_sehirici_next_stop`, `get_sehirici_trip_path`

---

## 28) Eksik / Dead Code (Doğrulama Gerekli)

Bu belgedeki 108 literal çağrı/96 ad ölçümü yalnız Flutter kaynak taramasıdır; çalışan veritabanı kataloğuyla eksiksiz bir varlık, overload, güvenlik modu ve ACL mutabakatı değildir.

- Flutter'da bulunan her literal adın canlı veritabanında doğru overload ile bulunduğu ayrıca doğrulanmalıdır.
- Migration veya canlı katalogda tanımlı olup Flutter'dan çağrılmayan RPC'ler bu istemci sayımının dışındadır. `cleanup_sehirici_old_locations`, `notify_sehirici_favorite_approaching` ve `atomic_finalize_payment_transaction` gibi imzalar service job, trigger veya Edge Function zincirinde kullanılabilir; istemci taramasında görünmemeleri tek başına dead-code kanıtı değildir.

**Önerilen doğrulama komutu:**
```sql
-- DB'de tanımlı olup Flutter'dan çağrılmayan RPC'ler
SELECT proname FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname LIKE '%\_%'
ORDER BY proname;
```

---

## 29) Değişiklik Günlüğü

- `2026-07-29` · v1 · İlk oluşturulma. 96 farklı RPC, ~110 çağrı yeri. Tüm `.rpc(...)` çağrıları `lib/` altında tarandı, migration dosyalarıyla çapraz doğrulandı.
- `2026-07-30` · v2 · Tam-dosya taraması 108 literal çağrı/96 ad olarak yeniden sayıldı; [`admin_update_reward_points_config(...)`](supabase/migrations/20260730000002_admob_reward_points_system.sql:816) istemci RPC'si ve backend-only SSV/puan/composition/iade imzaları gerçek GRANT/REVOKE sözleşmeleriyle eklendi; legacy TL grant ve eski checkout kapatması belgelendi.
