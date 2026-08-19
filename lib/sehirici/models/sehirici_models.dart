// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';

/// Şehir içi servis modülü — veri modelleri.

enum SehiriciVehicleType {
  minibus,
  bus,
  midibus,
  dolmus,
  tram,
  other;

  static SehiriciVehicleType fromString(String? s) {
    switch (s) {
      case 'minibus':
        return SehiriciVehicleType.minibus;
      case 'bus':
        return SehiriciVehicleType.bus;
      case 'midibus':
        return SehiriciVehicleType.midibus;
      case 'dolmus':
        return SehiriciVehicleType.dolmus;
      case 'tram':
        return SehiriciVehicleType.tram;
      default:
        return SehiriciVehicleType.other;
    }
  }

  String get label {
    switch (this) {
      case SehiriciVehicleType.minibus:
        return 'Minibüs';
      case SehiriciVehicleType.bus:
        return 'Otobüs';
      case SehiriciVehicleType.midibus:
        return 'Midibüs';
      case SehiriciVehicleType.dolmus:
        return 'Dolmuş';
      case SehiriciVehicleType.tram:
        return 'Tramvay';
      case SehiriciVehicleType.other:
        return 'Diğer';
    }
  }

  IconData get icon {
    switch (this) {
      case SehiriciVehicleType.minibus:
        return Icons.airport_shuttle;
      case SehiriciVehicleType.bus:
        return Icons.directions_bus;
      case SehiriciVehicleType.midibus:
        return Icons.directions_bus_filled;
      case SehiriciVehicleType.dolmus:
        return Icons.local_taxi;
      case SehiriciVehicleType.tram:
        return Icons.tram;
      case SehiriciVehicleType.other:
        return Icons.commute;
    }
  }

  Color get iconColor {
    switch (this) {
      case SehiriciVehicleType.minibus:
        return const Color(0xFF4CAF50); // Yeşil
      case SehiriciVehicleType.bus:
        return const Color(0xFF2196F3); // Mavi
      case SehiriciVehicleType.midibus:
        return const Color(0xFF1976D2); // Koyu Mavi
      case SehiriciVehicleType.dolmus:
        return const Color(0xFFFFC107); // Sarı
      case SehiriciVehicleType.tram:
        return const Color(0xFFE53935); // Kırmızı
      case SehiriciVehicleType.other:
        return const Color(0xFF757575); // Gri
    }
  }
}

enum SehiriciTripStatus {
  planned,
  active,
  paused,
  completed,
  cancelled;

  static SehiriciTripStatus fromString(String? s) {
    switch (s) {
      case 'planned':
        return SehiriciTripStatus.planned;
      case 'active':
        return SehiriciTripStatus.active;
      case 'paused':
        return SehiriciTripStatus.paused;
      case 'completed':
        return SehiriciTripStatus.completed;
      case 'cancelled':
        return SehiriciTripStatus.cancelled;
      default:
        return SehiriciTripStatus.planned;
    }
  }

  String get dbValue => name;

  String get label {
    switch (this) {
      case SehiriciTripStatus.planned:
        return 'Planlandı';
      case SehiriciTripStatus.active:
        return 'Yolda';
      case SehiriciTripStatus.paused:
        return 'Mola';
      case SehiriciTripStatus.completed:
        return 'Tamamlandı';
      case SehiriciTripStatus.cancelled:
        return 'İptal';
    }
  }
}

class SehiriciCity {
  final String id;
  final String name;
  final String slug;
  final double centerLat;
  final double centerLng;
  final int zoomLevel;
  final bool isActive;

  const SehiriciCity({
    required this.id,
    required this.name,
    required this.slug,
    required this.centerLat,
    required this.centerLng,
    this.zoomLevel = 13,
    this.isActive = true,
  });

  factory SehiriciCity.fromJson(Map<String, dynamic> json) {
    return SehiriciCity(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      slug: json['slug'] as String? ?? '',
      centerLat: (json['center_lat'] as num?)?.toDouble() ?? 0,
      centerLng: (json['center_lng'] as num?)?.toDouble() ?? 0,
      zoomLevel: (json['zoom_level'] as num?)?.toInt() ?? 13,
      isActive: json['is_active'] as bool? ?? true,
    );
  }
}

