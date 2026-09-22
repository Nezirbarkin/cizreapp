# Şehir İçi Servis Modülü (`lib/sehirici/`)

Son güncelleme: 2026-09-22

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
│   ├── sehirici_models.dart                   # Şehir/hat/durak/sefer/şoför/ayar modelleri
│   └── sehirici_icon_models.dart              # Harita ikon kütüphanesi (araç + durak)
├── services/
│   ├── sehirici_city_service.dart             # Şehir + ayarlar
│   ├── sehirici_line_service.dart             # Hat + durak + hat-durak bağı + rota önbelleği
│   ├── sehirici_trip_service.dart             # Sefer + realtime
│   ├── sehirici_favorite_service.dart         # Favori duraklar
│   ├── sehirici_driver_service.dart           # Şoför kayıt/atama
│   ├── sehirici_icon_service.dart             # İkon CRUD + görsel yükleme (storage)
│   ├── sehirici_icon_catalog.dart             # Uygulama içi ikon kataloğu (önbellekli)
│   ├── sehirici_road_snap_service.dart        # OSRM ile yol rotası
│   ├── sehirici_errors.dart                   # Admin hata metinleri (Türkçe)
│   └── sehirici_location_tracker.dart         # Şoför canlı konum
├── providers/
│   └── sehirici_provider.dart                 # Singleton state
├── utils/
│   ├── sehirici_marker_bitmaps.dart           # İkon -> harita bitmap'i (çizim / yüklenen görsel)
│   ├── sehirici_arrivals.dart                 # Durağa varış hesabı
│   └── sehirici_route_geometry.dart           # Rota geometrisi yardımcıları
├── widgets/
│   ├── sehirici_live_map.dart                 # Canlı harita (gerçekçi araç/durak, rota, çipler)
│   ├── sehirici_map_sheets.dart               # Durak / araç / hat alt sayfaları
│   ├── sehirici_common_widgets.dart           # Hat rozeti, araç/durak küçük resmi, çipler
│   ├── sehirici_compact_card.dart             # Anasayfa açılır/kapanır kart
│   └── sehirici_story_card.dart               # Hikaye kartı
├── screens/
│   ├── sehirici_lines_screen.dart             # Kullanıcı: hat listesi
│   ├── sehirici_line_detail_screen.dart       # Kullanıcı: hat detayı
│   ├── sehirici_favorites_screen.dart         # Kullanıcı: favoriler
│   └── sehirici_driver_panel_screen.dart      # Şoför: sefer yönetimi
└── admin/                                     # Admin > Şehiriçi Yönetimi
    ├── sehirici_admin_management_content.dart # Kabuk: başlık, şehir seçici, sekmeler
    ├── sehirici_admin_controller.dart         # Ortak durum (şehir/hat/durak/şoför/ikon/ayar)
    ├── sehirici_admin_kit.dart                # Ortak görsel araçlar (alt sayfa, girdi, onay)
    ├── sehirici_admin_overview_tab.dart       # Genel Bakış: özet, uyarılar, canlı harita
    ├── sehirici_admin_lines_tab.dart          # Hatlar: arama/filtre/sıralama/rota
    ├── sehirici_admin_stops_tab.dart          # Duraklar
    ├── sehirici_admin_icons_tab.dart          # İkonlar: araç ve durak ikon kütüphanesi
    ├── sehirici_admin_drivers_tab.dart        # Şoförler
    ├── sehirici_admin_cities_tab.dart         # Şehirler
    ├── sehirici_admin_settings_tab.dart       # Ayarlar + rota bakımı + harita görünümü
    ├── sehirici_*_editor_sheet.dart           # Hat / durak / ikon / şehir düzenleyicileri
    ├── sehirici_driver_sheets.dart            # Şoför ekle / hat ata / düzenle
    ├── sehirici_line_stops_editor_dialog.dart # Hat durakları (sırala, ekle, kaydet)
    ├── sehirici_location_picker_dialog.dart   # Haritadan konum / çoklu durak seçici
    └── sehirici_line_route_draw_dialog.dart   # Haritada rota çizimi
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
- Genel Bakış: özet sayılar, dikkat isteyen durumlar (kod/adı boş hat, durağı ya da rotası olmayan/eski kalan hat, bağlantısız durak, hat atanmamış şoför) ve canlı harita
- Şehir oluşturur / düzenler (aktif/pasif), şehir seçici ile şehirler arasında geçer
- Hat ekler / düzenler (kod, ad, renk paleti, **araç türü = ikon kütüphanesinden**, ücret), listede sürükleyerek sıralar
- Hat duraklarını sıralar / ekler / çıkarır: tek işlemde kaydedilir, haritadan yeni durak dizilebilir, kayıtlı rota eskirse kaydederken yenilenir
- Hat rotası: duraklardan otomatik (gerçek yol), haritada elle çizim, ayıklama, silme; toplu bakım Ayarlar'da
- **İkon kütüphanesi**: yerleşik araç/durak çizimlerini değiştirir, yeni araç türü ya da durak ikonu ekler, kendi PNG/WebP görselini yükler (döndürme, boyut, alt uç ayarı), varsayılan durak ikonunu seçer
- Durak ekler / düzenler (harita seçici, adres, kod)
- Şoför ataması yapar (kullanıcı arama)
- Canlı servisleri izler (aynı kullanıcı haritası)
- Modül ayarları (açma/kapama, konum aralığı, ETA yenileme, otomatik rota yazımı, harita görünümü)
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
- `sehirici_marker_icons` — harita ikon kütüphanesi (`kind` = araç/durak; yerleşik çizim adı **ya da** yüklenen görsel). `sehirici_lines.vehicle_type` artık bu tabloya (`kind='vehicle'`, `key`) bağlı metindir; admin yeni araç türü ekleyebilir. Görseller herkese açık `sehirici-icons` kovasında (en çok 1 MB, PNG/WebP/JPEG)
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

