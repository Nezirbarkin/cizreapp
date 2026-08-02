# Server-Authoritative Checkout — Uygulama Raporu
**Tarih:** 2026-08-02
**Kapsam:** Tüm finansal akışların (orders, order_items, coupons, flash_sales, balance, iyzico) CLIENT-AUTHORITATIVE'den SERVER-AUTHORITATIVE, ATOMIC ve IDEMPOTENT'e dönüşümü.

---

## 1) Kök Neden Analizi

Eski mimari istemciyi "güvenilir hesaplayıcı" olarak kabul ediyordu. Belgelenen güvenlik açıkları:

| # | Sorun | Saldırı Vektörü |
|---|-------|-----------------|
| 1 | `public.create_order_with_items` istemciden `unit_price`/`subtotal`/`total` alıyordu | Fiyat manipülasyonu |
| 2 | `public.validate_coupon(UUID, TEXT, NUMERIC, UUID)` istemciden `subtotal` alıyordu | Kupon kötüye kullanımı |
| 3 | `public.use_coupon(...)` istemciden `discount_amount` alıyordu | Kupon %100 indirim |
| 4 | `public.complete_online_payment` `callback_data->order_data` üzerinden sipariş oluşturuyordu | Sipariş enjekte etme |
| 5 | `public.atomic_finalize_payment_transaction` `EXCEPTION WHEN OTHERS` ile hataları yutuyordu | Sessiz hata → tutarsız DB |
| 6 | `public.claim_flash_sale` istemciden gelen miktar ile stok düşüyordu | Stok taşması |
| 7 | iyzico callback `URL substring` kontrolü ile başarı belirliyordu | Sahte callback |
| 8 | `identityNumber: '11111111111'` hardcoded fallback | Sahte TCKN |
| 9 | IYZICO_ENV eksikse sandbox URL'ye düşüyordu | Production'da sandbox |
| 10 | IYZICO API key/Secret kod içinde literal olarak | Credential sızıntısı |
| 11 | iyzico callback loglarında `token` prefix veya `auth header` izi | Log sızıntısı |
| 12 | `user_balances` authenticated UPDATE açıktı | Bakiye artırma |
| 13 | `orders`, `order_items`, `payment_transactions` authenticated INSERT açıktı | Tabloya doğrudan yazma |
| 14 | iyzico retrieve'de imza doğrulaması yapılmıyordu | MDI/MSI bypass |

---

## 2) Hedef Mimari

```
┌─────────────┐  sadece {product_id, quantity, variant, address_id,
│ Flutter UI  │  coupon_id/code, payment_method, notes, idempotency_key}
└──────┬──────┘
       │  supabase.rpc('prepare_checkout_session', ...)
       ▼
┌──────────────────────────┐
│ private.prepare_checkout │  FOR UPDATE row locks + NUMERIC(12,2)
│   _session (SECURITY     │  + coupon / flash_sale / stock revalidate
│   DEFINER)               │  + UNIQUE(user_id, idempotency_key)
└──────────┬───────────────┘
           │  session.server_* snapshot
           ▼
       (UI gösterir, kullanıcı onaylar)
           │
           │  commit_cod_order / commit_balance_order / iyzico-payment-init
           ▼
┌──────────────────────────┐
│ private.commit_* (ATMC)  │  Tek transaction: orders + order_items +
│   veya commit_online     │  coupon_usages + flash_sale_reservations +
│   _order                 │  user_balances (bakiye için) +
│                          │  payment_transactions (online için)
└──────────────────────────┘
```

**Yeni eklenen / değişen RPC'ler (8 adet):**
- `private.prepare_checkout_session` — sunucu otoritesinde quote üretir
- `private.commit_cod_order` — tek transaction'da COD sipariş oluşturur
- `private.commit_balance_order` — tek transaction'da bakiye sipariş oluşturur
- `private.commit_online_order` — callback sonrası session'dan sipariş üretir
- `private.atomic_finalize_payment_transaction` — iyzico retrieve sonuçlarını doğrular, sipariş oluşturmaz
- `private.validate_coupon` — server-side discount hesaplar
- `private.use_coupon` — server-side coupon usage yazar
- `public.cancel_order` — kullanıcı kendi siparişini iptal eder (state machine)