class SehiriciStop {
  final String id;
  final String name;
  final String? code;
  final double lat;
  final double lng;
  final String? address;
  final bool isActive;

  const SehiriciStop({
    required this.id,
    required this.name,
    this.code,
    required this.lat,
    required this.lng,
    this.address,
    this.isActive = true,
  });

  factory SehiriciStop.fromJson(Map<String, dynamic> json) {
    return SehiriciStop(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Durak',
      code: json['code'] as String?,
      lat: (json['lat'] as num?)?.toDouble() ?? 0,
      lng: (json['lng'] as num?)?.toDouble() ?? 0,
      address: json['address'] as String?,
      isActive: json['is_active'] as bool? ?? true,
    );
  }
}

/// Hat-durak ilişkisindeki durak (sıra + ETA bilgisi ile).
class SehiriciLineStop {
  final String stopId;
  final int stopOrder;
  final int minutesFromStart;
  final double? distanceKm;
  final String name;
  final double lat;
  final double lng;

  const SehiriciLineStop({
    required this.stopId,
    required this.stopOrder,
    required this.minutesFromStart,
    this.distanceKm,
    required this.name,
    required this.lat,
    required this.lng,
  });

  factory SehiriciLineStop.fromJson(Map<String, dynamic> json) {
    return SehiriciLineStop(
      stopId: json['stop_id'] as String,
      stopOrder: (json['stop_order'] as num?)?.toInt() ?? 0,
      minutesFromStart: (json['minutes_from_start'] as num?)?.toInt() ?? 0,
      distanceKm: (json['distance_km'] as num?)?.toDouble(),
      name: json['name'] as String? ?? 'Durak',
      lat: (json['lat'] as num?)?.toDouble() ?? 0,
      lng: (json['lng'] as num?)?.toDouble() ?? 0,
    );
  }

  SehiriciStop get asStop => SehiriciStop(
        id: stopId,
        name: name,
        lat: lat,
        lng: lng,
      );
}

class SehiriciLine {
  final String id;
  final String code;
  final String name;
  final String colorHex;
  final SehiriciVehicleType vehicleType;
  final int? estimatedMinutes;
  final double fareAmount;
  final bool isActive;
  final List<SehiriciLineStop> stops;
  /// Önbelleğe alınmış yol-takip eden rota noktaları ([lat, lng] çiftleri).
  /// null ise henüz hesaplanmamış — SehiriciLineService.getRoadRoute ile
  /// hesaplanıp sehirici_lines.route_polyline'a kaydedilir.
  final List<List<double>>? roadPolyline;

  const SehiriciLine({
    required this.id,
    required this.code,
    required this.name,
    this.colorHex = '#1976D2',
    this.vehicleType = SehiriciVehicleType.bus,
    this.estimatedMinutes,
    this.fareAmount = 0,
    this.isActive = true,
    this.stops = const [],
    this.roadPolyline,
  });

  Color get color {
    try {
      return Color(int.parse(colorHex.replaceFirst('#', '0xFF')));
    } catch (_) {
      return const Color(0xFF1976D2);
    }
  }

