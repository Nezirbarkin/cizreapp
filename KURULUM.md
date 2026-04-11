# CizreApp - Kurulum ve Kullanım Rehberi

## 📱 Proje Hakkında

CizreApp, Flutter + Supabase ile geliştirilmiş, hem alışveriş (marketplace) hem de sosyal medya özelliklerini birleştiren kapsamlı bir mobil uygulamadır.

### Özellikler

✅ **Market & E-Ticaret**
- Kategoriler, dükkanlar, ürünler
- Alışveriş sepeti ve sipariş sistemi
- Ödeme entegrasyonu (iyzico hazır)

✅ **Sosyal Medya**
- Gönderi paylaşma, beğeni, yorum
- Story sistemi (24 saat)
- Takip/Takipçi sistemi

✅ **Mesajlaşma**
- Gerçek zamanlı chat
- Konuşma listesi

✅ **Profil & Ayarlar**
- Kullanıcı profili
- Tema değiştirme (Yeşil/Mavi)

✅ **Admin Panel** (Web)
- Dashboard ve raporlar
- Satıcı, üye, sipariş yönetimi
- Kampanya ve bildirim sistemi

✅ **Satıcı Panel** (Web)
- Satıcı dashboard
- Sipariş ve ürün yönetimi
- Raporlar

---

## 🚀 Kurulum Adımları

### 1. Gereksinimler

- Flutter SDK (3.32.0 veya üzeri)
- Dart SDK
- Android Studio / VS Code
- Supabase hesabı

### 2. Projeyi Klonlayın

```bash
git clone <repository-url>
cd cizreapp
```

### 3. Bağımlılıkları Yükleyin

```bash
flutter pub get
```

### 4. Supabase Kurulumu

