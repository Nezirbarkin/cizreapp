# Server-Authoritative Checkout + Atomik Finansal Akış

**Tarih:** 2026-08-02
**Kapsam:** Sipariş, kupon, flaş satış, bakiye, iyzico ödemesi — tüm finansal akışlar
**Hedef:** Client-authoritative fiyat/kupon/stok/bakiye alanlarını tamamen kaldırıp, sunucu tarafında atomik ve idempotent hale getirmek

---

## 1. KÖK NEDEN (Neden Bu Kadar Büyük Değişiklik Gerekli?)

Mevcut uygulama, sipariş oluşturma ve ödeme akışlarında **client-authoritative** veri modeli kullanıyor. Yani Flutter istemcisi aşağıdaki finansal alanları hesaplayıp backend'e gönderiyor:

| Alan | Kaynak | Risk |
|---|---|---|
| `subtotal` | client hesaplar | Düşük gösterilebilir |
| `delivery_fee` | client hesaplar | Sıfırlanabilir |
| `discount` | client hesaplar | Çok yüksek set edilebilir |
| `coupon_discount` | client hesaplar | Sahte kupon varmış gibi davranılabilir |
| `total` | client hesaplar | Ücretsiz sipariş oluşturulabilir |
| `commission_amount` | client hesaplar | Manipüle edilebilir |
| Bakiye düşülecek `amount` | client söyler | Düşük tutar düşülebilir |
| iyzico `price`, `paidPrice`, `buyer` | client gönderir | TCKN, fiyat, adres sahtelenebilir |
| `product_name` | client gönderir | Sahte ürün ismi siparişe yazılır |
| `shop_id` | client seçer | Başka mağazaya sipariş yönlendirilebilir |
| `payment_status` | client update eder | Ödeme atlanabilir |

### Somut saldırı yüzeyleri (kod analizi)

**`lib/features/shop/services/order_service.dart:88-150`** → İstemci `user_id`, `shop_id`, `subtotal`, `total`, `coupon_id`, `coupon_discount` alanlarını doğrudan `orders` tablosuna INSERT ediyor. RLS sadece `user_id = auth.uid()` kontrolü yapıyor; fiyat/total doğrulaması yok.

**`lib/features/market/services/flash_sale_service.dart:67-86`** → `claim_flash_sale` RPC'si `p_user_id` parametresi alıyor ama RPC içinde (20260726120001_flash_sale_and_price_alert_setup.sql:107-109) sadece `sold_count`'u arttırıyor; claim rezervasyonu herhangi bir `user_id + checkout_session` ile ilişkilendirilmiyor. `release_flash_sale` RPC'si (satır 145-148) ise kullanıcı kontrolü yapmadan `sold_count`'u azaltabiliyor.

**`lib/features/market/services/payment_service.dart:43-52`** → Edge Function'a `user_id`, `order_data`, `buyer` (TCKN dahil), `billing_address`, `shipping_address` gönderiliyor.

**`supabase/functions/iyzico-payment-init/index.ts:242`** → `identityNumber: buyer.identityNumber || "11111111111"` sabit TCKN fallback'i.

