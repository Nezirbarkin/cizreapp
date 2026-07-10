# İptal + İade Admin Onaylı Akışı

Müşteri iptal **talebi** açar, admin onaylar → aynı anda sipariş iptal edilir ve
(iade koşulu varsa) CizreApp bakiyesine otomatik iade yapılır.

## Akış

```
MÜŞTERİ                    ADMIN                    VERİTABANI (RPC)
   │                          │                          │
   │ order_detail_screen      │                          │
   │ "İptal Talebi Oluştur"   │                          │
   │ (sebep girer)            │                          │
   ├─────────────────────────────────────────────────────►│
   │                          │                          │ create_cancellation_request
   │                          │                          │  ├ sipariş sahibi? status uygun?
   │                          │                          │  ├ aktif talep yok?
   │                          │                          │  ├ refund snapshot (payment_method'a göre)
   │                          │                          │  └ INSERT (status=pending) + admin notification
   │◄──────── "Talep alındı, admin onayı bekleniyor" ─────┤
   │                          │                          │
   │                          │ Cüzdan Yönetimi →        │
   │                          │ "İptal Talepleri" tab    │
   │                          │ liste + detay            │
   │                          │                          │
   │                          │ Onayla / Reddet          │
   │                          ├─────────────────────────►│
   │                          │                          │ approve_cancellation_request (SECURITY DEFINER)
   │                          │                          │  ├ admin mi? (is_admin)
   │                          │                          │  ├ SELECT ... FOR UPDATE (race protection)
   │                          │                          │  ├ refund_amount>0 ise add_to_balance RPC
   │                          │                          │  │   └ balance_transactions (type=refund)
   │                          │                          │  ├ orders.status='cancelled'
   │                          │                          │  │   payment_status='refunded' (iade varsa)
   │                          │                          │  ├ restore_product_stock trigger (confirmed→cancelled)
   │                          │                          │  ├ cancellation_requests.status='approved'
   │                          │                          │  └ notification (cancellation_approved)
   │◄──── "İptal onaylandı, ₺X bakiyenize eklendi" ───────┤
```

Reddetme akışında sadece `status='rejected'` + müşteriye bildirim; sipariş
olduğu gibi kalır.

## İade Kuralları (snapshot, talep anında kilitlenir)

