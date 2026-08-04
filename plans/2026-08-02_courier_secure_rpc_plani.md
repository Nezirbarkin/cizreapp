# Kurye Paket/Ödeme RPC'lerini Sunucu Otoritesine Taşıma Planı

**Tarih:** 2026-08-03
**Kapsam:** `courier_requests`, `courier_earnings`, `courier_payout_requests` ve yardımcı sipariş RPC'leri. Tüm finansal akış + PII görünürlüğü + admin payout onay/red.

---

## 1. Mimari kararlar

- **Tek yönlü akış (state machine):** `pending → accepted → delivery_pending_confirmation → delivered`. `delivery_pending_confirmation` yeni ara durum; gönderici tek adımla onaylayınca kurye kazancı atomik oluşur.
- **Sunucu otoritesi:** Tüm finansal/timestamp/courier_id alanları istemciden kabul edilmez; sunucu hesaplar.
- **PII ayrımı:** Bekleyen havuz RPC'leri yalnız `id, distance_km, total_fee, created_at, delivery_card_label, shop_name` döner. Tam PII (ad, telefon, adres, koordinat, açıklama) yalnız atanmış kurye için `get_assigned_package_details(p_request_id)` ile.
- **Payout modeli:** Yeni `courier_payout_items(payout_id, earning_id, amount_snapshot, status)` tablosu. `request_courier_payout` tüm `pending` earnings'leri `FOR UPDATE` ile kilitler, `requested` yapar, payout header + item satırlarını aynı TX'te oluşturur. `admin_approve_courier_payout` yalnız payout'a bağlı item'ları `paid` yapar.
- **Çift aksiyon koruması:** `courier_request_rejections` normalized tablo + `(request_id, courier_id)` unique. `accept_package_request` `FOR UPDATE` + status/courier_id atomik.
- **Idempotency:** `create_package_request(p_idempotency_key UUID)` parametreli. `(sender_id, idempotency_key)` UNIQUE. Çift tıklama aynı talebi döner.
- **`deduct_from_balance` paket akışından çıkıyor:** Authenticated EXECUTE'ı revoke edilir (kurye ödemesi zaten service_role/admin tarafından yapılır; paket ücreti `create_package_request` içinde atomik yapılır). Diğer service_role çağrıları bozulmaz.

## 2. Migration dosyası: `supabase/migrations/20260802000005_secure_courier_delivery_and_payout.sql`

İçerik sırası:

