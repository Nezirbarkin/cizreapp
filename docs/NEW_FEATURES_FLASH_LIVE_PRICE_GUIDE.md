# Yeni Özellikler: Flash Satış, Fiyat Alarmı, Canlı Yayın Alışverişi

CizreApp'e eklenen üç yeni e-ticaret özelliği için kurulum ve kullanım rehberi.

---

## 📦 Genel Bakış

| Özellik | Backend | Client | Tetikleme |
|---------|---------|--------|-----------|
| Fiyat Düşüş Alarmı | `price_alerts` + DB trigger | [`price_alert_service.dart`](../lib/features/market/services/price_alert_service.dart) | Sunucu-taraflı (ürün fiyatı düşünce) |
| Flash Satış | `flash_sales` + RPC (atomic stok) | [`flash_sale_service.dart`](../lib/features/market/services/flash_sale_service.dart) | Realtime (stok değişimi) |
| Canlı Yayın Alışverişi | `live_sessions` + Agora | [`live_shopping_service.dart`](../lib/features/market/services/live_shopping_service.dart) + [`agora_service.dart`](../lib/features/market/services/agora_service.dart) | Supabase Realtime + Agora RTC |

---

## 1️⃣ Kurulum — Supabase Migration'ları

Supabase Studio → SQL Editor'da sırayla çalıştır (idempotent'tir):

> **Linter düzeltmesi:** Eğer tablolar zaten oluşturulmuşsa ve Supabase linter
> (`function_search_path_mutable`, `anon_security_definer_function_executable`)
> uyarıları görünüyorsa, [`supabase/20260724000000_fix_linter_warnings.sql`](../supabase/20260724000000_fix_linter_warnings.sql)
> migration'ını da çalıştırın. Aşağıdaki setup dosyaları bu düzeltmeleri zaten içerir.

1. **`supabase/FLASH_SALE_AND_PRICE_ALERT_SETUP.sql`**
   - `flash_sales` + `price_alerts` tabloları
   - `claim_flash_sale` / `release_flash_sale` RPC (atomic stok)
   - `notify_price_drops()` trigger (ürün fiyatı düşünce alarm + push)
   - RLS politikaları
   - Realtime publication ekleme

2. **`supabase/LIVE_SHOPPING_SETUP.sql`**
   - `live_sessions` + `live_pinned_products` + `live_messages` tabloları
   - `start_live_session` / `end_live_session` RPC
   - RLS politikaları
   - Realtime publication ekleme

> Migration'larda `supabase_realtime` publication'a tablo eklenir; Supabase Dashboard → Database → Replication bölümünde bu tabloların Realtime için işaretli olduğundan emin olun.

---

## 2️⃣ Kurulum — Agora (Canlı Yayın)