Admin RPC'leri (hepsi `auth_sehirici_is_admin()` kontrollü, SECURITY DEFINER):
- `admin_upsert_sehirici_marker_icon` / `admin_delete_sehirici_marker_icon` / `admin_set_default_sehirici_marker_icon`  — ikon kütüphanesi (yerleşik/varsayılan/kullanımdaki ikon silinemez)
- `admin_set_sehirici_line_stops` — hattın duraklarını TEK işlemde değiştirir (eskiden sil+ekle iki istekti, ikincisi patlarsa hat duraksız kalıyordu)
- `admin_reorder_sehirici_lines` — hat sırası
- `admin_upsert_sehirici_line` / `_stop` / `_city` ve `admin_delete_*`

Migration'lar: `supabase/migrations/20260921000009_sehirici_marker_icon_catalog.sql`, `20260921000010_sehirici_admin_line_tools.sql`.

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
- [`lib/features/admin/screens/admin_dashboard_parts/_part_drawer.dart`](../../lib/features/admin/screens/admin_dashboard_parts/_part_drawer.dart) — "Şehiriçi Yönetimi" menüsü (admin panelinin gerçek drawer'ı `_buildDrawer` burada; eskiden bu satır `widgets/admin_drawer.dart`'ı gösteriyordu ama o widget hiç kullanılmıyordu, 2026-08-16'da silindi)
- [`lib/features/admin/screens/admin_dashboard_screen.dart`](../../lib/features/admin/screens/admin_dashboard_screen.dart) — dispatch case
- [`lib/core/widgets/settings_sidebar.dart`](../../lib/core/widgets/settings_sidebar.dart) — "Şoför Paneli" butonu

## Testler

```bash
flutter test test/sehirici
```

- `sehirici_live_map_test.dart` — canlı harita (sahte harita platformu ile marker/çizgi/yakınlık düzeyleri)
- `sehirici_admin_ui_test.dart` / `sehirici_admin_dialogs_test.dart` — yönetim paneli (sahte Supabase: `test/helpers/sehirici_fake_backend.dart`)
- `sehirici_admin_logic_test.dart` — modeller, ikon kataloğu, hata metinleri, varış hesabı, servis parametreleri

Görsel doğrulama için `SEHIRICI_PREVIEW_DIR=<klasör>` verilirse widget testleri ekran PNG'lerini oraya yazar (web önizleme kararsız olduğu için).

Detaylı test planı: [`docs/SEHIRICI_TEST_PLANI.md`](../../docs/SEHIRICI_TEST_PLANI.md)

## Performans

Detaylı notlar: [`lib/sehirici/PERFORMANCE_NOTES.md`](PERFORMANCE_NOTES.md)

Özet:
- Singleton provider (tek state kaynağı)
- Per-city TTL cache (5 dk)
- Optimistik favori toggle + rate limit
- Realtime channel leak koruması
- Modül kapalıyken sıfır ek yük