**Yeni eklenen tablolar (3 adet):**
- `private.server_checkout_sessions` — 15dk TTL'li, server_*_ alanları
- `private.flash_sale_reservations` — flash sale rezervasyonu
- `private.server_checkout_audit` — append-only denetim (UPDATE/DELETE trigger-blocked)

**Edge Function'lar (3 adet tamamen yeniden yazıldı):**
- `iyzico-payment-init` — sadece `{checkout_session_id, idempotency_key}` alır
- `iyzico-payment-callback` — token → retrieve → signature/mismatch kontrolleri → commit_online_order
- `use-balance-for-order` — sadece `{checkout_session_id}` alır, bakiye yetersizse RPC exception fırlatır

---

## 3) Yeni DB Nesneleri ve Kolonlar

### private schema
```sql
CREATE SCHEMA IF NOT EXISTS private;
REVOKE ALL ON SCHEMA private FROM PUBLIC, anon, authenticated;
GRANT USAGE ON SCHEMA private TO service_role;
```

### private.server_checkout_sessions
| Kolon | Tip | Açıklama |
|---|---|---|
| id | UUID PK | oturum kimliği |
| user_id | UUID NOT NULL | auth.uid() |
| idempotency_key | TEXT NOT NULL | client üretir |
| **UNIQUE(user_id, idempotency_key)** | | retry = aynı session |
| status | TEXT CHECK (active, completed, expired, cancelled) | |
| payment_method | TEXT CHECK (cod, online, balance) | |
| address_id | UUID NOT NULL | |
| coupon_id | UUID | opsiyonel |
| coupon_code | TEXT | opsiyonel |
| notes | TEXT | |
| invoice_data | JSONB | |
| order_group_id | UUID | multi-shop bağlantı |
| **server_subtotal** | NUMERIC(12,2) | sunucu hesaplar |
| **server_delivery_fee** | NUMERIC(12,2) | |
| **server_coupon_discount** | NUMERIC(12,2) | |
| **server_total** | NUMERIC(12,2) | |
| **server_commission_total** | NUMERIC(12,2) | |
| expected_paid_price | NUMERIC(12,2) | iyzico için |
| payment_transaction_id | UUID | bağlantı |
| items_snapshot | JSONB | sunucu snapshot |
| expires_at | TIMESTAMPTZ | DEFAULT now() + 15min |
| created_at | TIMESTAMPTZ | |
| completed_at | TIMESTAMPTZ | |
| CHECK (server_total = server_subtotal + server_delivery_fee - server_coupon_discount) | | tutarlılık |

### private.flash_sale_reservations
| Kolon | Tip |
|---|---|
| id | UUID PK |
| session_id | UUID NOT NULL → server_checkout_sessions |
| sale_id | UUID NOT NULL → flash_sales |
| product_id | UUID NOT NULL |
| quantity | INT NOT NULL |
| unit_price | NUMERIC(12,2) (snapshot) |
| status | TEXT CHECK (active, committed, released, expired) |
| expires_at | TIMESTAMPTZ |
| **UNIQUE(session_id, sale_id)** | |

### private.server_checkout_audit
| Kolon | Tip |
|---|---|
| id | UUID PK |
| event_type | TEXT |
| user_id | UUID |
| order_id | UUID |
| payment_transaction_id | UUID |
| amount | NUMERIC(12,2) |
| payload | JSONB |
| created_at | TIMESTAMPTZ |

Trigger:
```sql
BEFORE UPDATE OR DELETE ON private.server_checkout_audit
FOR EACH STATEMENT EXECUTE FUNCTION block_update_delete();
-- RAISE EXCEPTION 'audit table is append-only'
```

### public.orders eklenen kolonlar
- `checkout_session_id UUID` (UNIQUE per user)
- `committed_at TIMESTAMPTZ`
- `price_mismatch BOOLEAN DEFAULT false`

### public.payment_transactions eklenen kolonlar
- `checkout_session_id UUID`
- `expected_amount NUMERIC(12,2)`
- `expected_currency TEXT`
- `expected_conversation_id TEXT`
- `expected_basket_id TEXT`
- `iyzico_environment TEXT`
- `idempotency_key TEXT` (UNIQUE per user)
- `reconciliation_status TEXT` (none, amount_mismatch, currency_mismatch, env_mismatch, signature_invalid)
- `reconciliation_note TEXT`

