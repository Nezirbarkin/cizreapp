# Üç Görev Çözüm Planı

## Görev 1: Admin Panelinde Kuryesi Olmayan Dükkanlar için Teslimat Ücreti Belirleme

### Mevcut Durum
- Admin panelinde `_showShopDetailDialog` ve `_showEditShopDialog` metodları var
- `shops` tablosunda `min_delivery_fee` kolonu zaten mevcut (migration'dan)
- Dükkan modelinde de bu alan var

### Yapılacaklar
1. `admin_dashboard_screen.dart` içindeki `_showEditShopDialog` metoduna teslimat ücreti alanı ekle
2. `has_own_courier=false` olan dükkanlar için min_delivery_fee düzenlenebilir hale getir
3. Dialog'da `min_delivery_fee` TextField'ı ekle

### Dosyalar
- `lib/features/admin/screens/admin_dashboard_screen.dart` - Edit shop dialog güncelle

---

## Görev 2: Onaylanmamış Dükkanların Uygulamada Gösterilmemesi

### Mevcut Durum
- `ShopService.getShops()` sadece `is_active=true` filtresi kullanıyor
- `is_approved` kontrolü yok
- Market ekranında onay bekleyen dükkanlar gösteriliyor

### Yapılacaklar
1. `ShopService.getShops()` metoduna `.eq('is_approved', true)` filtresi ekle
2. `ShopService.getShopsByCategory()` metoduna da aynı filtreyi ekle
3. `ShopService.searchShops()` metoduna da filtre ekle

### Dosyalar
- `lib/features/market/services/shop_service.dart` - Filtreleri ekle

---

## Görev 3: Sosyal Medya Gönderi Resim Yükleme Sorunu

### Mevcut Durum
- `create_post_screen.dart` içinde `_uploadImages()` metodu var
- `_uploadedImageUrls` listesine URL'ler ekleniyor gibi görünüyor ama实际问题 olmalı
- Gönderi paylaşılıyor ama resim boş gösteriyor

### Olası Sorunlar
1. `_uploadImages()` metodunda `await` ile beklenmeden `_uploadedImageUrls` listesine ekleniyor olabilir
2. Supabase storage bucket veya RLS sorunu olabilir
3. `createPost` çağrısı sırasında `_uploadedImageUrls` henüz dolmamış olabilir

### Yapılacaklar
1. `create_post_screen.dart` içindeki `_uploadImages()` metodunu incele ve düzelt
2. `_uploadedImageUrls` listesine URL'lerin doğru eklendiğinden emin ol
3. Supabase storage bucket'ının doğru yapılandırıldığını kontrol et

### Dosyalar
- `lib/features/social/screens/create_post_screen.dart` - Upload metodunu düzelt

---

## Uygulama Sırası
1. **Görev 2** (en kolay) - ShopService filtresi ekle
2. **Görev 1** - Admin panel dialog güncelle
3. **Görev 3** - Resim yükleme sorunu ara ve çöz
