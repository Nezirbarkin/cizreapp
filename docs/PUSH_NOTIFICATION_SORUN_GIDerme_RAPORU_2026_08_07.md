# Push Notification — Durum Tespiti ve Bulgular Raporu

**Tarih:** 2026-08-07
**Proje:** CizreApp (Flutter + Supabase)
**Kapsam:** Neden push notification gelmediğinin tespiti, mevcut düzenin derinlemesine analizi, çift bildirim riskinin değerlendirilmesi, canlıda çalıştırılacak test senaryoları.

---

## 1. Yönetici Özeti (TL;DR)

Proje **büyük bir refaktörün ortasında**: 2026-08-02 tarihli `20260802000003_secure_push_notification_pipeline.sql` migration'ı ile tüm push pipeline'ı **transactional outbox + worker** mimarisine taşınmış. Eski HTTP-tabanlı, anon-JWT'li, hata-yutan iki Edge Function (`send-push`, `send-push-notification`) **artık 410 Gone** döndürüyor.

**Push gelmemesinin en olası 3 nedeni (öncelik sırasıyla):**

| # | Olasılık | Kanıt |
|---|---|---|
| 1 | **`pg_cron` job kurulmamış veya INTERNAL_WORKER_SECRET secret ayarlanmamış** → worker her dakika çalışmıyor, outbox birikiyor, push hiç gitmiyor. | `cron.job` tablosunda `process-notification-outbox-every-minute` yoksa; outbox `pending` sayısı artıyorsa bu kesin nedendir. |
| 2 | **`profiles.fcm_token` NULL** → kullanıcı giriş yapmamış, çıkış yapmış veya `clear_my_fcm_token` çalıştırılmış. Token kayıt akışı (`PushNotificationService.initialize` → `onAuthStateChange` → `set_my_fcm_token`) 2026-08-02 refaktöründen sonra değişti; eski sürümlerde token kaydı başarısız kalabilir. | Diagnostic sorgu `I) FCM token kayıtlı kullanıcı sayısı`. |
| 3 | **Bildirim tercihi (notification_preferences) kapalı** → `NotificationService.createNotification` tercihe bakıyor, kapalıysa DB'ye hiç insert etmiyor, push da gitmiyor. | Diagnostic + UI'da "Bildirim Ayarları" ekranı. |