### UNIQUE indeksler
- `orders_user_session_uniq` (user_id, checkout_session_id)
- `payment_tx_user_idem_uniq` (user_id, idempotency_key)
- `payment_tx_token_uniq` (token)
- `order_items_unique_line` (order_id, product_id, variant_id)

---

## 4) Dosya Değişiklikleri

### Yeni — Database
| Dosya | Amaç |
|---|---|
| `supabase/migrations/20260802000005_server_authoritative_checkout_schema.sql` | private schema + 3 tablo + orders/payment_transactions kolon ekleme |
| `supabase/migrations/20260802000006_prepare_checkout_session_rpc.sql` | prepare_checkout_session RPC |
| `supabase/migrations/20260802000007_commit_cod_and_balance_orders.sql` | commit_cod_order + commit_balance_order RPC |
| `supabase/migrations/20260802000013_coupon_limit_enforcement_strict.sql` | private.validate_coupon + private.use_coupon |
| `supabase/migrations/20260802000009_lock_payment_finalizer_to_backend.sql` | private.atomic_finalize_payment_transaction + private.commit_online_order |
| `supabase/migrations/20260802000010_order_state_machine_rpc.sql` | cancel_order + mark_order_paid/shipped/delivered |
| `supabase/migrations/20260802000011_idempotent_uniqueness.sql` | UNIQUE indeksler |
| `supabase/migrations/20260802000008_revoke_legacy_writes.sql` | eski RPC'leri DROP + tablo INSERT/DELETE yasağı |
| `supabase/migrations/20260802000012_audit_views.sql` | 5 denetim view |

### Yeni — Edge Functions
| Dosya | Değişiklik |
|---|---|
| `supabase/functions/iyzico-payment-init/index.ts` | sadece {checkout_session_id, idempotency_key}; tüm veriyi session'dan okur |
| `supabase/functions/iyzico-payment-callback/index.ts` | token → retrieve → signature/mismatch doğrulama → commit_online_order |
| `supabase/functions/use-balance-for-order/index.ts` | sadece {checkout_session_id}; bakiye yetersizse 409 |

### Yeni — Flutter
| Dosya | Amaç |
|---|---|
| `lib/models/checkout_session_model.dart` | ServerQuote modeli (server_*, items_snapshot) |
| `lib/models/cart_item.dart` | Görsel cart item (fiyat alanları yalnızca UI için) |
| `lib/services/checkout_service.dart` | prepare/commit/init RPC client'ı |
| `lib/services/order_service.dart` | UI uyumluluk adapter'ı (OrderService → CheckoutService) |
| `lib/services/payment_service.dart` | online + balance adapter |
| `lib/services/cart_service.dart` | server-authoritative prepareCheckout |
| `lib/services/flash_sale_service.dart` | sadece okuma; rezervasyon YOK |
| `lib/widgets/server_quote_display.dart` | ortak gösterim widget'ı |
| `lib/screens/product_detail_checkout_button.dart` | "Hızlı Satın Al" akışı |
| `lib/screens/multi_shop_checkout_handler.dart` | shop_id gruplama + ortak order_group_id |

### Eski API'ler (tamamen kaldırıldı)
- `public.create_order_with_items` — DROP
- `public.validate_coupon` — DROP
- `public.use_coupon` — DROP
- `public.complete_online_payment` — DROP
- `public.atomic_finalize_payment_transaction` — DROP
- `public.claim_flash_sale` — DROP
- `public.release_flash_sale` — DROP
- `public.use_balance_for_order` — DROP

---

## 5) Sunucu Hesaplama Kuralları

### Subtotal
```sql
subtotal = SUM( CASE
  WHEN is_flash_sale THEN flash_price * quantity
  ELSE unit_price * quantity
END )
```
**Snapshot items_snapshot içinde saklanır.** Commit anında yeniden hesaplanır.

### Delivery Fee
```sql
IF subtotal >= shop.free_delivery_min_amount THEN 0
ELSE shop.delivery_fee
```
Tek mağaza checkout'unda mağazanın delivery_fee'si, multi-shop'ta mağazaların toplamı.

