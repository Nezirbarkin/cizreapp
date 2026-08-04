// ignore_for_file: deprecated_member_use

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Tek bir kuryenin (role='courier') haritada gösterilecek kırpılmış bilgisi.
/// Konum paylaşımı açık olan kullanıcılar için geçerlidir; null lat/lng
/// olanlar haritaya hiç girmez, hizmet dışında tutulur.
/// NOT: phone alanı kaldırıldı; kurye telefon numarası artık public
/// akışta ifşa edilmez. Tam konum yerine yalnız approx_lat/lng (0.01
/// derece ~1.1 km karelaj) gösterilir.
class CourierInfo {
  final String id;
  final String name;
  final String? avatarUrl;
  final int deliveredCount;
  final double lat;
  final double lng;
  final DateTime? updatedAt;

  const CourierInfo({
    required this.id,
    required this.name,
    this.avatarUrl,
    this.deliveredCount = 0,
    required this.lat,
    required this.lng,
    this.updatedAt,
  });

  /// `get_nearby_couriers` RPC satırından kırpılmış kurye bilgisi üretir.
  /// lat/lng null olanlar `null` döner — hizmet bunları cache'e almaz.
  static CourierInfo? fromRow(Map<String, dynamic> row) {
    final lat = (row['approx_lat'] as num?)?.toDouble();
    final lng = (row['approx_lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return null;
    final id = row['id'] as String?;
    if (id == null) return null;
    return CourierInfo(
      id: id,
      name:
          (row['full_name'] as String?) ??
          (row['username'] as String?) ??
          'Kurye',
      avatarUrl: row['avatar_url'] as String?,
      deliveredCount: (row['delivered_count'] as num?)?.toInt() ?? 0,
      lat: lat,
      lng: lng,
      updatedAt: row['last_location_update'] != null
          ? DateTime.tryParse(row['last_location_update'] as String)
          : null,
    );
  }
}

/// Konum paylaşan kuryeler için tek doğruluk kaynağı.
///
/// • Singleton: uygulama ömrü boyunca tek bir realtime kanal ve tek cache.
/// • İlk abone geldiğinde `profiles` tablosunu role='courier' ile dinlemeye
///   başlar; son abone ayrılınca kanal kapatılır (refcount).
/// • Sütunlar veritabanında yoksa PostgrestException fırlatır; hizmet
///   progressively dar sütun setlerine düşer ki yeni eklenen sütunlar
///   (delivered_count, avatar_url, phone) prod'da hazır olmasa bile konum
///   gösterilsin.
/// • İstemciler `subscribe(onChange)` ile güncel `Map<id, CourierInfo>` alır.
class CourierStreamService {
  static final CourierStreamService _instance =
      CourierStreamService._internal();
  factory CourierStreamService() => _instance;
  CourierStreamService._internal();

  final SupabaseClient _client = Supabase.instance.client;
  final Map<String, CourierInfo> _cache = {};
  final List<void Function(Map<String, CourierInfo>)> _listeners = [];

  Timer? _pollTimer;
  StreamSubscription<List<Map<String, dynamic>>>? _channelSub;
  bool _bootstrapInFlight = false;
  String? _lastError;

  String? get lastError => _lastError;
  int get count => _cache.length;
  Map<String, CourierInfo> snapshot() => Map.unmodifiable(_cache);

  /// Güncel cache'i al ve değişikliklerde [onChange] çağrılsın. İlk
  /// dinleme yapıldığında akış başlatılır, son dinleme bırakıldığında
  /// kapatılır (refcount). Dönüş değeri olan fonksiyon unsubscribe için
  /// çağrılmalı.
  void subscribe(void Function(Map<String, CourierInfo>) onChange) {
    _listeners.add(onChange);
    // Anlık snapshot
    onChange(Map.unmodifiable(_cache));
    if (_channelSub == null) {
      _bootstrapAndStart();
    }
  }

  /// Dinlemeyi bırakır. Tüm istemciler ayrıldığında realtime kanal kapatılır.
  void unsubscribe(void Function(Map<String, CourierInfo>) onChange) {
    _listeners.remove(onChange);
    if (_listeners.isEmpty) {
      _channelSub?.cancel();
      _channelSub = null;
      _pollTimer?.cancel();
      _pollTimer = null;
    }
  }

  Future<void> _bootstrapAndStart() async {
    // İlk sorgu: cache'i doldur. Sonra periyodik poll ile güncelle.
    // (Realtime'dan profiles row payload almak PII sızdırır.)
    if (_bootstrapInFlight) return;
    _bootstrapInFlight = true;
    try {
      final rows = await _fetchCouriers();
      _mergeRows(rows);
      _emit();
    } catch (e) {
      _lastError = '$e';
      debugPrint('⚠️ CourierStreamService.bootstrap hatası: $e');
    } finally {
      _bootstrapInFlight = false;
    }

    // Periyodik poll: 30 saniyede bir cache'i güncelle. Realtime
    // yerine RPC poll tercih edildi; çünkü profiles tablosu için
    // SELECT grant'i REVOKE edildi ve realtime row payload'ı PII
    // sızdırır.
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      try {
        final rows = await _fetchCouriers();
        _mergeRows(rows);
        _emit();
      } catch (e) {
        debugPrint('⚠️ CourierStreamService.poll hatası: $e');
      }
    });
  }

