# Sipariş & Ürün Fiyatı Düzeltmeleri — Test Planı ve Doğrulama

**Tarih:** 2026-07-29
**Kapsam:** Sipariş oluşturma ve ürün fiyatı akışında tespit edilen 6 bug'ın düzeltilmesi ve regresyon testleri.

## 1) Düzeltilen Bug'lar (Önceki Analiz)

| # | Seviye | Bug | Düzeltme |
|---|---|---|---|
| 1 | 🔴 | Sepet join'inde `discount_price` yok → kullanıcı detayda indirimli görüp sepete ekleyince indirimsiz fiyat üzerinden işlem | `CartItem.productDiscountPrice` + `effectivePrice` getter + tüm join'lerde discount_price çekimi |
| 2 | 🔴 | Çift email gönderimi (Dart + DB trigger) | Dart'taki email çağrıları kaldırıldı (push kaldı) |
| 3 | 🟡 | Multi-shop checkout'ta `discountByShop` parametresi hiç geçilmiyordu → DB'ye `discount=0` yazılıyordu | `ShopCartSummary.discount` alanı + `_placeOrder`'da map oluşturulup geçiriliyor |
| 4 | 🟢 | Snapshot sorunu (race condition) | Mevcut kod zaten `getCart` her çağrıda güncel fiyat çekiyor — kapsam dışı |
| 5 | 🟡 | Onay SMS kodu ekranda açık gösteriliyordu → production güvenlik riski | 3 dosyada `kDebugMode` koşuluna sarıldı |
| 6 | 🟡 | IDE uyarısı: kullanılmayan `kIsWeb` import | `kDebugMode` ile değiştirildi |

## 2) Test Stratejisi

3 katmanlı test yaklaşımı benimsendi:

### 2.1 Model Testleri (Birim, Saf Dart)
**Dosyalar:** `test/models/cart_model_test.dart` (yeni), `test/models/order_model_test.dart` (eklendi)

- **CartItem** mantığı (28 test):
  - `effectivePrice` 7 durum: null/invalid/valid/tutarsız veri/sıfır/eşit
  - `itemTotal` 3 durum: indirimsiz/indirimli/quantity 0
  - `hasDiscount` 4 durum: discount_price/old_price/yok/eşit
  - `itemDiscount` 4 durum: tasarruf hesabı
  - `discountPercentage` 3 durum
  - `fromJson` 3 durum: parse (null/int/double)
  - `copyWith` 2 durum
  - `CartSummary.fromItems` 2 durum

- **OrderItem** entegrasyonu (4 test):
  - `OrderItem.price` artık effective (indirimli) fiyatı yansıtır
  - "price" kolonu "product_price" kolonundan öncelikli
  - `subtotal` doğru hesaplanır (price * quantity)
  - int/double sayı tipleri desteklenir

### 2.2 Servis Smoke Testleri (Kod Düzeyinde Doğrulama)
**Dosya:** `test/services/order_service_smoke_test.dart` (yeni, 8 test)

Supabase mock'lanamadığı için gerçek servis çağrıları yerine **kaynak kodu parse ederek** kritik kalıpların korunduğunu doğrular:

- `createOrder` Dart'tan email çağrıları YOK (çift email fix)
- `createMultiShopOrder` Dart'tan email çağrıları YOK
- Push notification hâlâ çağrılıyor (DB'de push kanalı yok)
- `createMultiShopOrder` imzasında `discountByShop` parametresi var
- `discountByShop?[shopId] ?? 0.0` koruması korunmuş
- `OrderService` sınıfı ve `freeOrderLimitPerUser = 1` mevcut
- Multi-shop checkout `discountByShop` map'ini oluşturup geçiriyor

### 2.3 Güvenlik & Entegrasyon Smoke Testleri
**Dosya:** `test/services/security_smoke_test.dart` (yeni, 10 test)

- **SMS doğrulama kodu** (4 test):
  - 3 dosyada `displayedCode` `kDebugMode` koşulunda (market, multi-shop, shop checkout)
  - Tüm 3 dosyada `kDebugMode` import edilmiş
- **Sepet join yapısı** (2 test):
  - `CartService.getCart` join'inde `discount_price` alanı var
  - `CartService._mapToCartItem` `productDiscountPrice` parse ediyor
- **Product model sözleşmesi** (1 test):
  - `Product.effectivePrice` discount_price'ı önceliklendirir

## 3) Test Sonuçları

```
flutter test → 271 test, 0 başarısız (All tests passed!)
```

**Test Dağılımı:**

| Test Dosyası | Yeni/Eklenen | Toplam Test |
|---|---|---|
| `test/models/cart_model_test.dart` | Yeni (28) | 28 |
| `test/models/order_model_test.dart` | +4 yeni grup | ~36 (önceki 32 + 4) |
| `test/services/order_service_smoke_test.dart` | Yeni (8) | 8 |
| `test/services/security_smoke_test.dart` | Yeni (10) | 10 |
| Mevcut diğer testler | Değişmedi | 197 |
| **Toplam** | **+50 yeni** | **271** |

## 4) Çalıştırma

```bash
# Tüm testler
flutter test

# Sadece yeni testler
flutter test test/models/cart_model_test.dart
flutter test test/services/order_service_smoke_test.dart
flutter test test/services/security_smoke_test.dart

# Belirli bir grup
flutter test --plain-name "effectivePrice"

# Static analiz
flutter analyze
```

## 5) Gelecek İyileştirmeler (Kapsam Dışı)

1. **CartService gerçek entegrasyon testleri**: Supabase mock kütüphanesi (`mockito` veya `supabase_test`) eklenerek join sorguları test edilebilir.
2. **Widget testleri**: `CheckoutScreen` `_placeOrder` akışı için widget testleri (provider mock'la).
3. **Snapshot koruması**: `cart_items` tablosuna `price_snapshot` kolonu eklenip migration ile kalıcı fiyat koruması.
4. **Flash sale fiyatı**: `effectivePrice`'a flash sale entegrasyonu (`_activeFlashSale` durumuna göre dinamik fiyat).
5. **Multi-shop kupon UI**: Dükkan başına kupon alanı zaten altyapısı hazır.
