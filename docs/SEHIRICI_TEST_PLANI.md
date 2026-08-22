# Şehir İçi Servis Modülü — Flutter Test Planı

Son güncelleme: 2026-07-25

## 1) Otomatik Testler (CI'da çalışır)

### 1.1 Unit Testler — `test/sehirici/sehirici_models_test.dart`
Mevcut durumda 15 test, hepsi geçiyor.

Kapsam:
- `SehiriciVehicleType.fromString` — tüm enum değerleri + bilinmeyen değer
- `SehiriciTripStatus.fromString` ve `dbValue`
- `SehiriciCity.fromJson` — tam + eksik alanlar
- `SehiriciLine.fromJson` — hat + durak listesi + geçersiz renk + stops yok
- `SehiriciActiveTrip.fromJson` ve `copyWithLocation` (line bilgisi korunur)
- `SehiriciSettings.fromSettingsMap` — string "true" + gerçek bool + eksik

Çalıştırma:
```bash
flutter test test/sehirici/sehirici_models_test.dart
```

### 1.2 Gelecek Widget/Entegrasyon Testleri
Aşağıdaki widget testleri, `google_maps_flutter`'ın platform
binding gerektirmesi nedeniyle tam mock gerektirir. Aşamalı olarak
eklenecek:

- `SehiriciCompactCard` — module kapalıyken `SizedBox.shrink()` döner
- `SehiriciCompactCard` — expanded toggle: tap → içerik açılır
- `SehiriciLiveMap` — boş liste ile render hatası vermez
- `SehiriciProvider` — `toggleFavorite` optimistic update + rate limit

Mock stratejisi:
- `Supabase.instance.client` yerine `SupabaseClient` mock
- `MethodChannel google_maps_flutter` mock channel

## 2) Manuel Test Senaryoları

### 2.1 Admin Tarafı
1. Admin panele giriş → "Şehiriçi Yönetimi" menüsü görünüyor mu?
2. Şehir ekleme: "Yeni Şehir" → ad/slug/lat/lng gir → kaydet → listede görünüyor mu?
3. Şehir aktif/pasif toggle: kapalı şehir, kullanıcıda görünmüyor mu?
4. Hat ekleme: şehir seç → "Yeni Hat" → kod/ad/renk/araç tipi → kaydet
5. Durak ekleme: "Yeni Durak" → ad/lat/lng → kaydet
6. Şoför ekleme: "Şoför Ekle" → kullanıcı ara → ekle
7. Ayarlar tab: "Modül Aktif" kapat → kullanıcı tarafı gizleniyor mu?
8. "Kullanıcı Favorileri" kapat → favori ekleme butonu disabled mı?

### 2.2 Kullanıcı Tarafı
1. Anasayfa → Hikaye bölümü altında "Şehiriçi Servisler" kartı görünüyor mu?
2. Kartı aç (toggle) → harita + şehir seçici + aktif sefer özetleri
3. Şehir değiştir → hatlar ve harita güncelleniyor mu?
4. "Tüm hatlar" linki → hat listesi ekranı açılıyor mu?
5. Hat detayı: durak listesi + harita + favori yıldızı
6. Favori durağa dokun → yıldız doluyor → "Favori Duraklarım" ekranında görünüyor mu?
7. Aynı durağa hızlıca 2 kez dokun → rate-limit devreye girer (ikinci tıklama atlanır)
8. Favoriyi kaldır → listeden kayboluyor mu?
9. Modül kapalıyken: kart gizleniyor mu? Hat listesi ekranı "kapalı" mesajı mı gösteriyor?

### 2.3 Şoför Tarafı
1. Settings sidebar → "Şoför Paneli" butonu görünüyor mu?
2. Şoför kaydı yoksa → "Şoför kaydınız bulunamadı" mesajı
3. Admin şoför ekledikten sonra: panel → hat listesi
4. Hat seç → "Başlat" → sefer aktif, konum izni istenir
5. Konum izni verildikten sonra → haritada araç marker'ı görünüyor mu?
6. "Mola" butonu → status=paused, konum paylaşımı durur
7. "Devam" → status=active, konum tekrar paylaşılır
8. "Seferi Bitir" → onay → status=completed → hat seçim ekranına dönülür
9. Önceki aktif sefer varsa → yeni başlatınca eskisi otomatik kapanır