1. **Ön hazırlık**
   - `courier_requests.idempotency_key uuid` ve `(sender_id, idempotency_key)` UNIQUE INDEX (NULL'lar ayrı tutulur).
   - `courier_requests.delivery_confirmed_at timestamptz`, `delivery_confirmed_by uuid`.
   - `courier_requests.delivery_card_label text` (snapshot).
   - `courier_earnings` üzerinde `package_request_id IS NOT NULL` koşullu UNIQUE INDEX (idempotent earnings).
   - `courier_earnings.amount_snapshot numeric(12,2)` (kazanç oluşturulduğunda snapshot).
   - Yeni `courier_request_rejections(request_id uuid, courier_id uuid, created_at timestamptz DEFAULT now(), PRIMARY KEY(request_id, courier_id))`.
   - Yeni `courier_payout_items(id uuid PK, payout_id uuid NOT NULL REFERENCES courier_payout_requests(id) ON DELETE CASCADE, earning_id uuid NOT NULL REFERENCES courier_earnings(id) ON DELETE RESTRICT, amount_snapshot numeric(12,2) NOT NULL, status text NOT NULL DEFAULT 'pending', created_at timestamptz DEFAULT now())` + UNIQUE(earning_id) + indexler.
   - `courier_payout_requests` üzerinde `(courier_id) WHERE status='pending'` partial UNIQUE INDEX (birden fazla açık payout engeli).
   - `courier_requests` performans indexleri: `(status, created_at)`, `(courier_id, status)`.

2. **Helper RPC'ler (internal)**
   - `private.is_courier_role()` → profiles.role='courier' kontrolü, SECURITY DEFINER. authenticated + service_role grant.
   - `private.is_admin()` zaten varsa yeniden kullan.

3. **A. create_package_request**
   - Paramlar: `p_pickup_lat double precision, p_pickup_lng double precision, p_delivery_lat double precision, p_delivery_lng double precision, p_sender_name text, p_sender_phone text, p_recipient_name text, p_recipient_phone text, p_pickup_address text, p_delivery_address text, p_delivery_address_detail text DEFAULT NULL, p_description text DEFAULT NULL, p_idempotency_key uuid`.
   - Sunucu: `auth.uid()`; `courier_service_settings` okur (enabled + allows_user_requests + base_fee + per_km_fee + commission_percent). Mesafe Haversine. Ücreti `numeric(12,2)`'ye round. `courier_fee = round(total_fee * (1 - commission/100), 2)`, `admin_commission = total_fee - courier_fee`. `user_balances FOR UPDATE` kilidi. Bakiye kontrolü. `balance_transactions` insert. `courier_requests` insert. Idempotency: aynı `(sender_id, key)` mevcutsa mevcut `id` döner (yeni insert/transaction yapmaz, hata da vermez).
   - TX rollback: herhangi bir adımda hata → talep + transaction ikisi de geri alınır.
   - GRANT: yalnız authenticated.
   - RETURN: `TABLE(id, total_fee, courier_fee, admin_commission, status, created_at)`.

4. **B. list_available_package_requests()**
   - Param yok. `auth.uid()` + `is_courier_role()`.
   - Sorgu: `status='pending' AND courier_id IS NULL AND sender_id <> auth.uid() AND (cardinality(rejected_by) = 0 OR NOT (auth.uid() = ANY(rejected_by)))` (rejected_by sütunu fallback olarak korunur; yeni `courier_request_rejections` de kullanılır; ikisi arasında OR — yeni tablo yazma).
   - RETURN: `id, distance_km, total_fee, courier_fee, delivery_card_label, created_at, delivery_window_minutes, weight_kg` (varsa).

5. **B2. list_available_orders()** (marketplace siparişleri)
   - `get_available_orders_for_courier(uuid)` REPLACE: `auth.uid()` kullanır, kurye rolü doğrular, PII döndürmez. RETURN: `id, total, shop_id, shop_name, created_at, order_item_count`.
   - Parametre imzası değiştiği için `DROP FUNCTION get_available_orders_for_courier(uuid)` önce.

6. **B3. get_courier_active_orders()** REPLACE: atanmış kurye/admin için tam PII döndürür, `auth.uid()` zorunlu. Sütun listesi sabit.

7. **B4. get_assigned_package_details(p_request_id uuid)**: atanmış kurye/sender/admin için tam PII. Tek satır döner. `auth.uid()` zorunlu.

8. **C. accept_package_request(p_request_id uuid)**
   - `auth.uid()` + `is_courier_role()`. `FOR UPDATE` kilit. `status='pending' AND courier_id IS NULL` kontrolü. Snap-shot'tan `courier_fee/admin_commission` yeniden hesaplanır. `status='accepted'`, `courier_id=auth.uid()`, `accepted_at=now()`. `courier_request_rejections` insert (ON CONFLICT do nothing) veya rejected_by sütunundan temizleme.
   - RETURN: tek satır tam PII (B4 ile aynı).
   - GRANT: authenticated.

9. **C2. reject_package_request(p_request_id uuid)**
   - `auth.uid()`. `courier_request_rejections` INSERT ON CONFLICT. rejected_by sütununa da append (atomic update: `rejected_by = rejected_by || ARRAY[auth.uid()] WHERE NOT (auth.uid() = ANY(rejected_by))`).
   - GRANT: authenticated.

10. **D. request_package_delivery_confirmation(p_request_id uuid)**
    - Yalnız atanmış kurye (`courier_id = auth.uid() AND status='accepted'`). Status `delivery_pending_confirmation`. `delivery_requested_at=now()`.

11. **D2. confirm_package_delivery(p_request_id uuid)**
    - Yalnız gerçek sender (`sender_id = auth.uid()`) VEYA admin. Talep `FOR UPDATE`. Yalnız `status='delivery_pending_confirmation' OR status='accepted'` (geriye dönük kabul). status='delivered', `delivered_at=now()`, `delivery_confirmed_at=now()`, `delivery_confirmed_by=auth.uid()`. Aynı TX'te `courier_earnings` INSERT (idempotent: `package_request_id` koşullu unique). `profiles.delivered_count = delivered_count + 1` (atomic UPDATE, RLS bu kolonu authenticated'e yazdırmamalı — bu yüzden helper RPC içinde SECURITY DEFINER ile yapılır). `notifications` INSERT (outbox trigger'a düşer).

12. **D3. admin_resolve_package_dispute(p_request_id uuid, p_resolution text, p_confirm boolean)**
    - Yalnız admin. `resolution` audit. `confirm=true` → D2 ile aynı (kazanç oluşur); `false` → status='cancelled', kazanç oluşmaz. Audit.

13. **E. request_courier_payout(p_idempotency_key uuid)**
    - `auth.uid() + is_courier_role()`. Açık payout partial unique index'i sayesinde aynı anda iki payout oluşmaz. `courier_earnings FOR UPDATE WHERE courier_id=auth.uid() AND status='pending'`. Tutar = toplam. Payout INSERT. Items INSERT (her earning için). Earnings UPDATE status='requested'. RETURN: payout header + item count.
    - Hiç earnings yoksa hata.

14. **E2. admin_approve_courier_payout(p_payout_id uuid, p_payment_reference text)**
    - Yalnız admin. Payout FOR UPDATE. `status='pending'`. Items UPDATE status='paid'. Earnings UPDATE (sadece payout'a bağlı earnings) status='paid'. Payout status='approved', `approved_at=now()`, `approved_by=auth.uid()`, `payment_reference=p_payment_reference`. Notifications.

15. **E3. admin_reject_courier_payout(p_payout_id uuid, p_reason text)**
    - Yalnız admin. Items UPDATE status='rejected'. Earnings UPDATE (sadece payout'a bağlı) status='pending' (geri kazançlı duruma). Payout status='rejected', `rejected_at=now()`, `rejection_reason=p_reason`. Notifications.

16. **F. deduct_from_balance yalıtımı**
    - `REVOKE EXECUTE … FROM authenticated` (her overload). service_role grant korunur.

17. **G. RLS temizliği**
    - `DROP POLICY IF EXISTS` aşağıdakiler:
      - `courier_requests`: `courier_requests_authenticated`, `Users can view own courier requests`, `Couriers can update assigned requests`, `courier_requests_select_scoped`, `courier_requests_insert_sender`, `courier_requests_update_courier_or_admin`, `courier_requests_delete_sender_or_admin`.
      - `courier_earnings`: `Admins update earnings`, `Admins view all earnings`, `Couriers insert own earnings`, `Couriers view own earnings`.
      - `courier_payout_requests`: `Admins update payouts`, `Admins view all payouts`, `Couriers create payouts`, `Couriers view own payouts`.
    - Yeni politikalar:
      - `courier_requests`:
        - `cr_select_owner_or_admin`: SELECT TO authenticated USING (sender_id = (SELECT auth.uid()) OR courier_id = (SELECT auth.uid()) OR is_admin()).
        - `cr_insert_sender_only`: INSERT TO authenticated WITH CHECK (sender_id = (SELECT auth.uid()) AND courier_id IS NULL AND status = 'pending').  ← yalnız geriye uyumluluk için; create_package_request tercih edilir.
        - `cr_update_admin`: UPDATE TO authenticated USING (is_admin()) WITH CHECK (is_admin()).
        - `cr_delete_admin`: DELETE TO authenticated USING (is_admin()).
        - Couriers tüm UPDATE yetkisini kaybeder (RPC üzerinden yapar). Ancak `accept_package_request` SECURITY DEFINER ve tabloya doğrudan yazacak → tablo grant'lerini authenticated'ten kaldırmamız gerekir.
      - `courier_earnings`: hiçbir authenticated INSERT/UPDATE/DELETE yapamaz. SELECT sadece `courier_id = auth.uid() OR is_admin()` (TO authenticated, OR birleşik).
      - `courier_payout_requests`: hiçbir authenticated INSERT/UPDATE/DELETE yapamaz. SELECT sadece `courier_id = auth.uid() OR is_admin()`.
    - Grant'ler: `REVOKE INSERT, UPDATE, DELETE ON courier_requests, courier_earnings, courier_payout_requests FROM authenticated;` (SELECT kalır).

18. **H. Outbox/bildirim tetikleyicisi**
    - `notifications` insert eden tüm RPC'ler (D2, D3, E2, E3) mevcut trigger'a güvenir (20260802000003).

19. **AUDIT VIEW'i migration içinde değil**; test dosyası içinde.

## 3. Test dosyası: `supabase/tests/database/004_courier_financial_security.test.sql`

pgTAP testleri (her biri `lives_ok`/`throws_ok`/`results_eq`):

1. Anon `create_package_request` çağıramaz.
2. Customer `courier_earnings` insert/update/delete yapamaz.
3. Customer `courier_payout_requests` insert yapamaz.
4. Courier `courier_earnings` insert/update yapamaz (RLS yok + grant yok).
5. Courier pending'ten `delivered`'a direkt UPDATE yapamaz (artık grant/RLS yok).
6. create_package_request sahte `total_fee` kabul etmez (sunucu hesaplar; istemcinin gönderdiği yoksayılır). Bunu test etmek için RPC `total_fee` parametresi yok; client fakedolar gönderemez. Test: insert sonrası `total_fee` döner ve settings ile uyumlu.
7. create_package_request atomik: yetersiz bakiye → talep ve transaction hiç oluşmaz.
8. İki kurye aynı talebi aynı anda kabul etmeye çalışırsa biri hata alır (race testi).
9. Courier pending havuzu: PII döndürmez (kolon adı kontrolü).
10. Normal customer `get_available_orders_for_courier(auth.uid())` çağırırsa PII sızmaz (returns rows; kolonlar).
11. Payout amount = items toplamı (matematiksel test).
12. İki kurye aynı anda payout isteği gönderirse biri hata alır (partial unique index).
13. Admin onayı yalnız bağlı earnings'leri `paid` yapar; aynı kuryenin diğer `pending` earnings'leri değişmez.
14. confirm_package_delivery ikinci kez çağrılırsa yeni earnings oluşmaz.
15. `auth_rls_initplan` ve `multiple_permissive_policies` kalmamış (`has_policy_for_roles` kontrolleri).

## 4. Audit SQL: `supabase/tests/20260802000005_courier_financial_audit.sql`

Salt-okunur. Çıktısı:
- Delivered olmayan/bulunmayan pakete bağlı earnings.
- Aynı package_request_id ile birden fazla earnings.
- courier_request.total_fee/courier_fee/admin_commission ile earnings.amount uyuşmazlıkları.
- balance_transaction'ı olmayan courier_request.
- Payout amount ile item toplamı uyuşmazlıkları.
- payment_reference olmayan approved payouts ve amount>100000 earnings/payouts.
- Durum aşamasını atlamış (accepted olmadan delivered) request'ler.

Yalnız SELECT/RAISE NOTICE. Veri silmez.

## 5. Flutter değişiklikleri

### `lib/features/user_courier/screens/send_package_screen.dart`
- `_submit` artık `create_package_request` RPC çağırır; istemcide `distance_km/total_fee` hesaplamaz, sunucu döner.
- DELETE fallback kaldırılır.
- Idempotency key: `_paketIdempotencyKey = const Uuid().v4()` (uuid paketi zaten projede varsa; yoksa `DateTime.now().microsecondsSinceEpoch.toString()` hash'lenir).

### `lib/features/user_courier/screens/package_tracking_screen.dart`
- Tek RPC: `get_assigned_package_details` (atanmış kurye) veya RLS üzerinden sender kendi satırı. `select()` değiştirilmez ama artık RPC'yi kullanır.

### `lib/features/user_courier/screens/package_history_screen.dart`
- Sadece sender'ın kendi talepleri. `select('id, status, total_fee, created_at, delivered_at')` → daraltılmış kolon. RPC'ye gerek yok (RLS yeterli, çünkü kendi satırı).

### `lib/features/courier/screens/courier_panel_screen.dart`
- `_loadOrders`: `list_available_package_requests()` çağırır. PII göstermek için kart tıklandığında `get_assigned_package_details` (henüz accepted değilse kısıtlı view + accept RPC sonrası tam görünüm).
- `_acceptPackage`: `accept_package_request(p_request_id)` RPC. UI'da çift tıklama kilidi.
- `_rejectPackage`: `reject_package_request(p_request_id)`.
- `_deliverPackage` adı `_requestDeliveryConfirmation`'a dönüşür: `request_package_delivery_confirmation`.
- Yeni `_markInTransit` veya görsel placeholder (ileride).
- `delivered_count` artışı + earnings insert client-side blokları tamamen kaldırılır.
- `_requestPayout`: `request_courier_payout(p_idempotency_key)`. Idempotency için Uuid.
- `_loadEarnings`: `courier_earnings` SELECT (RLS kendi satırları). items tablosu SELECT yok (gerekmiyor; sadece status/amount).

### `lib/features/admin/screens/admin_dashboard_parts/_part_courier.dart`
- `_approveCourierPayout`: `admin_approve_courier_payout(p_payout_id, p_payment_reference)` RPC. p_payment_reference UI dialog'undan alınır.
- `_rejectCourierPayout` (varsa/yoksa): `admin_reject_courier_payout(p_payout_id, p_reason)`.
- `courier_earnings` UPDATE'leri (mark paid/reset) kaldırılır; bunlar artık payout onay/red ile atomik.
- `courier_payout_requests` UPDATE kaldırılır.

### Yeni servis dosyası (öneri)
- `lib/core/services/courier_package_service.dart`: tüm yeni RPC çağrılarını saran sade API. Flutter ekranları bu servisi kullansın.

## 6. Doğrulama adımları (kod yazıldıktan sonra)

1. `dart format .`
2. `flutter analyze`
3. `supabase db reset` (lokal; Docker + Supabase CLI gerekir). Yoksa "ENV MISSING" raporu.
4. `supabase db lint --level error --fail-on error`
5. `supabase test db supabase/tests/database` (yeni 004 dahil)
6. Audit SQL'in SELECT-only olduğunun doğrulanması: dosyada DELETE/UPDATE/TRUNCATE yok.

## 7. Sıralı uygulama adımları

1. Migration SQL dosyası yazılır.
2. Yeni RPC'ler oluşturulur; eski grant/policy drop'ları en sonda.
3. Audit SQL yazılır.
4. Test dosyası yazılır.
5. Flutter dosyaları güncellenir.
6. dart format + analyze çalıştırılır.
7. Test/DB reset ortamı yoksa sonuç raporlanır; olan kadarı kanıtlanır.

## 8. Riskler / kabul edilen sınırlamalar

- **Test ortamı yoksa** migration ve testler sadece statik analizle doğrulanır. Açıkça "not executed" raporlanır.
- **`deduct_from_balance` authenticated'ten tamamen kapatılıyor** → mevcut authenticated kurye ödemesi kullanan başka akış varsa kırılır. Mevcut kod tarandı: yalnız `send_package_screen.dart` kullanıyor; bu ekran yeni RPC'ye taşınacak. Onun dışında service_role veya admin RPC'leri kullanıyor. Risk kabul edilebilir.
- **Flutter widget testi** bu görev kapsamı dışında; yalnızca static analyzer.
