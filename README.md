# CizreApp

Flutter + Supabase ile geliştirilmiş şehir içi pazar uygulaması.

## 🧪 Testler

Bu proje kapsamlı bir test altyapısına sahiptir.

### Lokal Çalıştırma

```bash
# Tüm testleri çalıştır
flutter test

# Belirli bir test dosyasını çalıştır
flutter test test/supabase_backend_test.dart
flutter test test/supabase_config_test.dart

# Coverage raporu oluştur
flutter test --coverage
genhtml coverage/lcov.info -o coverage/html
# coverage/html/index.html'i tarayıcıda aç
```

### Test Kategorileri

| Kategori | Dosya | Açıklama |
|---|---|---|
| **Modeller** | `test/models/` | User, Order, Cart, Product, Balance, vb. JSON parse/serialize testleri |
| **Servisler** | `test/services/` | OrderService, CartService, AdMob, Push, vb. |
| **Backend HTTP** | `test/supabase_backend_test.dart` | Plugin gerektirmez, gerçek Supabase'e HTTP üzerinden bağlanır |
| **Config** | `test/supabase_config_test.dart` | AppConstants + URL/Key doğrulama, plugin gerektirmez |
| **Güvenlik** | `test/services/security_smoke_test.dart` | SMS kodu gizleme, push direkt çağrı kontrolü |

### Backend Test Çıktısı Örneği

```
🔌 BAĞLANTI TESTLERİ Supabase URL ve Key doğrulama ✅
🌐 HTTP BACKEND TESTLERİ
  📡 REST API status: 401 (backend ayakta)
  🔐 Auth API status: 401
  📋 Categories: 5 kategori bulundu
  🏪 Shops: 5 aktif mağaza bulundu
  📦 Products: 5 aktif ürün bulundu
```

## 🤖 CI/CD

GitHub Actions ile her push'ta otomatik test çalışır:

- `.github/workflows/test.yml` — Unit + Backend testleri
- `.github/workflows/ios-build.yml` — iOS build
- `.github/workflows/security-database.yml` — Supabase DB lint + pgTAP

## 📁 Proje Yapısı

```
lib/
├── core/          # Modeller, servisler, util'ler
├── features/      # Auth, Market, Shop, Social, vb.
└── ...
test/             # Tüm testler
supabase/         # DB migrations, edge functions
.github/workflows/ # CI/CD
```