**Çift bildirim tarafı:** 2026-08-02 refaktörü ile **idempotent oldu** (outbox'ta `UNIQUE(notification_id)`, `ON CONFLICT DO NOTHING`). Ama **Dart tarafı** + **DB tarafı** aynı bildirimi iki kez üretebilecek kod yolları hâlâ mevcut. 4. bölümde listelendi.

---

## 2. Mevcut Düzen — Mimari Harita

### 2.1 Push pipeline'ın güncel hâli (2026-08-02 sonrası)

```
   [İSTEMCİ — Flutter]
       │
       │  (1) Supabase RPC: add_notification / admin_send_personal_notification
       │      / share_post_with_user / approve_cancellation_request / ...
       ▼
   [SUPABASE POSTGRES]   ── RPC SECURITY DEFINER ──
       │
       │  (2) INSERT INTO public.notifications
       │      (UNIQUE INDEX yok; çoklu INSERT mümkün)
       ▼
   [TRIGGER: notifications_outbox_trigger]
       │
       │  (3) enqueue_notification_outbox(NEW.id)
       │      ON CONFLICT (notification_id) DO NOTHING
       ▼
   [TABLO: notification_outbox]
       │     status='pending'
       │     UNIQUE(notification_id)  ← idempotency garantisi
       │
       │  ⏰ pg_cron her dakika (* * * * *)
       ▼
   [EDGE FUNCTION: process-notification-outbox]
       │     Auth: x-worker-secret header (INTERNAL_WORKER_SECRET env)
       │     claim_notification_outbox → FOR UPDATE SKIP LOCKED
       │     profiles.fcm_token + notification_tokens.token → token listesi
       │     FCM HTTP v1 API → sendFcm
       │     mark_outbox_sent | mark_outbox_failed (exponential backoff, 8 deneme → dead)
       ▼
   [FCM HTTP v1]  → [CIHAZ]  → [flutter_local_notifications gösterimi]
```

### 2.2 Güvenlik düzeltmeleri (bu refaktörle gelenler)

| Sorun | Önceki hâl | Yeni hâl |
|---|---|---|
| İstemci FCM token SELECT edip başkasına push atabiliyor | `from('profiles').select('fcm_token')` + `functions.invoke('send-push', ...)` | `_saveFCMToken` yalnızca `set_my_fcm_token` SECURITY DEFINER RPC'yi çağırır. Push gönderimi tamamen server-side. |
| Anon çağrı ile başkasına push | `send-push` body'den user_id alıyordu | `send-push` artık 410 Gone. Tüm push akışı `enqueue_notification_outbox` üzerinden service_role ile. |
| Sabit project URL + anon JWT ile net.http_post | `send_push_on_notification` + `notify_price_drops` | `send_push_on_notification_DEPRECATED` (RAISE EXCEPTION), `notify_price_drops` yalnızca notifications INSERT eder. |
| Çift push | Aynı event için birden fazla INSERT | `UNIQUE(notification_id)` outbox'ta + `ON CONFLICT DO NOTHING` → ikinci INSERT noop. |
| `fcm_token` sütununa sızıntı | anon SELECT mümkündü | 20260803000006 sonrası profiles'tan SELECT grant kaldırıldı; yalnız `public_profiles_safe` view + SECURITY DEFINER RPC'ler. |

### 2.3 Kim ne yapar — güncel akış matrisi

| Olay | Tetikleyen | DB tarafı | Outbox | Push |
|---|---|---|---|---|
| Beğeni/Yorum/Takip | Flutter `createLikeNotification` (DB trigger ile aynı kayıt) | `add_notification` RPC → INSERT notifications → outbox trigger → outbox INSERT | ✅ | ✅ |
| Sipariş durumu | `order_service.dart` `_sendOrderStatusNotification` + `_sendStatusNotificationToCustomer` (2 ayrı fonk.) | `add_notification` RPC | ✅ | ✅ (potansiyel DUPLİKAT) |
| Fiyat düşüşü | `notify_price_drops` DB trigger (AFTER UPDATE ON products) | INSERT notifications → outbox trigger | ✅ | ✅ (24 saatlik pencere ile dedup) |
| Admin kişisel | Admin paneli `admin_send_personal_notification` RPC | INSERT notifications + audit | ✅ | ✅ |
| Admin toplu | Admin paneli `admin_broadcast_notification` RPC | INSERT admin_broadcasts (topic push YOK) | ❌ | ❌ (broadcast tablosu) |
| Kurye atama | `courier_notification_service._notifyCourierOfAssignment` | `add_notification` RPC | ✅ | ✅ |
| Chat mesajı | `enqueue_notification_outbox_trigger` tip='message'|'chat' için RETURN NEW (outbox'a YAZMAZ) | INSERT notifications | ❌ | ❌ (chat kendi sistemi) |
| Paylaşım (post share) | Flutter → `share_post_with_user` RPC | INSERT notifications (60s idempotency) | ✅ | ✅ |

### 2.4 RPC güvenlik matrisi

| RPC | Çağıran | Yapar | Güvenlik |
|---|---|---|---|
| `add_notification` | authenticated | Herhangi bir kullanıcıya bildirim yazar | SECURITY DEFINER; RLS bypass. **Sınırsız kötüye kullanım riski** (herhangi bir authenticated user herkese notification yazabilir) |
| `enqueue_notification_outbox` | yalnızca service_role | Outbox'a ekler | Yalnızca trigger üzerinden çağrılmalı |
| `claim_notification_outbox` | yalnızca service_role | Atomik claim | Worker tek satırlık FOR UPDATE SKIP LOCKED |
| `mark_outbox_sent/failed` | yalnızca service_role | Outbox satırı günceller | |
| `admin_send_personal_notification` | authenticated + `is_admin()` | Kişisel bildirim + audit | 1-100/1-500 uzunluk sınırı |
| `admin_broadcast_notification` | authenticated + `is_admin()` | Broadcast + audit | `customers`/`sellers`/`all_users` allowlist |
| `share_post_with_user` | authenticated | Post paylaşımı bildirimi | 60s idempotency; self-share reddedilir |
| `set_my_fcm_token` | authenticated + auth.uid() | Kendi `profiles.fcm_token` | 20260803000006 sonrası tek yol |
| `clear_my_fcm_token` | authenticated | Çıkışta token sil | Service role'a yazma yetkisi |

---

## 3. Push Gelmemesinin 7 Olası Kök Nedeni — Kanıt Sorguları

### 3.1 pg_cron kurulu değil veya job yok

**Semptom:** Yeni bildirim DB'ye yazılıyor (bildirimler ekranında görünüyor), ama push gelmiyor.

**Kanıt:**
```sql
SELECT jobname, schedule, active
FROM cron.job
WHERE jobname='process-notification-outbox-every-minute';
-- Boş dönerse: cron job kurulmamış → push hiç gelmez.
```

**Çözüm:** `20260802000004_push_outbox_cron_scheduler.sql` uygulanmalı.
- `app.settings.internal_worker_secret` Postgres custom config'e eklenmeli (Supabase Dashboard → Database → Settings → Custom Postgres Config).
- `app.settings.supabase_url` ayarlanmamışsa default `https://xsbukxkgtmdyickknqzf.supabase.co` kullanılır.
- VEYA: hard-coded bir secret ile `current_setting('app.settings.internal_worker_secret', true)` döndürülemezse SQL hata fırlatır; bu durumda secret Supabase Edge Function secrets'ta da olmalı: `supabase secrets set INTERNAL_WORKER_SECRET=...`.

### 3.2 INTERNAL_WORKER_SECRET tutarsız

**Semptom:** Worker her çağrıda 401 alıyor; log: `worker_error: Unauthorized`.

**Kanıt:** Edge Function loglarında her dakika `POST /functions/v1/process-notification-outbox → 401` görüyorsanız, secret eşleşmiyor. cron tarafında kullanılan secret ile Edge Function env'i aynı olmalı.

**Çözüm:** İki tarafta da aynı secret; `supabase secrets set INTERNAL_WORKER_SECRET=...` sonrası Edge Function'ı redeploy et.

### 3.3 FIREBASE_SERVICE_ACCOUNT env eksik

**Semptom:** Worker 200 döner ama `processed: 0`; log: `FIREBASE_SERVICE_ACCOUNT secret missing`.

**Kanıt:** Edge Function loglarında 500 ile `FIREBASE_SERVICE_ACCOUNT secret missing`.

**Çözüm:** `supabase secrets set FIREBASE_SERVICE_ACCOUNT="$(cat service-account.json)"` — JSON tek satır olarak, newlines ile birlikte.

### 3.4 profiles.fcm_token NULL

**Semptom:** Outbox hızla boşalıyor (worker başarılı), ama kullanıcı push almıyor. Log: `outbox=... status=processed` (sent yerine processed — token yok).

**Kanıt:**
```sql
-- Kullanıcı ID'si biliniyorsa:
SELECT id, fcm_token, updated_at FROM public.profiles WHERE id = '<USER_ID>';
-- Toplu:
SELECT COUNT(*) FILTER (WHERE fcm_token IS NULL) AS tokensiz,
       COUNT(*) FILTER (WHERE fcm_token IS NOT NULL) AS tokenli
FROM public.profiles;
```

**Çözüm:**
1. Kullanıcı uygulamayı yeniden açmalı → `PushNotificationService.initialize()` → `_setupFCMToken()` → `set_my_fcm_token` çağrılır.
2. Eğer eski sürümden yükseltildiyse: `set_my_fcm_token` RPC'si `20260803000006` ile geldi; bu migration uygulanmamışsa `set_my_fcm_token` "function does not exist" hatası verir.

### 3.5 Bildirim tercihi kapalı

**Semptom:** DB'ye hiç notification INSERT edilmiyor.

**Kanıt:**
```sql
SELECT * FROM public.notification_preferences WHERE user_id = '<USER_ID>';
```
`order_updates_enabled=false` ise sipariş push'ları gönderilmez.

**Çözüm:** UI'da "Bildirim Ayarları" ekranını aç → ilgili kategori aç.

### 3.6 FCM token temiz token ama cihazda push izni yok

**Semptom:** Token kayıtlı, outbox sent, ama cihazda bildirim görünmüyor.

**Kanıt:** Cihazda `Ayarlar → Bildirimler → CizreApp` kapalı olabilir. `_requestPermissions` `AuthorizationStatus.denied` dönmüş olabilir.

**Çözüm:** Kullanıcı OS ayarlarından izin vermeli; uygulama `notification_settings_screen.dart` üzerinden yönlendirir.

### 3.7 Worker stale processing'e takıldı (worker crash koruması)

**Semptom:** Outbox'ta `processing` durumunda eski kayıtlar birikiyor; bunlar `release_stale_outbox` ile temizlenir ama 5 dakika boyunca bloke olur.

**Kanıt:**
```sql
SELECT COUNT(*) FROM public.notification_outbox
WHERE status='processing' AND locked_at < NOW() - INTERVAL '5 minutes';
```

**Çözüm:** Worker her claim'den önce `release_stale_outbox('5 minutes')` çağırıyor; normal çalışmada birikim olmaz. Birikim varsa worker deploy'u bozuk olabilir.

---

## 4. Çift Bildirim (Duplicate) — Risk Analizi

### 4.1 Çift bildirimin 4 olası kaynağı (mevcut kod taraması)

| # | Kaynak | Tetikleyen | Çift bildirim senaryosu | Önlem |
|---|---|---|---|---|
| 1 | **`add_notification` RPC idempotent DEĞİL** | `notification_service.dart:213` `_notificationService.createNotification` | Aynı fonksiyon aynı userId/type/entityId için iki kez çağrılırsa iki kayıt oluşur. Network retry durumunda görülebilir. | **Eksik.** Outbox idempotent ama notifications tablosunda `UNIQUE(user_id, type, entity_id)` constraint'i yok. `20260728000009_notification_fixes.sql` planlanmış ama production'a uygulanmamış olabilir (dosya mevcut değil, dosya adı farklı olabilir). |
| 2 | **Sipariş teslim akışı — birden fazla INSERT yolu** | `order_service.dart:722` + `seller_orders_screen.dart:337` + `courier_notification_service.dart:387` | Satıcı "Teslim Et" + Kurye "Teslim Et" aynı anda → 2 kayıt. Başlıklar farklı ("✅ Siparişiniz Teslim Edildi!" vs "Siparişiniz teslim edildi"), bu yüzden Flutter istemcideki dedup yakalamıyor. | **Kısmen.** `20260621120003_fix_duplicate_order_notifications_final.sql` eski duplikaları temizlemiş ama yeni oluşumları engellemiyor. Plan: `SIPARIS_BILDIRIM_KURYE_FIX_PLAN.md` Görev 1. |
| 3 | **Birden fazla push trigger yarış koşulu** | DB'de `notifications_push_trigger` 2026-08-02 sonrası **kaldırıldı**, ama eski sürümlerde `20260411120004_push_notification_trigger.sql` + `20260210000003_create_notification_triggers.sql` (post_like, post_comment vb.) birden fazla INSERT yapabilir. | Kullanıcı gönderiyi aynı anda hem beğenirse hem yorum yaparsa; ya da notification trigger'ları çift kurulursa. | **Sağlandı.** 2026-08-02 sonrası tek yol outbox; eski trigger'lar trigger_outbox_trigger tarafından overwrite edildi. Ama `notification_post_like_trigger` gibi eski trigger'lar hâlâ INSERT yapıyor → outbox trigger'ı onları da yakalıyor → sadece **tek** push gidiyor (UNIQUE constraint sayesinde). Yani **push** çift olmasa da **in-app bildirim listesi** çift olabilir. |
| 4 | **share_post_with_user 60s idempotency pencere** | `20260802000003` Bölüm E | İlk share + 30 saniye sonra aynı share → sadece 1 kayıt. ✅ | Sağlandı. |

### 4.2 Mevcut koddaki hâlâ 2 INSERT yapan kritik satırlar

```dart
// lib/features/shop/services/order_service.dart
// Sipariş oluşturulduğunda:
//   Satıcıya: createNotification(... 'new_order' ...)
//   Müşteriye: createNotification(... 'order_update' ...)  ← updateOrderStatus'ta TEKRAR
// lib/features/seller/screens/seller_orders_screen.dart:336
//   _sendStatusNotificationToCustomer → 'order_delivered'
// lib/core/services/courier_notification_service.dart:387
//   notifyCustomerOrderDelivered → 'order_delivered' (başlık AYNI ama titleKey aynı)
//   AYRICA: 'pending_review' INSERT bloğu kaldırılmış ama PendingReviewChecker ayrı INSERT yapar
```

**Sonuç:** Sipariş teslim edildiğinde **2 adet `order_delivered` bildirimi** üretilebilir. Plan belgelerinde (`plans/SIPARIS_BILDIRIM_KURYE_FIX_PLAN.md`) "Görev 1" olarak işaretlenmiş ama hâlâ açık.

### 4.3 İstemci tarafı dedup (notification_service.dart:62-83)

```dart
// entityId + titleKey bazlı dedup. AYNI başlık = AYNI kalıyor.
// Sorun: iki farklı kaynak (Dart + DB trigger) aynı bildirimi farklı başlıkla
// gönderebilir (örn. "Siparişiniz teslim edildi 🎉" vs "✅ Siparişiniz Teslim
// Edildi!"). Bu durumda dedup çalışmaz, iki kayıt görünür.
final titleKey = notification.title ?? notification.type;
final groupKey = '${notification.entityId}_$titleKey';
```

**Çözüm:** titleKey yerine `(entityId, type)` bazlı dedup; ya da backend tarafında `UNIQUE(user_id, type, entity_id, created_at::date)` constraint'i.

### 4.4 Çift bildirim testi

`supabase/diagnostics/20260807_push_dedup_invariants.sql` dosyası:
- Aynı (user_id, type, entity_id) için 7 günlük pencerede birden fazla kayıt olup olmadığını listeler.
- DRY_RUN ve EXECUTE modunda duplicate temizliği yapar (en yeniyi tutar).

---

## 5. Test Senaryoları (Çalıştırma Rehberi)

### 5.1 Lokalde/Dashboard'da diagnostik (5 dakika)

**Dosya:** `supabase/diagnostics/20260807_push_pipeline_health_check.sql`

```bash
# 1) Supabase Dashboard > SQL Editor'de bu dosyanın içeriğini yapıştır
# 2) Çalıştır
# 3) Çıktıdaki ❌ işaretli satırlara odaklan:
#    - A1/A2/A3: outbox tablosu + trigger durumu
#    - C1/C2: pg_cron + cron job
#    - D: RPC'lerin service_role erişimi
#    - E: secret env ayarı
#    - F/G: son 24 saatteki outbox istatistikleri + dead/failed kayıtlar
#    - H: pending birikim (worker yavaş)
#    - I: FCM token kayıtlı kullanıcı oranı
#    - J: bildirim tipi dağılımı
```

**Hızlı teşhis tablosu:**

| Kontrol | Beklenen | Eğer ❌ |
|---|---|---|
| A1, A2 | ✅ | `20260802000003` migration uygulanmamış |
| A3 | ✅ kaldırıldı | `20260802000003` uygulanmamış; eski iki trigger aktif → çift push riski |
| B | ✅ temiz | Eski `20260726120001` migration'ı hâlâ aktif; yeniden deploy gerekli |
| C1, C2 | ✅ | `20260802000004` + custom config ayarı eksik |
| D (her satır) | ✅ | RPC yoksa: `20260802000003` uygulanmamış |
| F: pending > 100 | ❌ ise sorun var | Worker yavaş veya cron çalışmıyor |
| G: dead > 0 | ❌ ise sorun var | FCM service_account hatalı veya token permanent error |
| I: tokensiz % > 50 | ❌ | Token kayıt akışı bozuk |

### 5.2 Çift bildirim temizleme (DRY-RUN)

**Dosya:** `supabase/diagnostics/20260807_push_dedup_invariants.sql`

```bash
# 1) DRY-RUN: üst blokları çalıştır; sadece SELECT yapar
# 2) Hangi tipte kaç duplicate var gör
# 3) EXECUTE moduna geçmek için yorumlu DELETE bloğunu aç
# 4) BEGIN; ... COMMIT; ile transaction'da çalıştır (geri alınabilir)
```

### 5.3 Flutter tarafı runtime testi

**Dosya:** `test/secure_push/push_runtime_health_test.dart`

```bash
# Canlı Supabase'e karşı koşmak için env gerekli
set SUPABASE_URL=https://xsbukxkgtmdyickknqzf.supabase.co
set SUPABASE_ANON_KEY=eyJ...
set TEST_USER_EMAIL=test@example.com
set TEST_USER_PASSWORD=...
flutter test test/secure_push/push_runtime_health_test.dart
```

**Test ettikleri:**
- A) Supabase bağlantısı kuruluyor mu?
- B) `notification_preferences` tablosu erişilebilir mi? (anon yetkisi)
- C) `notification_outbox` RLS ile anon için tamamen kapalı mı?
- D) `send-push` Edge Function 410 Gone mi? (decommissioned)
- E) Test kullanıcısı giriş yapabiliyor mu?

