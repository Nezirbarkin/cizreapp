# ADIM 3 — Güvenli Push Notification Pipeline

Tarih: 2026-08-02
Kapsam: Yalnızca push bildirim hattının tekil, güvenli, güvenilir
hale getirilmesi. Diğer mimari sorunlara geçilmez.

---

## 1. Kök neden (özet)

Push bildirim hattı üç farklı güvenlik açığı taşıyor:

1. **Anom kullanıcı keyfi push gönderebiliyor** — `send-push` Edge
   Function'ı çağıranın kimliğini doğrulamıyor, request body'sinden
   `user_id`, `title`, `body`, `topic` kabul ediyor. Service role ile
   başka kullanıcının FCM token'ını okuyup mesaj atabiliyor.
2. **Yetkisiz roller genel push tetikleyebiliyor** — `send-push-notification`
   fonksiyonu seller/courier/driver/news rollerine başka kullanıcı adına
   serbest title/body ile push gönderebiliyor.
3. **Trigger HTTP çağrısı yapıyor** — `send_push_on_notification` ve
   `notify_price_drops` fonksiyonları sabit project URL + anon JWT ile
   `net.http_post` çağrısı yapıyor; hata olursa yutuluyor, çift push
   üretilebiliyor, Flutter tarafında ek olarak manuel `functions.invoke`
   çağrıları yapılıyor.

Hedef: Flutter istemcisi asla FCM token göremez, push gönderemez;
güvenli domain RPC'leri notifications + outbox kaydı oluşturur; tek bir
worker FCM'ye gönderir.

---

## 2. Bulgu taraması — tüm çağrı noktaları

### 2.1 `send-push` / `send-push-notification` çağrıları (Flutter)

| Dosya | Satır(lar) | Amaç |
|---|---|---|
| `lib/features/profile/screens/user_profile_screen.dart` | 2693 | Post paylaşımı push |
| `lib/features/profile/screens/profile_screen.dart` | 2354 | Post paylaşımı push |
| `lib/features/admin/widgets/notifications_content_v2.dart` | 1456, 1514 | Admin kişisel + topic push |
| `lib/features/admin/screens/admin_dashboard_parts/_part_courier.dart` | 1102 | Kurye ödeme onayı push |
| `lib/core/services/transfer_service.dart` | 194 | Havale onay/red push |
| `lib/core/services/courier_notification_service.dart` | 143, 330, 372 | Kurye atama + toplu kurye push |

### 2.2 `fcm_token` okumaları (Flutter)

- `lib/core/services/notification_service.dart:186`
- `lib/core/services/transfer_service.dart:187`
- `lib/core/services/courier_notification_service.dart:122, 219`
- `lib/features/admin/screens/admin_dashboard_parts/_part_courier.dart:1095`
- `lib/core/services/push_notification_service.dart` (kendi token'ını yazar —
  bu meşru, değişmeyecek)

### 2.3 SQL tarafı

| Migration | Satır | Sorun |
|---|---|---|
| `20260411120004_push_notification_trigger.sql` | 23, 26, 30-49 | sabit URL + anon JWT + `net.http_post` |
| `20260726120001_flash_sale_and_price_alert_setup.sql` | 261-262, 287-307 | sabit URL + anon JWT + `net.http_post` |
| `20260208000004_fix_chat_notification_trigger.sql` | — | eski chat push trigger'ı (ilgisiz) |
| `20260208000002_chat_push_notification_trigger.sql` | — | eski chat push trigger'ı (ilgisiz) |

---

## 3. Mimari hedef akış

```
Güvenli domain RPC (server-side)
  → INSERT public.notifications
  → AFTER INSERT trigger → INSERT public.notification_outbox
  → Worker (process-notification-outbox) periyodik claim eder
  → FCM HTTP v1 API
  → status: sent | failed (retry) | dead
```

- Outbox, notification_id referansı taşır; ham FCM token'ı içermez.
- Worker, `notification_outbox` ve `notifications` satırlarını server
  tarafında okur, FCM token'ını `profiles.fcm_token` + `notification_tokens`
  tablolarından kendisi alır.
- Aynı `notification.id` UNIQUE constraint ile sadece bir kez kuyruğa
  girer. Worker `FOR UPDATE SKIP LOCKED` ile atomik claim eder.

---

## 4. Uygulama adımları

### 4.1 Yeni ileri migration

