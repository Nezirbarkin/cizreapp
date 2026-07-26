import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/sehirici_route_model.dart';

/// Rota yönetim servisi
class SehiriciRouteService {
  final SupabaseClient _client;
  SehiriciRouteService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  /// Hat için rota oluştur (planlanmış rota - durakları çizerek)
  Future<SehiriciRoute?> createLineRoute(String lineId) async {
    try {
      // Hatın duraklarını al
      final stopsResponse = await _client.from('sehirici_line_stops').select(
            'stop_id, stop_order, sehirici_stops(lat, lng, name)',
          ).eq('line_id', lineId).order('stop_order');

      // Rota noktalarını oluştur
      List<RoutePoint> points = [];
      for (int i = 0; i < (stopsResponse as List).length; i++) {
        final stop = stopsResponse[i];
        final stopData = stop['sehirici_stops'] as Map?;

        points.add(RoutePoint(
          order: i,
          lat: (stopData?['lat'] as num?)?.toDouble() ?? 0,
          lng: (stopData?['lng'] as num?)?.toDouble() ?? 0,
          stopId: stop['stop_id'] as String?,
          timestamp: DateTime.now(),
        ));
      }

      // Veritabanında rota kayıt et
      final routeResponse = await _client.from('sehirici_routes').insert({
        'line_id': lineId,
        'points': points.map((p) => p.toJson()).toList(),
        'status': RouteStatus.draft.dbValue,
      }).select().single();

      return SehiriciRoute.fromJson(routeResponse);
    } catch (e) {
      debugPrint('createLineRoute hata: $e');
      return null;
    }
  }

  /// Sefer başlat (rota aktif olur)
  Future<bool> startRoute(
    String routeId,
    String driverId,
  ) async {
    try {
      await _client.from('sehirici_routes').update({
        'status': RouteStatus.active.dbValue,
        'driver_id': driverId,
        'started_at': DateTime.now().toIso8601String(),
      }).eq('id', routeId);

      return true;
    } catch (e) {
      debugPrint('startRoute hata: $e');
      return false;
    }
  }

  /// Rota noktasını güncelle (konum takibi)
  Future<bool> updateRoutePoint(
    String routeId,
    int order,
    double lat,
    double lng,
    double? accuracy,
  ) async {
    try {
      // Mevcut rota noktalarını al
      final routeResponse = await _client
          .from('sehirici_routes')
          .select('points')
          .eq('id', routeId)
          .single();

      final points =
          (routeResponse['points'] as List?)?.cast<Map<String, dynamic>>() ?? [];

      // İlgili noktayı güncelle
      if (order < points.length) {
        points[order] = {
          ...points[order],
          'lat': lat,
          'lng': lng,
          'accuracy': accuracy,
          'timestamp': DateTime.now().toIso8601String(),
        };
      }

      await _client
          .from('sehirici_routes')
          .update({'points': points}).eq('id', routeId);

      return true;
    } catch (e) {
      debugPrint('updateRoutePoint hata: $e');
      return false;
    }
  }

  /// Rotayı tamamla
  Future<bool> completeRoute(String routeId) async {
    try {
      await _client.from('sehirici_routes').update({
        'status': RouteStatus.completed.dbValue,
        'completed_at': DateTime.now().toIso8601String(),
      }).eq('id', routeId);

      return true;
    } catch (e) {
      debugPrint('completeRoute hata: $e');
      return false;
    }
  }

  /// Rotayı iptal et
  Future<bool> cancelRoute(String routeId) async {
    try {
      await _client.from('sehirici_routes').update({
        'status': RouteStatus.cancelled.dbValue,
      }).eq('id', routeId);

      return true;
    } catch (e) {
      debugPrint('cancelRoute hata: $e');
      return false;
    }
  }

  /// Hat için aktif rotayı getir
  Future<SehiriciRoute?> getActiveRoute(String lineId) async {
    try {
      final response = await _client
          .from('sehirici_routes')
          .select()
          .eq('line_id', lineId)
          .eq('status', RouteStatus.active.dbValue)
          .maybeSingle();

      if (response == null) return null;
      return SehiriciRoute.fromJson(response);
    } catch (e) {
      debugPrint('getActiveRoute hata: $e');
      return null;
    }
  }

  /// Hat için tüm rotaları getir
  Future<List<SehiriciRoute>> getLineRoutes(String lineId) async {
    try {
      final response = await _client
          .from('sehirici_routes')
          .select()
          .eq('line_id', lineId)
          .order('created_at', ascending: false);

      return (response as List)
          .map((r) => SehiriciRoute.fromJson(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('getLineRoutes hata: $e');
      return [];
    }
  }

  /// Rotayı sil (admin)
  Future<bool> deleteRoute(String routeId) async {
    try {
      await _client.from('sehirici_routes').delete().eq('id', routeId);
      return true;
    } catch (e) {
      debugPrint('deleteRoute hata: $e');
      return false;
    }
  }

  /// Birden fazla rotayı sil (linedeki diğer rotalar)
  Future<bool> deleteOtherRoutes(String lineId, String keepRouteId) async {
    try {
      await _client
          .from('sehirici_routes')
          .delete()
          .eq('line_id', lineId)
          .neq('id', keepRouteId);
      return true;
    } catch (e) {
      debugPrint('deleteOtherRoutes hata: $e');
      return false;
    }
  }
}
