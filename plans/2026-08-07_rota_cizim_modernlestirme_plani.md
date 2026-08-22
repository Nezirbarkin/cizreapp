# Rota Çizim Modernizasyonu + Kullanıcı Haritası + Şöför Otomatik Rota

**Tarih**: 2026-08-07
**Kapsam**: Admin draw aracı modernize, kullanıcı haritasında hat seçimi, şöför paneli "rota gittiğim yerlerden oluşsun" ayarı, araç yön göstergesi.

---

## Özet — kullanıcının istekleri

| # | İstek | Çözüm |
|---|-------|-------|
| 1 | "rota ciz daha modernleştir" | Draw dialog yeniden tasarlanacak (yan panel, sürükle-bırak, segmentli toolbar) |
| 2 | "kaydedildiğinde kullanıcı haritada gösterilsin" | Cache invalidation + kullanıcı haritasında otomatik görünüm |
| 3 | "hangi yere gidecekse hat bastığında rotası gelsin / dolmuş ikonuna tıklayınca rotası çıksın" | Hat/durak tile'a "haritada göster" butonu + harita zoom/highlight |
| 4 | "şöför panelinde otomatik rota çizilmesi için bir ayar" | Driver panel settings'e `auto_route_from_traveled_path` toggle |
| 5 | "admin istediğinde ilk rota şöförün gittiği yerlerden oluşsun (kuş bakışı değil)" | Draw dialog'a "Son seferden öner" butonu (Douglas-Peucker sadeleştirilmiş gerçek GPS) |
| 6 | "araba hangi yöne gidiyor belli olsun" | Mevcut rotation zaten çalışıyor; ikon modernize edilecek (ok ucu) |

---

## A) Draw Dialog Modernizasyonu

**Dosya**: `lib/sehirici/admin/sehirici_line_route_draw_dialog.dart` (komple yeniden yazım)

Yenilikler:
- **Yan panel** (sağ, 280px): sıralı nokta listesi, sürükle-bırak ile yeniden sıralanabilir, her satırda numara + km mesafesi + sil butonu
- **Üst toolbar** (Material 3 segmented): Geri Al, Temizle, Çizime Odakla, **Duraklardan Öner**, **Son Seferden Öner**, Kaydet
- **Noktalar**: numaralı pin (1, 2, 3…), sürüklenebilir (`Marker.draggable`), sürükle-bittiğinde koordinat güncellenir
- **Alt bilgi barı**: toplam km, tahmini süre (30 km/sa ort), nokta sayısı
- **Kaydet**: yalnızca `_dirty` ve ≥2 nokta ise aktif; imza değişmemişse aynı RPC'ye yazar
- **Çıkış onayı**: `_dirty` ise discard onay dialog'u (mevcut davranış korunur)
- **"Duraklardan Öner"**: hattın duraklarını sırayla bağlayıp `_points`'i doldurur (sadece başlangıç önerisi; admin düzeltir)
- **"Son Seferden Öner"**: `SehiriciLineService.getLatestCompletedTripPath(lineId)` → Douglas-Peucker sadeleştirme → `_points`'i yükle

**Yardımcı pure function (yeni)** — `lib/sehirici/utils/sehirici_route_geometry.dart`:
```dart
/// Douglas-Peucker polyline sadeleştirme (haversine mesafeyle).
/// toleranceMeters: bu mesafeden kısa sapma gösteren noktalar atılır.
List<LatLng> simplifyPath(List<LatLng> path, {double toleranceMeters = 8});

/// Polyline'ın toplam uzunluğu (metre).
double pathLengthMeters(List<LatLng> path);

/// Ortalama 30 km/sa hızla seyahat süresi (dakika).
int estimateDurationMinutes(double meters);
```

---

## B) Kullanıcı Haritası: Hat Seçimi

**Dosyalar**:
- `lib/sehirici/widgets/sehirici_live_map.dart` (yeni parametre)
- `lib/sehirici/screens/sehirici_lines_screen.dart` (UI değişiklikleri)
- `lib/sehirici/providers/sehirici_provider.dart` (state)

**SehiriciLiveMap** — yeni parametre:
```dart
final String? highlightLineId;  // null = tüm hatlar eşit; dolu = sadece bu hat vurgulu
```

Davranış:
- `highlightLineId != null` iken o hattın polylines'ı tam opaklık + kalın, diğer hatlar %25 opaklık + ince
- `highlightLineId`'ye uyan tüm marker'lar (durak + aktif sefer) zIndex'lenir
- İlk seçimde harita otomatik o hattın tüm duraklarını kapsayacak şekilde `LatLngBounds` fit yapar