**Dosya**: `supabase/migrations/20260802000003_secure_push_notification_pipeline.sql`

İçeriği:

1. **Eski nesneleri etkisizleştir**
   - `DROP TRIGGER IF EXISTS notifications_push_trigger ON notifications;`
   - `DROP TRIGGER IF EXISTS products_price_drop_alert ON products;`
   - Eski `send_push_on_notification` ve `notify_price_drops` SQL
     fonksiyonlarının isimlerini değiştirerek "kullanılmaz" hale getir:
     `send_push_on_notification_DEPRECATED` ve `notify_price_drops_LEGACY`
     olarak yeniden adlandır. Yeni canlı tanımlar aşağıda.
   - NOT: Önceki migration dosyaları değiştirilmeyecek; sadece ileri
     migration ile yeni canlı nesneler yazılacak.

2. **`public.notification_outbox` tablosu**
   ```sql
   create table public.notification_outbox (
     id uuid primary key default gen_random_uuid(),
     notification_id uuid not null references public.notifications(id) on delete cascade,
     status text not null default 'pending'
       check (status in ('pending','processing','sent','failed','dead')),
     attempts int not null default 0,
     next_attempt_at timestamptz not null default now(),
     locked_at timestamptz,
     locked_by text,
     last_error text,
     sent_at timestamptz,
     created_at timestamptz not null default now(),
     updated_at timestamptz not null default now(),
     constraint notification_outbox_notification_uniq unique (notification_id)
   );
   create index idx_outbox_pending on public.notification_outbox(next_attempt_at)
     where status in ('pending','failed');
   create index idx_outbox_locked on public.notification_outbox(locked_by)
     where status = 'processing';
   alter table public.notification_outbox enable row level security;
   -- RLS: anon/authenticated için tüm işlemleri kapat.
   -- Yalnızca SECURITY DEFINER RPC'ler ve service_role erişir.
   ```
   RLS politikası:
   ```sql
   create policy "outbox_no_direct_access"
     on public.notification_outbox for all
     to authenticated, anon
     using (false) with check (false);
   ```
   `GRANT SELECT,INSERT,UPDATE,DELETE` yalnızca `service_role`'a verilecek;
   client rolleri için yalnızca red.

3. **`enqueue_notification_outbox()` SECURITY DEFINER RPC**
   - Parametre: `p_notification_id uuid`.
   - Davranış: `ON CONFLICT (notification_id) DO NOTHING` ile outbox'a
     insert. Hata fırlatmaz (idempotent).
   - `REVOKE EXECUTE FROM PUBLIC, anon, authenticated;`
   - `GRANT EXECUTE TO service_role;`
   - `SET search_path = public, pg_temp;`

4. **`claim_notification_outbox(p_limit int, p_worker_id text)` RPC**
   - `FOR UPDATE SKIP LOCKED` ile N kayıt alır.
   - Her birinin `status='processing'`, `locked_at=now()`,
     `locked_by=p_worker_id`, `attempts=attempts+1`,
     `next_attempt_at=now() + interval '15 seconds' * (attempts+1)` yap.
   - RETURNING ile outbox satırlarını + JOIN ile notification içeriğini
     döndür.
   - `REVOKE EXECUTE FROM PUBLIC, anon, authenticated;`
   - `GRANT EXECUTE TO service_role;`

5. **`mark_outbox_sent(p_outbox_id uuid)` ve `mark_outbox_failed(...)`**
   - `sent`: status='sent', sent_at=now(), locked_* null.
   - `failed`: attempts artışı, max_attempts (örn 8) aşıldıysa status='dead'.
   - Service role only.

6. **`release_stale_outbox(p_max_age interval)` RPC**
   - Worker crash koruması: `locked_at < now() - p_max_age` olan
     processing kayıtlarını pending'e geri al.

7. **Yeni `notify_on_notification()` AFTER INSERT trigger**
   - `pg_net` çağrısı YAPMAZ.
   - Sadece `enqueue_notification_outbox(NEW.id)` çağırır.
   - SECURITY DEFINER; chat/message tipleri için outbox'a ekleme
     (mevcut davranışla uyumlu, ama bu kez outbox'a eklemez; sessizce
     geçer — chat için ayrı tetikleyici zaten var).
   - `SET search_path = public, pg_temp;`
   - Trigger `notifications_push_trigger` yerine yeni isimle bağlanır:
     `notifications_outbox_trigger`.
   - Mevcut `notifications_push_trigger` yukarıda DROP edildi.