  /// Kuryeleri getir. profiles tablosundan doğrudan SELECT yapılmaz;
  /// SECURITY DEFINER get_nearby_couriers() RPC'si kullanılır. RPC
  /// yalnız güvenli sütunları (id, full_name, username, avatar_url,
  /// delivered_count, yuvarlatılmış approx_lat/lng, last_location_update)
  /// döner; telefon/PII sızdırmaz, konum 0.01 derece (~1.1 km)
  /// karelajına yuvarlanır.
  Future<List<Map<String, dynamic>>> _fetchCouriers() async {
    try {
      final res = await _client.rpc<List<dynamic>>(
        'get_nearby_couriers',
        params: {'p_max_age_seconds': 600},
      );
      return List<Map<String, dynamic>>.from(res);
    } catch (e) {
      debugPrint('⚠️ CourierStreamService.get_nearby_couriers hatası: $e');
      return [];
    }
  }

  void _mergeRows(List<Map<String, dynamic>> rows) {
    // Realtime + bootstrap yarışı olabilir; cache'i tamamen bu kaynaktan
    // türetmek (sadece lat/lng paylaşanlar) yerine, "bu satır hâlâ geçerli
    // mi?" sorusunu sormalıyız. Realtime tek tablo olduğu için snapshot
    // her olayda tüm role='courier' satırlarını verir — bu yüzden
    // önce bu satırları cache'e yazıp, sonra "artık listede olmayan ama
    // cache'te duran" satırları çıkarmak daha doğru.
    final seen = <String>{};
    for (final row in rows) {
      final info = CourierInfo.fromRow(row);
      if (info == null) continue;
      _cache[info.id] = info;
      seen.add(info.id);
    }
    // Realtime snapshot tüm role='courier' satırlarını verdiği için
    // listede olmayan eski cache elemanlarını temizle. Bu, kurye
    // konum paylaşımını kapattığında (last_known_lat null olur) marker'ın
    // haritadan kaybolmasını sağlar.
    _cache.removeWhere((id, _) => !seen.contains(id));
  }

  void _emit() {
    final Map<String, CourierInfo> snap = Map<String, CourierInfo>.unmodifiable(
      Map<String, CourierInfo>.from(_cache),
    );
    for (final l in List<void Function(Map<String, CourierInfo>)>.from(
      _listeners,
    )) {
      try {
        l(snap);
      } catch (e) {
        debugPrint('⚠️ CourierStreamService listener hatası: $e');
      }
    }
  }
}