### 5.4 Statik kaynak taraması (mevcut)

**Dosya:** `test/secure_push/push_client_calls_test.dart`

```bash
flutter test test/secure_push/push_client_calls_test.dart
```

`lib/` içinde:
- `functions.invoke('send-push'...)` veya `functions.invoke('send-push-notification'...)` çağrısı var mı? → ❌ ise ihlal.
- `from('profiles').select('fcm_token'...)` var mı? → ❌ ise ihlal (token sızıntısı).

### 5.5 DB değişmezleri (pgTAP)

**Dosya:** `supabase/tests/database/003_secure_push_pipeline_invariants.test.sql`

```bash
# supabase start ile lokal Supabase ayağa kalktıktan sonra
supabase test db
```

20 testten oluşur; outbox şeması, RPC varlığı, eski trigger'ların kaldırılması, admin RPC'leri, notify_price_drops net.http_post içermemesi vb. doğrular.

---

## 6. Acil Yapılacaklar (Operasyonel)

### 6.1 Push hiç gelmiyorsa (en hızlı 5 adım)

1. **Supabase Dashboard → SQL Editor →** `supabase/diagnostics/20260807_push_pipeline_health_check.sql` dosyasını çalıştır.
2. **C2 kontrolünde** ❌ görüyorsan: `20260802000004_push_outbox_cron_scheduler.sql` çalıştır; öncesinde Dashboard → Database → Settings → Custom Postgres Config'e `app.settings.internal_worker_secret = '<SECRET>'` ekle.
3. **E kontrolünde** ⚠️ görüyorsan: `supabase secrets set INTERNAL_WORKER_SECRET=<SECRET>` + Edge Function redeploy.
4. **I kontrolünde** tokensiz % > 50 ise: 1-2 test kullanıcısıyla uygulamayı aç, çıkış-yap, tekrar giriş yap; `PushNotificationService.initialize()` loglarını kontrol et.
5. **H kontrolünde** pending > 100 ise: worker yavaş; `max_attempts=8` ile 8 retry yeterli olmalı; cron her dakika çalışıyorsa 1 saat içinde boşalmalı.