8. **Yeni `notify_price_drops()`**
   - `CREATE OR REPLACE FUNCTION` ile mevcut tanımın üzerine yaz.
   - Sabit URL/JWT kaldırılır, `net.http_post` çağrısı yok.
   - Sadece `INSERT INTO notifications (...)` yapar. Genel trigger zaten
     outbox kaydını oluşturur.
   - **Çift notification engeli**: aynı `product_id` ve `user_id` için
     aktif `price_alerts` varsa `triggered_at`'i kontrol et; aynı
     `product_id`/`user_id` için son 24 saat içinde `type='price_drop'`
     notification varsa yeni bildirim oluşturma. (Mevcut `triggered_at`
     ile zaten ikinci kez alarm çalışmaz — `is_active=false`'a çekiliyor.
     Bu koruma zaten sağlam; ek olarak 24 saat penceresi eklenir.)
   - SECURITY DEFINER, `SET search_path = public, pg_temp;`
   - EXECUTE: `REVOKE ... FROM PUBLIC, anon`, `GRANT ... TO authenticated`.

9. **Yetki düzeltmeleri (forward migrations)**
   - `public.send_push_on_notification` → `send_push_on_notification_DEPRECATED`
     (eski body aynen kalır ama erişilemez; REVOKE EXECUTE).
   - `public.notify_price_drops` → `notify_price_drops_LEGACY` değil;
     `CREATE OR REPLACE` ile yukarıdaki yeni tanım geçerli olur. Eski
     tetikleyici (products_price_drop_alert) `DROP TRIGGER` ile kaldırıldı,
     yeni tetikleyici `products_price_drop_alert_v2` adıyla bağlanır.

10. **Share-post için dar kapsamlı RPC**
    - `public.share_post_with_user(p_post_id uuid, p_recipient_id uuid)`
    - SECURITY DEFINER; `auth.uid()` zorunlu.
    - Post mevcut mu (`public.posts` kontrol), `is_hidden=false` veya
      alıcı dost mu, gönderen paylaşım yetkisi var mı (`posts.privacy =
      'public'` veya `privacy = 'friends'` ve `auth.uid()` ile
      takipleşiliyor). Gizli/silinmiş/yasaklı reddedilir.
    - Alıcı = gönderen ise reddedilir.
    - `INSERT INTO public.notifications` server tarafında
      `type='post_share'`, `actor_id=auth.uid()`, `user_id=p_recipient_id`,
      `entity_id=p_post_id` ile yapılır. Title/content server tarafında
      üretilir (sabit metin: "Gönderi paylaşıldı").
    - Idempotency: aynı `(actor_id, user_id, entity_id, type='post_share')`
      için son 1 dakika içinde notification varsa yeni insert yapmaz.
      Bunu sağlamak için trigger ile outbox'a eklenmeden önce
      `EXISTS` kontrolü eklenir.
    - REVOKE EXECUTE FROM PUBLIC, anon; GRANT EXECUTE TO authenticated.

### 4.2 Backend worker

**Yeni dosya**: `supabase/functions/process-notification-outbox/index.ts`

- Secret koruma:
  - `INTERNAL_WORKER_SECRET` env değişkeni zorunlu.
  - HTTP `x-worker-secret` (veya `Authorization: Bearer <secret>`) header'ı
    eşleşmezse 401.
- Yöntem: sadece POST.
- Config:
  - `claim_limit` default 25.
  - `max_attempts` default 8.
- Adımlar:
  1. `service_role` ile `claim_notification_outbox` RPC çağır.
  2. Her outbox satırı için ilgili notification satırını oku
     (`type`, `user_id`, `title`, `content`, `metadata`, `entity_id`).
  3. Hedef kullanıcının FCM token(lar)ını `profiles.fcm_token` +
     `notification_tokens` tablosundan al.
  4. FCM HTTP v1 API ile gönder.
  5. UNREGISTERED/NOT_FOUND token'ları güvenli şekilde temizle
     (UPDATE profiles SET fcm_token = NULL ... ve DELETE FROM
     notification_tokens ...).
  6. Başarı → `mark_outbox_sent`.
  7. Hata → `mark_outbox_failed` (exponential backoff outbox tarafında).
  8. Tüm FCM token / service account / OAuth header / notification data
     loglanmaz. Sadece `notification_id` (uuid) ve `user_id` (uuid) +
     generic status bilgisi loglanır.
