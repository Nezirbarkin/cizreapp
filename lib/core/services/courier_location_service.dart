import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

class CourierLocationService {
  static final CourierLocationService _instance = CourierLocationService._internal();

  factory CourierLocationService() {
    return _instance;
  }

  CourierLocationService._internal();

  StreamSubscription<Position>? _positionStream;
  Timer? _updateTimer;
  bool _isTracking = false;

  /// Eksik profiles satırı için self-heal denemesi yalnızca bir kez yapılır.
  /// Satır gerçekten yoksa insert eder; insert başarısız olursa (RLS/kısıt)
  /// her periyodik güncellemede tekrar denemek anlamsız ve gürültülü olur.
  bool _profileSelfHealAttempted = false;

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
      _positionStream = Geolocator.getPositionStream(
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
          debugPrint('⚠️ Kurye konum akışı hatası (timer devam ediyor): $error');
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

  /// Konumu profiles tablosuna yazar. Başarı durumunda true, hata/null
  /// kullanıcıda false döner (çağıran taraf buton geri bildirimi için kullanır).
  ///
  /// Strateji:
  ///  1) Önce `select('id')` ile satırın var olup olmadığını kontrol et.
  ///  2) Satır varsa düz `update` (location patch). .select() eklemeye gerek
  ///     yok; RLS UPDATE politikası başarılıysa exception fırlatmaz.
  ///  3) Satır yoksa (handle_new_user atlamış / satır silinmiş) bir kez
  ///     self-heal: `insert` ile role='courier' + konum yaz. Yarış durumunda
  ///     (arada satır oluşmuşsa) Postgrest code=23505 gelir; bunu yakalayıp
  ///     düz update'e düş — UPDATE politikası satırı bulabildiği için yazar.
  ///
  /// Mobil ağ kesintili olduğunda DNS/Socket hataları aralıklı çıkar; bu
  /// yüzden ağ hatasında birkaç kez kısa gecikmeyle yeniden dener.
  Future<bool> _updateLocationInDatabase(
    Position position, {
    int maxAttempts = 3,
  }) async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    if (userId == null) return false;

    final locationPatch = {
      'last_known_lat': position.latitude,
      'last_known_lng': position.longitude,
      'last_location_update': DateTime.now().toIso8601String(),
    };

    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        // 1) Satır var mı? SELECT herkese açık (profiles_select_policy USING true).
        final existing = await client
            .from('profiles')
            .select('id')
            .eq('id', userId)
            .maybeSingle();

        if (existing != null) {
          // 2) Satır var. Düz update — RLS UPDATE politikası kendi satırı için
          // izin veriyor, Postgrest hata fırlatmazsa başarılı sayılır.
          await client.from('profiles').update(locationPatch).eq('id', userId);
          debugPrint(
            '📍 Konum güncellendi (deneme $attempt): '
            '${position.latitude}, ${position.longitude}',
          );
          return true;
        }

        // 3) Satır yok. Self-heal: handle_new_user trigger'ı atlamış olabilir.
        if (_profileSelfHealAttempted) {
          debugPrint(
            '❌ Konum yazılamadı: profiles satırı bulunamadı, self-heal '
            'daha önce denendi ve başarısız oldu (id=$userId).',
          );
          return false;
        }
        _profileSelfHealAttempted = true;

        try {
          await _insertProfileRow(client, userId, position);
          debugPrint(
            '✅ Eksik profiles satırı oluşturuldu ve konum yazıldı '
            '(id=$userId, role=courier)',
          );
          return true;
        } on PostgrestException catch (pe) {
          if (pe.code == '23505') {
            // Yarış: arada satır oluşmuş. SELECT'i tekrar etmeden düz
            // update'i dene — UPDATE politikası mevcut satırı bulup yazar.
            debugPrint(
              'ℹ️ Self-heal yarışı (23505): satır oluşmuş, update ile devam.',
            );
            await client.from('profiles').update(locationPatch).eq('id', userId);
            return true;
          }
          debugPrint(
            '⚠️ profiles satırı oluşturma Postgrest hatası: '
            'code=${pe.code}, message=${pe.message}, details=${pe.details}, '
            'hint=${pe.hint}',
          );
          return false;
        }
      } catch (e) {
        if (e is PostgrestException) {
          debugPrint(
            '⚠️ Konum yazma denemesi $attempt/$maxAttempts Postgrest hatası: '
            'code=${e.code}, message=${e.message}, details=${e.details}, '
            'hint=${e.hint}',
          );
        } else {
          debugPrint(
            '⚠️ Konum yazma denemesi $attempt/$maxAttempts başarısız: $e',
          );
        }
        if (attempt < maxAttempts) {
          await Future.delayed(Duration(seconds: 2 * attempt));
        }
      }
    }
    return false;
  }

  /// Eksik profiles satırını auth kullanıcı meta verisinden oluşturur ve
  /// konumu yazar. handle_new_user trigger'ının yaptığı insert'i taklit eder
  /// (id, email, full_name, username) ve ek olarak role='courier' + konum
  /// alanlarını set eder. INSERT RLS kuralı (id = auth.uid()) kendi satırını
  /// eklemeye izin verir.
  ///
  /// Çağıran taraf `code=23505` (duplicate key) hatasını ayrıca yakalar;
  /// bu metot sadece insert denemesini yapar, hata kodlarını ayırt etmez.
  Future<void> _insertProfileRow(
    SupabaseClient client,
    String userId,
    Position position,
  ) async {
    final user = client.auth.currentUser;
    final email = user?.email ?? '';
    final meta = user?.userMetadata ?? const <String, dynamic>{};
    final fullName = (meta['full_name'] as String?) ??
        (meta['name'] as String?) ??
        '';
    final username = (meta['username'] as String?) ?? '';

    await client.from('profiles').insert({
      'id': userId,
      'email': email,
      'full_name': fullName,
      'username': username,
      'role': 'courier',
      'last_known_lat': position.latitude,
      'last_known_lng': position.longitude,
      'last_location_update': DateTime.now().toIso8601String(),
    });
  }

  Future<void> stopTracking() async {
    _isTracking = false;
    await _positionStream?.cancel();
    _updateTimer?.cancel();
    _positionStream = null;
    _updateTimer = null;
    // Bir sonraki takip oturumu, gerekirse self-heal'i tekrar deneyebilsin.
    _profileSelfHealAttempted = false;
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
