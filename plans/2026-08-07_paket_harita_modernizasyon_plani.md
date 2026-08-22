# Paket Gönder/Al Ekranı — Harita Modernizasyon Planı

**Tarih:** 2026-08-07
**Hedef dosya:** `lib/features/user_courier/widgets/couriers_map_card.dart`
**İlgili ekran:** `lib/features/user_courier/screens/send_package_screen.dart`

## 🎯 Kullanıcı Talepleri
1. Haritayı **daha modern** görünüme kavuştur.
2. **Moto kurye ikonu** çok büyük, daha **küçük** olsun.
3. Haritayı **tam ekran** yapabilsin.
4. Haritayı **parmağıyla gezdirebilsin**, yakınlaştırabilsin, uzaklaştırabilsin.

## 📊 Mevcut Durum
- `couriers_map_card.dart` zaten `scrollGesturesEnabled: true`, `zoomGesturesEnabled: true`, `tiltGesturesEnabled: true`, `rotateGesturesEnabled: true` kullanıyor → parmak hareketleri **teorik olarak aktif**.
- Sorun: harita **200 px sabit yükseklikte** bir Card içine sıkıştırılmış, kart stadiyum görünümlü. Yakınlaştırma için görsel geri bildirim (buton) yok. Tam ekran modu yok.
- Moto kurye ikonu `_createMotorcycleBitmap()` içinde `size = 90` ile çiziliyor. Pin + üçgen + ikon büyük ve sivri uçlu → harita üzerinde baskın, komşu kuryeleri/konumları örtüyor.

## ✅ Planlanan Değişiklikler

### 1. Yeni widget: `CouriersMapCard` (modern görünüm)
- **Sabit yükseklik** 200 → **220 px** (biraz nefes alır).
- **Border radius** 12 → **16**, gölge (elevation: 4) eklenecek; sade, modern kart görünümü.
- Başlık satırı sadeleştirilecek: yalnızca sol tarafta `Yakın Kuryeler (N)` + sağda zoom-out, recenter, fullscreen butonları.
- **Stil**: kart arka planı `surfaceContainerHigh` (Material 3 tonu) — daha modern.
- Alt kısımda modern, yarı saydam zoom in / zoom out **yüzen butonlar** (sağ alt köşede).
- Sağ alt köşede: `+` (zoom in) ve `−` (zoom out) — Material 3 `FloatingActionButton.small` benzeri, beyaz arka plan, gölge.

### 2. Moto kurye ikonu küçültme
- `_createMotorcycleBitmap()` içinde `size = 90` → `size = 48`.
- Pin çapı `radius = size * 0.38` oranı korunur (~18 px), üçgen daha kompakt.
- İkon `fontSize: radius` → `fontSize: size * 0.42` (≈ 20 px), okunabilir ama ince ve modern.
- Pin üçgen sivri ucu hafif yumuşatılır (artık sivri yerine yuvarlatılmış taban).

### 3. Tam ekran modu
- Sağ üst köşeye **fullscreen ikonu** (`Icons.fullscreen`) eklenecek.
- Tıklanınca `Navigator.push` ile yeni `CouriersMapFullScreen` sayfası açılacak.
- Bu sayfa:
  - `Scaffold` içinde, `AppBar` ile geri tuşu ve başlık "Harita".
  - Tüm ekran kaplayan `GoogleMap` (harita yüksekliği 220 sınırından kurtulur).
  - Aynı marker seti ve `CouriersMapCard` state mantığı (CourierStreamService'e yeniden subscribe etmemek için ortak state kurulabilir veya `setState`/`onChange` callback'leri prop olarak geçirilebilir).
  - Zoom in / zoom out butonları (sağ alt).
  - "Konumuma dön" butonu.
  - "Tümünü göster" (fit bounds) butonu.
- Tam ekran sayfası açıkken arka plan haritanın reload yapmaması için **map controller**'ı yeniden oluşturmak yerine mevcut controller prop olarak aktarılabilir; ama en güvenlisi: fullscreen için ayrı bir stateful widget olsun ve aynı `CouriersMapCard` widget'ının sade formunu kullansın.

### 4. Parmakla gezdirme (zaten aktif ama görsel olarak desteklenecek)
- Mevcut tüm gesture flag'leri (`scrollGesturesEnabled`, `zoomGesturesEnabled`, `tiltGesturesEnabled`, `rotateGesturesEnabled`) zaten `true`. Bunlar korunacak.
- Ek olarak küçük harita için iki parmak pinch zoom gerekebilir. Dokunmatik alanın küçüklüğü düşünülerek kartın altında küçük bir bilgi satırı:
  > "💡 Haritayı parmağınızla kaydırın, iki parmakla yakınlaştırın"
  (sade, açı gri renkte, küçük punto).