**sehirici_lines_screen.dart**:
- Her `_LineTile`'a `trailing`'e ikinci ikon: `Icons.map` ("haritada göster") — sadece haritayı öne çıkarır, detay sayfasına gitmez
- Üst haritanın altında, eğer seçili hat varsa, küçük bir "X" ile kapatılabilen yatay chip:
  ```
  Seçili: 1A — Cumhuriyet Meydanı Hattı  [×]
  ```
- Çift tıklama korunur (detay sayfasına gider); tek-tıklamada eğer haritada zaten o hat seçiliyse detaya git, değilse haritada göster

**SehiriciProvider**:
```dart
String? _highlightedLineId;
String? get highlightedLineId => _highlightedLineId;
void highlightLine(String? lineId);  // null = temizle
```

---

## C) Şöför Paneli: Otomatik Rota Ayarı

**DB migration** (yeni): `supabase/migrations/20260807130000_sehirici_auto_route_setting.sql`
```sql
ALTER TABLE public.sehirici_drivers
  ADD COLUMN IF NOT EXISTS auto_route_from_traveled_path BOOLEAN
  NOT NULL DEFAULT FALSE;
COMMENT ON COLUMN public.sehirici_drivers.auto_route_from_traveled_path IS
  'true ise şoför ilk seferinde, hatta henüz admin rotası yokken, ~1-2 km sonra GPS noktalarından otomatik rota oluşturup kaydeder';
```
RLS zaten `sehirici_drivers_update_self` şoförün kendi satırını güncellemesine izin veriyor — ek değişiklik gerekmez.

**Dart**:
- `SehiriciDriverService`:
  - `getMyDriverProfile` SELECT'ine `auto_route_from_traveled_path` ekle
  - `updateDriverSettings` parametre listesi: `bool? autoRouteFromTraveledPath`
- `sehirici_driver_panel_screen.dart`:
  - `_showSettingsDialog`'a (mevcut dialog, satır ~482) yeni `SwitchListTile`:
    ```
    "Rotamı gittiğim yerlerden oluştur"
    "Hat için henüz rota yoksa, sefer başlangıcında otomatik oluşturulur"
    ```
  - `_startTrip` sonrası: eğer `line.roadPolyline == null && driverProfile.auto_route_from_traveled_path == true` ise `_autoRouteWatcher` başlat
  - `_autoRouteWatcher`: 30 sn'de bir kontrol → GPS noktaları (kendi tracker'ından) ≥ 10 ve toplam mesafe ≥ 1 km ise → sadeleştir → `cacheRoutePolyline(...)` çağır → Snackbar: "Rota otomatik oluşturuldu (X nokta)" → provider cache invalidate

**Nokta kaynağı**: Şöförün kendi tracker'ı zaten `getTripPath`'e yazıyor. `_activeTrip.tripId` ile `getTripPath` çağrılır — yeni RPC gerekmez.

---

## D) Admin: Şöför Verisinden Rota Oluştur

Draw dialog'daki **"Son Seferden Öner"** butonu (yukarıda A'da geçti):
1. `SehiriciLineService.getLatestCompletedTripPath(lineId)` — yeni fonksiyon
2. Noktalar `simplifyPath(..., toleranceMeters: 10)` ile sadeleştirilir
3. Mevcut `_points` değiştirilir + `_dirty = true`
4. Snackbar: "12 nokta yüklendi (orijinal 87 noktadan)"

**Yeni fonksiyon** — `SehiriciLineService.getLatestCompletedTripPath`:
```dart
Future<List<LatLng>> getLatestCompletedTripPath(String lineId) async {
  // Mevcut seferlerden completed status'ündekileri çek, en yenisini al,
  // sonra getTripPath ile tüm noktaları al.
  // (mevcut sehirici_route_service.dart.getLineRoutes üzerinden)
}
```

Daha temiz implementasyon için yeni RPC:
```sql
CREATE OR REPLACE FUNCTION public.get_sehirici_latest_completed_trip_path(
  p_line_id UUID
) RETURNS TABLE(lat DOUBLE PRECISION, lng DOUBLE PRECISION, recorded_at TIMESTAMPTZ)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT tl.lat, tl.lng, tl.recorded_at
  FROM public.sehirici_trip_locations tl
  JOIN public.sehirici_trips t ON t.id = tl.trip_id
  WHERE t.line_id = p_line_id AND t.status = 'completed'
    AND t.id = (
      SELECT id FROM public.sehirici_trips
      WHERE line_id = p_line_id AND status = 'completed'
      ORDER BY started_at DESC LIMIT 1
    )
  ORDER BY tl.recorded_at ASC;
$$;
GRANT EXECUTE ON FUNCTION public.get_sehirici_latest_completed_trip_path(UUID) TO authenticated;
```
(Yeni RPC çünkü iki sorgu yerine tek atomik okuma; performans + basitlik.)