#### 4.1. Supabase Projesi Oluşturun
1. [Supabase](https://supabase.com) hesabı oluşturun
2. Yeni proje oluşturun
3. Project URL ve Anon Key'i alın

#### 4.2. Veritabanı Şemasını Yükleyin

Supabase Dashboard > SQL Editor'e gidin ve [`supabase_schema.sql`](supabase_schema.sql) dosyasındaki SQL kodlarını çalıştırın:

```sql
-- 1. supabase_schema.sql dosyasını açın
-- 2. Tüm içeriği kopyalayın
-- 3. Supabase SQL Editor'e yapıştırın
-- 4. Run tuşuna basın
```

#### 4.3. Test Verilerini Yükleyin

```sql
-- test_data.sql dosyasındaki verileri yükleyin
-- Bu market test verileri içerir
```

### 5. Supabase Anahtarlarını Ekleyin

[`lib/main.dart`](lib/main.dart) dosyasını açın ve Supabase bilgilerinizi girin:

```dart
await Supabase.initialize(
  url: 'YOUR_SUPABASE_URL', // Buraya URL'inizi girin
  anonKey: 'YOUR_SUPABASE_ANON_KEY', // Buraya Anon Key'inizi girin
);
```

### 6. Uygulamayı Çalıştırın

```bash
# Android Emulator veya cihaz
flutter run

# iOS Simulator (Mac gerekli)
flutter run -d ios

# Web (tarayıcı)
flutter run -d chrome
```

---

## 📊 Veritabanı Yapısı

### Ana Tablolar

1. **profiles** - Kullanıcı profilleri
2. **shops** - Satıcı dükkanları
3. **categories** - Ürün/dükkan kategorileri
4. **products** - Ürünler
5. **orders** - Siparişler
6. **posts** - Sosyal medya gönderileri
7. **stories** - 24 saatlik hikayeler
8. **messages** - Mesajlar
9. **conversations** - Konuşmalar

### Güvenlik (RLS)

Tüm tablolar Row Level Security (RLS) ile korunmaktadır:
- Kullanıcılar sadece kendi verilerini görebilir/düzenleyebilir
- Admin'ler tüm verilere erişebilir
- Satıcılar sadece kendi dükkan verilerine erişebilir

---

## 🎨 Tasarım & Tema

Proje [`tasarım.php`](tasarım.php) dosyasındaki tasarıma göre geliştirilmiştir:

- **Primary Color**: `#00C853` (Yeşil)
- **Secondary Color**: `#007AFF` (Mavi)
- **Font**: Inter

Tema değiştirme profil ayarlarından yapılabilir.

---

## 🔐 Kullanıcı Rolleri

### 1. Customer (Müşteri)
- Alışveriş yapabilir
- Sosyal medya kullanabilir
- Mesajlaşabilir

### 2. Seller (Satıcı)
- Dükkan açabilir
- Ürün ekleyebilir
- Sipariş yönetebilir
- Satıcı paneline erişebilir

### 3. Admin (Yönetici)
- Tüm yetkilere sahip
- Admin paneline erişebilir
- Satıcı onaylayabilir
- Sistem ayarlarını değiştirebilir

---

## 📁 Proje Yapısı

```
lib/
├── core/
│   ├── models/          # Veri modelleri
│   ├── theme/           # Tema ve renkler
│   └── constants/       # Sabitler
├── features/
│   ├── auth/            # Giriş/Kayıt
│   ├── market/          # Market modülü
│   ├── social/          # Sosyal medya
│   ├── shop/            # Sepet & Sipariş
│   ├── chat/            # Mesajlaşma
│   ├── profile/         # Profil & Ayarlar
│   └── main/            # Ana navigasyon
└── main.dart            # Ana dosya

web/
├── admin/               # Admin panel (HTML)
└── satici/              # Satıcı panel (HTML)
```

---

## 🧪 Test Kullanıcıları

Test verileri yüklendikten sonra:

**Test Kullanıcı ID**: `78665f8b-6a07-40f3-b13d-d4b5a29296c6`

---

## 🌐 Web Panelleri

### Admin Panel
```
web/admin/index.html
```

Özellikler:
- Dashboard ve istatistikler
- Satıcı yönetimi
- Üye yönetimi
- Sipariş takibi
- Kampanya yönetimi
- Bildirim gönderimi

### Satıcı Panel
```
web/satici/index.html
```

Özellikler:
- Satış raporları
- Sipariş yönetimi
- Ürün yönetimi
- Ödeme bilgileri
- Dükkan ayarları

Web panellerini açmak için:
```bash
# Admin panel
open web/admin/index.html

# Satıcı panel
open web/satici/index.html
```

---

## 🔔 Bildirim Sistemi (Opsiyonel)

Firebase Cloud Messaging (FCM) entegrasyonu için:

1. Firebase Console'da proje oluşturun
2. `google-services.json` (Android) ve `GoogleService-Info.plist` (iOS) indirin
3. `firebase_messaging` paketini ekleyin
4. Notification servisini yapılandırın

---

## 💳 Ödeme Entegrasyonu (iyzico)

iyzico entegrasyonu için:

1. [iyzico](https://www.iyzico.com) hesabı oluşturun
2. API Key ve Secret Key alın
3. `lib/core/constants/payment_config.dart` oluşturun:

```dart
class PaymentConfig {
  static const String iyzico ApiKey = 'YOUR_API_KEY';
  static const String iyzicoSecretKey = 'YOUR_SECRET_KEY';
  static const String iyzicoBaseUrl = 'https://sandbox-api.iyzipay.com'; // Test
}
```

---

## 🐛 Debug Modu

Debug modunu açmak için:

```dart
// lib/main.dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Debug modu
  if (kDebugMode) {
    print('🐛 Debug Mode Active');
  }
  
  // ...
}
```

---

## 📝 Önemli Notlar

### Supabase RLS Politikaları
- Tüm tablolar RLS ile korunmaktadır
- Yeni tablo eklerken mutlaka RLS politikası ekleyin
- Test ederken RLS politikalarını kontrol edin

### Performans
- Story'ler 24 saat sonra otomatik silinir
- Mesajlar gerçek zamanlı stream ile çalışır
- Ürün listeleri sayfalama ile yüklenir

### Güvenlik
- Hassas bilgileri `.env` dosyasında saklayın
- API anahtarlarını GitHub'a yüklemeyin
- Production'da HTTPS kullanın

---

## 🆘 Sorun Giderme

### Supabase Bağlantı Hatası
```
Error: Failed to connect to Supabase
```
**Çözüm**: URL ve Anon Key'i kontrol edin

### Build Hatası (Android)
```
Error: Minimum SDK version
```
**Çözüm**: `android/app/build.gradle` içinde `minSdkVersion 21` olmalı

### RLS Permission Denied
```
Error: new row violates row-level security policy
```
**Çözüm**: RLS politikalarını kontrol edin, gerekirse yeniden oluşturun

---

## 📞 Destek

Sorularınız için:
- GitHub Issues
- Email: support@cizreapp.com
- Web: www.cizreapp.com

---

## 📄 Lisans

Bu proje MIT lisansı altında lisanslanmıştır.

---

## 🎯 Sonraki Adımlar

1. ✅ Supabase veritabanını kurun
2. ✅ Test verilerini yükleyin
3. ✅ Uygulamayı test edin
4. 🔲 iyzico ödeme entegrasyonu
5. 🔲 Push notification entegrasyonu
6. 🔲 App Store ve Google Play yayını

---

**Başarılar! 🚀**
