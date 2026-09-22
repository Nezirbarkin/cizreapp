import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/sehirici_models.dart';
import '../utils/sehirici_route_geometry.dart';
import 'sehirici_errors.dart';

/// Hatlar ve duraklar servisi.
class SehiriciLineService {
  final SupabaseClient _client;
  SehiriciLineService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  // Basit per-şehir cache (TTL: 5 dakika)
  static final Map<String, _CacheEntry<List<SehiriciLine>>> _lineCache = {};
  static const Duration _cacheTtl = Duration(minutes: 5);

  void clearCache() => _lineCache.clear();

  Future<List<SehiriciLine>> getLinesWithStops(
    String cityId, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final cached = _lineCache[cityId];
      if (cached != null &&
          DateTime.now().difference(cached.timestamp) < _cacheTtl) {
        return cached.data;
      }
    }

    try {
      final response =
          await _client.rpc('get_sehirici_lines_with_stops', params: {
        'p_city_id': cityId,
      });

      final list = (response as List)
          .map((e) => SehiriciLine.fromJson(e as Map<String, dynamic>))
          .toList();

      _lineCache[cityId] = _CacheEntry(list, DateTime.now());
      return list;
    } catch (e) {
      debugPrint('SehiriciLineService.getLinesWithStops hata: $e');
      return const [];
    }
  }

  Future<List<SehiriciActiveTrip>> getActiveTrips({String? cityId}) async {
    try {
      final response =
          await _client.rpc('get_sehirici_active_trips', params: {
        'p_city_id': cityId,
      });
      return (response as List)
          .map((e) =>
              SehiriciActiveTrip.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('SehiriciLineService.getActiveTrips hata: $e');
      return const [];
    }
  }

  Future<List<SehiriciActiveTrip>> getTripsForStop(String stopId) async {
    try {
      final response =
          await _client.rpc('get_sehirici_trips_for_stop', params: {
        'p_stop_id': stopId,
      });
      return (response as List)
          .map((e) =>
              SehiriciActiveTrip.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('SehiriciLineService.getTripsForStop hata: $e');
      return const [];
    }
  }

  // ─────────────────────────────────────────────
  // Admin CRUD — Hat
  // ─────────────────────────────────────────────

  /// Şehirdeki TÜM hatlar (pasifler dahil) DURAKLARIYLA birlikte.
  ///
  /// Eskiden duraklar hiç çekilmiyordu (`'stops': const []`), bu yüzden admin
  /// hat listesinde her hat "0 durak" görünüyordu ve rotanın güncelliği
  /// (durak imzası) hesaplanamıyordu.
  Future<List<SehiriciLine>> getAllLinesAdmin(String cityId) async {
    try {
      final response = await _client
          .from('sehirici_lines')
          .select(
            '*, sehirici_line_stops(stop_id, stop_order, minutes_from_start, '
            'distance_km, sehirici_stops(name, lat, lng, code, address))',
          )
          .eq('city_id', cityId)
          .order('display_order', ascending: true)
          .order('code', ascending: true);
      return (response as List).map((raw) {
        final row = Map<String, dynamic>.from(raw as Map);
        final nested = row.remove('sehirici_line_stops');
        final stops = <Map<String, dynamic>>[];
        if (nested is List) {
          for (final item in nested) {
            if (item is! Map) continue;
            final m = Map<String, dynamic>.from(item);
            final stop = m['sehirici_stops'] is Map
                ? Map<String, dynamic>.from(m['sehirici_stops'] as Map)
                : const <String, dynamic>{};
            stops.add({
              'stop_id': m['stop_id'],
              'stop_order': m['stop_order'],
              'minutes_from_start': m['minutes_from_start'],
              'distance_km': m['distance_km'],
              'name': stop['name'],
              'lat': stop['lat'],
              'lng': stop['lng'],
              'code': stop['code'],
              'address': stop['address'],
            });
          }
          stops.sort((a, b) => ((a['stop_order'] as num?) ?? 0)
              .compareTo((b['stop_order'] as num?) ?? 0));
        }
        return SehiriciLine.fromJson({...row, 'stops': stops});
      }).toList();
    } catch (e) {
      debugPrint('getAllLinesAdmin hata: $e');
      return [];
    }
  }

  /// Hattı kaydeder; başarısız olursa nedenini içeren [SehiriciAdminException]
  /// fırlatır (boş kod, çakışan kod, geçersiz renk/tür…). [vehicleKey] ikon
  /// kütüphanesindeki anahtardır. [displayOrder] null ise mevcut sıra korunur
  /// (yeni hat listenin sonuna eklenir).
  Future<String> saveLine({
    String? id,
    required String cityId,
    required String code,
    required String name,
    required String colorHex,
    required String vehicleKey,
    int? estimatedMinutes,
    double fareAmount = 0,
    bool isActive = true,
    int? displayOrder,
  }) async {
    try {
      final lineId = id ?? const Uuid().v4();
      await _client.rpc('admin_upsert_sehirici_line', params: {
        'p_id': lineId,
        'p_city_id': cityId,
        'p_code': code.trim(),
        'p_name': name.trim(),
        'p_color_hex': colorHex.trim(),
        'p_vehicle_type': vehicleKey,
        'p_estimated_minutes': estimatedMinutes,
        'p_fare_amount': fareAmount,
        'p_is_active': isActive,
        'p_display_order': displayOrder,
      });
      clearCache();
      return lineId;
    } catch (e) {
      debugPrint('saveLine hata: $e');
      throw SehiriciAdminException(sehiriciErrorMessage(e));
    }
  }

  /// Eski imza: yalnız başarı bilgisi döner. Yeni kod [saveLine] kullanmalı.
  Future<bool> upsertLine({
    String? id,
    required String cityId,
    required String code,
    required String name,
    required String colorHex,
    required SehiriciVehicleType vehicleType,
    String? vehicleKey,
    int? estimatedMinutes,
    double fareAmount = 0,
    bool isActive = true,
    int? displayOrder,
  }) async {
    try {
      await saveLine(
        id: id,
        cityId: cityId,
        code: code,
        name: name,
        colorHex: colorHex,
        vehicleKey: vehicleKey ?? vehicleType.name,
        estimatedMinutes: estimatedMinutes,
        fareAmount: fareAmount,
        isActive: isActive,
        displayOrder: displayOrder,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Hatların listedeki sırasını tek çağrıyla kaydeder ([lineIds] görüntüleme
  /// sırasıdır).
  Future<void> reorderLines(String cityId, List<String> lineIds) async {
    try {
      await _client.rpc('admin_reorder_sehirici_lines', params: {
        'p_city_id': cityId,
        'p_line_ids': lineIds,
      });
      clearCache();
    } catch (e) {
      debugPrint('reorderLines hata: $e');
      throw SehiriciAdminException(sehiriciErrorMessage(e));
    }
  }

  Future<bool> updateLineActive(String lineId, bool isActive) async {
    try {
      await _client
          .from('sehirici_lines')
          .update({'is_active': isActive}).eq('id', lineId);
      clearCache();
      return true;
    } catch (e) {
      debugPrint('updateLineActive hata: $e');
      return false;
    }
  }

  Future<bool> deleteLine(String lineId) async {
    try {
      await deleteLineOrThrow(lineId);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Hattı ve (CASCADE ile) duraklarla bağını siler. Bu hatta atanmış
  /// şoförlerin ataması boşa düşer (FK: ON DELETE SET NULL).
  Future<void> deleteLineOrThrow(String lineId) async {
    try {
      await _client.rpc('admin_delete_sehirici_line', params: {'p_id': lineId});
      clearCache();
    } catch (e) {
      debugPrint('deleteLine hata: $e');
      throw SehiriciAdminException(sehiriciErrorMessage(e));
    }
  }

  // ─────────────────────────────────────────────
  // Admin CRUD — Durak
  // ─────────────────────────────────────────────

  Future<List<SehiriciStop>> getStopsByCity(String cityId) async {
    try {
      final response = await _client
          .from('sehirici_stops')
          .select()
          .eq('city_id', cityId)
          .order('name', ascending: true);
      return (response as List)
          .map((e) => SehiriciStop.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('getStopsByCity hata: $e');
      return [];
    }
  }

  Future<bool> upsertStop({
    String? id,
    required String cityId,
    required String name,
    String? code,
    required double lat,
    required double lng,
    String? address,
    bool isActive = true,
  }) async {
    try {
      await saveStop(
        id: id,
        cityId: cityId,
        name: name,
        code: code,
        lat: lat,
        lng: lng,
        address: address,
        isActive: isActive,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Durağı kaydeder; başarısız olursa [SehiriciAdminException] fırlatır.
  /// Kaydedilen durağın id'sini döner.
  Future<String> saveStop({
    String? id,
    required String cityId,
    required String name,
    String? code,
    required double lat,
    required double lng,
    String? address,
    bool isActive = true,
  }) async {
    if (name.trim().isEmpty) {
      throw const SehiriciAdminException('Durak adı boş olamaz.');
    }
    if (!lat.isFinite || !lng.isFinite || lat.abs() > 90 || lng.abs() > 180) {
      throw const SehiriciAdminException('Geçerli bir konum girin.');
    }
    try {
      final stopId = id ?? const Uuid().v4();
      await _client.rpc('admin_upsert_sehirici_stop', params: {
        'p_id': stopId,
        'p_city_id': cityId,
        'p_name': name,
        'p_code': code,
        'p_lat': lat,
        'p_lng': lng,
        'p_is_active': isActive,
        // BUG FIX: `address` parametre olarak alınıyordu ama RPC'ye hiç
        // gönderilmiyordu — admin panelindeki "Adres" alanı sessizce
        // kayboluyordu. RPC'ye p_address 20260819000004 ile eklendi.
        'p_address': address,
      });
      clearCache();
      return stopId;
    } catch (e) {
      debugPrint('saveStop hata: $e');
      throw SehiriciAdminException(sehiriciErrorMessage(e));
    }
  }

  Future<bool> deleteStop(String stopId) async {
    try {
      await deleteStopOrThrow(stopId);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Durağı siler. Bir hatta bağlıysa o hattın durak listesinden de
  /// (CASCADE ile) çıkar — çağıran bunu kullanıcıya önceden söylemeli.
  Future<void> deleteStopOrThrow(String stopId) async {
    try {
      await _client.rpc('admin_delete_sehirici_stop', params: {'p_id': stopId});
      clearCache();
    } catch (e) {
      debugPrint('deleteStop hata: $e');
      throw SehiriciAdminException(sehiriciErrorMessage(e));
    }
  }

  // ─────────────────────────────────────────────
  // Hat-Durak sıralaması
  // ─────────────────────────────────────────────

  Future<List<SehiriciLineStop>> getLineStops(String lineId) async {
    try {
      final response = await _client
          .from('sehirici_line_stops')
          .select('stop_id, stop_order, minutes_from_start, distance_km, '
              'sehirici_stops!inner(name, lat, lng)')
          .eq('line_id', lineId)
          .order('stop_order', ascending: true);

      return (response as List).map((e) {
        final m = e as Map<String, dynamic>;
        final stops = m['sehirici_stops'] as Map<String, dynamic>?;
        return SehiriciLineStop(
          stopId: m['stop_id'] as String,
          stopOrder: (m['stop_order'] as num?)?.toInt() ?? 0,
          minutesFromStart: (m['minutes_from_start'] as num?)?.toInt() ?? 0,
          distanceKm: (m['distance_km'] as num?)?.toDouble(),
          name: stops?['name'] as String? ?? 'Durak',
          lat: (stops?['lat'] as num?)?.toDouble() ?? 0,
          lng: (stops?['lng'] as num?)?.toDouble() ?? 0,
        );
      }).toList();
    } catch (e) {
      debugPrint('getLineStops hata: $e');
      return [];
    }
  }

  Future<bool> setLineStops(
    String lineId,
    List<Map<String, dynamic>> stops,
  ) async {
    try {
      await setLineStopsOrThrow(lineId, stops);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Hattın duraklarını TEK İŞLEMDE değiştirir (`admin_set_sehirici_line_stops`).
  ///
  /// Eskiden "önce hepsini sil, sonra yeniden ekle" diye iki ayrı istek
  /// atılıyordu; ikincisi başarısız olursa hat DURAKSIZ kalıyordu. Sunucu
  /// işlevi silme + eklemeyi birlikte yapar: hata olursa eski duraklar korunur.
  Future<void> setLineStopsOrThrow(
    String lineId,
    List<Map<String, dynamic>> stops,
  ) async {
    try {
      await _client.rpc('admin_set_sehirici_line_stops', params: {
        'p_line_id': lineId,
        'p_stops': stops
            .map((s) => {
                  'stop_id': s['stop_id'],
                  'stop_order': s['stop_order'],
                  'minutes_from_start': s['minutes_from_start'] ?? 0,
                  'distance_km': s['distance_km'] ?? 0,
                })
            .toList(),
      });
      clearCache();
    } catch (e) {
      debugPrint('setLineStops hata: $e');
      throw SehiriciAdminException(sehiriciErrorMessage(e));
    }
  }

  // ─────────────────────────────────────────────
  // Yol-takip eden rota önbelleği (admin tarafından elle çizilir)
  // ─────────────────────────────────────────────

  /// Durak sırasına karşılık gelen imzayı (stop_id'lerin stop_order'a göre
  /// virgülle birleştirilmiş hâlinin md5'i) üretir. RPC tarafında da
  /// aynı hesaplama yapıldığı için birebir aynı sonucu verir.
  /// Static: instance durumu kullanmaz, böylece Supabase başlatılmadan
  /// test edilebilir.
  static String computeStopsSignature(List<SehiriciLineStop> stopsInOrder) {
    final joined = stopsInOrder.map((s) => s.stopId).join(',');
    return md5.convert(utf8.encode(joined)).toString();
  }

  /// Admin'in elle çizdiği (veya OSRM'den gelen) yol-takip eden rotayı
  /// `sehirici_lines.route_polyline` JSONB alanına yazar. `source` sadece
  /// metadata — model bu alanı kullanmıyor, sadece noktaları okuyor.
  /// Returns: başarılıysa true, durak imzası uyuşmazsa veya hata olursa false.
  Future<bool> cacheRoutePolyline({
    required String lineId,
    required List<SehiriciLineStop> lineStopsInOrder,
    required List<List<double>> points,
    String source = 'manual',
  }) async {
    if (points.length < 2) {
      debugPrint('cacheRoutePolyline: en az 2 nokta gerekli');
      return false;
    }
    try {
      final signature = computeStopsSignature(lineStopsInOrder);
      await _client.rpc('cache_sehirici_route_polyline', params: {
        'p_line_id': lineId,
        'p_stops_signature': signature,
        'p_polyline': {
          'points': points,
          'stops_signature': signature,
          'source': source,
          'cached_at': DateTime.now().toIso8601String(),
        },
      });
      clearCache();
      return true;
    } catch (e) {
      debugPrint('cacheRoutePolyline hata: $e');
      return false;
    }
  }

  /// route_polyline alanını temizler (admin "rotayı sil" derse).
  Future<bool> clearRoutePolyline(String lineId) async {
    try {
      // Mevcut RPC sadece INSERT/UPDATE yapıyor, null geçemeyiz.
      // RLS bypass için aynı RPC'yi boş nokta listesi ile çağırmak
      // imzayı da bozar — bunun yerine doğrudan UPDATE (admin RLS'i var).
      // Önce durak imzasını al:
      final stops = await getLineStops(lineId);
      if (stops.isEmpty) {
        // Durak yoksa imza üretilemez; sadece UPDATE dene
        await _client
            .from('sehirici_lines')
            .update({'route_polyline': null}).eq('id', lineId);
        clearCache();
        return true;
      }
      final signature = computeStopsSignature(stops);
      await _client.rpc('cache_sehirici_route_polyline', params: {
        'p_line_id': lineId,
        'p_stops_signature': signature,
        'p_polyline': {
          'points': <List<double>>[],
          'stops_signature': signature,
          'source': 'cleared',
          'cached_at': DateTime.now().toIso8601String(),
        },
      });
      clearCache();
      return true;
    } catch (e) {
      debugPrint('clearRoutePolyline hata: $e');
      return false;
    }
  }

  // ─────────────────────────────────────────────
  // Toplu rota bakımı (admin ayarlar sekmesi)
  // ─────────────────────────────────────────────

  /// Kayıtlı rotası olan tüm hatları (şehirden bağımsız) döner.
  /// Yalnız toplu bakım işlemleri için — normal akış şehir bazlı okur.
  Future<List<({String id, String code, String name, List<LatLng> points})>>
      getLinesWithRoute() async {
    try {
      final response = await _client
          .from('sehirici_lines')
          .select('id,code,name,route_polyline')
          .not('route_polyline', 'is', null)
          .order('code', ascending: true);

      final out = <({String id, String code, String name, List<LatLng> points})>[];
      for (final row in (response as List).cast<Map<String, dynamic>>()) {
        final raw = row['route_polyline'];
        if (raw is! Map) continue;
        final pts = raw['points'];
        if (pts is! List) continue;
        final points = pts
            .whereType<List>()
            .where((p) => p.length == 2)
            .map((p) => LatLng(
                  (p[0] as num).toDouble(),
                  (p[1] as num).toDouble(),
                ))
            .toList();
        if (points.isEmpty) continue; // 'cleared' kaydı — rotası yok sayılır
        out.add((
          id: row['id'] as String,
          code: row['code'] as String? ?? '',
          name: row['name'] as String? ?? '',
          points: points,
        ));
      }
      return out;
    } catch (e) {
      debugPrint('getLinesWithRoute hata: $e');
      return const [];
    }
  }

  /// Kayıtlı rotası olan TÜM hatların rotasını siler.
  /// Returns: (silinen hat sayısı, başarısız hat sayısı).
  Future<({int cleared, int failed})> clearAllRoutePolylines() async {
    final lines = await getLinesWithRoute();
    var cleared = 0;
    var failed = 0;
    for (final line in lines) {
      if (await clearRoutePolyline(line.id)) {
        cleared++;
      } else {
        failed++;
      }
    }
    clearCache();
    return (cleared: cleared, failed: failed);
  }

  /// Kayıtlı rotaları [sanitizeRoutePolyline] ile temizleyip geri yazar.
  ///
  /// Rota silinmez — yalnız GPS gürültüsü (üst üste binen noktalar ve
  /// "git-gel" yapan aykırı fixler) ayıklanır. Nokta sayısı değişmeyen
  /// hatlar zaten temiz demektir; boşuna yazma yapılmaz.
  ///
  /// Returns: her hat için (kod, önceki nokta, sonraki nokta) raporu.
  Future<List<({String code, int before, int after, bool saved})>>
      sanitizeAllRoutePolylines() async {
    final lines = await getLinesWithRoute();
    final report = <({String code, int before, int after, bool saved})>[];

    for (final line in lines) {
      final cleaned = sanitizeRoutePolyline(line.points);
      // Temizlik bir şey değiştirmediyse ya da rotayı yok ettiyse dokunma:
      // 2 noktanın altına düşen bir sonuç kaydedilirse hat rotasız kalır.
      if (cleaned.length == line.points.length || cleaned.length < 2) {
        report.add((
          code: line.code,
          before: line.points.length,
          after: line.points.length,
          saved: false,
        ));
        continue;
      }

      final stops = await getLineStops(line.id);
      final saved = await cacheRoutePolyline(
        lineId: line.id,
        lineStopsInOrder: stops,
        points: cleaned
            .map((p) => <double>[p.latitude, p.longitude])
            .toList(growable: false),
        source: 'admin_sanitized',
      );
      report.add((
        code: line.code,
        before: line.points.length,
        after: cleaned.length,
        saved: saved,
      ));
    }
    clearCache();
    return report;
  }

  /// Hattın en son 'completed' seferine ait GPS noktalarını zaman sırasına
  /// göre döner. Admin draw aracı "Son Seferden Öner" akışı için kullanır —
  /// noktaları Douglas-Peucker ile sadeleştirip `route_polyline` olarak
  /// yazabilir. Hata veya sonuç yoksa boş liste döner.
  Future<List<LatLng>> getLatestCompletedTripPath(String lineId) async {
    try {
      final response = await _client.rpc(
        'get_sehirici_latest_completed_trip_path',
        params: {'p_line_id': lineId},
      );
      if (response is! List) return const [];
      return response
          .cast<Map<String, dynamic>>()
          .map((r) => LatLng(
                (r['lat'] as num).toDouble(),
                (r['lng'] as num).toDouble(),
              ))
          .toList();
    } catch (e) {
      debugPrint('getLatestCompletedTripPath hata: $e');
      return const [];
    }
  }
}

class _CacheEntry<T> {
  final T data;
  final DateTime timestamp;
  _CacheEntry(this.data, this.timestamp);
}