### 2.4 Realtime / Canlı Konum
1. Şoför sefer başlat → kullanıcı tarafında marker anında görünür
2. Şoför hareket edince → kullanıcı marker'ı realtime güncellenir
3. Şoför "Seferi Bitir" → kullanıcı tarafında marker kaybolur
4. Çoklu sefer: 2+ şoför aynı anda → tüm marker'lar görünür
5. Arka planda → ekran kapalıyken konum güncellemesi devam eder (Android foreground service gerekir — future)

## 3) Veritabanı Testleri (SQL)

```sql
-- 3.1 Şehir ekle
INSERT INTO sehirici_cities (name, slug, center_lat, center_lng)
VALUES ('Cizre', 'cizre', 37.3255, 42.1876);

-- 3.2 Hat ekle
INSERT INTO sehirici_lines (city_id, code, name, color_hex, vehicle_type)
SELECT id, '1A', 'Hastane - Üniversite', '#1976D2', 'bus'
FROM sehirici_cities WHERE slug = 'cizre';

-- 3.3 Durak ekle
INSERT INTO sehirici_stops (city_id, name, lat, lng)
SELECT c.id, 'Meydan', 37.3260, 42.1880
FROM sehirici_cities c WHERE c.slug = 'cizre';

-- 3.4 Hat-durak ilişkisi
INSERT INTO sehirici_line_stops (line_id, stop_id, stop_order, minutes_from_start)
SELECT l.id, s.id, 0, 0
FROM sehirici_lines l, sehirici_stops s, sehirici_cities c
WHERE l.code='1A' AND s.name='Meydan' AND c.slug='cizre';

-- 3.5 RPC testleri
SELECT * FROM get_sehirici_lines_with_stops(
  (SELECT id FROM sehirici_cities WHERE slug='cizre')
);
SELECT * FROM get_sehirici_active_trips();

-- 3.6 RLS testleri
SET ROLE authenticated;
-- Kullanıcı kendi favorisini görebilir
SELECT * FROM sehirici_favorite_stops;
-- Admin olmayan şehir silemez (beklenen hata)
DELETE FROM sehirici_cities WHERE slug='cizre';
```

## 4) Performans Testleri

- İlk açılış: `SehiriciProvider.initialize()` ~200-400 ms (Supabase
  round-trip × 2 paralel)
- Anasayfa kart açma: <16 ms (60 FPS)
- Realtime güncelleme: marker kayması <500 ms
- 50 marker ile harita: >50 FPS (cluster eklenmedi)
- Memory: `_lineCache` ~50 KB / şehir

## 5) Regression Testleri

Mevcut proje üzerinde etkilenen alanlar:
- `lib/main.dart` — MultiProvider'a SehiriciProvider eklendi (geri uyumlu)
- `lib/features/market/screens/market_screen.dart` — Hikaye bölümü
  altına bir `SehiriciCompactCard` eklendi (modül kapalıysa gizlenir)
- `lib/features/admin/screens/admin_dashboard_parts/_part_drawer.dart` — yeni menü öğesi
- `lib/features/admin/screens/admin_dashboard_screen.dart` — yeni case
- `lib/core/widgets/settings_sidebar.dart` — yeni "Şoför Paneli" butonu

Bu değişiklikler geriye dönük uyumludur; modül devre dışı bırakılırsa
eski davranış tamamen korunur.

## 6) Bilinen Sınırlamalar / Future Work

- GoogleMap widget testleri mock gerektiriyor (platform channel)
- Konum geçmişi (trip_locations) tablosu için cron job kurulmalı
  (Supabase → `cleanup_sehirici_old_locations`)
- Android'de arka plan konum paylaşımı için foreground service
- ETA hesabı basit mesafe-bazlı; gerçek trafik verisi için
  Google Directions API entegrasyonu (ek ücret)
