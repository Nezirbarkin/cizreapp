import 'dart:async';
import 'dart:io' show Platform;
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

/// Kurye konum akışı için platforma özel ayarlar.
///
/// Düz [LocationSettings] ile akış, uygulama arka plana alınır alınmaz
/// (Android'de ekran kapanınca, iOS'ta suspend olunca) susuyordu — yani
/// kurye tam teslimat sırasında, telefon cebindeyken haritada donuyordu.
/// Android'de foreground service bildirimi, iOS'ta background location
/// modu ile akış sürdürülür. Manifest izinleri (FOREGROUND_SERVICE_LOCATION,
/// ACCESS_BACKGROUND_LOCATION) zaten tanımlı.
LocationSettings _courierLocationSettings({
  required int distanceFilter,
  Duration? timeLimit,
}) {
  if (!kIsWeb && Platform.isIOS) {
    return AppleSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: distanceFilter,
      timeLimit: timeLimit,
      pauseLocationUpdatesAutomatically: false,
      allowBackgroundLocationUpdates: true,
      showBackgroundLocationIndicator: true,
      activityType: ActivityType.otherNavigation,
    );
  }
  if (!kIsWeb && Platform.isAndroid) {
    return AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: distanceFilter,
      timeLimit: timeLimit,
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationText: 'Konumunuz müşterilerle paylaşılıyor',
        notificationTitle: 'CizreApp Kurye',
        enableWakeLock: true,
      ),
    );
  }
  return LocationSettings(
    accuracy: LocationAccuracy.high,
    distanceFilter: distanceFilter,
    timeLimit: timeLimit,
  );
}

class CourierLocationService {
  static final CourierLocationService _instance =
      CourierLocationService._internal();

  factory CourierLocationService() {
    return _instance;
  }

  CourierLocationService._internal();

  StreamSubscription<Position>? _positionStream;
  Timer? _updateTimer;
  Timer? _streamRestartTimer;
  bool _isTracking = false;
  bool _periodicUpdateInProgress = false;

  /// `ensure_my_profile` idempotent ve yalnız eksik legacy profili tamamlıyor;
  /// her konum yazımında (10 sn'de bir) çağrılması saf israftı — konum
  /// başına iki ağ gidiş-dönüşü. Oturum başına bir kez yeter; konum RPC'si
  /// "profil yok" hatası verirse aşağıda yeniden denenir.
  bool _profileEnsured = false;

  bool get isTracking => _isTracking;

  /// Konum takip/publish akışını başlatır. İlk konum alınıp veritabanına
  /// YAZILDIĞINDA true döner; izin reddedilirse veya ilk DB yazımı
  /// başarısız olursa (eksik sütun/RLS/ağ) false döner ve _isTracking
  /// false kalır. Böylece arayüzdeki "Konum Paylaş" butonu gerçeği yansıtır.
  Future<bool> startTracking() async {
    if (_isTracking) return true;

    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          debugPrint('Konum izni reddedildi');
          return false;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        debugPrint('Konum izni kalıcı olarak reddedildi');
        return false;
      }