  factory SehiriciLine.fromJson(Map<String, dynamic> json) {
    final stopsRaw = json['stops'];
    List<SehiriciLineStop> stops = const [];
    if (stopsRaw is List) {
      stops = stopsRaw
          .map((e) => SehiriciLineStop.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    List<List<double>>? roadPolyline;
    final polylineRaw = json['route_polyline'];
    if (polylineRaw is Map) {
      final pts = polylineRaw['points'];
      if (pts is List) {
        roadPolyline = pts
            .whereType<List>()
            .map((p) => p.map((v) => (v as num).toDouble()).toList())
            .where((p) => p.length == 2)
            .toList();
      }
    }

    return SehiriciLine(
      id: json['line_id'] as String? ?? json['id'] as String,
      code: json['code'] as String? ?? '',
      name: json['name'] as String? ?? '',
      colorHex: json['color_hex'] as String? ?? '#1976D2',
      vehicleType: SehiriciVehicleType.fromString(
          json['vehicle_type'] as String?),
      estimatedMinutes: (json['estimated_minutes'] as num?)?.toInt(),
      fareAmount: (json['fare_amount'] as num?)?.toDouble() ?? 0,
      isActive: json['is_active'] as bool? ?? true,
      stops: stops,
      roadPolyline: roadPolyline,
    );
  }
}

/// Aktif sefer özeti (canlı konum + sıradaki durak + ETA).
class SehiriciActiveTrip {
  final String tripId;
  final String lineId;
  final String lineCode;
  final String lineName;
  final String lineColor;
  final String? driverName;
  final String? licensePlate;
  final TimeOfDay? workingHoursStart;
  final TimeOfDay? workingHoursEnd;
  final double? currentLat;
  final double? currentLng;
  final double? currentHeading;
  final double? currentSpeed;
  final DateTime? startedAt;
  final String? nextStopId;
  final String? nextStopName;
  final double? nextStopLat;
  final double? nextStopLng;
  final int? etaMinutes;
  final SehiriciTripStatus status;

  const SehiriciActiveTrip({
    required this.tripId,
    required this.lineId,
    required this.lineCode,
    required this.lineName,
    required this.lineColor,
    this.driverName,
    this.licensePlate,
    this.workingHoursStart,
    this.workingHoursEnd,
    this.currentLat,
    this.currentLng,
    this.currentHeading,
    this.currentSpeed,
    this.startedAt,
    this.nextStopId,
    this.nextStopName,
    this.nextStopLat,
    this.nextStopLng,
    this.etaMinutes,
    this.status = SehiriciTripStatus.active,
  });

  Color get color {
    try {
      return Color(int.parse(lineColor.replaceFirst('#', '0xFF')));
    } catch (_) {
      return const Color(0xFF1976D2);
    }
  }

  factory SehiriciActiveTrip.fromJson(Map<String, dynamic> json) {
    TimeOfDay? parseTimeOfDay(String? timeStr) {
      if (timeStr == null) return null;
      final parts = timeStr.split(':');
      if (parts.length < 2) return null;
      return TimeOfDay(hour: int.tryParse(parts[0]) ?? 0, minute: int.tryParse(parts[1]) ?? 0);
    }

    return SehiriciActiveTrip(
      tripId: json['trip_id'] as String? ?? json['id'] as String,
      lineId: json['line_id'] as String,
      lineCode: json['line_code'] as String? ?? '',
      lineName: json['line_name'] as String? ?? '',
      lineColor: json['line_color'] as String? ?? '#1976D2',
      driverName: json['driver_name'] as String?,
      licensePlate: json['license_plate'] as String?,
      workingHoursStart: parseTimeOfDay(json['working_hours_start'] as String?),
      workingHoursEnd: parseTimeOfDay(json['working_hours_end'] as String?),
      currentLat: (json['current_lat'] as num?)?.toDouble(),
      currentLng: (json['current_lng'] as num?)?.toDouble(),
      currentHeading: (json['current_heading'] as num?)?.toDouble(),
      currentSpeed: (json['current_speed'] as num?)?.toDouble(),
      startedAt: json['started_at'] != null
          ? DateTime.tryParse(json['started_at'] as String)
          : null,
      nextStopId: json['next_stop_id'] as String?,
      nextStopName: json['next_stop_name'] as String?,
      nextStopLat: (json['next_stop_lat'] as num?)?.toDouble(),
      nextStopLng: (json['next_stop_lng'] as num?)?.toDouble(),
      etaMinutes: (json['eta_minutes'] as num?)?.toInt(),
      status: SehiriciTripStatus.fromString(json['status'] as String?),
    );
  }

  /// Hafif kopya: sadece harita için gereken alanlar.
  SehiriciActiveTrip copyWithLocation({
    double? lat,
    double? lng,
    double? heading,
    double? speed,
    int? etaMinutes,
    String? nextStopId,
    String? nextStopName,
    double? nextStopLat,
    double? nextStopLng,
  }) {
    return SehiriciActiveTrip(
      tripId: tripId,
      lineId: lineId,
      lineCode: lineCode,
      lineName: lineName,
      lineColor: lineColor,
      driverName: driverName,
      licensePlate: licensePlate,
      workingHoursStart: workingHoursStart,
      workingHoursEnd: workingHoursEnd,
      currentLat: lat ?? currentLat,
      currentLng: lng ?? currentLng,
      currentHeading: heading ?? currentHeading,
      currentSpeed: speed ?? currentSpeed,
      startedAt: startedAt,
      nextStopId: nextStopId ?? this.nextStopId,
      nextStopName: nextStopName ?? this.nextStopName,
      nextStopLat: nextStopLat ?? this.nextStopLat,
      nextStopLng: nextStopLng ?? this.nextStopLng,
      etaMinutes: etaMinutes ?? this.etaMinutes,
      status: status,
    );
  }

  /// Realtime INSERT ile gelen yeni seferlerde hat tablosu join edilmediği
  /// için boş kalan kod/ad/renk alanlarını, provider'ın zaten yüklü olan
  /// hat listesinden zenginleştirmek için kullanılır.
  SehiriciActiveTrip copyWithLine(SehiriciLine line) {
    return SehiriciActiveTrip(
      tripId: tripId,
      lineId: lineId,
      lineCode: line.code,
      lineName: line.name,
      lineColor: line.colorHex,
      driverName: driverName,
      licensePlate: licensePlate,
      workingHoursStart: workingHoursStart,
      workingHoursEnd: workingHoursEnd,
      currentLat: currentLat,
      currentLng: currentLng,
      currentHeading: currentHeading,
      currentSpeed: currentSpeed,
      startedAt: startedAt,
      nextStopId: nextStopId,
      nextStopName: nextStopName,
      nextStopLat: nextStopLat,
      nextStopLng: nextStopLng,
      etaMinutes: etaMinutes,
      status: status,
    );
  }
}

class SehiriciFavoriteStop {
  final String id;
  final String stopId;
  final int notifyMinutesBefore;

  const SehiriciFavoriteStop({
    required this.id,
    required this.stopId,
    this.notifyMinutesBefore = 5,
  });

  factory SehiriciFavoriteStop.fromJson(Map<String, dynamic> json) {
    return SehiriciFavoriteStop(
      id: json['id'] as String,
      stopId: json['stop_id'] as String,
      notifyMinutesBefore:
          (json['notify_minutes_before'] as num?)?.toInt() ?? 5,
    );
  }
}

/// Modül ayarları (app_settings tablosundan okunan değerler).
class SehiriciSettings {
  final bool moduleEnabled;
  final String? defaultCityId;
  final int locationUpdateIntervalSec;
  final int etaRefreshSeconds;
  final int maxHistoryMinutes;
  final bool allowUserFavorites;

  const SehiriciSettings({
    this.moduleEnabled = true,
    this.defaultCityId,
    this.locationUpdateIntervalSec = 10,
    this.etaRefreshSeconds = 30,
    this.maxHistoryMinutes = 60,
    this.allowUserFavorites = true,
  });

  factory SehiriciSettings.fromSettingsMap(Map<String, dynamic> map) {
    bool getBool(String key) {
      final v = map[key];
      if (v is bool) return v;
      if (v is String) return v.toLowerCase() == 'true';
      return false;
    }

    return SehiriciSettings(
      moduleEnabled: getBool('sehirici_module_enabled'),
      defaultCityId: map['sehirici_default_city_id'] as String?,
      locationUpdateIntervalSec:
          int.tryParse('${map['sehirici_location_update_interval_sec'] ?? '10'}') ??
              10,
      etaRefreshSeconds:
          int.tryParse('${map['sehirici_eta_refresh_seconds'] ?? '30'}') ?? 30,
      maxHistoryMinutes:
          int.tryParse('${map['sehirici_max_history_minutes'] ?? '60'}') ?? 60,
      allowUserFavorites: getBool('sehirici_allow_user_favorites'),
    );
  }
}