---

## E) Araç Yön Göstergesi

**Dosya**: `lib/sehirici/widgets/sehirici_live_map.dart`

Mevcut:
```dart
rotation: trip.currentHeading ?? 0  // L739, L1011
```

Değişiklikler:
- `_createVehicleBitmap` modernize edilecek: daire içinde **yukarı bakan üçgen ok** + araç tipi ikonu. Ok, marker'ın "ön" yönü = `rotation: 0`. Heading değiştikçe tüm marker döner → ok yönü görünür.
- Araç detail sheet'inde (mevcut `_showTripDetailsDialog` L1293) yeni satır:
  ```
  🧭 Yön: 145° (GD) — heading > 0 ise
  ```
- Sürücünün başlık verisi yoksa (heading == 0 → araba duruyor veya bearing hesaplanmamış), önceki konumdan hesaplanan bearing fallback'i:
  ```dart
  if (trip.currentHeading == null || trip.currentHeading! == 0) {
    // Önceki trip_locations noktasından bearing hesapla
  }
  ```

---

## F) Testler

| Test dosyası | Kapsam |
|---|---|
| `test/sehirici/sehirici_route_geometry_test.dart` (yeni) | `simplifyPath` (kollinear → tek nokta, 90° köşe korunur, tolerance sıfırsa identity), `pathLengthMeters`, `estimateDurationMinutes` |
| Mevcut `sehirici_time_utils_test.dart` | korunur |
| Mevcut `sehirici_line_service_stops_signature_test.dart` | korunur |
| Mevcut `sehirici_models_test.dart` | korunur |

---

## Değişecek / Eklenen Dosyalar

| Dosya | Tür | Açıklama |
|---|---|---|
| `lib/sehirici/admin/sehirici_line_route_draw_dialog.dart` | **MODIFY** (büyük) | Modernize + 2 yeni buton |
| `lib/sehirici/widgets/sehirici_live_map.dart` | **MODIFY** | `highlightLineId` + ok ikonu + heading fallback |
| `lib/sehirici/screens/sehirici_lines_screen.dart` | **MODIFY** | Tile'da haritada-göster + seçili hat chip |
| `lib/sehirici/screens/sehirici_driver_panel_screen.dart` | **MODIFY** | Yeni toggle + otomatik rota watcher |
| `lib/sehirici/services/sehirici_driver_service.dart` | **MODIFY** | Yeni sütun + update param |
| `lib/sehirici/services/sehirici_line_service.dart` | **MODIFY** | `getLatestCompletedTripPath` |
| `lib/sehirici/providers/sehirici_provider.dart` | **MODIFY** | `highlightedLineId` state |
| `lib/sehirici/utils/sehirici_route_geometry.dart` | **NEW** | Douglas-Peucker + helpers |
| `lib/sehirici/sehirici.dart` | **MODIFY** | Yeni util export |
| `lib/sehirici/admin/sehirici_admin_management_content.dart` | **MODIFY** (opsiyonel) | Rota Çiz butonu zaten var |
| `supabase/migrations/20260807130000_sehirici_auto_route_setting.sql` | **NEW** | Yeni sütun |
| `supabase/migrations/20260807130001_sehirici_latest_completed_trip_path.sql` | **NEW** | Yeni RPC |
| `test/sehirici/sehirici_route_geometry_test.dart` | **NEW** | Birim testler |

---

## Kabul Kriterleri

1. `flutter analyze` hatasız.
2. `flutter test` tüm testler yeşil (mevcut 80 + yeni ~6 test).
3. Draw dialog: duraklardan/son seferden otomatik öner çalışır; manuel çizim korunur.
4. Kullanıcı haritası: hat tile'daki harita ikonu → harita zoom + o hat vurgulu; chip ile kapatılabilir.
5. Şöför paneli ayarı: açıksa ve hat rotası yoksa, ~1 km sonra otomatik rota oluşur + Snackbar bildirimi.
6. Araç marker'ı ok şeklinde; heading ile dönüyor; detail sheet'te yön bilgisi görünür.
7. Çizim sırasında rotayı seferden alırken "X nokta (orijinal Y'den)" gibi bilgilendirme gösterilir.

---

## Sıralama (önerilen)

1. **A** (draw dialog) — bağımsız, hızlı görsel kazanım
2. **E** (araç yönü) — küçük değişiklik, faydası büyük
3. **B** (kullanıcı haritası) — provider state + map highlight
4. **C** (şöör ayarı + DB migration) — backend + UI
5. **D** (admin son seferden öner) — yeni RPC + draw entegrasyonu
6. **F** (testler) — her şeyden sonra veya parça parça