      // Servis açık mı kontrol et; kapalıysa hata ver. Android'de kullanıcı
      // GPS'i kapatırsa burada null döner ve startTracking başarısız olur.
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('Konum servisi kapalı');
        return false;
      }

      // İlk konumu al — kısa timeout ile. GPS daha yeni açıldıysa fix
      // almak uzun sürebilir; burada bestForNavigation yerine high
      // kullanıyoruz çünkü best binaların içinde kilitlenebiliyor.
      final firstPosition = await _getPositionWithTimeout(
        const Duration(seconds: 8),
        accuracy: LocationAccuracy.high,
      );
      if (firstPosition == null) {
        debugPrint('Ilk konum alinamadi (timeout veya servis yok)');
        return false;
      }

      // İlk yazım başarısızsa "takip başladı" diye işaretleme; buton yanlış
      // başarı göstermesin. (Eksik migration/RLS burada yüzeye çıkar.)
      final written = await _updateLocationInDatabase(firstPosition);
      if (!written) {
        debugPrint('Ilk konum veritabanina yazilamadi; takip baslatilmadi');
        return false;
      }

      _isTracking = true;

      // Periyodik timer — 10 saniyede bir konum al, DB'ye yaz. Akış
      // hata verse bile timer çalışmaya devam eder; her zaman son savunma
      // hattı olarak işlev görür.
      _updateTimer?.cancel();
      _updateTimer = Timer.periodic(
        const Duration(seconds: 10),
        (_) => _updateLocationPeriodically(),
      );

      // Gerçek zamanlı akış — distanceFilter zaten gereksiz güncellemeyi
      // engellediği için timeLimit koymuyoruz. Sabit kuryede GPS 5 sn'de fix
      // veremeyip timeout/restart döngüsüne girer; bu da hareket anlık
      // güncellemesini keser ve kurye haritada eski yerde kalır. Periyodik
      // timer (10 sn) zaten son savunma hattı olarak çalıştığı için akışta
      // timeLimit'e gerek yok; gerçek platform hataları onDone/onError ile
      // yeniden başlatılır.
      _startPositionStream();

      debugPrint('Kurye konum takibi basladi');
      return true;
    } catch (e) {
      debugPrint('Konum takibi baslama hatasi: $e');
      _isTracking = false;
      return false;
    }
  }

  /// Mevcut akışı iptal edip yeniden başlatır. Hata sonrası çağrılır.
  void _startPositionStream() {
    _positionStream?.cancel();
    _positionStream = null;
    _positionStream = Geolocator.getPositionStream(
      // timeLimit yok: sabit kuryede GPS 5 sn'de fix veremeyip timeout/
      // restart döngüsüne girer; hareket anlık güncellemesi kesilir ve
      // kurye haritada eski yerde kalır. Periyodik timer son savunma.
      locationSettings: _courierLocationSettings(distanceFilter: 10),
    ).listen(
      (Position position) {
        _updateLocationInDatabase(position);
      },
      onError: (Object error) {
        // timeLimit veya platform hatası akışı öldürür; 10 sn sonra
        // yeniden başlat. Timer zaten çalıştığı için konum yayını
        // kesilmez.
        debugPrint('Kurye konum akisi hatasi (yeniden baslatilacak): $error');
        _scheduleStreamRestart();
      },
      onDone: () {
        debugPrint('Kurye konum akisi kapandi (yeniden baslatilacak)');
        _scheduleStreamRestart();
      },
      cancelOnError: false, // iptal etme, biz kendimiz yöneteceğiz
    );
  }

  void _scheduleStreamRestart() {
    _streamRestartTimer?.cancel();
    _streamRestartTimer = Timer(const Duration(seconds: 10), () {
      if (_isTracking) {
        _startPositionStream();
      }
    });
  }

  /// Timeout korumalı `getCurrentPosition`. Android'de GPS kilitlenirse
  /// bu çağrı sonsuza kadar askıda kalabilir; burada kısa bir süre sonra
  /// vazgeçip null dönüyoruz.
  Future<Position?> _getPositionWithTimeout(
    Duration timeout, {
    LocationAccuracy accuracy = LocationAccuracy.high,
  }) async {
    try {
      // Tek atımlık okuma: bilerek düz LocationSettings. Foreground service
      // yapılandırması yalnız sürekli akışa aittir — buraya konursa her
      // periyodik okumada kalıcı bildirim açılıp kapanırdı.
      return await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: accuracy,
          distanceFilter: 0,
          timeLimit: timeout,
        ),
      ).timeout(timeout + const Duration(seconds: 2));
    } on TimeoutException {
      debugPrint('getCurrentPosition zaman asimi');
      return null;
    } catch (e) {
      debugPrint('getCurrentPosition hatasi: $e');
      return null;
    }
  }

  Future<void> _updateLocationPeriodically() async {
    // Bir önceki periyodik güncelleme hâlâ çalışıyorsa (yavaş GPS) üst üste binme.
    if (_periodicUpdateInProgress) return;
    _periodicUpdateInProgress = true;
    try {
      final position = await _getPositionWithTimeout(
        const Duration(seconds: 8),
        accuracy: LocationAccuracy.high,
      );
      if (position == null) {
        // Konum alınamadı; bir sonraki periyotta yeniden dene. Eski
        // konum DB'de kaldığı için müşteri haritasında kurye son bilinen
        // yerde görünmeye devam eder.
        debugPrint('Periyodik konum alinamadi; son bilinen konum kullaniliyor');
        return;
      }
      await _updateLocationInDatabase(position);
    } catch (e) {
      debugPrint('Konum guncelleme hatasi: $e');
    } finally {
      _periodicUpdateInProgress = false;
    }
  }

  /// Konumu server'a güvenli RPC üzerinden yazar.
  ///
  /// Bu sürüm, 20260803000006_secure_profiles_privileges_and_pii migration'ı
  /// sonrasında doğrudan profiles INSERT/UPDATE yapmaz. Bunun yerine:
  ///  1) `ensure_my_profile()` ile eksik legacy profili güvenli varsayılanlarla
  ///     oluşturur (her zaman role=customer, is_admin=false).
  ///  2) `set_my_courier_location(p_lat, p_lng)` SECURITY DEFINER RPC'si
  ///     sunucu tarafında çağıranın role='courier' olduğunu doğrular, sınır
  ///     kontrolü yapar ve server timestamp yazar. Normal customer bu RPC'yi
  ///     çağıramaz; yetkisizse SQLSTATE 42501 alır.
  ///
  /// Not: Önceki sürümde olduğu gibi `role='courier'` istemciden atanamaz;
  /// kurye rol ataması yalnız admin tarafından `admin_set_user_role` RPC'si
  /// ile yapılır. Eğer kullanıcının role='courier' değilse RPC 42501 döner
  /// ve bu fonksiyon false döner.
  Future<bool> _updateLocationInDatabase(
    Position position, {
    int maxAttempts = 3,
  }) async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) return false;

    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        // 1) Eksik legacy profili güvenli varsayılanlarla oluştur (idempotent,
        //    mevcutsa dokunmaz). Oturum başına bir kez — ya da bir önceki
        //    konum yazımı başarısız olup buraya yeniden denemeyle
        //    döndüysek (o zaman gerçekten profil eksik olabilir).
        if (!_profileEnsured || attempt > 1) {
          try {
            await client.rpc('ensure_my_profile');
            _profileEnsured = true;
          } catch (e) {
            // ensure_my_profile yetki/auth hatası verirse yine de konum
            // deneyebiliriz; konum RPC kendi içinde kontrol yapacak.
            debugPrint('ensure_my_profile cagrisi atlandi: $e');
          }
        }

        // 2) Konumu server'a yaz. RPC çağıranın role='courier' olduğunu
        //    doğrular; değilse 42501 SQLSTATE ile reddeder. heading
        //    (gidiş yönü, derece 0=kuzey) opsiyonel: 0 "bilinmiyor/araç
        //    duruyor" anlamında gelebilir, sunucu olduğu gibi yazar.
        await client.rpc(
          'set_my_courier_location',
          params: {
            'p_lat': position.latitude,
            'p_lng': position.longitude,
            'p_heading': position.heading,
          },
        );
        // Hassas koordinat debug log'a yazılmaz.
        debugPrint('Konum guncellendi (deneme $attempt)');
        return true;
      } on PostgrestException catch (e) {
        if (e.code == '42501') {
          // Kullanıcı courier değil: konum servisi başlatılmamalıydı.
          // Sessizce false dönmek UI tarafında butonu geri çevirmesine yol
          // açar; bu doğru davranış. (Yetkisiz çağrı loglanmaz.)
          debugPrint('set_my_courier_location: kullanici courier degil');
          return false;
        }
        debugPrint(
          'Konum yazma denemesi $attempt/$maxAttempts Postgrest hatasi: '
          'code=${e.code}, message=${e.message}',
        );
      } catch (e) {
        debugPrint(
          'Konum yazma denemesi $attempt/$maxAttempts basarisiz: $e',
        );
      }
      if (attempt < maxAttempts) {
        await Future.delayed(Duration(seconds: 2 * attempt));
      }
    }
    return false;
  }

  Future<void> stopTracking() async {
    _isTracking = false;
    await _positionStream?.cancel();
    _updateTimer?.cancel();
    _streamRestartTimer?.cancel();
    _positionStream = null;
    _updateTimer = null;
    _streamRestartTimer = null;
    _periodicUpdateInProgress = false;
    _profileEnsured = false;
    debugPrint('Kurye konum takibi durduruldu');
  }

  Future<Position?> getCurrentLocation() async {
    return _getPositionWithTimeout(
      const Duration(seconds: 8),
      accuracy: LocationAccuracy.high,
    );
  }
}
