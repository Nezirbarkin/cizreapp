# Şehir İçi Servis Modülü — Performans Notları

Bu doküman, modülün performans kritik noktalarını ve alınan önlemleri özetler.

## 1) Provider (Singleton)
- `SehiriciProvider` singleton olarak tasarlandı (`_instance`). Tüm ekranlar
  aynı state'i paylaşır → aynı şehrin hat/durak/aktif-sefer verisi için tekrar
  tekrar ağ çağrısı yapılmaz.
- `initialize()` yalnızca bir kez çağrılır (main.dart MultiProvider'da).

## 2) Realtime Abonelik Yönetimi
- `SehiriciTripService.watchActiveTrips()` çağrıldığında eski channel kapatılır
  (memory leak yok).
- Anasayfa widget'ı (SehiriciCompactCard) açılırken realtime başlatır;
  sayfa kapanırken realtime'i durdurmaz (provider singleton üzerinden diğer
  ekranlar da izleyebilir). Ancak ekrandaki `_channel` field'ı referans
  için tutulur.

## 3) Veri Cache (Per-City TTL)
- `SehiriciLineService.getLinesWithStops()` 5 dakikalık bellek cache'i kullanır.
  Aynı şehrin hat/durakları kısa sürede tekrar istenirse Supabase'e
  gitmeden döner.
- `SehiriciCityService.getCities()` ve `getSettings()` bellek cache'i.

## 4) Favori Toggle Optimistik UI
- `toggleFavorite` UI'ı anında günceller (optimistik), API arka planda çalışır.
- Aynı durağa kısa aralıklarla (600 ms) tıklama throttle edilir (sunucu
  yükü + UI çift-tıklama korunur).
- Hata olursa optimistic update geri alınır.

## 5) Map Widget Optimizasyonları
- Marker/polyline `Set` immutable atanır (GoogleMap widget'ı rebuild
  olduğunda eşitlik karşılaştırması yapabilsin diye `Set.unmodifiable`
  değil, sadece `Set<>`).
- `consumeTapEvents: true` sadece durak marker'larında; araç marker'larında
  `false` — gereksiz tap işlemci devre dışı.
- `_rebuild()` yalnızca `lines` veya `activeTrips` referansı değiştiğinde
  çağrılır (`didUpdateWidget` kontrolü).
- `SehiriciLiveMap`'in `initialCameraPosition` yalnızca ilk oluşumda
  kullanılır; sonradan `_fitBounds()` ile gerçek konuma gider.

## 6) Throttled Refresh
- `SehiriciLinesScreen` her 30 saniyede `provider.refreshActiveTrips()`
  çağırır (rate limited — paralel yenileme yapılmaz).
- Şoför tarafında konum her 10 saniyede güncellenir (uygulama ayarı
  ile değiştirilebilir).

## 7) Lat/Lng Sıkıştırma (uzun vadeli)
- Durak ve aktif sefer marker'ları için ileride cluster (google_maps_cluster)
  eklenebilir. Şu an varsayılan marker kullanılıyor (overhead az).

## 8) İnitial Boot
- Modül `main.dart`'ta `..initialize()` ile başlatılır. `moduleEnabled=false`
  ise tüm veri çekimi atlanır → ilk açılışta ek yük yok.

## 9) Veritabanı
- RPC fonksiyonları server-side hesaplama yapar (ETA, durak join) →
  istemci tarafı JSON parse yükü düşük.
- Index'ler:
  - `idx_sehirici_trips_active` — `status IN ('active','paused')` üzerinde
  - `idx_sehirici_line_stops_line` — hat/durak sırası
  - `idx_sehirici_trip_locations_trip` — son konumlar (DESC)

## 10) Realtime Channel
- `supabase_realtime` publication'a `sehirici_trips` ve `sehirici_trip_locations`
  eklendi. Konum güncellemeleri saniyede 1 broadcast eder (uygulama kanal
  sayısı sınırlı; mevcut sistemle uyumlu).

## 11) Bellek
- `_lineCache` ve `_cachedCities` statik; temizlemek için admin panelden
  `provider.invalidateAllCaches()` çağrılabilir.
- `_tripLocations` tablosunda eski kayıtlar cron ile silinir (1 saat
  default — `sehirici_max_history_minutes`).