### 6.2 Çift bildirim oluyorsa

1. **Diagnostic DRY-RUN:** `supabase/diagnostics/20260807_push_dedup_invariants.sql` üst sorgular.
2. **Hangi tip çift:** `type` kolonuna göre dağılım.
3. **Sipariş teslim ise** (en yaygın): `plans/SIPARIS_BILDIRIM_KURYE_FIX_PLAN.md` Görev 1'i uygula:
   - `order_service.dart:722` `OrderStatus.delivered` case'ini kaldır
   - `seller_orders_screen.dart:336` `_sendStatusNotificationToCustomer` içinde delivered case'ini kaldır
   - `courier_notification_service.dart:387` `pending_review` insert bloğunu kaldır
4. **Genel çift ise:** `notification_service.dart:62-83` dedup mantığını `(entityId, type)` bazlı yap, `title` yerine.

### 6.3 Bildirim tercihi kapalı kullanıcılar için

`notification_preferences` tablosunda `order_updates_enabled=false` veya benzeri false ise `NotificationService.createNotification` `if (!isEnabled) return;` ile hiç insert etmiyor. Bu davranış doğru (kullanıcı kapatmış); kullanıcıya UI'dan açması gerektiğini bildir.

---

## 7. Uzun Vadeli İyileştirmeler

