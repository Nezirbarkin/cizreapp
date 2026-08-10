import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/sehirici_models.dart';

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

  Future<List<SehiriciLine>> getAllLinesAdmin(String cityId) async {
    try {
      final response = await _client
          .from('sehirici_lines')
          .select()
          .eq('city_id', cityId)
          .order('display_order', ascending: true);
      return (response as List)
          .map((e) => SehiriciLine.fromJson({
                ...e as Map<String, dynamic>,
                'stops': const [],
              }))
          .toList();
    } catch (e) {
      debugPrint('getAllLinesAdmin hata: $e');
      return [];
    }
  }

  Future<bool> upsertLine({
    String? id,
    required String cityId,
    required String code,
    required String name,
    required String colorHex,
    required SehiriciVehicleType vehicleType,
    int? estimatedMinutes,
    double fareAmount = 0,
    bool isActive = true,
    int displayOrder = 0,
  }) async {
    try {
      // RLS bypass: admin RPC üzerinden yaz
      final lineId = id ?? const Uuid().v4();
      await _client.rpc('admin_upsert_sehirici_line', params: {
        'p_id': lineId,
        'p_city_id': cityId,
        'p_code': code,
        'p_name': name,
        'p_color_hex': colorHex,
        'p_vehicle_type': vehicleType.name,
        'p_estimated_minutes': estimatedMinutes,
        'p_fare_amount': fareAmount,
        'p_is_active': isActive,
        'p_display_order': displayOrder,
      });
      clearCache();
      return true;
    } catch (e) {
      debugPrint('upsertLine hata: $e');
      return false;
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
      await _client.from('sehirici_lines').delete().eq('id', lineId);
      clearCache();
      return true;
    } catch (e) {
      debugPrint('deleteLine hata: $e');
      return false;
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
      final stopId = id ?? const Uuid().v4();
      await _client.rpc('admin_upsert_sehirici_stop', params: {
        'p_id': stopId,
        'p_city_id': cityId,
        'p_name': name,
        'p_code': code,
        'p_lat': lat,
        'p_lng': lng,
        'p_is_active': isActive,
      });
      clearCache();
      return true;
    } catch (e) {
      debugPrint('upsertStop hata: $e');
      return false;
    }
  }

  Future<bool> deleteStop(String stopId) async {
    try {
      await _client.rpc('admin_delete_sehirici_stop', params: {'p_id': stopId});
      clearCache();
      return true;
    } catch (e) {
      debugPrint('deleteStop hata: $e');
      return false;
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
      // Sil + yeniden ekle (basit ve güvenli)
      await _client.from('sehirici_line_stops').delete().eq('line_id', lineId);
      if (stops.isEmpty) {
        clearCache();
        return true;
      }
      final rows = stops
          .map((s) => {
                'line_id': lineId,
                'stop_id': s['stop_id'],
                'stop_order': s['stop_order'],
                'minutes_from_start': s['minutes_from_start'] ?? 0,
                'distance_km': s['distance_km'] ?? 0,
              })
          .toList();
      await _client.from('sehirici_line_stops').insert(rows);
      clearCache();
      return true;
    } catch (e) {
      debugPrint('setLineStops hata: $e');
      return false;
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