| `payment_method` | `refund_method` | `refund_amount` | İade hedefi |
|---|---|---|---|
| `balance` | `balance` | sipariş `total` | CizreApp bakiyesi (`add_to_balance`) |
| `online` | `balance` | sipariş `total` | CizreApp bakiyesi (admin İyzico'dan çeker) |
| `cash` | `none` | 0 | — (ödeme yapılmamış) |
| `card_on_delivery` | `none` | 0 | — (ödeme yapılmamış) |

## Dosyalar

### Veritabanı
- [`20260709000001_CREATE_CANCELLATION_REQUESTS.sql`](../supabase/migrations/20260709000001_CREATE_CANCELLATION_REQUESTS.sql)
  — `cancellation_requests` tablosu + RLS + index + updated_at trigger
- [`20260709000002_CANCELLATION_RPCS.sql`](../supabase/migrations/20260709000002_CANCELLATION_RPCS.sql)
  — 3 RPC + notification tipleri + GRANT
- [`20260709000003_CANCELLATION_SMOKE_TEST.sql`](../supabase/migrations/20260709000003_CANCELLATION_SMOKE_TEST.sql)
  — test senaryoları (manuel çalıştırma)

### Dart
- [`cancellation_request_service.dart`](../lib/features/shop/services/cancellation_request_service.dart)
  — `CancellationRequest` modeli + service (3 RPC sarmalayıcı)
- [`order_detail_screen.dart`](../lib/features/market/screens/order_detail_screen.dart)
  — müşteri "İptal Talebi Oluştur" dialog + bekleyen talep badge
- [`cancellation_requests_tab_widget.dart`](../lib/features/admin/widgets/cancellation_requests_tab_widget.dart)
  — admin onay/reddet UI
- [`admin_dashboard_screen.dart`](../lib/features/admin/screens/admin_dashboard_screen.dart)
  — Cüzdan Yönetimi'nde "İptal Talepleri" tab (7. sekme) + rozet

### Edge Function
- [`refund-to-balance`](../supabase/functions/refund-to-balance/index.ts)
  — **deprecated**. Yeni akış RPC kullanır; bu fonksiyon yalnızca ileriye dönük
  manuel iade senaryoları için bırakıldı.

### Admin Tek-Adım İptal (müşteri talebi olmadan)
- [`20260709000004_ADMIN_CANCEL_WITH_REFUND_RPC.sql`](../supabase/migrations/20260709000004_ADMIN_CANCEL_WITH_REFUND_RPC.sql)
  — `admin_cancel_with_refund(p_order_id, p_reason)` RPC. Admin bir siparişi
  direkt iptal ettiğinde (status dialogunda "İptal Edildi" + onay) çağrılır.
  Atomik: cancellation_requests kaydı (status=approved, audit) + add_to_balance
  (iade varsa) + orders cancelled + restore_stock + notification. Aynı RPC
  [`cancellation_request_service.dart`](../lib/features/shop/services/cancellation_request_service.dart)
  üzerinden `adminCancelWithRefund()` ile, [`admin_dashboard_screen.dart`](../lib/features/admin/screens/admin_dashboard_screen.dart)
  status değiştirme dialog'unda `cancelled` seçildiğinde tetiklenir.

## RPC'ler

### `create_cancellation_request(p_order_id, p_reason)`
Müşteri çağırır. `SECURITY DEFINER`, `search_path=public`.

Kontroller:
- `auth.uid()` dolu
- `p_reason` en az 3 karakter
- sipariş `user_id = auth.uid()`
- `orders.status IN ('pending','confirmed','preparing','ready','on_the_way')`
- aynı sipariş için aktif (`pending`) talep yok

İade snapshot'ını kilitler (`refund_method`, `refund_amount`). Adminlere
`cancellation_request` bildirimi gönderir.

### `approve_cancellation_request(p_request_id, p_admin_response)`
Admin çağırır. `SECURITY DEFINER`.

Atomik (tek transaction):
1. `is_admin()` kontrolü
2. `SELECT ... FOR UPDATE` ile talebi kilitle
3. `refund_amount > 0` ise `add_to_balance()` RPC → bakiyeye iade
4. `orders.status='cancelled'`, `payment_status='refunded'` (iade varsa),
   `cancelled_at`, `cancellation_reason`
5. `restore_product_stock` trigger'ı stokları geri yükler (confirmed→cancelled)
6. `cancellation_requests.status='approved'`, `reviewed_by`, `balance_transaction_id`
7. müşteriye `cancellation_approved` bildirimi

### `reject_cancellation_request(p_request_id, p_admin_response)`
Admin çağırır. `SECURITY DEFINER`.

- `is_admin()` kontrolü
- `p_admin_response` en az 3 karakter (zorunlu)
- `SELECT ... FOR UPDATE`
- `status='rejected'`, `admin_response`
- müşteriye `cancellation_rejected` bildirimi
- sipariş **etkilenmez**

## RLS

| İşlem | Yetki |
|---|---|
| SELECT | müşteri (kendi) / admin (tümü) / mağaza sahibi (kendi mağazası) |
| INSERT | authenticated, `user_id = auth.uid()` |
| UPDATE | admin (`is_admin()`) |
| DELETE | admin (`is_admin()`) |

RPC'ler `SECURITY DEFINER` olduğu için RLS'i bypass eder; yetki kontrolleri
RPC içinde `is_admin()` ve `auth.uid()` ile yapılır.

## Güvenlik Notları

- **Race condition**: `SELECT ... FOR UPDATE` iki adminin aynı talebi aynı anda
  onaylamasını önler. İkinci çağrıda RPC exception fırlatır.
- **Çift iade koruması**: her sipariş için tek `pending` talep (partial unique
  index) + onay sonrası `status='approved'` ile tekrar işlenemez.
- **Snapshot**: `refund_amount` talep anında kilitlenir; sonradan fiyat/sipariş
  değişse bile iade tutarı değişmez.
- **Stok**: `restore_product_stock` trigger'ı `confirmed → cancelled` geçişinde
  stokları geri yükler. `pending` siparişlerde stok zaten düşülmemişti
  (`decrease_product_stock` `confirmed`'da çalışır).
- **`add_to_balance` RETURNS UUID**: transaction_id döndürür; approve RPC bu
  id'yi `cancellation_requests.balance_transaction_id`'de saklar (audit).

## Test

Smoke test senaryoları:
[`20260709000003_CANCELLATION_SMOKE_TEST.sql`](../supabase/migrations/20260709000003_CANCELLATION_SMOKE_TEST.sql)

Senaryolar:
1. Bakiye ödemeli sipariş → iade var (balance +150, transaction, notification)
2. Cash ödemeli sipariş → iade yok (sadece iptal + bildirim)
3. Çift talep koruması (exception)
4. Status koruması (teslim edilmiş siparişe talep açılamaz)
5. Idempotent onay (ikinci onay exception fırlatır)
6. Reddetme (sipariş etkilenmez, bildirim gider)

Not: `auth.uid()` gerektiren RPC'ler SQL Editor'da doğrudan çalıştırılamaz;
Dart'tan gerçek JWT ile çağrılmalı.

## Deployment

```bash
# 1. Migration'ları Supabase'e uygula
# (SQL Editor veya supabase db push ile)
supabase/migrations/20260709000001_CREATE_CANCELLATION_REQUESTS.sql
supabase/migrations/20260709000002_CANCELLATION_RPCS.sql

# 2. Dart tarafı zaten analyze edilip temiz (flutter analyze: No issues)

# 3. (Opsiyonel) refund-to-balance edge function'a dokunulmadı
```

## Eski Davranış (değişen)

Eski `OrderService.cancelOrder(orderId)` direkt `orders.status='cancelled'`
yapıyordu, bakiye iadesi yoktu. Bu metod hâlâ var (geriye uyumluluk için,
`multi_shop_checkout`'ta bakiye yetersiz sipariş iptalinde kullanılıyor) ama
artık müşteri UI'sı iptal talebi akışını kullanıyor.

`return_requests` tablosu (teslim sonrası iade) **etkilenmedi**; o akış aynen
kalır. Yeni sistem sadece henüz teslim edilmemiş siparişlerin iptali içindir.