1. [agora.io](https://www.agora.io) üzerinde ücretsiz hesap aç, bir proje oluştur, **App ID** al.
2. Proje kök dizinindeki `.env` dosyasına ekle:

   ```
   AGORA_APP_ID=senin_app_id_in
   AGORA_TOKEN=opsiyonel_test_token
   ```

   > **Not:** Boş App ID ile yayın çalışmaz; viewer ekranında net hata mesajı gösterilir.
3. **Üretim için:** Statik token yerine, App Certificate ile token üreten bir Supabase Edge Function (Token Server) kurmanız önerilir. Mevcut `AgoraService` boş token olduğunda `''` gönderir; Agora App ID-only modu test amaçlı yeterlidir.

### iOS (opsiyonel)

`ios/Runner/Info.plist` içine kamera/mikrofon kullanım açıklamaları eklenmeli:

```xml
<key>NSCameraUsageDescription</key>
<string>Canlı yayın için kamera kullanılır</string>
<key>NSMicrophoneUsageDescription</key>
<string>Canlı yayında ses için mikrofon kullanılır</string>
```

Android izinleri (`CAMERA`, `RECORD_AUDIO`) `AndroidManifest.xml`'de zaten mevcut.

---

## 3️⃣ Kullanım — Kullanıcı Tarafı

### Fiyat Alarmı
- **Ürün detayında** "🔔 Fiyat Alarmı Kur" butonu → slider ile hedef fiyat seç.
- **Favoriler ekranı** AppBar'daki 🔔 ikonu → `MyPriceAlertsScreen` ile tüm alarmlarını gör/kaldır.
- Ürün fiyatı hedefin altına düştüğünde:
  - In-app notification (`notifications` tablosuna `price_drop` tipinde kayıt)
  - Push notification (FCM, `send-push-notification` Edge Function)

### Flash Satış
- **Favoriler ekranı** üstündeki "Flash Satışlar" butonu veya giriş bandı → `FlashSalesScreen`.
- Geri sayım banner + ürün kartında canlı stok progress bar.
- "Sepete ekle" → `claim_flash_sale` RPC ile atomic stok düşürme (eşzamanlı claim'ler sıralı işlenir, race condition yok).
- Süre dolunca ürün kartı "SÜRE DOLDU" overlay; stok bitince "TÜKENDİ".

### Canlı Yayın
- **Favoriler ekranı** AppBar'daki 📺 ikonu → `LiveSessionsScreen` (aktif + son biten yayınlar).
- Tıklayınca `LiveViewerScreen`: Agora uzak video + sağda canlı sohbet + altta pinli ürün.
- Realtime: yeni mesaj ve pin değişimi anlık yansır.

---

## 4️⃣ Kullanım — Satıcı Tarafı

Satıcı paneli (Seller Dashboard) → Drawer:

- **"Flash Satış Yönetimi"** → `SellerFlashSalesScreen`
  - "Yeni Flash Satış" FAB ile ürün seç + flash fiyat + stok + süre (1h/6h/12h/1g/3g) seç.
  - Aktif/yakında/bitti durum çipleri; "Durdur" ile pasifleştir.

- **"Canlı Yayın Başlat"** → `LiveHostScreen`
  - Hazırlık modunda kamera önizleme → "Yayına Başla" ile `live` duruma geçer.
  - Sağ panelde mağaza ürünlerinden pinleme (yatay kaydırmalı liste).
  - Kamera/mikrofon aç-kapa butonları.
  - "Bitir" ile `end_live_session` RPC çağrılır, kanal ayrılır.

---

## 5️⃣ Dosya Listesi (Yeni)

### Modeller
- [`lib/core/models/flash_sale_model.dart`](../lib/core/models/flash_sale_model.dart)
- [`lib/core/models/price_alert_model.dart`](../lib/core/models/price_alert_model.dart)
- [`lib/core/models/live_shopping_model.dart`](../lib/core/models/live_shopping_model.dart)

### Servisler
- [`lib/features/market/services/flash_sale_service.dart`](../lib/features/market/services/flash_sale_service.dart)
- [`lib/features/market/services/price_alert_service.dart`](../lib/features/market/services/price_alert_service.dart)
- [`lib/features/market/services/live_shopping_service.dart`](../lib/features/market/services/live_shopping_service.dart)
- [`lib/features/market/services/agora_service.dart`](../lib/features/market/services/agora_service.dart)

### Ekranlar
- [`lib/features/market/screens/flash_sales_screen.dart`](../lib/features/market/screens/flash_sales_screen.dart)
- [`lib/features/market/screens/my_price_alerts_screen.dart`](../lib/features/market/screens/my_price_alerts_screen.dart)
- [`lib/features/market/screens/live_sessions_screen.dart`](../lib/features/market/screens/live_sessions_screen.dart)
- [`lib/features/market/screens/live_viewer_screen.dart`](../lib/features/market/screens/live_viewer_screen.dart)
- [`lib/features/market/screens/live_host_screen.dart`](../lib/features/market/screens/live_host_screen.dart)
- [`lib/features/seller/screens/seller_flash_sales_screen.dart`](../lib/features/seller/screens/seller_flash_sales_screen.dart)

### Widget'lar
- [`lib/features/market/widgets/flash_countdown_banner.dart`](../lib/features/market/widgets/flash_countdown_banner.dart)
- [`lib/features/market/widgets/flash_sale_card.dart`](../lib/features/market/widgets/flash_sale_card.dart)
- [`lib/features/market/widgets/flash_sale_entry_banner.dart`](../lib/features/market/widgets/flash_sale_entry_banner.dart)
- [`lib/features/market/widgets/price_alert_dialog.dart`](../lib/features/market/widgets/price_alert_dialog.dart)

### Backend
- [`supabase/FLASH_SALE_AND_PRICE_ALERT_SETUP.sql`](../supabase/FLASH_SALE_AND_PRICE_ALERT_SETUP.sql)
- [`supabase/LIVE_SHOPPING_SETUP.sql`](../supabase/LIVE_SHOPPING_SETUP.sql)

---

## 6️⃣ Entegrasyon Noktaları (Mevcut Dosyalara Eklenenler)

- [`lib/features/market/screens/product_detail_screen.dart`](../lib/features/market/screens/product_detail_screen.dart): fiyat alarmı butonu + flash sale mini banner.
- [`lib/features/favorites/screens/favorites_screen.dart`](../lib/features/favorites/screens/favorites_screen.dart): fiyat alarmı + canlı yayın + flash satış girişleri.
- [`lib/features/seller/screens/seller_dashboard_screen.dart`](../lib/features/seller/screens/seller_dashboard_screen.dart): Drawer'da "Flash Satış Yönetimi" ve "Canlı Yayın Başlat" item'ları.
- [`pubspec.yaml`](../pubspec.yaml): `agora_rtc_engine: ^6.5.3` bağımlılığı.

---

## 7️⃣ Test İpuçları

1. **Fiyat Alarmı:** Ürün detayda alarm kur → Supabase'den ürün `price`'ını düşür → `notifications` tablosunda `price_drop` kaydı ve push gelmeli.
2. **Flash Satış:** Satıcı panelinden flash sale oluştur → başka hesapla ürünü sepete eklemeyi dene → stok progress bar güncellenmeli; iki cihaz aynı anda claim ederse RPC sıralı işlenir.
3. **Canlı Yayın:** `.env`'e App ID koy → satıcı yayına başla → başka cihazdan `LiveSessionsScreen`'de görünmeli → katılınca sohbet + pinli ürün akmalı.

---

## 8️⃣ Sınırlar / Sonraki Adımlar

- **Agora token** şu an statik/test. Üretimde Edge Function ile dinamik token üretmek güvenlik açısından gerekli.
- **Live video render** `live_viewer_screen.dart`'ta şimdilik placeholder (ilerleme göstergesi); gerçek video surface `VideoViewController.remote` + `AgoraVideoView` ile widget ağacına bağlanmalı (Agora v6 render API). Ses/sohbet/pin akışı tam çalışır.
- **İzleyici sayısı** için Supabase Realtime `presence` kullanılabilir (şu an `peak_viewer_count` alanı var ama presence tracking client-taraflı eklenmeli).