- `CORS` eklenmez; istemci burayı çağırmaz.
- Config.toml'a eklenecek: `verify_jwt = false` (JWT yok, secret var).

### 4.3 Eski Edge Function'lar

- `supabase/functions/send-push/index.ts` ve
  `supabase/functions/send-push-notification/index.ts` dosyaları
  **silinecek** (yerel kaynak kaldırma + canlıda `supabase functions
  delete`).
- Silinemiyorsa bile tüm fonksiyon gövdeleri 410 Gone döndürür
  hale getirilecek; `auth.uid()` veya service role bypass YOK.
- `supabase/config.toml` kayıtları bu fonksiyonlar için kaldırılacak.

### 4.4 Flutter tarafı düzeltmeleri

1. `lib/core/services/transfer_service.dart`
   - `_sendResolutionPush` tamamen kaldırılır.
   - `approveConfirmation`/`rejectConfirmation` sonrası
     `fcm_token` SELECT'i kaldırılır. RPC başarılı döndüğü için
     notification zaten trigger ile outbox'a yazılmış olacak.
   - `await _sendResolutionPush(...)` çağrıları silinir.

2. `lib/core/services/courier_notification_service.dart`
   - `_notifyCourierOfAssignment`: FCM token SELECT + `functions.invoke`
     blokları kaldırılır. Sadece `add_notification` RPC çağrısı kalır.
   - `notifyCouriersForNewOrder`: toplu kurye bildirimleri için
     `notifications` tablosuna toplu INSERT zaten mevcut (bunu
     koruyoruz). `_sendPushNotificationToCouriers` ve
     `sendPushNotificationToCouriers` tamamen kaldırılır.
   - `autoAssignCourierToOrder` zaten `add_notification` RPC'sini
     kullanıyor; ek push çağrısı yok, değişiklik gerekmez.

3. `lib/features/admin/screens/admin_dashboard_parts/_part_courier.dart`
   - Courier ödeme onayı sonrası yapılan `fcm_token` SELECT + push
     invoke bloğu kaldırılır. Sadece `notifications` INSERT kalır
     (zaten mevcut).

4. `lib/features/admin/widgets/notifications_content_v2.dart`
   - Admin kişisel bildirim için:
     - `functions.invoke('send-push', ...)` kaldırılır.
     - Yalnızca `notifications` INSERT yapılır.
     - Yeni `public.admin_send_personal_notification(p_user_id uuid,
       p_title text, p_content text, p_icon_type text)` dar kapsamlı
       RPC'si eklenir. Bu RPC admin rolünü server-side doğrular, içerik
       uzunluk sınırı uygular, audit kaydı (`admin_notification_audit`)
       oluşturur, ardından `notifications` INSERT yapar. Trigger
       outbox'a ekler.
   - Toplu bildirim (customers/sellers/all) için:
     - `functions.invoke('send-push-notification', ...)` (topic) kaldırılır.
     - Yeni `public.admin_broadcast_notification(p_title text,
       p_content text, p_icon_type text, p_target_audience text)` RPC'si
       eklenir. Sadece admin. `admin_broadcasts` tablosuna yazar.
       (Mevcut `admin_broadcasts` tablosu kullanılır.)
     - `notifications` toplu INSERT yok (mevcut yorumlarda zaten
       yapılmadığı yazıyor; bu iyi). Topic push gönderilmez — broadcast
       tablosundan Flutter push dinleyebilir veya realtime kanalı
       kullanılır. Bu refaktörün kapsamı dışında; sadece güvensiz
       kanalı kapatıyoruz.

5. `lib/features/profile/screens/user_profile_screen.dart` ve
   `lib/features/profile/screens/profile_screen.dart`
   - Post paylaşımı için `from('notifications').insert` + `functions.invoke`
     yerine sadece yeni `share_post_with_user(p_post_id, p_recipient_id)`
     RPC çağrılır. Hem ana ekran (share-to-friend) hem arkadas profili
     paylaşımı bu RPC'yi kullanır.

6. `lib/core/services/push_notification_service.dart`
   - Mevcut davranış: kendi FCM token'ını `profiles.fcm_token`'a
     yazıyor. Bu **meşru** — kullanıcı kendi cihazına ait token'ı
     yazıyor. Değiştirilmez.