### Coupon Discount (server-only)
```sql
-- private.validate_coupon içinde
discount = CASE coupon.discount_type
  WHEN 'percentage' THEN LEAST(subtotal * coupon.discount_value / 100, coupon.maximum_discount)
  WHEN 'fixed' THEN LEAST(coupon.discount_value, subtotal)
  ELSE 0
END
```
Client ASLA discount değeri GÖNDERMEZ; RPC kendisi hesaplar.

### Commission
```sql
commission = SUM( line_subtotal * shop.commission_rate / 100 )
```
Tüm commission alanları NUMERIC(12,2).

### Total (CHECK constraint)
```sql
total = subtotal + delivery_fee - coupon_discount
-- DB CHECK constraint aynı formülü zorunlu tutar
```

### Flash Sale Stok Rezervasyonu
```sql
-- prepare anında
SELECT * FROM flash_sales WHERE id = p_sale_id FOR UPDATE;
reserved = SUM(quantity) FROM flash_sale_reservations
           WHERE sale_id = p_sale_id AND status IN ('active','committed');
IF sold_count + reserved + requested > stock_limit THEN EXCEPTION flash_sold_out;

-- commit anında
UPDATE flash_sales SET sold_count = sold_count + reserved_qty WHERE id = p_sale_id;
UPDATE flash_sale_reservations SET status = 'committed';
```

### Bakiye Ödeme
```sql
-- private.commit_balance_order
SELECT * FROM user_balances WHERE user_id = p_user_id FOR UPDATE;
IF balance < session.server_total THEN EXCEPTION insufficient_balance;
UPDATE user_balances SET balance = balance - session.server_total;
INSERT INTO balance_transactions (user_id, amount, type, reference_id)
  VALUES (user_id, -session.server_total, 'order_payment', order_id);
```
Tüm bakiye hareketleri `balance_transactions` append-only tablosuna yazılır (audit trail).

---

## 6) iyzico Doğrulama Matrisi

| Kontrol | Nerede | Başarısızsa |
|---|---|---|
| IYZICO_ENV ayarı | `getIyzicoApiUrl()` | 503 Service Unavailable |
| IYZICO_API_KEY/SECRET mevcut | init/callback başlangıcı | 503 |
| TCKN / identity_number mevcut | init (iyzico zorunlu kuralı) | 400 IDENTITY_NUMBER_REQUIRED |
| session.user_id == auth.uid() | init | 403 forbidden |
| session.status == 'active' | init | 400 session_invalid |
| session.expires_at > now() | init | 400 session_expired |
| IYZICO_API_URL sandbox≠prod | init | hard fail (env değişkenine bağlı) |
| HMAC-SHA256 imza | callback retrieve | signature_invalid reconciliation |
| paidPrice == expected_paid_price | callback | amount_mismatch |
| currency == TRY | callback | currency_mismatch |
| basketId == expected | callback | basket_id_mismatch |
| conversationId == expected | callback | conversation_id_mismatch |
| fraudStatus == 1 (prod only) | callback | fraud_status_invalid |
| mdStatus == 1 (prod only) | callback | md_status_invalid |
| iyzico_environment == IYZICO_ENV | callback | env_mismatch |
| 'pending' durumda order oluşturma | callback finalizer | **ASLA** (rpc 0 order döner) |

**Log politikası:** Yalnızca transaction_id (UUID prefix 8 char), user_id prefix, iyzico_paymentId (UUID zaten), hata kodu. Token, signature, cardUserKey, cardToken, auth header, TCKN loglanmaz.

---

## 7) Dağıtım Sırası (Sıfır Veri Kaybı)

1. **Migration 20260802000005** (private schema + tablolar) — geriye dönük etki yok, sadece yeni objeler
2. **Migration 20260802000006** (prepare_checkout_session) — yeni RPC, eski etkilenmez
3. **Migration 20260802000007** (commit_cod/commit_balance) — yeni RPC
4. **Migration 20260802000013** (coupon strict) — `public.validate_coupon` DROP, eski istemci 404 alır
5. **Migration 20260802000009** (payment finalizer) — `public.complete_online_payment` DROP
6. **Migration 20260802000011** (UNIQUE indeksler) — mevcut veriyle çakışırsa migration hata verir (bu iyi, kabul etmemiz gereken durum)
7. **Migration 20260802000010** (state machine)
8. **Migration 20260802000008** (revoke legacy writes) — orders/order_items/payment_transactions authenticated INSERT/DELETE kapatılır
9. **Migration 20260802000012** (audit views)
10. **Edge Function deploy:**
    - `supabase functions deploy iyzico-payment-init`
    - `supabase functions deploy iyzico-payment-callback`
    - `supabase functions deploy use-balance-for-order`
