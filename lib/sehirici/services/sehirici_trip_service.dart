import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/sehirici_models.dart';

/// Sefer yönetimi ve canlı konum servisi.
class SehiriciTripService {
  final SupabaseClient _client;
  SehiriciTripService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  // ─────────────────────────────────────────────
  // Şoför: Sefer Başlat / Bitir / Güncelle
  // ─────────────────────────────────────────────

  /// Yeni sefer başlatır. Önceki aktif sefer varsa otomatik kapatır.
  Future<String?> startTrip({
    required String driverId,
    required String lineId,
    required double lat,
    required double lng,
  }) async {
    try {
      final response = await _client.rpc('start_sehirici_trip', params: {
        'p_driver_id': driverId,
        'p_line_id': lineId,
        'p_initial_lat': lat,
        'p_initial_lng': lng,
      });
      return response as String?;
    } catch (e) {
      debugPrint('SehiriciTripService.startTrip hata: $e');
      return null;
    }
  }

  /// Konum güncelle (her 10 sn'de bir).
  Future<bool> updateLocation({
    required String tripId,
    required double lat,
    required double lng,
    double? heading,
    double? speed,
    int? passengerCount,
  }) async {
    try {
      await _client.rpc('update_sehirici_trip_location', params: {
        'p_trip_id': tripId,
        'p_lat': lat,
        'p_lng': lng,
        'p_heading': heading,
        'p_speed': speed,
        'p_passenger_count': passengerCount,
      });
      return true;
    } catch (e) {
      debugPrint('SehiriciTripService.updateLocation hata: $e');
      return false;
    }
  }

  Future<bool> setStatus(String tripId, SehiriciTripStatus status) async {
    try {
      await _client.rpc('set_sehirici_trip_status', params: {
        'p_trip_id': tripId,
        'p_new_status': status.dbValue,
      });
      return true;
    } catch (e) {
      debugPrint('SehiriciTripService.setStatus hata: $e');
      return false;
    }
  }

  /// Şoförün mevcut aktif seferini getir.
  Future<Map<String, dynamic>?> getDriverActiveTrip(String driverId) async {
    try {
      final response = await _client
          .from('sehirici_trips')
          .select('*')
          .eq('driver_id', driverId)
          .inFilter('status', ['active', 'paused'])
          .order('started_at', ascending: false)
          .limit(1)
          .maybeSingle();
      return response;
    } catch (e) {
      debugPrint('getDriverActiveTrip hata: $e');
      return null;
    }
  }

  /// Sıradaki durağı hesapla (RPC).
  Future<({String? stopId, String? name, int? etaMinutes})>
      computeNextStop(String tripId) async {
    try {
      final response = await _client.rpc('compute_sehirici_next_stop',
          params: {'p_trip_id': tripId});
      if (response is List && response.isNotEmpty) {
        final row = response.first as Map<String, dynamic>;
        return (
          stopId: row['next_stop_id'] as String?,
          name: row['next_stop_name'] as String?,
          etaMinutes: (row['eta_minutes'] as num?)?.toInt(),
        );
      }
      return (stopId: null, name: null, etaMinutes: null);
    } catch (e) {
      debugPrint('computeNextStop hata: $e');
      return (stopId: null, name: null, etaMinutes: null);
    }
  }

  // ───���─────────────────────────────────────────
  // Realtime: Aktif seferleri canlı izle (kullanıcı tarafı)
  // ─────────────────────────────────────────────

  // DİKKAT: aktif sefer ve konum yolu ayrı kanallarda tutulur. Eskiden tek
  // `_channel` alanını paylaştıkları için watchActiveTrips/watchTripPaths
  // birbirini unsubscribe ediyordu (kanal clobber bug'ı).
  RealtimeChannel? _activeTripsChannel;
  RealtimeChannel? _tripPathsChannel;

