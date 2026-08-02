import 'package:flutter/foundation.dart';
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
}

class _CacheEntry<T> {
  final T data;
  final DateTime timestamp;
  _CacheEntry(this.data, this.timestamp);
}
