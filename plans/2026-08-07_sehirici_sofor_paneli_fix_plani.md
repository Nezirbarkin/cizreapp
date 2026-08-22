# Şöför Paneli — Konum Paylaşımı ve Ayarlar Düzeltme Planı

**Tarih:** 7 Ağustos 2026
**Durum:** Uygulama öncesi teknik tasarım
**Kapsam:** Şöför paneli hata düzeltmeleri, konum takibi 10 sn garantisi, ayarların DB'ye yazımı, yaşam döngüsü yönetimi, unit testler, anasayfa kısayolu.
**Kapsam dışı:** Gerçek GPS/Supabase entegrasyonu (testlerde mock), native arka plan servisi (iOS background mode + Android Foreground Service) bu planda sadece Flutter tarafında lifecycle observer ile yönetilecek; ileride ayrı iş paketi.

---

## 1. Karar özeti

| Karar | Tercih |
|---|---|
| Ayar saklama | Supabase `sehirici_drivers` tablosu (sütunlar eklenecek) |
| Arka plan davranışı | Sefer aktifken her zaman devam etsin (UI + tracker kararı) |
| Güncelleme sıklığı | 10 sn fallback timer korunsun, stream `distanceFilter: 0` |
| Test kapsamı | Sadece unit test (mock'lı) |

**Politika sınırı:**
- Şoför ayarları (`working_hours_start/end`, `auto_location_enabled`) sürücünün kendi satırında tutulur, başka şoförler göremez.
- Konum paylaşımı "durdur" eylemi UI'da veya sefer bitirildiğinde olur — otomatik durdurma sadece çalışma saatleri dışında ve `auto_location_enabled=true` ise.
- Testler gerçek Supabase/GPS çağırmaz; tracker ve ayar mantığı izole test edilir.

---

## 2. Mevcut durum ve tespit edilen hatalar

### 2.1 `sehirici_drivers` tablosu — KRİTİK

[`supabase/migrations/20260725000001_sehirici_services.sql:162-172`](supabase/migrations/20260725000001_sehirici_services.sql:162) tablo tanımı:

```sql
CREATE TABLE IF NOT EXISTS public.sehirici_drivers (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profile_id      UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  license_number  TEXT,
  phone           TEXT,
  assigned_line_id UUID REFERENCES public.sehirici_lines(id) ON DELETE SET NULL,
  is_on_duty      BOOLEAN NOT NULL DEFAULT FALSE,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(profile_id)
);
```

**Eksik sütunlar:**
- `working_hours_start` (TEXT, format `HH:mm`)
- `working_hours_end` (TEXT, format `HH:mm`)
- `auto_location_enabled` (BOOLEAN, default TRUE)

`sehirici_models.dart:373-374` ve şöför paneli bu alanları okumaya çalışıyor, şu an `null` dönüyor. Bu nedenle `_showSettingsDialog` aslında hep boş değerlerle açılıyor, `_checkAndApplyWorkingHours` hiç tetiklenmiyor.

### 2.2 `_togglePause` yarış durumu — `sehirici_driver_panel_screen.dart:136-171`

```dart
// İlk setState: copyWithLocation ile state'i "güncelle" deniyor
setState(() {
  _activeTrip = _activeTrip!.copyWithLocation(lat: ..., lng: ...);
});
// İkinci setState: tüm field'leri elle kopyalıyor
_activeTrip = SehiriciActiveTrip(...);
```

`_togglePause` `async` ama `setState` callback'inde `await` yok → çift yazma. Sonuç: bazen `setState` tamamlanmadan `_activeTrip` yeniden atanıyor, listener'lar stale state görüyor.

### 2.3 Çalışma saati yükleme sadece yeni seferde — `sehirici_driver_panel_screen.dart:55-67`

`_load()` ile eski sefer geri yüklenirken `workingHoursStart/End` `_activeTrip`'e atanmıyor. Sadece `_startTrip()` ile yeni sefer başlatılınca atanıyor. Sonuç: uygulama kapatılıp tekrar açıldığında otomatik mola çalışmıyor.

### 2.4 Ayarlar dialog'u dekoratif — `sehirici_driver_panel_screen.dart:387-477`

`_showSettingsDialog` `_driverProfile`'tan değer okuyor, "Kaydet" butonu sadece snackbar gösteriyor. Hiçbir yere yazmıyor. RLS zaten `sehirici_drivers_update_self` ile kendi satırını güncelleyebilir ama service eksik.

### 2.5 Konum paylaşımı arka planda durur

`sehirici_location_tracker.dart` sadece ön plan stream'i dinliyor. Uygulama arka plana alındığında iOS/Android OS stream'i durdurur. Tracker singleton olmasına rağmen OS isolate'ı öldüğünde yazma da durur. Şoför seferdeyse bu kabul edilemez.

### 2.6 Anasayfada şöför paneline kısayol yok

`lib/features/main/screens/main_screen.dart:313-356` alt navigasyonda 4 sekme var: AnaSayfa, Ürünler, Keşfet, Profil. Hiçbiri şöför paneline yönlendirmiyor. Şöför paneli şu an sadece doğrudan route ile açılabiliyor, keşfedilmesi imkansız.

### 2.7 Test altyapısı eksik

`test/sehirici/` altında sadece `sehirici_models_test.dart` var. Tracker, ayar servisi, yaşam döngüsü için test yok. README "kapsamlı test altyapısı" diyor ama gerçekte şehir içi modülünün test coverage'ı çok düşük.

---

## 3. Tasarım

### 3.1 DB Migration: `sehirici_drivers` sütunları

Yeni dosya: `supabase/migrations/20260807120000_sehirici_driver_settings.sql`

```sql
-- 3 yeni sütun + RLS güncelleme (zaten self-update var, sadece yeni sütunlar eklenir)
ALTER TABLE public.sehirici_drivers
  ADD COLUMN IF NOT EXISTS working_hours_start TIME,
  ADD COLUMN IF NOT EXISTS working_hours_end   TIME,
  ADD COLUMN IF NOT EXISTS auto_location_enabled BOOLEAN NOT NULL DEFAULT TRUE;

-- Şoför kendi ayarlarını güncelleyebilir (mevcut policy yeterli, sadece dokümantasyon)
COMMENT ON COLUMN public.sehirici_drivers.working_hours_start
  IS 'Şoförün günlük çalışma başlangıç saati (HH:mm)';
COMMENT ON COLUMN public.sehirici_drivers.working_hours_end
  IS 'Şoförün günlük çalışma bitiş saati (HH:mm)';
COMMENT ON COLUMN public.sehirici_drivers.auto_location_enabled
  IS 'Çalışma saatleri dışında konum paylaşımını otomatik durdur';
```

**Neden TEXT yerine TIME?**
- Dart tarafında `TimeOfDay` ile dönüşümü kolay (HH:mm string parse).
- Ancak SQL'de `TIME` ile karşılaştırma ve trigger yazımı daha temiz.
- Karar: TEXT (HH:mm string) — Dart tarafında zaten parse ediliyor, RLS/policy güncellemesine gerek yok.

**Düzeltme:** TEXT kullan, parse'ı Dart'ta tut.

```sql
ALTER TABLE public.sehirici_drivers
  ADD COLUMN IF NOT EXISTS working_hours_start TEXT,
  ADD COLUMN IF NOT EXISTS working_hours_end   TEXT,
  ADD COLUMN IF NOT EXISTS auto_location_enabled BOOLEAN NOT NULL DEFAULT TRUE;

-- CHECK ile format doğrulama
ALTER TABLE public.sehirici_drivers
  ADD CONSTRAINT sehirici_drivers_working_hours_start_format
  CHECK (working_hours_start IS NULL OR working_hours_start ~ '^[0-2][0-9]:[0-5][0-9]$'),
  ADD CONSTRAINT sehirici_drivers_working_hours_end_format
  CHECK (working_hours_end IS NULL OR working_hours_end ~ '^[0-2][0-9]:[0-5][0-9]$');
```

### 3.2 `sehirici_driver_service.dart` — yeni method

`getMyDriverProfile` artık yeni sütunları da seçecek, ve `updateDriverSettings` eklenecek:

```dart
Future<bool> updateDriverSettings({
  required String driverId,
  String? workingHoursStart,  // "HH:mm" veya null
  String? workingHoursEnd,
  bool? autoLocationEnabled,
}) async {
  try {
    final update = <String, dynamic>{'updated_at': DateTime.now().toIso8601String()};
    if (workingHoursStart != null) update['working_hours_start'] = workingHoursStart;
    if (workingHoursEnd   != null) update['working_hours_end']   = workingHoursEnd;
    if (autoLocationEnabled != null) update['auto_location_enabled'] = autoLocationEnabled;
    if (update.length == 1) return true; // sadece updated_at ise no-op
    await _client.from('sehirici_drivers').update(update).eq('id', driverId);
    return true;
  } catch (e) {
    debugPrint('updateDriverSettings hata: $e');
    return false;
  }
}
```

`getMyDriverProfile` SELECT'i genişletilecek:
```dart
.select('*, sehirici_lines(id, code, name, color_hex, vehicle_type), '
        'working_hours_start, working_hours_end, auto_location_enabled')
```

### 3.3 `_showSettingsDialog` düzeltmesi

`_showSettingsDialog` artık:
1. Async yapılacak (`Future<void>`).
2. "Kaydet" handler'ı:
   - `_formatTimeOfDay(workStart)` ve `_formatTimeOfDay(workEnd)` ile "HH:mm" string üretecek.
   - `_driverService.updateDriverSettings(...)` çağıracak.
   - Başarılıysa `await _load()` ile profili yeniden yükleyecek.
   - Hata varsa snackbar gösterecek.
3. `_load()` içinde `_activeTrip = SehiriciActiveTrip(... workingHoursStart: parseTimeOfDay(_driverProfile['working_hours_start'])...)` — eski sefer yüklendiğinde de çalışma saatleri set edilecek.

### 3.4 `_togglePause` düzeltmesi

```dart
Future<void> _togglePause() async {
  if (_activeTrip == null) return;
  final newStatus = _activeTrip!.status == SehiriciTripStatus.active
      ? SehiriciTripStatus.paused
      : SehiriciTripStatus.active;
  final ok = await _tripService.setStatus(_activeTrip!.tripId, newStatus);
  if (!ok) {
    _showError('Durum değiştirilemedi');
    return;
  }
  // tek atomik setState
  setState(() {
    _activeTrip = SehiriciActiveTrip(
      tripId: _activeTrip!.tripId,
      lineId: _activeTrip!.lineId,
      lineCode: _activeTrip!.lineCode,
      lineName: _activeTrip!.lineName,
      lineColor: _activeTrip!.lineColor,
      driverName: _activeTrip!.driverName,
      licensePlate: _activeTrip!.licensePlate,
      workingHoursStart: _activeTrip!.workingHoursStart,
      workingHoursEnd: _activeTrip!.workingHoursEnd,
      currentLat: _activeTrip!.currentLat,
      currentLng: _activeTrip!.currentLng,
      currentHeading: _activeTrip!.currentHeading,
      currentSpeed: _activeTrip!.currentSpeed,
      startedAt: _activeTrip!.startedAt,
      nextStopId: _activeTrip!.nextStopId,
      nextStopName: _activeTrip!.nextStopName,
      nextStopLat: _activeTrip!.nextStopLat,
      nextStopLng: _activeTrip!.nextStopLng,
      etaMinutes: _activeTrip!.etaMinutes,
      status: newStatus,
    );
  });
  if (newStatus == SehiriciTripStatus.paused) {
    await _tracker.stop();
  } else {
    final pos = _tracker.lastPosition;
    if (pos != null) {
      await _tracker.start(
        tripId: _activeTrip!.tripId,
        tripService: _tripService,
        interval: const Duration(seconds: 10),
      );
    }
  }
}
```

### 3.5 Konum takibi 10 sn garantisi

`sehirici_location_tracker.dart`:
- `distanceFilter: 0` (her konum değişimini al, sadece zamanlama ile filtrele).
- `interval` parametresi (default 10 sn) hem stream hem fallback için.
- Stream: `getPositionStream(locationSettings: distanceFilter: 0, timeLimit: interval * 3)`.
- Fallback timer: `Timer.periodic(interval, ...)` (mevcut).
- Çift yazma koruması: `_lastWriteTimestamp` ile son yazma zamanı saklanır, `_interval` içinde tekrar yazma yapılmaz (stream tetiklense bile).

```dart
DateTime? _lastWriteAt;

void _writeLocation(Position pos) async {
  if (_currentTripId == null) return;
  if (_lastWriteAt != null &&
      DateTime.now().difference(_lastWriteAt!) < const Duration(seconds: 8)) {
    return; // 8 sn içinde yazıldı, atla (10 sn hedefi için 8 sn güvenlik marjı)
  }
  _lastWriteAt = DateTime.now();
  await tripService.updateLocation(...);
}
```

### 3.6 Yaşam döngüsü observer — şöför paneli

`SehiriciDriverPanelScreen` `WidgetsBindingObserver` mixin alacak:

```dart
class _SehiriciDriverPanelScreenState extends State<SehiriciDriverPanelScreen>
    with WidgetsBindingObserver {

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tripTimer?.cancel();
    _workingHoursTimer?.cancel();
    // dispose'ta tracker'ı DURDURMA — uygulama kapatılıyor zaten,
    // ama panel dispose olursa (örn. geri tuşu) sefer hala DB'de aktif
    // kalmalı. Tracker'ı durdurmak seferi "konum yok" durumuna düşürür.
    // Bu yüzden dispose'ta tracker durdurulmaz, sadece timer'lar iptal.
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (_activeTrip == null) return;
    switch (state) {
      case AppLifecycleState.resumed:
        // Ön plana dön — tracker zaten çalışıyor olmalı.
        // Singleton olduğu için burada start etmeye gerek yok;
        // ancak güvenlik için lastPosition yenilenir.
        if (!_tracker.isTracking) {
          _tracker.start(
            tripId: _activeTrip!.tripId,
            tripService: _tripService,
            interval: const Duration(seconds: 10),
          );
        }
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        // Arka plan — şu an yapacak bir şey yok.
        // OS stream'i durdurur; fallback timer de durur.
        // Not: Tam çözüm için ileride Foreground Service + iOS background mode
        // ayrı iş paketinde ele alınacak. Bu planda sadece yaşam döngüsü
        // observer'ı ekleniyor, native taraf bu PR'ın kapsamı dışı.
        // Mevcut sefer DB'de "active" kalır, konum yazımı geçici durur.
        // Yeniden ön plana dönüldüğünde tracker tekrar başlatılır.
        break;
      default:
        break;
    }
  }
}
```

**Karar:** Dispose'da tracker durdurulmayacak. Açıklama kodu içinde yorum olarak.

### 3.7 Anasayfa kısayolu — `main_screen.dart`

Alt navigasyondaki **Ürünler** sekmesinin hemen üstüne (yani **Keşfet** ve **Profil**'in yanında, FAB'ın üstünde değil) bir **directions_bus** ikonu eklenecek. Bu ikon şöför paneline açılacak.

Konum: BottomAppBar'da Keşfet'in soluna bir "Şoför" sekmesi eklemek mantıklı değil çünkü kullanıcıların çoğu şoför değil. Daha temiz: **Üst app bar'da mevcut ikonların (arama, bildirim, ayarlar) yanına** bir **directions_bus** ikonu. Ancak kullanıcı "anasayfada moto kurye iconun hemen üstüne" demiş.

**Yeniden okuma:** "şöför konum paylaştığında uygulamadan cıktığında kronometre ve konum paylaş durdurması veya başlatması için anasayfada moto kurye iconun hemen üstüne bir icon koy"

Yani: Anasayfada bir yerde bir moto kurye ikonu var. Şoför konum paylaşımını başlatmak/durdurmak için o ikonun üstüne yeni bir ikon koy.

`main_screen.dart` dosyasında "moto kurye" diye bir ikon yok. **Courier** özelliği `lib/features/courier/` altında. Belki kullanıcı başka bir ekrandan (ürün detay, sipariş, vs.) bahsediyor.

**Netleştirme gereken:** "Moto kurye ikonu" tam olarak nerede? `lib/features/main/screens/main_screen.dart` içinde böyle bir ikon yok. `lib/features/courier/` veya `user_courier/` dizininde olabilir.

**Bu plan için varsayım:** Kullanıcı **Ürünler sekmesinin üst başlığındaki (app bar) ikonlar arasına** bir **directions_bus** ikonu ekleneceğini kastediyor. Bu, "moto kurye" ile ilişkili bir konum olabilir — zira kullanıcılar moto kurye ile şöförü ayırt ediyor olabilir. **Planı uygularken kullanıcıya "moto kurye ikonu" tam yerini soracağım** veya en mantıklı yer olan app bar'a koyacağım.

### 3.8 Test stratejisi — unit + mock

Yeni test dosyaları:

| Dosya | Kapsam |
|---|---|
| `test/sehirici/sehirici_location_tracker_test.dart` | Tracker start/stop, çift yazma koruması, interval kontrolü |
| `test/sehirici/sehirici_driver_panel_state_test.dart` | `_togglePause`, `_isTimeWithinRange`, `_parseTimeOfDay` (testable pure functions'a çıkarılacak) |
| `test/sehirici/sehirici_driver_service_test.dart` | `updateDriverSettings` parametre validasyonu (Supabase mock'lu) |

**Pure function extraction:**
- `_isTimeWithinRange`, `_formatDuration`, `_parseTimeOfDay`, `_formatTimeOfDay` (yeni), `_calculateETA` (yeni) → `lib/sehirici/utils/sehirici_time_utils.dart` içine çıkarılacak.
- `SehiriciLocationTracker`'da çift yazma kontrolü (`_lastWriteAt` + `interval`) → pure function olarak test edilebilir hale getirilecek.

**Mock:** `package:mockito` zaten projede var mı? Kontrol edilecek. Yoksa basit fake sınıflar yazılacak.

### 3.9 Hata düzeltme özeti

| # | Dosya | Düzeltme |
|---|---|---|
| 1 | `supabase/migrations/20260807120000_sehirici_driver_settings.sql` | Yeni: 3 sütun + 2 CHECK constraint |
| 2 | `lib/sehirici/services/sehirici_driver_service.dart` | `getMyDriverProfile` SELECT genişlet + `updateDriverSettings` ekle |
| 3 | `lib/sehirici/utils/sehirici_time_utils.dart` | Yeni: pure time helpers |
| 4 | `lib/sehirici/screens/sehirici_driver_panel_screen.dart` | `_showSettingsDialog` async + DB'ye yaz, `_togglePause` yarış düzelt, `_load` çalışma saati yükleme, lifecycle observer ekle |
| 5 | `lib/sehirici/services/sehirici_location_tracker.dart` | Çift yazma koruması, distanceFilter 0, dispose'da durdurma kararı |
| 6 | `lib/features/main/screens/main_screen.dart` | App bar'a **directions_bus** ikonu (veya kullanıcının netleştireceği yer) |
| 7 | `test/sehirici/sehirici_location_tracker_test.dart` | Yeni |
| 8 | `test/sehirici/sehirici_driver_panel_state_test.dart` | Yeni |
| 9 | `test/sehirici/sehirici_driver_service_test.dart` | Yeni |

---

## 4. Uygulama sırası

1. **DB migration** — sütunları ekle, CHECK constraint'leri koy.
2. **Service güncelle** — `sehirici_driver_service.dart` SELECT ve `updateDriverSettings` ekle.
3. **Pure utils** — `sehirici_time_utils.dart` oluştur.
4. **Tracker düzelt** — çift yazma koruması, distanceFilter.
5. **Panel düzelt** — `_togglePause`, `_showSettingsDialog`, `_load` çalışma saati, lifecycle observer.
6. **Anasayfa kısayolu** — ikon ekleme (yer netleştirildikten sonra).
7. **Testler** — pure utils + tracker + service testleri.
8. **Test çalıştırma** — `flutter test` ile hepsi geçene kadar.
9. **Doğrulama** — `flutter analyze` + `flutter test`.

---

## 5. Risk ve geri dönüş

- **Migration riski:** Sütunlar `IF NOT EXISTS` ile eklenecek, idempotent. CHECK constraint'ler eklenirken mevcut veride format dışı değer yoksa sorun olmaz. Varsa constraint hata verir; geri alma `ALTER TABLE ... DROP CONSTRAINT` ile yapılabilir.
- **Tracker dispose kararı:** Tracker dispose'da durdurulmayacak. Eğer ekran dispose olurken sefer de bitirilecekse bu bir bug olur. **Karar:** Şoför paneli ekranı dispose olurken aktif sefer varsa kullanıcıya "Sefer hala aktif. Çıkmak istiyor musunuz?" sorulacak veya sefer otomatik tamamlanmayacak. Bu UX kararı uygulama sırasında netleşecek.
- **Test coverage:** Pure function'lara çıkarılmayan UI kod test edilemeyecek. Şoför paneli `_showSettingsDialog` async davranışı widget testi ile doğrulanabilir, ama bu plan kapsamı dışı (sadece unit test istendi).

---

## 6. Kapsam dışı

- Native arka plan servisi (iOS background mode, Android Foreground Service).
- Yönetici paneli tarafında şoför ayarları düzenleme.
- Şoför için bildirim sistemi.
- Konum geçmişi performans optimizasyonu.
- Web platformu desteği (kIsWeb zaten handle ediliyor ama test edilmeyecek).