1. **DB seviyesi UNIQUE constraint:**
   ```sql
   ALTER TABLE public.notifications
     ADD CONSTRAINT notifications_user_type_entity_dedup
     UNIQUE NULLS NOT DISTINCT (user_id, type, entity_id);
   -- (PostgreSQL 15+ syntax; eski sürümde partial unique index)
   CREATE UNIQUE INDEX notifications_dedup_idx
     ON public.notifications (user_id, type, COALESCE(entity_id, ''))
     WHERE entity_id IS NOT NULL;
   ```
   Mevcut duplicate'leri temizledikten sonra eklenebilir.

2. **Push başarı metrikleri:** `notification_outbox` üzerinde bir metrik view'ı oluştur: `sent/failed/dead` oranları saatlik olarak `pg_cron` ile bir `notification_metrics` tablosuna yazılsın.

3. **FCM error code'larını structured logla:** Worker'da `UNREGISTERED` / `INVALID_ARGUMENT` token'lar temizleniyor; diğer hata kodlarını (quota, internal) de categorize et.

4. **Bildirim test modu:** Debug build'lerde `lib/core/services/notification_service.dart` `createNotification` fonksiyonuna `--debug-notifications` flag'i ekle: hangi tercih nedeniyle düştüğünü, outbox satırını, FCM yanıtını logla.