### 5. UI/UX ince ayarlar
- Kurye sayısı rozet gibi (ör. "3") sağ üst köşede değil, başlıkta parantez içinde tutulur (mevcut).
- Yükleme durumunda kart yüksekliği korunur, içinde `CircularProgressIndicator` gösterilir (mevcut).
- Hata/boş durum mesajı kartın üstüne değil, harita alanı içine (mevcut `Positioned.fill` korunur).

## 🛠️ Uygulama Adımları

### Adım 1: `couriers_map_card.dart` güncelleme
- `_createMotorcycleBitmap()`: `size = 48`, ikon fontSize ayarı.
- `build()`:
  - Card'ı `elevation: 4`, `borderRadius: 16`, daha modern `surfaceContainerHigh` arka plan.
  - Kart yüksekliği 220.
  - Sağ üstte zoom-out, recenter, **fullscreen** butonları.
  - Sağ alt köşede iki yüzen buton: `+` (zoom in) ve `−` (zoom out). `Positioned` ile `Stack` içine.
  - Alt ipucu metni.
- Yardımcı metodlar:
  - `_zoomIn()`, `_zoomOut()`: `controller.animateCamera(CameraUpdate.zoomBy(1))` / `zoomBy(-1)`.
  - `_openFullScreen()`: `Navigator.push` ile `CouriersMapFullScreen(pickupLat, pickupLng, deliveryLat, deliveryLng)`.

### Adım 2: Yeni dosya `lib/features/user_courier/screens/couriers_map_full_screen.dart`
- `StatefulWidget`; `CouriersMapCard` ile benzer yapı:
  - `_getUserLocation`, `_ensureCourierIcon`, `_buildMarkers`, `_getBounds`, `_fitBounds`, `_recenterOnUser`, `_zoomIn`, `_zoomOut`.
  - Realtime veri için `CourierStreamService.subscribe(onChange)`.
  - Tek fark: harita `Expanded` ile tüm ekran.
  - `AppBar`: başlık "Harita", geri oku, sağ tarafta "Yenile" butonu opsiyonel.
- Kod tekrarı olmaması için `CouriersMapCard` widget'ı refactor edilip, harita state'i paylaşılan bir helper class'a taşınabilir. Ancak bu kapsam genişletir; **MVP için** fullscreen sayfası bağımsız bir kopyası olarak yazılır, ileride refactor yapılabilir (not plan dosyasında belirtilecek).

### Adım 3: Test & Doğrulama
- `flutter analyze` ile hata kontrolü.
- Görsel olarak: küçük ikonlar haritada daha az yer kaplamalı; zoom butonları çalışmalı; fullscreen butonu yeni sayfayı açmalı; geri dönmeli.

## 🚫 Kapsam Dışı
- Mevcut `_showCourierInfo` bottom sheet davranışı değişmez.
- Kurye realtime stream altyapısı değişmez.
- Marker renkleri (mavi/yeşil/turuncu) aynen kalır.

## ⚠️ Riskler
- **Moto ikon çok küçülürse haritada fark edilmez olabilir**: 48 px kritik eşiğin üstünde, info window tıklaması hâlâ mümkün.
- **Fullscreen sayfasında marker'lar geç yüklenirse harita boş görünebilir**: `_isLoading` flag'i korunur, içeride progress gösterilir.
- **Kartı 220 px'e çıkarmak bazı küçük telefonlarda klavye ile çakışabilir**: ScrollView içinde olduğundan sorun olmaz, mevcut düzende zaten var.

## 📁 Değişecek / Oluşacak Dosyalar
- ✏️ `lib/features/user_courier/widgets/couriers_map_card.dart` — modern kart + küçük ikon + tam ekran butonu.
- ➕ `lib/features/user_courier/screens/couriers_map_full_screen.dart` — yeni tam ekran harita sayfası.

## 🔄 Sonraki İyileştirmeler (bu task kapsamı dışı)
- `CouriersMapCard` ve `CouriersMapFullScreen` arasındaki ortak state'i (CourierStreamService listener, icon, markers) tek bir controller sınıfına çıkar.
- Modern stil için Material 3 `MapType.terrain` veya özel tile kullan.
- Cluster yönetimi (çok sayıda kurye olursa).