11. **Flutter:** Yeni build yayınla (minimum app version gate ile eski istemci yeni mutasyonları kullanamaz)

**Geri dönüş:** Her migration'ın DROP IF EXISTS koruması vardır; bir sonraki migration'ı yazarken geri alma yolu açıktır.

---

## 8) Idempotency Garantileri

| Akış | Garanti Mekanizması |
|---|---|
| prepare_checkout_session | UNIQUE(user_id, idempotency_key) → aynı key ile aynı session |
| commit_cod/balance | session.status == 'completed' ise mevcut order_id döner |
| commit_online_order | orders_user_session_uniq + txn.zaten success ise erken çıkış |
| atomic_finalize_payment_transaction | 'success' ise updated=false döner (idempotent) |
| iyzico callback (token ile) | payment_tx_token_uniq + status kontrolü |

Her başarısız/hatalı deneme aynı idempotency_key ile tekrar denenebilir; sunucu AYNI sonucu verir.

---

## 9) Atomiklik Garantileri

| RPC | Tek transaction kapsamı |
|---|---|
| `private.commit_cod_order` | orders + order_items + coupon_usages + flash_sale_reservations.commit + flash_sales.sold_count + session.completed |
| `private.commit_balance_order` | Yukarıdaki + user_balances FOR UPDATE + UPDATE + balance_transactions INSERT |
| `private.commit_online_order` | payment_transactions FOR UPDATE + orders + order_items + flash_sale_reservations + payment_transactions.order_id link |

`EXCEPTION` durumunda PostgreSQL otomatik ROLLBACK yapar; hiçbir tablo yarı dolu kalmaz.

---

## 10) Sızdırma Önleme (PII / Secret)

- **IYZICO_API_KEY / IYZICO_SECRET_KEY** yalnızca Edge Function secrets; source code, log, FCM payload'da YOK
- **iyzico token** sadece Edge Function içinde; log'da sadece 8-char prefix
- **card_token / cardUserKey** asla DB veya log'a yazılmaz
- **TCKN** profile'a yazılır; iyzico payload'unda kullanılır ama loglanmaz
- **auth header** Edge Function içinde kalır, loglanmaz
- **Hardcoded `'11111111111'`** tamamen kaldırıldı (artık `profiles.tc_no` zorunlu)
- **Sahte TCKN üretimi** YOK (eksikse 400 IDENTITY_NUMBER_REQUIRED)
- **Üretimde IYZICO_ENV eksikse** Edge Function 503 döner (fail closed)
- **Üretim callback URL substring** kontrolü KALDIRILDI; tek doğrulama retrieve + signature

---

## 11) Minimum Uygulama Sürümü (App Version Gate)

Önceki istemcilerin eski mutasyonları çağırmasını engellemek için `app_meta` (veya Supabase `app_version` RPC) tablosundan `min_required_version` döndürülür. Eski istemci `force_update` ekranı gösterir.

```sql
-- 20260802000014 (opsiyonel)
CREATE TABLE IF NOT EXISTS public.app_meta (
  key TEXT PRIMARY KEY,
  value JSONB
);
INSERT INTO public.app_meta VALUES
  ('min_required_version', '"2.0.0"'),
  ('deprecate_legacy_rpc', 'true');
```

Flutter:
```dart
final meta = await supabase.from('app_meta').select('value').eq('key', 'min_required_version');
if (compareVersions(currentVersion, meta) < 0) showForceUpdate();
```

---

## 12) Audit Sorguları (cron / manuel)

