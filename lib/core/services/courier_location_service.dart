import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

class CourierLocationService {
  static final CourierLocationService _instance =
      CourierLocationService._internal();

  factory CourierLocationService() {
    return _instance;
  }

  CourierLocationService._internal();

  StreamSubscription<Position>? _positionStream;
  Timer? _updateTimer;
  bool _isTracking = false;

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
          debugPrint('❌ Konum izni reddedildi');
          return false;
        }
      }

      // requestPermission() sonrası güncellenmiş 'permission' değerini kontrol et.
      // (Eski kod, istekten önceki bayat değeri kontrol ediyordu.)
      if (permission == LocationPermission.deniedForever) {
        debugPrint('❌ Konum izni kalıcı olarak reddedildi');
        return false;
      }

      // İlk konumu al
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 0,
        ),
      );

      // İlk yazım başarısızsa "takip başladı" diye işaretleme; buton yanlış
      // başarı göstermesin. (Eksik migration/RLS burada yüzeye çıkar.)
      final written = await _updateLocationInDatabase(position);
      if (!written) {
        debugPrint('❌ İlk konum veritabanına yazılamadı; takip başlatılmadı');
        return false;
      }

      _isTracking = true;

      // Konumu düzenli olarak güncelle
      _updateTimer = Timer.periodic(const Duration(seconds: 10), (_) {
        _updateLocationPeriodically();
      });

      // Gerçek zamanlı akış
      _positionStream =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.best,
              distanceFilter: 10, // 10 metrelik değişim
              timeLimit: Duration(seconds: 5),
            ),
          ).listen(
            (Position position) {
              _updateLocationInDatabase(position);
            },
            onError: (Object error) {
              // timeLimit veya platform hatası akışı öldürmesin; logla ve devam et.
              // Konum hala periyodik timer ile güncellendiği için takip kesilmez.
              debugPrint(
                '⚠️ Kurye konum akışı hatası (timer devam ediyor): $error',
              );
            },
          );

      debugPrint('✅ Kurye konum takibi başladı');
      return true;
    } catch (e) {
      debugPrint('❌ Konum takibi başlama hatası: $e');
      _isTracking = false;
      return false;
    }
  }

  bool _periodicUpdateInProgress = false;
  Future<void> _updateLocationPeriodically() async {
    // Bir önceki periyodik güncelleme hâlâ çalışıyorsa (yavaş GPS) üst üste binme.
    if (_periodicUpdateInProgress) return;
    _periodicUpdateInProgress = true;
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 0,
        ),
      );
      await _updateLocationInDatabase(position);
    } catch (e) {
      debugPrint('⚠️ Konum güncelleme hatası: $e');
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
        //    mevcutsa dokunmaz). Bu adım idempotenttir.
        try {
          await client.rpc('ensure_my_profile');
        } catch (e) {
          // ensure_my_profile yetki/auth hatası verirse yine de konum
          // deneyebiliriz; konum RPC kendi içinde kontrol yapacak.
          debugPrint('ℹ️ ensure_my_profile çağrısı atlandı: $e');
        }

        // 2) Konumu server'a yaz. RPC çağıranın role='courier' olduğunu
        //    doğrular; değilse 42501 SQLSTATE ile reddeder.
        await client.rpc(
          'set_my_courier_location',
          params: {'p_lat': position.latitude, 'p_lng': position.longitude},
        );
        // Hassas koordinat debug log'a yazılmaz.
        debugPrint('📍 Konum güncellendi (deneme $attempt)');
        return true;
      } on PostgrestException catch (e) {
        if (e.code == '42501') {
          // Kullanıcı courier değil: konum servisi başlatılmamalıydı.
          // Sessizce false dönmek UI tarafında butonu geri çevirmesine yol
          // açar; bu doğru davranış. (Yetkisiz çağrı loglanmaz.)
          debugPrint('❌ set_my_courier_location: kullanıcı courier değil');
          return false;
        }
        debugPrint(
          '⚠️ Konum yazma denemesi $attempt/$maxAttempts Postgrest hatası: '
          'code=${e.code}, message=${e.message}',
        );
      } catch (e) {
        debugPrint(
          '⚠️ Konum yazma denemesi $attempt/$maxAttempts başarısız: $e',
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
    _positionStream = null;
    _updateTimer = null;
    debugPrint('✅ Kurye konum takibi durduruldu');
  }

  Future<Position?> getCurrentLocation() async {
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 0,
        ),
      );
    } catch (e) {
      debugPrint('❌ Geçerli konum alma hatası: $e');
      return null;
    }
  }
}