5. **`admin_broadcasts` → push eşdeğerli:** Plan belgelerinde not düşülen `admin_broadcasts` tablosundan topic push yansıması yapılmamış. Realtime subs ile kullanıcı tarafı broadcast'leri görüyor ama push gitmiyor. Bu bilinçli bir karar (güvenlik); admin panelinde "Bu duyuruyu push olarak da gönder" toggle'ı eklenebilir.

---

## 8. Sonuç ve Hızlı Kontrol Listesi

| Soru | Yanıt |
|---|---|
| Push hiç gelmiyor mu? | `supabase/diagnostics/20260807_push_pipeline_health_check.sql` çalıştır. C2'de ❌ → cron kur. E'de ⚠️ → secret set et. I'da ❌ → kullanıcı yeniden giriş yapsın. |
| Çift bildirim geliyor mu? | `supabase/diagnostics/20260807_push_dedup_invariants.sql` DRY-RUN. type='order_delivered' çıkıyorsa `SIPARIS_BILDIRIM_KURYE_FIX_PLAN.md` Görev 1. |
| Push geliyor ama bildirim listede görünmüyor mu? | `notifications` tablosunda INSERT var mı? Yoksa `notification_preferences` kapalı. Varsa outbox'ta `pending`/`sent` durumuna bak. |
| Push geliyor, listede var, ama cihazda badge yanmıyor mu? | `flutter_local_notifications` Android kanal kontrolü; `showBadge: true` zaten var (`high_importance_channel`). Kanal kullanıcı tarafından "önemsiz" olarak işaretlenmiş olabilir. |
| Eski sürümden yükseltildi, push gelmiyor? | `20260803000006_secure_profiles_privileges_and_pii.sql` uygulanmamış olabilir → `set_my_fcm_token` RPC yok → `_saveFCMToken` sessizce başarısız oluyor → token NULL kalıyor. |

---

**Hazırlayan:** Claude (Claude Code)
**Tarih:** 2026-08-07 19:10 UTC+3
**Versiyon:** 1.0