7. **Genel arama temizliği**
   - Proje genelinde `functions.invoke('send-push` ve
     `functions.invoke('send-push-notification` çağrıları
     aranır ve kaldırılır. Doğrulama için aşağıdaki test kullanılır.

### 4.5 Admin notification audit tablosu

`public.admin_notification_audit` tablosu oluşturulur:
- `id`, `admin_id`, `action` (personal | broadcast), `target_audience`,
  `recipient_id` (nullable), `title`, `content`, `created_at`.

### 4.6 Yeni testler

- `supabase/tests/database/003_secure_push_pipeline_invariants.test.sql`
  - `notification_outbox` mevcut, RLS açık, `anon`/`authenticated`
    için SELECT/INSERT/UPDATE/DELETE reddi.
  - `enqueue_notification_outbox` yalnızca `service_role` EXECUTE alır.
  - `claim_notification_outbox` yalnızca `service_role` EXECUTE alır.
  - `share_post_with_user` yalnızca `authenticated` EXECUTE alır;
    self-share reddedilir; missing post reddedilir.
  - `notify_price_drops` yeni tanımında `net.http_post` çağrısı yok
    (kaynak kodu taraması yerine fonksiyon `prosrc` içinde string
    arama testi).
  - `send_push_on_notification` artık mevcut değil (DROP).
  - `notification_outbox_notification_uniq` UNIQUE constraint mevcut.
  - Bildirim INSERT sonrası outbox'a otomatik eklendiği testi (trigger
    sonrası rowcount).

- `supabase/functions/_shared/push_pipeline_security_test.ts`
  - Worker'a yetkisiz istek 401.
  - Worker'a yanlış secret 401.
  - Birim testi: claim RPC'si ile aynı kayıt ikinci kez claim edilemez
    (eşzamanlılık simülasyonu).
  - FCM 404/UNREGISTERED → token temizleme çağrısı yapılır.

- Flutter tarafı:
  - `test/secure_push/push_client_calls_test.dart` — kaynak taraması:
    `send-push` veya `send-push-notification` string'i içeren
    `functions.invoke` çağrısı kalmamış olmalı.

### 4.7 Çalıştırılacak testler

- `dart format` (sadece değişen dosyalar)
- `flutter analyze`
- Mevcut `flutter test`
- `deno lint supabase/functions/process-notification-outbox/`
- `deno check supabase/functions/process-notification-outbox/index.ts`
- `supabase db lint` (gerekli ise)
- Local ortamda migration dry-run (`supabase db push --dry-run`)
- **Canlıda `supabase db reset` YAPILMAYACAK**
- **Eski uygulanmış migration DEĞİŞTİRİLMEYECEK**

---

## 5. Değiştirilecek / oluşturulacak dosya envanteri

### Yeni dosyalar
- `supabase/migrations/20260802000003_secure_push_notification_pipeline.sql`
- `supabase/functions/process-notification-outbox/index.ts`
- `supabase/functions/_shared/push_pipeline_security_test.ts`
- `supabase/tests/database/003_secure_push_pipeline_invariants.test.sql`
- `test/secure_push/push_client_calls_test.dart`

### Silinecek dosyalar
- `supabase/functions/send-push/index.ts`
- `supabase/functions/send-push-notification/index.ts`

### Değişecek Flutter dosyaları
- `lib/core/services/transfer_service.dart`
- `lib/core/services/courier_notification_service.dart`
- `lib/features/admin/screens/admin_dashboard_parts/_part_courier.dart`
- `lib/features/admin/widgets/notifications_content_v2.dart`
- `lib/features/profile/screens/user_profile_screen.dart`
- `lib/features/profile/screens/profile_screen.dart`

### Değişecek config
- `supabase/config.toml` (eski fonksiyon kayıtları temizlenir, yeni
  worker için `verify_jwt = false` eklenir)

### Değişmeyecek
- Önceden uygulanmış tüm migration dosyaları.
- `lib/core/services/push_notification_service.dart` (kendi token'ını
  yazma meşru).
- `lib/core/services/notification_service.dart` (bu sadece FCM token
  okur ama bunu push göndermek için değil, gönderim mantığı içermez;
  ancak dosya push göndermek için kullanılmıyorsa bırakılır. Kontrol
  edilecek.)

---

## 6. Authorization matrisi (yeni durum)