  /// Belirli bir şehrin aktif seferlerini realtime dinler.
  /// Eski aktif-sefer kanalı varsa kapatır.
  ///
  /// [onTripDelete] yalnızca satır silindiğinde değil, sefer *sonlandığında*
  /// (status 'completed'/'cancelled'/'planned' olduğunda) da çağrılır: seferler
  /// DB'den silinmez, status'ü değiştirilir. Eskiden bu olaylar sessizce
  /// yutuluyordu (`return`) ve biten araç haritada sonsuza kadar asılı kalıyordu.
  RealtimeChannel watchActiveTrips({
    String? cityId,
    required void Function(SehiriciActiveTrip trip) onTripUpdate,
    required void Function(String tripId) onTripDelete,
  }) {
    _activeTripsChannel?.unsubscribe();

    final ch = _client.channel('sehirici_active_trips_${cityId ?? 'all'}');

    ch.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'sehirici_trips',
      callback: (payload) {
        try {
          if (payload.eventType == PostgresChangeEvent.delete) {
            final oldId = payload.oldRecord['id'] as String?;
            if (oldId != null) onTripDelete(oldId);
            return;
          }
          final newRow = payload.newRecord;
          final status = newRow['status'] as String?;
          if (status != 'active' && status != 'paused') {
            // Sefer bitti/iptal edildi: satır silinmediği için DELETE olayı
            // gelmez. Haritadan/listeden düşmesi için kaldırma olarak yay.
            final id = newRow['id'] as String?;
            if (id != null) onTripDelete(id);
            return;
          }
          onTripUpdate(SehiriciActiveTrip(
            tripId: newRow['id'] as String,
            lineId: newRow['line_id'] as String,
            lineCode: '',
            lineName: '',
            lineColor: '#1976D2',
            currentLat: (newRow['current_lat'] as num?)?.toDouble(),
            currentLng: (newRow['current_lng'] as num?)?.toDouble(),
            currentHeading: (newRow['current_heading'] as num?)?.toDouble(),
            currentSpeed: (newRow['current_speed'] as num?)?.toDouble(),
            etaMinutes: (newRow['eta_minutes'] as num?)?.toInt(),
            nextStopId: newRow['next_stop_id'] as String?,
            status: SehiriciTripStatus.fromString(status),
          ));
        } catch (e) {
          debugPrint('Realtime trip callback hata: $e');
        }
      },
    );

    ch.subscribe();
    _activeTripsChannel = ch;
    return ch;
  }

  void stopWatching() {
    _activeTripsChannel?.unsubscribe();
    _tripPathsChannel?.unsubscribe();
    _activeTripsChannel = null;
    _tripPathsChannel = null;
  }

  // ─────────────────────────────────────────────
  // Seferin geçtiği yol (konum geçmişi)
  // ─────────────────────────────────────────────

  /// Belirli bir aktif seferin şoförünün geçtiği tüm konum noktalarını
  /// zaman sırasına göre döner. Polyline çizmek için kullanılır.
  Future<List<({double lat, double lng, DateTime recordedAt})>>
      getTripPath(String tripId) async {
    try {
      final response = await _client.rpc('get_sehirici_trip_path',
          params: {'p_trip_id': tripId});
      if (response is! List) return const [];
      return response
          .cast<Map<String, dynamic>>()
          .map((r) => (
                lat: (r['lat'] as num).toDouble(),
                lng: (r['lng'] as num).toDouble(),
                recordedAt: DateTime.parse(r['recorded_at'] as String),
              ))
          .toList();
    } catch (e) {
      debugPrint('getTripPath hata: $e');
      return const [];
    }
  }

  /// Aynı anda birden fazla [SehiriciLiveMap] mount olabildiği için (ana
  /// akıştaki compact kart + story kart + hatlar ekranı) kanal adı örnek
  /// başına benzersiz olmalı. Sabit "sehirici_trip_paths" adıyla, tek soket
  /// üzerinden aynı topic'e ikinci kez katılma denemesi Phoenix tarafında
  /// reddediliyor ve ikinci haritanın canlı yol polyline'ı hiç güncellenmiyordu.
  static int _tripPathsChannelSeq = 0;

  /// Birden fazla aktif seferin konum geçmişini realtime dinler.
  /// Yeni nokta geldiğinde `onPoint(tripId, lat, lng)` çağrılır.
  /// Eski konum-geçmişi kanalını kapatır (aktif-sefer kanalını BOZMAZ).
  RealtimeChannel watchTripPaths({
    required void Function(String tripId, double lat, double lng) onPoint,
  }) {
    _tripPathsChannel?.unsubscribe();

    final ch =
        _client.channel('sehirici_trip_paths_${_tripPathsChannelSeq++}');

    ch.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'sehirici_trip_locations',
      callback: (payload) {
        try {
          final newRow = payload.newRecord;
          final tripId = newRow['trip_id'] as String?;
          final lat = (newRow['lat'] as num?)?.toDouble();
          final lng = (newRow['lng'] as num?)?.toDouble();
          if (tripId != null && lat != null && lng != null) {
            onPoint(tripId, lat, lng);
          }
        } catch (e) {
          debugPrint('Realtime trip path callback hata: $e');
        }
      },
    );

    ch.subscribe();
    _tripPathsChannel = ch;
    return ch;
  }
}