```sql
-- 24 saat içinde mismatch ödeme
SELECT * FROM private.v_session_amount_mismatch;

-- 15dk'dan eski pending session (cron temizler)
SELECT * FROM private.v_pending_stale_sessions;
-- DELETE FROM private.server_checkout_sessions
--   WHERE id IN (SELECT id FROM private.v_pending_stale_sessions);
-- (cron job — supabase_cron / pg_cron ile 5dk'da bir)

-- Tükenmiş kuponlar
SELECT * FROM private.v_coupon_exhausted;

-- Bugünkü başarısız ödemeler
SELECT * FROM private.v_failed_payments_today;

-- Son denetim olayları
SELECT * FROM private.v_recent_audit_events
WHERE event_type IN ('amount_mismatch', 'env_mismatch', 'signature_invalid');
```

---

## 13) Bilinen Artık Riskler ve Azaltma

| Risk | Azaltma |
|---|---|
| Cronsuz bırakırsan pending session'lar şişer | supabase_cron ile 5dk'da bir `v_pending_stale_sessions` temizle |
| App version gate deploy edilmezse eski istemci hatalı RPC çağırır | `app_meta.min_required_version` + Flutter force update |
| Bakiye yetersizliği UI'da anlık görünmez (gerçek kontrol server'da) | prepare aşamasında user_balances.amount SELECT yapılabilir (sadece gösterge) |
| iyzico sandbox→prod geçişinde environment değişimi | `iyzico_environment` kolonunda saklanıyor; env_mismatch kontrolü aktif |
| Kupon usage_limit_per_user denetimi | private.validate_coupon içinde `SELECT count(*) FROM coupon_usages WHERE user_id = p_user_id AND coupon_id = p_coupon_id` ek kontrolü (migration 20260802000013'te var) |
| Ürün stok eşzamanlılığı | FOR UPDATE row lock + reservation tablosu ile taşma engellenir |
| Audit tablosu sınırsız büyür | retention policy 90 gün (cron DELETE) |

---

## 14) Kullanıcının Yapması Gerekenler (Dağıtım Checklist)

1. **Migration'ları sırayla prod'a uygula** (yukarıdaki sıra). Her birini `psql` veya Supabase Dashboard üzerinden çalıştır. Mevcut veri varsa 20260802000011 (UNIQUE indeksler) çakışma verebilir; çakışan veriyi temizledikten sonra tekrar dene.
2. **Edge Function secrets tanımla** (Supabase Dashboard → Edge Functions → Secrets):
   - `IYZICO_API_KEY=<production key>`
   - `IYZICO_SECRET_KEY=<production secret>`
   - `IYZICO_ENV=production` (sandbox testi için ayrı deploy)
3. **Edge function'ları deploy et:**
   ```bash
   supabase functions deploy iyzico-payment-init
   supabase functions deploy iyzico-payment-callback
   supabase functions deploy use-balance-for-order
   ```
4. **Flutter tarafında entegrasyon:**
   - `CheckoutService` DI ile inject et
   - Eski `OrderService.createOrder` çağrılarını `prepareCheckout + commit` ile değiştir
   - Cart UI'da fiyat gösterimini `ServerQuoteDisplay` widget'ına geçir
   - Multi-shop checkout'ta `MultiShopCheckoutHandler` kullan
5. **App version gate yayınla** (min_version 2.0.0). Play Store / App Store'a yeni build gönder.
6. **Cron job'ları kur:**
   - `pg_cron` veya Supabase Scheduled Functions: her 5dk'da bir `v_pending_stale_sessions` temizle
   - Günde 1 kez `server_checkout_audit` 90 günden eski kayıtları temizle
7. **Monitoring:** `v_failed_payments_today` ve `v_session_amount_mismatch` view'larını Sentry/PagerDuty'ye bağla
8. **Sandbox smoke testi:**
   - Test kuponu (%100) ile prepare → mismatch davranışı
   - Sandbox iyzico token al → callback → order oluştuğunu doğrula
   - Bakiye yetersiz sipariş → 409 döndüğünü doğrula
   - Aynı idempotency_key ile 2x prepare → aynı session_id döndüğünü doğrula
9. **Prod geçişi:**
   - IYZICO_ENV=production yap
   - İlk 5 siparişi canlı izle (mismatch audit'leri kontrol et)
   - 24 saat sonra `v_failed_payments_today` raporunu incele

---

**Durum:** Tüm migration'lar, RPC'ler, Edge Function'lar, Flutter servisleri ve refactor'lar tamamlandı. Kullanıcı yalnızca yukarıdaki 9 adımı uygulayarak canlıya alabilir.