| Aktör | Çağrı | Yetki | Sonuç |
|---|---|---|---|
| Anonim istemci | `process-notification-outbox` | yok (no JWT, no secret) | 401 |
| Anonim istemci | `send-push` (eski) | deploy kaldırıldı | 404 |
| Anonim istemci | `send-push-notification` (eski) | deploy kaldırıldı | 404 |
| Customer Flutter | `share_post_with_user` | authenticated | OK (self-share reddedilir) |
| Customer Flutter | `enqueue_notification_outbox` | yok (SECURITY DEFINER + service_role only) | 403 |
| Customer Flutter | `claim_notification_outbox` | yok | 403 |
| Seller Flutter | `enqueue_notification_outbox` | yok | 403 |
| Courier Flutter | `enqueue_notification_outbox` | yok | 403 |
| Driver Flutter | `enqueue_notification_outbox` | yok | 403 |
| News Flutter | `enqueue_notification_outbox` | yok | 403 |
| Admin Flutter | `admin_send_personal_notification` | admin role + dar parametreler | OK |
| Admin Flutter | `admin_broadcast_notification` | admin role + dar parametreler | OK |
| Server (worker, service_role + secret) | `process-notification-outbox` | `INTERNAL_WORKER_SECRET` | OK |

---

## 7. Outbox/worker akışı (özet)

```
INSERT notifications
    ↓ AFTER INSERT trigger
enqueue_notification_outbox(notification_id)
    ↓ ON CONFLICT DO NOTHING (UNIQUE)
INSERT notification_outbox (status='pending')

[periyodik çağrı]
POST process-notification-outbox  (x-worker-secret)
    ↓ claim_notification_outbox(limit, worker_id) — FOR UPDATE SKIP LOCKED
her kayıt için:
    ↓ read notifications + profiles.fcm_token + notification_tokens
    ↓ FCM HTTP v1
    ↓ başarı → mark_outbox_sent
    ↓ başarısız → mark_outbox_failed (artar attempts; max geçildiyse dead)
    ↓ UNREGISTERED → DELETE fcm_token
```

---

## 8. Kullanıcıdan beklenen manuel işlemler

- `INTERNAL_WORKER_SECRET` üretmek ve Supabase Edge Secrets'a
  `supabase secrets set INTERNAL_WORKER_SECRET=...` ile yazmak.
- `FIREBASE_SERVICE_ACCOUNT` zaten kurulu varsayımı; yoksa
  set edilecek.
- Worker zamanlaması: Supabase Dashboard → Database → Cron Jobs veya
  harici scheduler (cron, GitHub Actions, vs.). Migration bunu yapmaz.
  Kullanıcı seçimine bırakılır; **uygulama adımı olmadan geçici
  scheduler eklenmez**.
- Eski iki fonksiyonun canlıdan kaldırılması:
  `supabase functions delete send-push --project-ref <ref>`
  `supabase functions delete send-push-notification --project-ref <ref>`

---

## 9. Kalan riskler

- Worker'ın periyodik çalıştırılması için scheduler gerekiyor; bu
  dışarıdan sağlanmadıkça outbox birikir.
- Eski `chat_push_notification_trigger` ve benzeri eski trigger'lar
  ayrı bir refaktör; bu adımda sadece `notifications_push_trigger` ve
  `products_price_drop_alert` etkisizleştirilir.
- `admin_broadcasts` → topic push eşdeğerli realtime yansıması bu
  adımda yapılmaz; sadece güvensiz push kanalı kapatılır.
- Topic push kaldırıldı; admin broadcast'leri artık sadece
  `admin_broadcasts` tablosu üzerinden yayılır. Realtime subs var mı
  kontrol edilecek; yoksa kullanıcılar yeni broadcast'i görmek için
  listeyi yenilemek zorunda kalır. Bu **kabul edilen trade-off** —
  güvenlik yararı, UX kaybını haklı çıkarır.
- `notification_tokens` tablosu bu kod tabanında hiç kullanılmıyor
  görünüyor; outbox/worker `notification_tokens` zaten okumuyor. Bu
  refaktörde değiştirilmez.

---

## 10. Uygulama sırası (kullanıcı onayı sonrası)

1. Migration dosyasını yaz.
2. Worker fonksiyonunu yaz.
3. Eski iki fonksiyonu 410 stub'a çevir veya sil.
4. Flutter düzeltmelerini uygula.
5. config.toml'u güncelle.
6. Test dosyalarını yaz.
7. Static analiz + format + deno lint.
8. Raporu ver.
