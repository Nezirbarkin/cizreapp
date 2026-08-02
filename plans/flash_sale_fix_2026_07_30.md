# Flaş İndirim Düzeltme Planı (2026-07-30)

## Sorunlar (kullanıcı bildirimi)

1. **Flaş indirim tutardan kesilmiyor** — Sepete eklenen flaş indirimli ürün, sepet tutarı/ödeme tutarında flaş fiyatı üzerinden değil, ürünün normal `price`'ı (veya `discount_price`'ı) üzerinden hesaplanıyor.
2. **Flaş indirim etiketi ürün kartında gösterilmiyor** — `product.hasDiscount` sadece `discount_price` kolonuna baktığı için, `flash_sales` tablosunda tanımlı aktif flaş indirimde rozet hiç çıkmıyor.
3. **(ek bulgu) Flash sale sepete eklenmiyor** — `FlashSalesScreen._addToCart` sadece `claimFlashSale` çağırıyor; ardından `cart` tablosuna insert yapmıyor. Stok düşüyor ama kullanıcının sepetinde ürün görünmüyor.
4. **(ek bulgu) Sepet ve checkout tutarlarında flaş indirim yansımıyor** — `cart_screen.dart` ve `checkout_screen.dart` `item.productPrice` veya `item.effectivePrice` kullanıyor, `flash_price` hiç hesaba katılmıyor.

## Kök neden

`CartItem.effectivePrice` mantığı sadece `productDiscountPrice` ve `productPrice` kullanıyor. `flash_sales` tablosundaki `flash_price`, `CartItem` modeline hiç taşınmıyor. Dolayısıyla sepet/ödeme akışının tamamı flaş fiyattan bihaber.

`Product.hasDiscount` de yalnızca `products.discount_price` kolonuna bakıyor; bu yüzden ürün kartı rozeti (FlashDiscountBadge) flaş indirimde görünmüyor. Tüm ürün kartları (`_buildProductCard`, `_buildDiscountedProductCard`, `_buildProductCardForGrid`, `shop_detail_screen._buildProductCard`, `favorites_screen._ProductCard`) bu kola bağlı.

`FlashSalesScreen._addToCart` ise yarım kalmış: `claim_flash_sale` RPC'sini çağırıp stoğu düşürüyor, ama `cart` tablosuna insert yapmıyor. Kullanıcı "Sepete eklendi" mesajı alıyor ama sepetine gittiğinde ürün yok. Bu, stoğun "kaybolmasına" da yol açıyor.

## Çözüm stratejisi

Flaş indirim bilgisi `variant_data` JSONB kolonunda **saklanmaz** (variant_data varyant özelliklerine ayrılmış), bunun yerine `cart` tablosuna **iki yeni kolon** eklenir:
- `flash_sale_id UUID NULL` — `flash_sales.id`'ye FK (referans için; sipariş onaylanınca `release_flash_sale` çağırabilmek ve raporlama için)
- `flash_price NUMERIC(10,2) NULL` — sepete eklendiği anda sabitlenen flaş fiyat (satıcı sonradan değiştirse bile kullanıcı aleyhine değişmez)

Bu iki kolon `order_items`'a da aynen aktarılır (fatura, iade, raporlama için). `release_flash_sale` hâlâ `flash_sale_id` üzerinden çağrılabilir.

`Product` modeline `activeFlashSale` alanı eklenmez; bunun yerine ürün kartlarında mevcut `FlashSaleService.getActiveFlashSaleForProduct` ile isteğe bağlı kontrol yapılır. Daha az değişiklik, daha az migration.

## Değişiklik listesi

### 1. Veritabanı (Supabase migration)

Yeni dosya: `supabase/migrations/20260730000001_cart_flash_sale_columns.sql`

- `cart` tablosuna `flash_sale_id UUID NULL` ve `flash_price NUMERIC(10,2) NULL` ekle.
- `order_items` tablosuna `flash_sale_id UUID NULL` ve `flash_price NUMERIC(10,2) NULL` ekle.
- Gerekli indeksler: `idx_cart_flash_sale (flash_sale_id)`.

### 2. `lib/core/models/cart_model.dart`

- `CartItem`'a `final String? flashSaleId;` ve `final double? flashPrice;` alanları ekle.
- `fromJson`/`toJson`/`copyWith` güncelle.
- **`effectivePrice` getter'ı önce `flashPrice`'a baksın** (en öncelikli indirim), sonra `productDiscountPrice`, sonra `productPrice`.
- `itemDiscount`/`hasDiscount`/`discountPercentage` mantığı da `flashPrice`'ı dikkate alsın.
- `_mapToCartItem` (CartService içindeki) yeni alanları doldursun.

