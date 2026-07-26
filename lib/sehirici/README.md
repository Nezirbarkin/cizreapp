# Şehir İçi Servis Modülü (`lib/sehirici/`)

Son güncelleme: 2026-07-25

## Genel Bakış
Şehir içi toplu taşıma servisleri (otobüs, minibüs, midibüs, dolmuş,
tramvay) için tam kapsamlı yönetim modülü. Üç rol destekler:
**Kullanıcı**, **Şoför**, **Admin**.

## Dizin Yapısı
```
lib/sehirici/
├── sehirici.dart                              # Barrel export
├── README.md                                  # Bu dosya
├── PERFORMANCE_NOTES.md                       # Performans notları
├── models/
│   └── sehirici_models.dart                   # Tüm modeller
├── services/
│   ├── sehirici_city_service.dart             # Şehir + ayarlar
│   ├── sehirici_line_service.dart             # Hat + durak + aktif sefer
│   ├── sehirici_trip_service.dart             # Sefer + realtime
│   ├── sehirici_favorite_service.dart         # Favori duraklar
│   ├── sehirici_driver_service.dart           # Şoför kayıt/atama
│   └── sehirici_location_tracker.dart         # Şoför canlı konum
├── providers/
│   └── sehirici_provider.dart                 # Singleton state
├── widgets/
│   ├── sehirici_live_map.dart                 # GoogleMap widget
│   └── sehirici_compact_card.dart             # Anasayfa açılır/kapanır kart
├── screens/
│   ├── sehirici_lines_screen.dart             # Kullanıcı: hat listesi
│   ├── sehirici_line_detail_screen.dart       # Kullanıcı: hat detayı
│   ├── sehirici_favorites_screen.dart         # Kullanıcı: favoriler
│   └── sehirici_driver_panel_screen.dart      # Şoför: sefer yönetimi
└── admin/
    └── sehirici_admin_management_content.dart # Admin: 5 sekme
```

## Roller ve Yetenekler

### Kullanıcı
- Hatları görüntüler (kod, ad, durak sayısı, ücret)
- Durakları listeler ve haritada görür
- Canlı servis konumunu izler (realtime)
- Tahmini varış süresini (ETA) görür
- Favori durak ekler/kaldırır
- Servis bildirimleri alır (favori durağa yaklaşınca)

### Şoför
- Seferi başlatır / bitirir
- Canlı konum paylaşır (her 10 sn)
- Hat seçimi yapar
- Mola / devam (durum güncelleme)
- Sıradaki durağı görür

### Admin
- Şehir oluşturur / düzenler (aktif/pasif)
- Hat ekler (kod, ad, renk, araç tipi, ücret)
- Durak ekler / düzenler
- Şoför ataması yapar (kullanıcı arama)
- Canlı servisleri izler (aynı kullanıcı haritası)
- Modül ayarları (açma/kapama, konum aralığı, ETA yenileme)
- Kullanıcı favorileri izni

## Veritabanı

Migration: [`supabase/20260725000001_sehirici_services.sql`](../../supabase/20260725000001_sehirici_services.sql)

Tablolar:
- `sehirici_cities` — şehirler
- `sehirici_lines` — hatlar (rota)
- `sehirici_stops` — duraklar
- `sehirici_line_stops` — hat-durak ilişkisi (sıra + ETA)
- `sehirici_drivers` — şoför profilleri
- `sehirici_trips` — aktif/geçmiş seferler
- `sehirici_trip_locations` — konum geçmişi (1 saat)
- `sehirici_favorite_stops` — kullanıcı favorileri
- `app_settings` (sehirici_* anahtarları) — modül ayarları

RPC'ler:
- `get_sehirici_lines_with_stops(city_id)`
- `get_sehirici_active_trips(city_id)`
- `get_sehirici_trips_for_stop(stop_id)`
- `start_sehirici_trip(...)`
- `update_sehirici_trip_location(...)`
- `set_sehirici_trip_status(...)`
- `compute_sehirici_next_stop(trip_id)`
- `cleanup_sehirici_old_locations(minutes)`
- `notify_sehirici_favorite_approaching(...)`

Realtime: `sehirici_trips` ve `sehirici_trip_locations`
`supabase_realtime` publication'a eklendi.

## Kurulum Adımları

1. **Veritabanı**: `supabase/20260725000001_sehirici_services.sql`
   dosyasını Supabase SQL Editor'da çalıştırın.
2. **Ayarlar**: Admin panel → Şehiriçi Yönetimi → Ayarlar →
   "Modül Aktif" açık olduğundan emin olun.
3. **Şehir**: Admin → Şehiriçi Yönetimi → Şehirler → "Yeni Şehir"
4. **Hat/Durak**: Admin → Şehiriçi Yönetimi → Hatlar / Duraklar
5. **Şoför**: Admin → Şehiriçi Yönetimi → Şoförler → kullanıcıyı seçin

## Entegrasyon Noktaları (Mevcut Projeye)

- [`lib/main.dart`](../../lib/main.dart:22) — SehiriciProvider MultiProvider'a eklendi
- [`lib/main.dart`](../../lib/main.dart) — routes (`/sehirici-lines`, `/sehirici-favorites`, `/sehirici-driver`)
- [`lib/features/market/screens/market_screen.dart`](../../lib/features/market/screens/market_screen.dart) — Hikaye altına SehiriciCompactCard
- [`lib/features/admin/widgets/admin_drawer.dart`](../../lib/features/admin/widgets/admin_drawer.dart) — "Şehiriçi Yönetimi" menüsü
- [`lib/features/admin/screens/admin_dashboard_screen.dart`](../../lib/features/admin/screens/admin_dashboard_screen.dart) — dispatch case
- [`lib/core/widgets/settings_sidebar.dart`](../../lib/core/widgets/settings_sidebar.dart) — "Şoför Paneli" butonu

## Testler

```bash
flutter test test/sehirici/sehirici_models_test.dart
```

Detaylı test planı: [`docs/SEHIRICI_TEST_PLANI.md`](../../docs/SEHIRICI_TEST_PLANI.md)

## Performans

Detaylı notlar: [`lib/sehirici/PERFORMANCE_NOTES.md`](PERFORMANCE_NOTES.md)

Özet:
- Singleton provider (tek state kaynağı)
- Per-city TTL cache (5 dk)
- Optimistik favori toggle + rate limit
- Realtime channel leak koruması
- Modül kapalıyken sıfır ek yük
