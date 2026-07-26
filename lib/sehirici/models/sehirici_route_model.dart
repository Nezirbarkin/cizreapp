/// Rota modeli - Hat sefer rotasını temsil eder
class SehiriciRoute {
  final String id;
  final String lineId;
  final String? tripId; // Sefer ID (varsa)
  final String? driverId; // Şoför ID (varsa)
  final List<RoutePoint> points; // Rota noktaları
  final DateTime createdAt;
  final DateTime? startedAt; // Sefer başlama tarihi
  final DateTime? completedAt; // Sefer tamamlama tarihi
  final RouteStatus status;

  const SehiriciRoute({
    required this.id,
    required this.lineId,
    this.tripId,
    this.driverId,
    this.points = const [],
    required this.createdAt,
    this.startedAt,
    this.completedAt,
    this.status = RouteStatus.draft,
  });

  factory SehiriciRoute.fromJson(Map<String, dynamic> json) {
    final pointsRaw = json['points'] as List?;
    List<RoutePoint> points = const [];
    if (pointsRaw is List) {
      points = pointsRaw
          .map((p) => RoutePoint.fromJson(p as Map<String, dynamic>))
          .toList();
    }

    return SehiriciRoute(
      id: json['id'] as String,
      lineId: json['line_id'] as String,
      tripId: json['trip_id'] as String?,
      driverId: json['driver_id'] as String?,
      points: points,
      createdAt: DateTime.parse(json['created_at'] as String),
      startedAt: json['started_at'] != null
          ? DateTime.parse(json['started_at'] as String)
          : null,
      completedAt: json['completed_at'] != null
          ? DateTime.parse(json['completed_at'] as String)
          : null,
      status: RouteStatus.fromString(json['status'] as String?),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'line_id': lineId,
        'trip_id': tripId,
        'driver_id': driverId,
        'points': points.map((p) => p.toJson()).toList(),
        'created_at': createdAt.toIso8601String(),
        'started_at': startedAt?.toIso8601String(),
        'completed_at': completedAt?.toIso8601String(),
        'status': status.dbValue,
      };
}

/// Rota üzerindeki bir nokta
class RoutePoint {
  final int order; // Sıra numarası
  final double lat;
  final double lng;
  final String? stopId; // Durak ID (varsa)
  final DateTime timestamp;
  final double? accuracy; // GPS doğruluğu

  const RoutePoint({
    required this.order,
    required this.lat,
    required this.lng,
    this.stopId,
    required this.timestamp,
    this.accuracy,
  });

  factory RoutePoint.fromJson(Map<String, dynamic> json) {
    return RoutePoint(
      order: (json['order'] as num?)?.toInt() ?? 0,
      lat: (json['lat'] as num?)?.toDouble() ?? 0,
      lng: (json['lng'] as num?)?.toDouble() ?? 0,
      stopId: json['stop_id'] as String?,
      timestamp: DateTime.parse(json['timestamp'] as String),
      accuracy: (json['accuracy'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        'order': order,
        'lat': lat,
        'lng': lng,
        'stop_id': stopId,
        'timestamp': timestamp.toIso8601String(),
        'accuracy': accuracy,
      };
}

enum RouteStatus {
  draft, // Taslak (planlanmış rota)
  active, // Aktif (sefer devam ediyor)
  completed, // Tamamlandı
  cancelled; // İptal edildi

  static RouteStatus fromString(String? s) {
    switch (s) {
      case 'draft':
        return RouteStatus.draft;
      case 'active':
        return RouteStatus.active;
      case 'completed':
        return RouteStatus.completed;
      case 'cancelled':
        return RouteStatus.cancelled;
      default:
        return RouteStatus.draft;
    }
  }

  String get dbValue => name;

  String get label {
    switch (this) {
      case RouteStatus.draft:
        return 'Taslak';
      case RouteStatus.active:
        return 'Aktif';
      case RouteStatus.completed:
        return 'Tamamlandı';
      case RouteStatus.cancelled:
        return 'İptal';
    }
  }
}
