# 🏪 CizreApp - Alışveriş & Sosyal Medya Platformu

## 📋 Proje Özeti

CizreApp, Flutter + Supabase ile geliştirilmiş, hem alışveriş (pazaryeri) hem de sosyal medya özelliklerine sahip kapsamlı bir mobil ve web uygulamasıdır.

### Özellikler
- ✅ **Kullanıcı Uygulaması**: Alışveriş, sosyal medya, mesajlaşma
- ✅ **Satıcı Paneli**: Dükkan yönetimi, sipariş takibi, ürün ekleme
- ✅ **Admin Paneli**: Sistem yönetimi, raporlar, kullanıcı/satıcı yönetimi
- ✅ **Gerçek Zamanlı**: Supabase ile canlı veri senkronizasyonu
- ✅ **Çoklu Tema**: Yeşil ve Mavi tema desteği

---

## 🚀 Kurulum Adımları

### 1. Flutter Paketlerini Yükleyin
```bash
cd c:/Users/lenovo/cizreapp
flutter pub get
```

### 2. Supabase Projesi Oluşturun

1. [supabase.com](https://supabase.com) adresine gidin
2. Yeni bir proje oluşturun
3. **SQL Editor**'a gidin
4. `supabase_schema.sql` dosyasındaki tüm SQL kodunu çalıştırın

### 3. Supabase Bilgilerini Ekleyin

`lib/core/constants/app_constants.dart` dosyasını açın ve aşağıdaki bilgileri güncelleyin:

```dart
static const String supabaseUrl = 'YOUR_SUPABASE_PROJECT_URL';
static const String supabaseAnonKey = 'YOUR_SUPABASE_ANON_KEY';
```

**Bu bilgileri nereden alacaksınız:**
- Supabase projenize gidin
- Settings > API'ye tıklayın
- `Project URL` ve `anon/public` anahtarını kopyalayın

---

## 📁 Proje Yapısı

```
lib/
├── core/                          # Çekirdek katman
│   ├── constants/                 # Sabitler
│   │   └── app_constants.dart     # Uygulama sabitleri
│   ├── theme/                     # Tema yönetimi
│   │   └── app_theme.dart         # Yeşil/Mavi temalar
│   ├── models/                    # Veri modelleri
│   │   ├── user_model.dart        # Kullanıcı modeli
│   │   ├── product_model.dart     # Ürün modeli
│   │   ├── shop_model.dart        # Dükkan modeli
│   │   ├── order_model.dart       # Sipariş modeli
│   │   └── post_model.dart        # Gönderi (sosyal) modeli
│   ├── services/                  # Servisler (oluşturulacak)
│   │   ├── supabase_service.dart  # Supabase bağlantısı
│   │   ├── auth_service.dart      # Kimlik doğrulama
│   │   ├── storage_service.dart   # Dosya yükleme
│   │   └── notification_service.dart # Bildirimler
│   └── utils/                     # Yardımcı fonksiyonlar
│       ├── validators.dart        # Form doğrulama
│       ├── formatters.dart        # Veri formatlama
│       └── helpers.dart           # Genel yardımcılar
│
├── features/                      # Özellik katmanı
│   ├── auth/                      # Kimlik doğrulama
│   │   ├── screens/               # Giriş/Kayıt ekranları
│   │   ├── providers/             # State yönetimi
│   │   └── widgets/               # Özel bileşenler
│   │
│   ├── market/                    # Alışveriş modülü
│   │   ├── screens/               # Market ekranları
│   │   │   ├── home_screen.dart
│   │   │   ├── category_screen.dart
│   │   │   ├── shop_detail_screen.dart
│   │   │   └── product_detail_screen.dart
│   │   ├── providers/
│   │   └── widgets/
│   │
│   ├── social/                    # Sosyal medya modülü
│   │   ├── screens/               # Sosyal ekranlar
│   │   │   ├── feed_screen.dart
│   │   │   ├── profile_screen.dart
│   │   │   └── post_create_screen.dart
│   │   ├── providers/
│   │   └── widgets/
│   │
│   ├── cart/                      # Sepet modülü
│   │   ├── screens/
│   │   ├── providers/
│   │   └── widgets/
│   │
│   ├── orders/                    # Sipariş modülü
│   │   ├── screens/
│   │   ├── providers/
│   │   └── widgets/
│   │
│   ├── messages/                  # Mesajlaşma modülü
│   │   ├── screens/
│   │   ├── providers/
│   │   └── widgets/
│   │
│   └── settings/                  # Ayarlar modülü
│       ├── screens/
│       ├── providers/
│       └── widgets/
│
├── admin/                         # Admin paneli (Web)
│   ├── screens/
│   ├── providers/
│   └── widgets/
│
├── seller/                        # Satıcı paneli (Web)
│   ├── screens/
│   ├── providers/
│   └── widgets/
│
└── main.dart                      # Ana dosya
```

---

## 🗄️ Veritabanı Şeması

Supabase'de oluşturulan ana tablolar:

### 👥 Kullanıcılar
- **profiles** - Kullanıcı profilleri (customer, seller, admin)
- **addresses** - Teslimat adresleri

### 🏪 Market
- **categories** - Ürün kategorileri (Market, Manav, Yemek, vb.)
- **shops** - Dükkanlar
- **products** - Ürünler
- **product_reviews** - Ürün değerlendirmeleri

### 🛒 Alışveriş
- **cart_items** - Sepet öğeleri
- **orders** - Siparişler
- **order_items** - Sipariş detayları
- **campaigns** - Kampanyalar
- **coupons** - Kuponlar

### 📱 Sosyal Medya
- **posts** - Gönderiler
- **post_likes** - Beğeniler
- **post_comments** - Yorumlar
- **stories** - Hikayeler (24 saat)
- **story_views** - Hikaye görüntülemeleri
- **follows** - Takip sistemi

### 💬 Mesajlaşma
- **conversations** - Konuşmalar
- **conversation_participants** - Katılımcılar
- **messages** - Mesajlar

### 🔔 Bildirimler
- **notifications** - Bildirimler
- **notification_tokens** - Push notification tokenları

### 🛠️ Destek
- **support_tickets** - Destek talepleri
- **app_settings** - Uygulama ayarları

---

## 🎨 Tema Sistemi

Uygulama iki tema destekler:

### Yeşil Tema (Varsayılan)
- Primary: `#00C853`
- Secondary: `#00a844`

### Mavi Tema
- Primary: `#007AFF`
- Secondary: `#0066cc`

Tema değiştirme ayarlardan yapılabilir.

---

## 🔐 Kullanıcı Rolleri

### 1. Customer (Müşteri)
- Ürün satın alma
- Sosyal medya kullanımı
- Mesajlaşma
- Sipariş takibi

### 2. Seller (Satıcı)
- Dükkan yönetimi
- Ürün ekleme/düzenleme
- Sipariş yönetimi
- Müşteri bildirimleri
- Raporlar

### 3. Admin (Yönetici)
- Tüm sistem yönetimi
- Kullanıcı/Satıcı onayı
- Komisyon ayarları
- Kategori yönetimi
- Kampanya oluşturma
- Genel raporlar

---

## 📱 Ana Ekranlar

### Müşteri Uygulaması

#### 1. Market Ekranı
- Kategoriler
- Dükkanlar
- Ürünler
- Arama
- Filtreler

#### 2. Ürünler Ekranı
- Vitrin
- Öne çıkan ürünler
- İndirimler

#### 3. Sosyal Medya Ekranı
- Gönderi akışı
- Hikayeler
- Beğeni/Yorum
- Paylaşım

#### 4. Sepet Ekranı
- Sepet yönetimi
- Ödeme seçenekleri
- Adres seçimi

#### 5. Profil Ekranı
- Kullanıcı bilgileri
- Siparişlerim
- Ayarlar
- Çıkış

### Alt Navigasyon
- 🏪 Market
- 🛍️ Ürünler
- 🛒 Sepet (Ortada, büyük)
- 🌍 Sosyal
- 👤 Profil

---

## 🔄 Sıradaki Adımlar

### ✅ Tamamlanan
1. ✅ Proje yapısı oluşturuldu
2. ✅ Supabase şeması hazırlandı
3. ✅ Flutter dependencies eklendi
4. ✅ Tema sistemi oluşturuldu
5. ✅ Core modeller (User, Product, Shop, Post, Order) hazırlandı

### 🚧 Yapılacaklar

#### 6. Authentication Modülü
```dart
// lib/features/auth/screens/login_screen.dart
// lib/features/auth/screens/register_screen.dart
// lib/features/auth/providers/auth_provider.dart
// lib/core/services/auth_service.dart
```

#### 7. Ana Navigation
```dart
// lib/features/main/screens/main_screen.dart
// Alt navigasyon ile 5 ana ekran arası geçiş
```

#### 8. Market Modülü
```dart
// Kategoriler listesi
// Dükkan listesi
// Ürün detayı
// Arama fonksiyonu
```

#### 9. Sosyal Medya Modülü
```dart
// Post oluşturma
// Feed gösterimi
// Beğeni/Yorum sistemi
// Hikaye ekleme
```

#### 10. Sepet & Sipariş
```dart
// Sepet yönetimi
// Ödeme ekranı
// Sipariş takibi
```

#### 11. Admin Panel (Web)
```dart
// Dashboard
// Kullanıcı yönetimi
// Satıcı yönetimi
// Raporlar
```

#### 12. Satıcı Panel (Web)
```dart
// Dükkan yönetimi
// Ürün yönetimi
// Sipariş yönetimi
// Raporlar
```

---

## 💡 Önemli Notlar

### Supabase RLS (Row Level Security)
Veritabanında RLS kuralları aktif. Kullanıcılar sadece kendi verilerine erişebilir.

### Dosya Yükleme
Supabase Storage kullanılacak:
- Profil fotoğrafları
- Ürün görselleri
- Gönderi fotoğrafları
- Story görselleri

### Bildirimler
Firebase Cloud Messaging (FCM) ile push bildirimler:
- Sipariş güncellemeleri
- Yeni mesajlar
- Sosyal etkileşimler
- Kampanya bildirimleri

### Ödeme Entegrasyonu
İyzico API kullanılacak:
```dart
// lib/core/services/payment_service.dart
// Kredi kartı ödemeleri
// Kapıda ödeme
```

---

## 🔧 Geliştirme Komutları

```bash
# Uygulamayı çalıştır
flutter run

# Paketleri güncelle
flutter pub get

# Build (Android)
flutter build apk --release

# Build (iOS)
flutter build ios --release

# Build (Web)
flutter build web --release

# Code generation (gerekirse)
flutter pub run build_runner build --delete-conflicting-outputs
```

---

## 📞 Destek & İletişim

- **Web**: www.cizreapp.com
- **Admin Panel**: www.cizreapp.com/admin
- **Satıcı Panel**: www.cizreapp.com/satici

---

## 📄 Lisans

Bu proje CizreApp için özel olarak geliştirilmiştir.

---

**Son Güncelleme**: 20 Ocak 2026
**Versiyon**: 1.0.0
**Developer**: CizreApp Team
#   c i z r e a p p  
 