**`supabase/functions/iyzico-payment-callback/index.ts:872-882`** → `atomic_finalize_payment_transaction` çağrılıyor, fakat `complete_online_payment` (callback_data.order_data'dan fiyat okuyor) client tarafından daha önce eklenen `callback_data` üzerinden çalışıyor — yani server-authoritative değil, callback_data'ya yazılan client-authoritative fiyatı okuyor.

**`supabase/functions/use-balance-for-order/index.ts:44-93`** → `amount` ve `order_total` client'tan alınıyor. Bakiye düşümü ile sipariş güncellemesi ayrı sorgular; sipariş güncellenemezse bakiye iade edilmeye çalışılıyor (gerçek transaction değil, ardışık RPC + manuel iade).

**`supabase/migrations/20260801000002_complete_online_payment_coupon_id.sql:103-170`** → Online ödeme tamamlandığında `INSERT INTO orders (...) VALUES (v_total, v_subtotal, ...)` direkt `callback_data` üzerinden yapılıyor. `callback_data` ise init sırasında client'ın gönderdiği veriyle doluyor.

---

## 2. HEDEF MİMARİ

### 2.1. Veri akışı (yeni)

```
┌─────────┐   1. Ürün/Adet/Adres/Kupon/PaymentMethod + idempotency_key
│ Flutter │ ─────────────────────────────────────────────────────────┐
└─────────┘                                                           │
                                                                     ▼
┌────────────────────────────────────────────────────────────────────────────┐
│ RPC: prepare_checkout_session(p_*)                                          │
│ • auth.uid() doğrula                                                       │
│ • Ürün/fiyat/mağaza/stok/variant sunucuda doğrula                         │
│ • Aktif flaş satış varsa sunucuda fiyat/stok/limit kilitle (FOR UPDATE)     │
│ • Kupon sunucuda doğrula, indirimi sunucuda hesapla                        │
│ • Teslimat ücretini sunucuda hesapla (free_delivery eşiği dahil)           │
│ • Komisyonu sunucuda hesapla (shops.commission_rate)                        │
│ • server_checkout_sessions + session_items + reservations INSERT            │
│ • Hesaplanmış quote döndür (subtotal/delivery/discount/total/commission)    │
│ • Döndürürken client-authoritative alanlar ASLA kullanılmaz                 │
└────────────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
┌────────────────────────────────────────────────────────────────────────────┐
│ RPC: commit_cod_order(p_session_id)        ← cash/card-on-delivery         │
│ • Session FOR UPDATE kilitle, auth.uid() doğrula, süre kontrol              │
│ • Quote hâlâ geçerli mi doğrula (re-validation)                            │
│ • orders + order_items + coupon_usages + rezervasyon commit                 │
│ • Bildirim outbox kaydı                                                    │
│ • Session completed                                                        │
│ • Idempotent (UNIQUE(user_id, idempotency_key) zaten var)                   │
└────────────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼ (online ödeme seçildiyse)
┌────────────────────────────────────────────────────────────────────────────┐
│ Edge: iyzico-payment-init                                                  │
│ • SADECE checkout_session_id + idempotency_key alır                       │
│ • Session user_id == auth.uid() doğrula                                    │
│ • Session tutarlarını service-role RPC üzerinden oku                        │
│ • Buyer bilgisi profiles + addresses'ten SUNUCUDA al                       │
│ • iyzico checkout form başlat (TCKN zorunlu ise gerçek profile'dan)        │
│ • payment_transactions INSERT (idempotency_key ile unique)                  │
└────────────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼ (iyzico 3D sonrası)
┌────────────────────────────────────────────────────────────────────────────┐
│ Edge: iyzico-payment-callback                                              │
│ • Token → iyzico retrieve, imza doğrula                                    │
│ • Server expected amount/currency/conversationId/basketId karşılaştır      │
│ • Aynı SQL transaction'da:                                                 │
│     - payment_transactions UPDATE success/failure                          │
│     - orders + order_items INSERT (server snapshot'tan)                    │
│     - coupon_usages INSERT                                                 │
│     - flash_sale_reservations commit (sold_count++)                        │
│     - session completed                                                    │
│ • Mismatch → orders oluşturma, transaction = amount_mismatch statusu       │
└────────────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼ (bakiye seçildiyse)
┌────────────────────────────────────────────────────────────────────────────┐
│ RPC: commit_balance_order(p_session_id)                                    │
│ • Session FOR UPDATE kilitle                                               │
│ • user_balances FOR UPDATE, yeterlilik kontrol                             │
│ • Tek transaction'da:                                                      │
│     - user_balances UPDATE (düşüm)                                         │
│     - balance_transactions INSERT (append-only ledger)                     │
│     - orders + order_items INSERT (server snapshot'tan)                    │
│     - coupon_usages INSERT                                                 │
│     - flash_sale_reservations commit (sold_count++)                        │
│     - session completed                                                    │
│ • Hata → tümü rollback                                                    │
└────────────────────────────────────────────────────────────────────────────┘
```

### 2.2. Yeni DB nesneleri

**Şema: `private`** (veya `app_private`; superuser dışında erişilemez)

```
private.server_checkout_sessions (
  id UUID PK
  user_id UUID NOT NULL  -- auth.uid()'den set, client değiştiremez
  idempotency_key TEXT NOT NULL
  payment_method TEXT NOT NULL  -- 'cash' | 'card_on_delivery' | 'balance' | 'online'
  currency CHAR(3) NOT NULL DEFAULT 'TRY'
  shop_id UUID NOT NULL
  address_id UUID
  coupon_id UUID
  server_subtotal NUMERIC(12,2) NOT NULL
  server_delivery_fee NUMERIC(12,2) NOT NULL
  server_discount NUMERIC(12,2) NOT NULL DEFAULT 0
  server_coupon_discount NUMERIC(12,2) NOT NULL DEFAULT 0
  server_commission_amount NUMERIC(12,2) NOT NULL
  server_total NUMERIC(12,2) NOT NULL
  expected_currency CHAR(3) NOT NULL DEFAULT 'TRY'
  expected_paid_price NUMERIC(12,2)  -- iyzico için init'te set
  status TEXT NOT NULL DEFAULT 'pending'  -- pending|committed|expired|cancelled
  expires_at TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '15 minutes')
  payment_transaction_id UUID
  order_id UUID
  order_group_id UUID  -- multi-shop
  created_at, updated_at TIMESTAMPTZ
  UNIQUE(user_id, idempotency_key)
  CHECK (server_total >= 0)
  CHECK (server_subtotal >= 0)
)

private.server_checkout_session_items (
  id UUID PK
  session_id UUID FK → server_checkout_sessions(id) ON DELETE CASCADE
  product_id UUID NOT NULL
  variant_data JSONB
  quantity INTEGER NOT NULL CHECK (quantity > 0 AND quantity <= 100)
  server_unit_price NUMERIC(12,2) NOT NULL  -- server hesapladı
  server_subtotal NUMERIC(12,2) NOT NULL
  flash_sale_id UUID
  server_flash_price NUMERIC(12,2)  -- flaş ise
  shop_id UUID NOT NULL
  product_name_snapshot TEXT NOT NULL  -- fatura/snapshot için (server'dan)
  shop_name_snapshot TEXT NOT NULL
  product_image_url_snapshot TEXT
  created_at TIMESTAMPTZ
)

private.flash_sale_reservations (
  id UUID PK
  sale_id UUID FK → flash_sales(id)
  session_id UUID FK → server_checkout_sessions(id) ON DELETE CASCADE
  user_id UUID NOT NULL
  product_id UUID NOT NULL
  quantity INTEGER NOT NULL CHECK (quantity > 0)
  status TEXT NOT NULL DEFAULT 'active'  -- active|committed|released|expired
  expires_at TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '15 minutes')
  committed_at TIMESTAMPTZ
  released_at TIMESTAMPTZ
  created_at TIMESTAMPTZ
  UNIQUE(session_id, sale_id)  -- aynı session'da aynı sale iki kez
)

private.server_checkout_audit  -- şüpheli eşleşmeler, sadece admin SELECT
```

**Ek kolonlar (mümkünse public'te duran mevcut tablolara):**
- `flash_sales.sold_count` zaten var; rezervasyonlar `flash_sale_reservations` üzerinden
- `payment_transactions.checkout_session_id` UUID (yeni)
- `payment_transactions.expected_amount` NUMERIC(12,2) (init'te set)
- `payment_transactions.expected_currency` CHAR(3)
- `payment_transactions.environment` TEXT CHECK ('sandbox'|'production')
- `payment_transactions.idempotency_key` TEXT
- `orders.checkout_session_id` UUID
- `orders.price_mismatch` BOOLEAN (callback'te sapma tespit edilirse)
- `orders.committed_at` TIMESTAMPTZ

### 2.3. RLS düzenlemesi

**`public.orders`** — INSERT/UPDATE/DELETE authenticated için tamamen kapatılır (REVOKE + DROP POLICY). Sadece SECURITY DEFINER RPC'ler insert edebilir. SELECT mevcut kurallarla devam (sahibi/satıcı/admin).

**`public.order_items`** — INSERT/UPDATE authenticated için kapatılır. SELECT devam.

**`public.payment_transactions`** — INSERT/UPDATE authenticated için kapatılır. SELECT: kullanıcı kendi transaction'ını + admin.

**`public.coupon_usages`** — INSERT authenticated için kapatılır (kupon kullanımı sadece commit RPC'leri içinden). SELECT: kullanıcı kendi kullanımları + admin.

**`public.flash_sales`** — sold_count artık doğrudan authenticated UPDATE'ine açık olmamalı; sadece SECURITY DEFINER RPC'ler.

**`private.*` tablolar** — public şemadan tamamen gizli. authenticated/anon GRANT yok. service_role ve SECURITY DEFINER RPC'ler üzerinden erişim.

---

## 3. DEĞİŞEN / YENİ DOSYALAR

### 3.1. Yeni Supabase migration'ları (forward-only)

| Dosya | Amaç |
|---|---|
| `supabase/migrations/20260802000006_server_authoritative_checkout_schema.sql` | `private` şema, `server_checkout_sessions`, `server_checkout_session_items`, `flash_sale_reservations` tabloları, yeni kolonlar (orders/payment_transactions) |
| `supabase/migrations/20260802000007_prepare_checkout_session_rpc.sql` | `prepare_checkout_session` RPC'si — server-side quote builder |
| `supabase/migrations/20260802000008_commit_cod_and_balance_orders.sql` | `commit_cod_order`, `commit_balance_order` RPC'leri |
| `supabase/migrations/20260802000008_revoke_legacy_checkout_writes.sql` | Eski `create_order_with_items` DROP, `orders`/`order_items`/`coupon_usages`/`payment_transactions` RLS INSERT/UPDATE authenticated REVOKE, eski `claim_flash_sale`/`release_flash_sale` GRANT revoke |
| `supabase/migrations/20260802000009_lock_payment_finalizer_to_backend.sql` | `complete_online_payment` ve `atomic_finalize_payment_transaction` private şemaya taşı, GRANT sadece service_role |
| `supabase/migrations/20260802000010_state_machine_order_status.sql` | `transition_order_status` SECURITY DEFINER RPC — durum geçişleri allowlist ile |
| `supabase/migrations/20260802000011_idempotent_session_uniqueness.sql` | Idempotency_key unique constraint'leri, dedupe trigger'ları |
| `supabase/migrations/20260802000012_server_authoritative_audit_views.sql` | Şüpheli kayıt audit view'ları (orders.total != item_snapshot_sum, vb.) |
| `supabase/migrations/20260802000013_coupon_limit_enforcement_strict.sql` | `validate_coupon` ve `use_coupon` sadeleştir — `p_discount_amount` parametresini kaldır, yeni server-side fiyatlandırma |

### 3.2. Değişen Edge Function'lar

| Dosya | Değişiklik |
|---|---|
| `supabase/functions/iyzico-payment-init/index.ts` | Sadece `checkout_session_id` ve `idempotency_key` alır. Buyer/price/items client'tan alınmaz, server snapshot'tan okunur. TCKN fallback kaldırılır. `IYZICO_ENV` zorunlu. |
| `supabase/functions/iyzico-payment-callback/index.ts` | Token → retrieve, imza doğrula, expected amount karşılaştır (NUMERIC), tüm sipariş oluşturma artık `complete_online_payment` içinde tek transaction. `callback_data.order_data` fiyatı kullanılmaz. |
| `supabase/functions/use-balance-for-order/index.ts` | **KALDIRILACAK** — yeni `commit_balance_order` RPC'si ile değiştirilir. |

### 3.3. Değişen Flutter dosyaları

| Dosya | Değişiklik |
|---|---|
| `lib/features/market/services/order_service.dart` | Tüm `createOrder`, `createMultiShopOrder` → `prepareCheckout` + `commitOrder` çağrıları. `subtotal/delivery_fee/discount/total/commissionAmount/couponDiscount` parametreleri kaldırılır. `userId` parametresi kaldırılır (auth.uid()'den alınır). `freeOrderLimitPerUser` kontrolü kaldırılır (sunucu yapacak). |
| `lib/core/services/payment_service.dart` | `initializePayment` artık sadece `checkoutSessionId` alır. `orderData`, `buyer`, `billingAddress`, `shippingAddress` parametreleri kaldırılır. |
| `lib/features/market/services/cart_service.dart` | `flash_sale_id` ve `flash_price` client-authoritative alanlar kaldırılır; cart sadece `product_id + quantity + variant_data` taşır. |
| `lib/features/market/services/flash_sale_service.dart` | `claimFlashSale`, `releaseFlashSale` metotları kaldırılır. UI sadece "aktif flaş var mı" bilgisi için `getActiveFlashSaleForProduct` kullanır. Stok rezervasyonu checkout sırasında yapılır. |
| `lib/features/market/screens/checkout_screen.dart` | Onay butonu: önce `prepareCheckout` (server quote), kullanıcı yeniden onaylar, sonra `commitOrder` (cash) veya `initializePayment` (online). Toplam sunucudan gelir. TCKN/buyer bloğu tamamen kaldırılır. |
| `lib/features/market/screens/multi_shop_checkout_screen.dart` | Her mağaza için ayrı `prepareCheckout` (server-side) veya tek `order_group` ile tek session. `use_coupon` client çağrıları tamamen kaldırılır. |
| `lib/features/market/screens/product_detail_screen.dart` | "Sepete eklerken" `claim_flash_sale` çağrıları kaldırılır. Sadece quantity seçimi. |
| `lib/features/market/screens/cart_screen.dart` | Stok/fiyat tahmini server tarafından güncellenebilir; client kendi hesabı yerine server'dan dönen quote'u gösterir. |

### 3.4. Yeni Flutter dosyaları (yardımcı)

| Dosya | Amaç |
|---|---|
| `lib/core/services/checkout_service.dart` | `prepareCheckout()`, `commitOrder()`, `commitBalanceOrder()` için yeni servis. Tüm session/quote state burada. |
| `lib/core/models/checkout_session_model.dart` | `CheckoutSession`, `CheckoutSessionItem`, `CheckoutQuote` modelleri. |

---

## 4. SUNUCU HESAPLAMA KURALLARI

### 4.1. `prepare_checkout_session` (sunucu tarafı)

Parametreler: `p_items JSONB`, `p_address_id UUID`, `p_coupon_id UUID`, `p_payment_method TEXT`, `p_idempotency_key TEXT`, `p_order_group_id UUID?`.

Adımlar:
1. `auth.uid()` zorunlu.
2. `idempotency_key` ile mevcut session var mı? Varsa döndür (idempotent).
3. `address_id` gerçekten `auth.uid()`'ye mi ait? (user_addresses tablosu üzerinden)
4. Her item için:
   - `products` tablosundan `is_available=true`, `shop_id` doğrula, `stock_quantity` >= quantity
   - Normal fiyat: `COALESCE(discount_price, price)` (sunucu)
   - Aktif flaş satış var mı? `flash_sales WHERE product_id AND is_active=true AND NOW() BETWEEN start_at AND end_at`. Varsa:
     - `flash_sale_reservations` INSERT et (FOR UPDATE ile `flash_sales` kilitle)
     - Rezervasyon miktarı + mevcut sold_count stock_limit'i aşmamalı
     - `server_unit_price = flash_price` (sunucu)
   - Varyant: `product_variants` tablosunda gerçekten var mı
   - `server_subtotal_item = server_unit_price * quantity`
5. Kupon (varsa):
   - `shop_coupons` üzerinden `is_active=true`, `start_date<=NOW()<=end_date`, `shop_id` uyumu
   - `usage_limit`, `usage_per_user` (coupon_usages'dan say) sunucuda kontrol
   - `minimum_order_amount` server subtotal'a göre
   - İndirim = `discountFor(subtotal)` (yüzde/sabit) ama `maximum_discount_amount` ile clamp
6. Teslimat ücreti:
   - `shops.delivery_fee`, `shops.free_delivery_min_amount`
   - `delivery_fee = 0` eğer `subtotal >= free_delivery_min_amount`, yoksa `shops.delivery_fee`
7. Komisyon: `commission_amount = subtotal * (shops.commission_rate / 100)`
8. `total = subtotal - coupon_discount + delivery_fee` (sunucu, NUMERIC)
9. `total >= 0` zorunlu.
10. Ücretli ürünlerde `total = 0` kabul edilmez (sunucuda free-order policy ayrı kontrol).
11. `notes` ve `invoice_*` alanları için uzunluk/format sınırı.
12. `server_checkout_sessions` + `server_checkout_session_items` INSERT, `expires_at = NOW() + 15min`.
13. Döndür: tam quote (id, items, subtotal, delivery, discount, coupon_discount, total, commission, expires_at).

### 4.2. `commit_cod_order` (cash / card_on_delivery)

Parametre: `p_session_id UUID`.

Transaction içinde:
1. `server_checkout_sessions FOR UPDATE` kilitle, `auth.uid()` doğrula, `status='pending'`, `expires_at > NOW()`.
2. Quote hâlâ geçerli mi? (re-validate: ürün/fiyat/stok hâlâ uygun mu — sunucu tarafında yeniden hesapla, server snapshot ile eşleşmeli).
3. `orders` INSERT (tüm finansal alanlar sunucu değerleri, `payment_status='pending'`, `status='pending'`).
4. `order_items` INSERT (server snapshot'tan — `price`, `product_name`, `shop_name` server'dan).
5. Kupon: `coupon_usages` INSERT + `shop_coupons.usage_count++` (FOR UPDATE ile).
6. Flaş: `flash_sale_reservations` UPDATE status='committed' + `flash_sales.sold_count += reserved_quantity` (FOR UPDATE).
7. Bildirim outbox: `notification_outbox` INSERT (push/email trigger için).
8. `server_checkout_sessions` UPDATE status='completed', `order_id = ...`.
9. Aynı `idempotency_key` ile yeni çağrı gelirse mevcut order döner (UNIQUE constraint + early-return).

### 4.3. `commit_balance_order`

Aynen `commit_cod_order` + bakiye adımı:
- `user_balances FOR UPDATE`, yeterlilik kontrol.
- `user_balances.balance -= amount`, `total_spent += amount`.
- `balance_transactions` INSERT (append-only ledger, `type='order_payment'`, `reference_id=order_id`).
- Hata → tümü rollback.

### 4.4. `commit_online_order` (iyzico callback içinden)

`complete_online_payment` ve `atomic_finalize_payment_transaction` artık private şemada. Callback Edge Function yalnızca service-role ile çağırır.

Transaction içinde:
1. `payment_transactions FOR UPDATE` kilitle.
2. Status `pending` değilse zaten işlenmiş → mevcut order'ı döndür.
3. iyzico retrieve response'unu `expected_amount`, `expected_currency`, `conversationId`, `basketId` ile karşılaştır.
   - Eşleşmiyorsa: status='amount_mismatch', admin_audit kaydı, sipariş oluşturma. 200 dön ama reconciliation'a düşür.
4. `server_checkout_sessions FOR UPDATE`, auth.uid doğrula, status='pending'.
5. `orders` + `order_items` INSERT (server snapshot'tan).
6. `coupon_usages` INSERT (gerekirse).
7. `flash_sale_reservations` commit.
8. `payment_transactions` UPDATE success + order_id link.
9. `server_checkout_sessions` UPDATE completed.
10. Aynı `paymentId` veya `token` ikinci kez gelirse mevcut order döner (UNIQUE).

---

## 5. IYZICO DOĞRULAMA MATRİSİ

| Kontrol | Kaynak | Eşleşmezse |
|---|---|---|
| `token` retrieve başarılı | iyzico API | Sipariş oluşturma |
| `retrieve.status == 'success'` | iyzico | Sipariş oluşturma |
| `paymentId` UNIQUE | DB | Sipariş oluşturma (zaten var) |
| `conversationId == session.expected_conversation_id` | DB | amount_mismatch |
| `basketId == session.expected_basket_id` | DB | amount_mismatch |
| `currency == 'TRY'` | iyzico | amount_mismatch |
| `paidPrice == session.expected_amount` (NUMERIC) | iyzico | amount_mismatch |
| `price == sum(basketItems)` | iyzico | amount_mismatch |
| `fraudStatus == 1` (production) | iyzico | Sipariş oluşturma |
| `mdStatus == 1` (production) | iyzico | Sipariş oluşturma |
| `IYZICO_ENV == 'production'` ve response production'dan | env | fail closed |
| İmza doğrulama (HMAC-SHA256) | iyzico | signature_invalid |

İmza doğrulaması `crypto.timingSafeEqual` benzeri constant-time karşılaştırma ile yapılmalı (Deno'da `crypto.subtle.verify`).

Loglanacak alanlar yalnızca: `payment_transaction_id` (UUID prefix), `error_code`, `expected_amount`/`actual_amount` (sapma varsa), `reconciliation_status`. **Loglanmayacak alanlar:** token, signature, API key, secret key, kart token, cardUserKey, TCKN, kart numarası, full name, full email.

---

## 6. KUPON VE FLAŞ SATIŞ CONCURRENCY ÇÖZÜMÜ

### Kupon
- `validate_coupon` ve `use_coupon` RPC'leri sadece session-commit sırasında çağrılır. Authenticated client EXECUTE yetkisi kaldırılır.
- `shop_coupons` FOR UPDATE ile kilitle.
- `usage_count` artışı + `coupon_usages` INSERT aynı transaction'da.
- `usage_per_user` kontrolü coupon_usages üzerinden (UNIQUE(coupon_id, user_id, order_id) → idempotent).
- Eşzamanlı iki istek: aynı `idempotency_key` → tek INSERT; farklı key'ler ama aynı kupon → ikinci commit `usage_count` kontrolünde fail olur.

### Flaş satış
- `claim_flash_sale` ve `release_flash_sale` authenticated GRANT kaldırılır.
- Rezervasyon: `flash_sale_reservations` INSERT + `flash_sales FOR UPDATE` (satır kilidi, `sold_count` anlık güncellenmez, sadece kontrol için).
- Rezervasyon: `reserved_qty + sold_count <= stock_limit` sunucuda kontrol.
- Commit: `flash_sales.sold_count += quantity` (sadece `commit_cod_order` / `commit_balance_order` / `commit_online_order` içinden).
- 20 paralel checkout aynı `flash_sale` için: tek seferde bir transaction kilidi alır, diğerleri sırada bekler; hepsi ya başarılı olur (toplam <= stock_limit) ya da sonrakiler `Insufficient stock` alır.
- `release`: sadece session expired/cancelled tarafından. Client çağrısı yok.
- Add-to-cart: `sold_count` artık değişmez, sadece `cart` tablosuna eklenir.

---

## 7. FLUTTER'DAN KALDIRILAN ALANLAR (Client-Authoritative)

### `order_service.dart`
- `userId` parametresi (her metottan)
- `shopId` parametresi (her metottan — server session'dan alır)
- `subtotal`, `deliveryFee`, `discount`, `total`, `commissionAmount`, `couponDiscount` parametreleri
- `freeOrderLimitPerUser` static alanı
- `orderItems.price` (server snapshot'tan gelir)
- Push notification'ın `content` alanı (server outbox'tan oluşur)
- `customerPhone` (auth.uid ile adres üzerinden server alır)

### `payment_service.dart`
- `initializePayment({orderData, buyer, billingAddress, shippingAddress})` → `initializePayment({checkoutSessionId, idempotencyKey})`
- `cancelPaymentTransaction` (client tarafından çağrılamaz; server out-of-band yapar)

### `flash_sale_service.dart`
- `claimFlashSale` (tamamen kaldırılır)
- `releaseFlashSale` (tamamen kaldırılır)
- `createFlashSale` (satıcı RPC üzerinden, SECURITY DEFINER)

### `cart_service.dart`
- `flashSaleId`, `flashPrice` parametreleri (server checkout'ta tekrar seçer)
- Cart'ta `price` alanı (yalnızca tahmini UI göstergesi olarak kalabilir, server quote otoritedir)

### `checkout_screen.dart` & `multi_shop_checkout_screen.dart`
- `orderData` map'i içindeki tüm fiyat alanları
- `buyer` map'i (identityNumber dahil)
- `billing_address`, `shipping_address` (server profiles+addresses'ten alır)
- Coupon `discountFor()` istemci tarafı hesabı (server quote otoritedir)
- `use_coupon` RPC çağrıları (tamamen kaldırılır)
- Cash/balance ödemede `_orderService.createOrder` direkt çağrısı (artık `prepareCheckout` + `commitOrder`)

### Minimum app version gate
- `info.plist` / `build.gradle` `CFBundleVersion` / `versionCode` minimum sürüm bump
- Backend RPC'lerde (iyzico-init ve complete_online_payment) client `app_version` header'ı okunur, eski sürümse 426 (Upgrade Required) dönülür.
- Veya geçici bakım modu: yeni sürüm yayımlanana kadar checkout POST'ları 503.

---

## 8. BEKLENEN TEST SENARYOLARI (15. bölümün uygulaması)

### AUTHORIZATION
- [ ] anon `prepare_checkout_session` çağırırsa 401/42501
- [ ] authenticated başka user'ın `address_id` ile çağırırsa reject
- [ ] authenticated doğrudan `orders` INSERT yaparsa RLS reject
- [ ] authenticated doğrudan `order_items` INSERT yaparsa RLS reject
- [ ] authenticated `payment_transactions` UPDATE yaparsa RLS reject
- [ ] `create_order_with_items` RPC artık yok (DROP)
- [ ] `use_coupon` authenticated EXECUTE yetkisi yok
- [ ] `claim_flash_sale` / `release_flash_sale` authenticated EXECUTE yetkisi yok
- [ ] `complete_online_payment` authenticated EXECUTE yetkisi yok
- [ ] `atomic_finalize_payment_transaction` authenticated EXECUTE yetkisi yok

### PRICE TAMPERING
- [ ] `price=1, total=1, delivery_fee=0, coupon_discount=9999` parametreleri server tarafından yok sayılır (client artık gönderemez)
- [ ] Server fiyatı 1000 TL olan ürün için session.server_total = 1000 TL (client müdahale edemez)
- [ ] Başka mağazanın kuponu ile kendi mağazası session'ı oluşturulamaz
- [ ] Süresi dolmuş kupon `validate_coupon` reddeder
- [ ] Maksimum indirim sınırı aşılamaz
- [ ] Ücretli ürün client tarafından 0 TL yapılamaz
- [ ] Gerçekten ücretsiz ürünlerde server free-order policy çalışır

### ATOMICITY/IDEMPOTENCY
- [ ] Aynı `idempotency_key` iki kez `prepare_checkout_session` → tek session
- [ ] İki eşzamanlı `commit_balance_order` aynı key → tek sipariş + tek bakiye düşümü + tek ledger
- [ ] Yetersiz bakiyede sipariş yok, ledger yok
- [ ] Order item insert hatası → tüm transaction rollback
- [ ] Kupon hatası → tüm transaction rollback
- [ ] Bildirim outbox hatası → transaction stratejisine uygun (sipariş commit'lenir, outbox tekrar denenir)
- [ ] Aynı iyzico callback iki kez → tek order
- [ ] Aynı `paymentId` iki transaction'a bağlanamaz

### FLASH SALE
- [ ] 20 paralel `prepare_checkout_session` aynı `flash_sale_id` ile → 20 başarılı VEYA stok yetmezse sıralı red
- [ ] `flash_sale_reservations` user_id ile başka kullanıcı release edemez
- [ ] Expired reservation `commit_*` ile işlenemez
- [ ] Aynı reservation iki kez commit edilemez
- [ ] Add-to-cart `sold_count` değiştirmez

### IYZICO
- [ ] Payment init sadece `checkout_session_id` kabul eder
- [ ] Client `total/items/buyer` gönderse bile yok sayılır
- [ ] İmza geçersiz → sipariş oluşmaz
- [ ] Currency uyuşmazlığı → sipariş oluşmaz
- [ ] `conversationId`/`basketId` uyuşmazlığı → sipariş oluşmaz
- [ ] `expected_amount` uyuşmazlığı → `amount_mismatch` status
- [ ] Production'da sandbox response → fulfillment oluşmaz
- [ ] Eksik `IYZICO_ENV` → fail closed (403)
- [ ] Başarılı callback → tek order, server quote tutarı
- [ ] Loglar token/signature/API key/TCKN içermez

---

## 9. MİGRATION VE EDGE FUNCTION DEPLOY SIRASI

Kullanıcının tercihine göre (Minimum app version gate):

1. **Yeni şema + RPC'ler** (Migration 20260802000005 → 20260802000013)
   - private.* tablolar oluşur
   - Yeni RPC'ler hazır
   - Eski yüzey hâlâ açık

2. **Yeni Edge Function'lar** (iyzico-init/iyzico-callback yeni versiyon)
   - Deploy edilir
   - service_role ile yeni RPC'leri çağırır
   - Eski fonksiyon URL'i hâlâ erişilebilir (geriye uyumlu olduğu sürece)

3. **Güncellenmiş Flutter istemcisi** yayımlanır
   - Yeni minimum sürüm gate
   - Yeni akışı kullanır

4. **Eski RPC'ler ve yazma yüzeyleri kapatılır** (Migration 20260802000008, 20260802000009)
   - `create_order_with_items` DROP
   - `orders` / `order_items` / `coupon_usages` / `payment_transactions` RLS INSERT/UPDATE authenticated REVOKE
   - `claim_flash_sale` / `release_flash_sale` / `validate_coupon` / `use_coupon` authenticated GRANT kaldır
   - `complete_online_payment` / `atomic_finalize_payment_transaction` private şemaya taşı
   - Eski Edge Function URL'leri 410 Gone döner

5. **Audit + reconciliation** (Migration 20260802000012 + admin dashboard view)
   - Şüpheli kayıtlar listelenir
   - Manuel review süreci

---

## 10. MEVCUT ŞÜPHELİ KAYITLAR AUDIT (Migration 20260802000012)

Read-only view'lar:

- `v_audit_orders_price_mismatch`: `orders.total != (SELECT SUM(price*quantity) FROM order_items WHERE order_id = orders.id) ± 0.01`
- `v_audit_orders_zero_with_paid_items`: `total=0` ama order_items `price*quantity > 0`
- `v_audit_coupon_overuse`: `coupon_usages` sayısı > `shop_coupons.usage_limit`
- `v_audit_payment_amount_mismatch`: `payment_transactions.amount != orders.total`
- `v_audit_orphan_online_orders`: `payment_transactions.payment_status='success' AND order_id IS NULL`
- `v_audit_duplicate_payment_ids`: aynı `payment_id` birden fazla transaction'da
- `v_audit_flash_sold_count_drift`: `flash_sales.sold_count != (SELECT SUM(quantity) FROM flash_sale_reservations WHERE status='committed' AND sale_id=...)`

Bu view'lar migration'ın bir parçası olarak `public` şemada bırakılır (sadece admin SELECT policy ile).

---

## 11. UYGULANMASI GEREKEN KOMUTLAR (Canlıya Uygularken)

### 11.1. Local test
```bash
# Local DB'yi temizle ve yeni migration'ları uygula
supabase db reset  # SADECE local ortamda

# Migration'ı lint et
supabase db lint

# Edge Function'ları lint/format
deno fmt --check supabase/functions/iyzico-payment-init/index.ts
deno fmt --check supabase/functions/iyzico-payment-callback/index.ts
deno lint supabase/functions/iyzico-payment-init/index.ts
deno lint supabase/functions/iyzico-payment-callback/index.ts

# Flutter tarafı
dart format lib/features/market/services/order_service.dart \
              lib/features/market/services/payment_service.dart \
              lib/features/market/services/cart_service.dart \
              lib/features/market/services/flash_sale_service.dart \
              lib/core/services/payment_service.dart \
              lib/core/services/checkout_service.dart \
              lib/features/market/screens/checkout_screen.dart \
              lib/features/market/screens/multi_shop_checkout_screen.dart
flutter analyze
flutter test
```

### 11.2. Hedef ortam (production)
```bash
# Migration'ı dry-run ile doğrula
supabase db push --dry-run  # production'a basmadan önce

# Migration'ı uygula
supabase db push  # veya Dashboard > SQL Editor ile migration dosyalarını sırayla çalıştır

# Edge Function'ları deploy
supabase functions deploy iyzico-payment-init
supabase functions deploy iyzico-payment-callback

# Secrets doğrula (zorunlu)
supabase secrets set IYZICO_API_KEY=...
supabase secrets set IYZICO_SECRET_KEY=...
supabase secrets set IYZICO_ENV=production  # 'sandbox' ASLA
```

### 11.3. Secrets
- `IYZICO_API_KEY` — Supabase Dashboard > Edge Functions > Secrets
- `IYZICO_SECRET_KEY` — Supabase Dashboard > Edge Functions > Secrets
- `IYZICO_ENV` — `sandbox` veya `production` (zorunlu, fail-closed)
- Bu anahtarlar kaynak kodda/loglarda ASLA görünmemeli

---

## 12. UYGULANMASI GEREKEN DOSYA İŞLEMLERİ SIRASI (Claude tarafından)

Aşağıdaki sıra ile uygulanır. Her adımda migration → RPC test → Edge Function → Flutter adımı ayrı ayrı doğrulanabilir.

1. `supabase/migrations/20260802000006_server_authoritative_checkout_schema.sql` (private şema, yeni tablolar)
2. `supabase/migrations/20260802000007_prepare_checkout_session_rpc.sql`
3. `supabase/migrations/20260802000008_commit_cod_and_balance_orders.sql`
4. `supabase/migrations/20260802000013_coupon_limit_enforcement_strict.sql`
5. `supabase/migrations/20260802000009_lock_payment_finalizer_to_backend.sql` (yeni init/callback RPC'lerini kullanır)
6. `supabase/functions/iyzico-payment-init/index.ts` (yeni — sadece checkout_session_id alır)
7. `supabase/functions/iyzico-payment-callback/index.ts` (yeni — server snapshot'tan sipariş)
8. `supabase/functions/use-balance-for-order/index.ts` (DEPRECATED, yeni RPC'ye yönlendirir veya kaldır)
9. `lib/core/models/checkout_session_model.dart` (yeni)
10. `lib/core/services/checkout_service.dart` (yeni)
11. `lib/features/market/services/order_service.dart` (refactor)
12. `lib/core/services/payment_service.dart` (refactor)
13. `lib/features/market/services/cart_service.dart` (refactor)
14. `lib/features/market/services/flash_sale_service.dart` (claim/release kaldır)
15. `lib/features/market/screens/checkout_screen.dart` (refactor)
16. `lib/features/market/screens/multi_shop_checkout_screen.dart` (refactor)
17. `lib/features/market/screens/product_detail_screen.dart` (claim çağrılarını kaldır)
18. `supabase/migrations/20260802000010_state_machine_order_status.sql` (state machine RPC)
19. `supabase/migrations/20260802000011_idempotent_session_uniqueness.sql`
20. `supabase/migrations/20260802000008_revoke_legacy_checkout_writes.sql` (eski yüzeyleri kapat)
21. `supabase/migrations/20260802000012_server_authoritative_audit_views.sql`

---

## 13. AÇIKÇA KALAN RİSKLER (Bu planda çözülmeyen)

- **Geçmiş şüpheli siparişler:** Migration otomatik silme/onarım YAPMAZ. Manuel review gerekir.
- **Mevcut müşteri sepetleri:** Yeni RPC'lere geçiş anında eski `cart` satırları `flash_sale_id/flash_price` taşıyor olabilir; bunlar ignore edilir. Sepet sıfırlanması UI tarafında istenebilir.
- **Minimum app version gate'in yayımlanması:** App Store / Play Store yayın süresi var. Geçiş sürecinde eski istemci hâlâ çalışabilir; revoke adımı geciktirilir.
- **İyzico TCKN zorunluluğu:** Gerçek TCKN zorunlu ise kullanıcıya `profiles.tc_no` veya KYC akışı gerekebilir. Mevcut `profiles` tablosunda `tc_no` olup olmadığı kontrol edilmeli. Yoksa, bu plan "TCKN yoksa ödeme başlatmayı durdur" kuralını uygular.
- **`freeOrderLimitPerUser`:** Mevcut client-side kontrol kaldırılıyor. Server-side karşılığı `shop_coupons` veya yeni bir `app_settings` satırı olabilir. Plan, "gerçekten ücretsiz ürünler" için sunucu policy'si yazılması gerektiğini not eder.
- **Komisyon hesabı:** Mevcut kodda `commission_rate` shops'tan, `commission_amount` client tarafından hesaplanıyor. Yeni akışta `commission_amount` server tarafından hesaplanır ve `orders.commission_amount` kolonuna yazılır; mevcut trigger'lar (`admin_commission`, `seller_net_amount`) tetiklenmeye devam eder.
- **Multi-shop partial-success:** Mevcut akış bir alt sipariş başarısız olursa diğerlerini tutuyor. Yeni akış "all-or-nothing" öneriyor (rollback). Ürün tasarımı gerektiriyorsa ayrı bir `allow_partial` flag eklenebilir.

---

## 14. SONUÇ

Bu plan uygulandığında:

- ✅ Client hiçbir finansal alanı belirleyemez (user_id, product_name, price, total, kupon, bakiye, iyzico tutarı)
- ✅ Sunucu tarafında tüm fiyat/kupon/stok/komisyon hesaplaması NUMERIC
- ✅ Sipariş, kupon, flaş, bakiye, ödeme transaction'ları tek DB transaction'ında
- ✅ Aynı `idempotency_key` ile birden fazla istek tek sonuç üretir
- ✅ Eski mobil sürüm güvenlik açığı olan endpoint'leri kullanamaz (minimum version gate)
- ✅ İyzico callback'i imza + amount + currency + env doğrular, sapma → reconciliation
- ✅ Doğrudan tablo yazımı authenticated için tamamen kapalı
- ✅ Şüpheli mevcut kayıtlar audit view'ları ile raporlanır

Plan toplam **9 yeni migration + 2 Edge Function rewrite + 7 Flutter dosyası refactor + 2 yeni Flutter dosyası** gerektiriyor. Tüm adımlar forward-only, geriye dönük uyumsuz (eski mobil sürüm yeni API'yi kullanmak zorunda). Deploy sırası kullanıcının "Minimum app version gate" tercihiyle uyumlu.