### 3. `lib/features/market/services/cart_service.dart`

- `addToCart`'a `String? flashSaleId, double? flashPrice` parametreleri ekle.
- Insert/update sorgularında bu kolonları da yaz.
- Mevcut `cart` join'inde `flash_sale_id` ve `flash_price` kolonlarını da SELECT et.

### 4. `lib/features/market/services/flash_sale_service.dart`

- `claimFlashSale` artık stok düşürmenin yanı sıra **uygulama katmanına** hangi `flash_price`'ın sabitlendiğini döndürüyor (zaten `flash_price` dönüyor; dokümante et).
- `getActiveFlashSaleForProduct` ürün kartı rozeti için bir kere daha kullanılabilir; mevcut API yeterli.

### 5. `lib/features/market/providers/cart_provider.dart`

- `addToCart`'a `String? flashSaleId, double? flashPrice` parametreleri ekle ve `CartService`'e ilet.

### 6. `lib/features/market/screens/flash_sales_screen.dart`

- `_addToCart(FlashSale sale)` artık:
  1. `service.claimFlashSale(saleId, quantity)` çağırır.
  2. Başarılıysa `cartProvider.addToCart(productId, quantity, flashSaleId: sale.id, flashPrice: sale.flashPrice)` çağırır (cart_provider import'u eklenir).
  3. Hata varsa kullanıcıya bildir ve **`releaseFlashSale` çağır** (stok geri verilsin).

### 7. `lib/features/market/screens/product_detail_screen.dart`

- `_addToCart` içinde aktif flaş sale varsa `flashSaleId` ve `flashPrice`'ı `addToCart`'a ilet.
- Fiyat bloğunda flaş sale aktifse `product.effectivePrice` yerine `_activeFlashSale.flashPrice` gösterilebilir; ya da `Product.effectivePrice` mantığına (aşağıda) bırakılır. **Karar**: Mini banner zaten gösteriliyor; mevcut fiyat alanı `_activeFlashSale.flashPrice` ile override edilir, üstü çizili olarak `_activeFlashSale.originalPrice` gösterilir.

### 8. `lib/core/models/product_model.dart`

- (Opsiyonel) Geçici flaş sale bilgisi için `Product` modeline `activeFlashSale` eklemeyelim — sadece ekranlarda `getActiveFlashSaleForProduct` ile çekip UI'da kullanalım.

### 9. Tüm ürün kartlarında flaş indirim etiketini göster

Her ürün kartı bileşeninde:
- `if (product.hasDiscount || _activeFlashSale != null) FlashDiscountBadge(...)` 
- Eğer flaş sale aktifse yüzde: `_activeFlashSale.discountPercent.round()`
- Eğer flaş sale aktifse fiyat: `_activeFlashSale.flashPrice`
- Eğer flaş sale aktifse eski fiyat: `_activeFlashSale.originalPrice`
- **Önemli**: `setState` içinde `_activeFlashSale`'i tutmak kartları StatefulWidget yapar; kartlar Stateless olduğu için ek bir strateji gerekir.

**En az dokunuşlu strateji**:
- Ürün kartlarında **yalnızca** mevcut `product.hasDiscount` mantığına güvenmek yerine, kart bileşenlerini `FutureBuilder<FlashSale?>(future: getActiveFlashSaleForProduct(product.id))` ile sarmalayıp flaş sale varsa onu kullanan yeni küçük bir helper fonksiyon yaz (`effectiveDiscountPercent`, `effectiveOldPrice`, `effectiveDisplayPrice`).
- Bu yeni helper'lar tüm ürün kartlarına uygulanır.

Düzenlenmesi gereken 5 dosya:
- `lib/features/market/screens/market_screen.dart` (`_buildDiscountedProductCard`)
- `lib/features/market/screens/all_discounted_products_screen.dart` (`_buildProductCard`)
- `lib/features/market/screens/search_screen.dart` (`_buildProductCardForGrid`)
- `lib/features/market/screens/shop_detail_screen.dart` (`_buildProductCard`)
- `lib/features/favorites/screens/favorites_screen.dart` (`_ProductCard`)

Yeni helper dosyası: `lib/features/market/widgets/flash_aware_price_row.dart` (flaş sale + normal indirim + düz fiyatı tek yerde toplayan widget). Her ürün kartı bu widget'ı kullanır.

### 10. `lib/features/market/screens/cart_screen.dart`

- `_buildModernCartItem` içinde fiyat gösteriminde `item.effectivePrice` (artık flaş fiyatı da kapsar) kullanılsın.
- `item.flashPrice` varsa kırmızı etiket: `FlashSaleBadge(percentage: ...)`.
- Aynı şekilde `_buildModernShopSection` dükkan toplamı için zaten `itemTotal` kullanıyor; `itemTotal`'in doğru çalışması için yukarıdaki model değişikliği yeterli.

### 11. `lib/features/market/screens/checkout_screen.dart` ve `lib/features/market/screens/multi_shop_checkout_screen.dart`

- `item.productPrice` geçen yerler `item.effectivePrice` ile değiştirilir (zaten çoğu yerde öyle).
- `OrderItem` modeli `flashSaleId`/`flashPrice` taşımalı; bu yüzden `lib/core/models/order_model.dart` da güncellenmeli.
- `order_service.dart` içinde `OrderItem` oluşturulurken `flashSaleId`/`flashPrice` alanları set edilsin.
- Order oluşturma sonrası `flash_sale`'i "satıldı" diye işaretlemek için ekstra RPC gerekmez; `claim_flash_sale` zaten stoğu düşürüyor. **Ama**: Sepete eklenip ödeme yapılmayınca cart temizlendiğinde/ürün silindiğinde `release_flash_sale` çağrılmalıdır.

### 12. `release_flash_sale` entegrasyonu

- `cart_provider.removeFromCart` ve `clearCart` çağrıldığında, silinen cart satırında `flash_sale_id` varsa `release_flash_sale` çağrısı ekle.
- `cart_provider.updateQuantity` miktar azaltılıyorsa fark kadar `release_flash_sale` çağır.

### 13. `lib/core/models/order_model.dart`

- `OrderItem`'a `flashSaleId`/`flashPrice` ekle; `toJson`/`fromJson`/`copyWith` güncelle.

## Doğrulama adımları

1. `flutter analyze` hatasız.
2. Manuel test senaryoları:
   - **Senaryo A**: Aktif flaş sale olan ürünü ana sayfa kartında gör → rozet görünüyor mu, fiyat flaş fiyat mı?
   - **Senaryo B**: Aynı ürünü detay ekranında aç → "Flash: X ₺" mini banner + fiyat flaş fiyat + üstü çizili orijinal fiyat.
   - **Senaryo C**: Flaş sale ürününü sepete ekle → `cart` tablosunda `flash_sale_id` ve `flash_price` dolu mu? Sepet ekranında toplam flaş fiyat üzerinden mi?
   - **Senaryo D**: Sepetten ürünü sil → `flash_sales.sold_count` geri düşüyor mu (`release_flash_sale` çağrıldı mı)?
   - **Senaryo E**: Sepetteki flaş sale ürünüyle checkout'a git → `order_items` tablosunda `flash_sale_id` ve `flash_price` dolu mu, ödenen tutar doğru mu?
3. `flutter build apk --debug` başarılı.

## Görev sırası (uygulama)

1. SQL migration (cart + order_items kolonları)
2. Order_model.dart (OrderItem alanları)
3. Cart_model.dart (CartItem alanları + effectivePrice mantığı)
4. cart_service.dart (parametreler + SELECT)
5. cart_provider.dart (parametreler + release_flash_sale entegrasyonu)
6. flash_sales_screen.dart (claim + addToCart + release)
7. flash_aware_price_row.dart (yeni helper widget)
8. Tüm 5 ürün kartı (market/all_discounted/search/shop_detail/favorites)
9. product_detail_screen.dart (fiyat bloğu)
10. cart_screen.dart (rozet + fiyat)
11. checkout_screen.dart + multi_shop_checkout_screen.dart (OrderItem alanları)
12. order_service.dart (OrderItem oluştururken flash alanları)
13. flutter analyze + manuel test

## Riskler ve notlar

- **Migration geriye uyumlu**: Kolonlar nullable, mevcut cart satırları etkilenmez.
- **Stok yarış durumu**: `claim_flash_sale` zaten atomik (`FOR UPDATE`); release de atomik. Sepete ekle-sil-ekle döngüsünde stok kaybı olmaz.
- **Ürün kartlarına flash sale çekmek** her kart build'inde bir ek query demek. Bunu kabul edilebilir tutmak için kart bileşenlerini `FutureBuilder` ile sarmalarken, kart görünür olduğunda yükleme yapılacak şekilde `cacheExtent`/`addAutomaticKeepAlives` davranışı değiştirilmez; sadece `getActiveFlashSaleForProduct` zaten indexed bir sorgu (`idx_flash_sales_product`).
- **Mevcut davranışın bozulmaması**: `effectivePrice` sıralaması (flash > discount > price) eskisinden farklı, ama bu kullanıcının lehinedir (her zaman en iyi fiyat). Satıcı zaten `original_price` ile `flash_price` ayarlarken `flash_price < original_price` kısıtı var.
