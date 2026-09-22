import 'dart:convert';

import 'package:cizreapp/sehirici/models/sehirici_models.dart';
import 'package:cizreapp/sehirici/services/sehirici_line_service.dart';
import 'package:http/http.dart' as http;

/// Şehiriçi admin ekranı testleri için sahte Supabase (PostgREST) sunucusu.
///
/// `Supabase.initialize(httpClient: MockClient(backend.handle))` ile bağlanır.
/// Tablolar bellekte tutulur; `app_settings` yazımları okumaya yansır, RPC
/// çağrıları [calls] listesine kaydedilir (testler neyin gönderildiğini
/// doğrulayabilsin diye).
class SehiriciFakeBackend {
  SehiriciFakeBackend() {
    reset();
  }

  late List<Map<String, dynamic>> cities;
  late List<Map<String, dynamic>> lines;
  late List<Map<String, dynamic>> stops;
  late List<Map<String, dynamic>> drivers;
  late List<Map<String, dynamic>> icons;
  late Map<String, dynamic> settings;

  /// (yöntem, yol, gövde) — yalnız yazma isteklerini ve RPC'leri tutar.
  final List<({String method, String path, Object? body})> calls = [];

  /// Bu yol parçasını içeren isteğe hata döndür (RPC hata yolunu denemek için).
  String? failPathContaining;
  String failMessage = 'Sunucu hatası';

  Iterable<({String method, String path, Object? body})> rpcCalls(String name) =>
      calls.where((c) => c.path.endsWith('/rpc/$name'));

  void reset() {
    calls.clear();
    failPathContaining = null;
    cities = [
      {
        'id': 'city-1',
        'name': 'Cizre',
        'slug': 'cizre',
        'center_lat': 37.3274,
        'center_lng': 42.1907,
        'zoom_level': 16,
        'is_active': true,
      },
      {
        'id': 'city-2',
        'name': 'Silopi',
        'slug': 'silopi',
        'center_lat': 37.2492,
        'center_lng': 42.4676,
        'zoom_level': 15,
        'is_active': false,
      },
    ];
    lines = [
      lineRow(_blue, route: true),
      // 7B: kayıtlı rota var ama imzası duraklarla uyuşmuyor → "eski".
      lineRow(_red, route: true, signature: 'eski-imza'),
      // Durağı ve rotası olmayan, kod/adı dolu boş bir hat.
      lineRow(const SehiriciLine(id: 'L3', code: '9C', name: 'Sanayi Ring', colorHex: '#7B1FA2')),
      // Canlıda karşılaşılan kod/adı boş kayıt.
      lineRow(const SehiriciLine(id: 'L4', code: '', name: '', colorHex: '#1976D2')),
    ];
    final used = <String>{};
    stops = [];
    for (final l in [_blue, _red]) {
      for (final s in l.stops) {
        if (used.add(s.stopId)) {
          stops.add({
            'id': s.stopId,
            'name': s.name,
            'code': s.code,
            'lat': s.lat,
            'lng': s.lng,
            'address': s.address,
            'is_active': true,
            'city_id': 'city-1',
          });
        }
      }
    }
    // Hiçbir hatta bağlı olmayan durak.
    stops.add({
      'id': 's9',
      'name': 'Eski Terminal',
      'code': 'T09',
      'lat': 37.3250,
      'lng': 42.1870,
      'address': 'Terminal Cd.',
      'is_active': true,
      'city_id': 'city-1',
    });
    drivers = [
      {
        'id': 'd1',
        'profile_id': 'p1',
        'license_number': '34ABC123',
        'phone': '0532 000 00 01',
        'assigned_line_id': 'L1',
        'is_on_duty': true,
        'working_hours_start': '07:00:00',
        'working_hours_end': '19:00:00',
        'auto_trip_enabled': true,
        'profiles': {'full_name': 'Ahmet Yılmaz', 'username': 'ahmet', 'avatar_url': null},
      },
      {
        'id': 'd2',
        'profile_id': 'p2',
        'license_number': null,
        'phone': null,
        'assigned_line_id': null,
        'is_on_duty': false,
        'working_hours_start': null,
        'working_hours_end': null,
        'auto_trip_enabled': false,
        'profiles': {'full_name': 'Mehmet Kaya', 'username': 'mehmet', 'avatar_url': null},
      },
    ];
    // Boş dönerse istemci yerleşik listeyi kullanır; bir de admin'in eklediği
    // özel araç ikonu ve özel durak ikonu.
    icons = [
      _icon('builtin_minibus', 'vehicle', 'minibus', 'Minibüs', 'minibus', 10,
          builtin: true),
      _icon('builtin_dolmus', 'vehicle', 'dolmus', 'Dolmuş', 'dolmus', 20,
          builtin: true),
      _icon('builtin_midibus', 'vehicle', 'midibus', 'Midibüs', 'midibus', 30,
          builtin: true),
      _icon('builtin_bus', 'vehicle', 'bus', 'Otobüs', 'bus', 40, builtin: true),
      _icon('builtin_tram', 'vehicle', 'tram', 'Tramvay', 'tram', 50, builtin: true),
      _icon('builtin_other', 'vehicle', 'other', 'Diğer', 'car', 90,
          builtin: true, isDefault: true),
      _icon('ic-taksi', 'vehicle', 'taksi', 'Taksi', 'taxi', 60),
      _icon('builtin_stop_sign', 'stop', 'stop_sign', 'Durak Levhası', 'sign', 10,
          builtin: true, isDefault: true),
      _icon('builtin_stop_pin', 'stop', 'stop_pin', 'Modern İğne', 'pin', 20,
          builtin: true),
      _icon('builtin_stop_dot', 'stop', 'stop_dot', 'Sade Nokta', 'dot', 30,
          builtin: true),
    ];
    settings = {
      'sehirici_module_enabled': 'true',
      'sehirici_allow_user_favorites': 'true',
      'sehirici_location_update_interval_sec': '10',
      'sehirici_eta_refresh_seconds': '30',
      'sehirici_max_history_minutes': '60',
      'sehirici_auto_route_enabled': 'true',
    };
  }

  static Map<String, dynamic> _icon(
    String id,
    String kind,
    String key,
    String label,
    String shape,
    int order, {
    bool builtin = false,
    bool isDefault = false,
  }) =>
      {
        'id': id,
        'kind': kind,
        'key': key,
        'label': label,
        'builtin_shape': shape,
        'image_url': null,
        'image_path': null,
        'image_rotation': 0,
        'tint_with_line_color': true,
        'scale': 1.0,
        'anchor_bottom': false,
        'is_builtin': builtin,
        'is_active': true,
        'is_default': isDefault,
        'sort_order': order,
        'updated_at': '2026-09-21T10:00:00Z',
      };

  // ── Örnek hatlar ────────────────────────────────────────────

  static SehiriciLineStop _stop(
    String id,
    int order,
    String name,
    double lat,
    double lng,
    int minutes, {
    String? code,
    String? address,
  }) =>
      SehiriciLineStop(
        stopId: id,
        stopOrder: order,
        minutesFromStart: minutes,
        name: name,
        lat: lat,
        lng: lng,
        code: code,
        address: address,
      );

  static final SehiriciLine _blue = SehiriciLine(
    id: 'L1',
    code: '4A',
    name: 'Merkez – Hastane',
    colorHex: '#1976D2',
    vehicleType: SehiriciVehicleType.minibus,
    vehicleKeyRaw: 'minibus',
    estimatedMinutes: 22,
    fareAmount: 12,
    stops: [
      _stop('s1', 0, 'Otogar', 37.3268, 42.1885, 0, code: 'A01'),
      _stop('s2', 1, 'Belediye', 37.3271, 42.1899, 3),
      _stop('s3', 2, 'Çarşı', 37.3275, 42.1913, 6),
      _stop('s4', 3, 'Şehir Parkı', 37.3281, 42.1926, 9),
      _stop('s5', 4, 'Devlet Hastanesi', 37.3288, 42.1938, 13,
          address: 'Cumhuriyet Mah. Hastane Cd.'),
      _stop('s6', 5, 'Üniversite', 37.3296, 42.1951, 18),
    ],
    roadPolyline: const [
      [37.3268, 42.1885],
      [37.3268, 42.1899],
      [37.3271, 42.1899],
      [37.3271, 42.1913],
      [37.3275, 42.1913],
      [37.3275, 42.1926],
      [37.3281, 42.1926],
      [37.3281, 42.1938],
      [37.3288, 42.1938],
      [37.3288, 42.1951],
      [37.3296, 42.1951],
    ],
  );

  static final SehiriciLine _red = SehiriciLine(
    id: 'L2',
    code: '7B',
    name: 'Çarşı – Sanayi',
    colorHex: '#E53935',
    vehicleType: SehiriciVehicleType.bus,
    vehicleKeyRaw: 'bus',
    estimatedMinutes: 15,
    fareAmount: 10,
    stops: [
      _stop('s2', 0, 'Belediye', 37.3271, 42.1899, 0),
      _stop('s3', 1, 'Çarşı', 37.3275, 42.1913, 3),
      _stop('s7', 2, 'Kaymakamlık', 37.3262, 42.1913, 7),
      _stop('s8', 3, 'Sanayi Sitesi', 37.3255, 42.1926, 11),
    ],
    roadPolyline: const [
      [37.3271, 42.1899],
      [37.3275, 42.1899],
      [37.3275, 42.1913],
      [37.3262, 42.1913],
      [37.3262, 42.1926],
      [37.3255, 42.1926],
    ],
  );

  /// Bir [SehiriciLine]'ı PostgREST'in `sehirici_lines` satırına çevirir
  /// (iç içe `sehirici_line_stops` + `route_polyline`).
  static Map<String, dynamic> lineRow(
    SehiriciLine l, {
    bool route = false,
    String? signature,
  }) =>
      {
        'id': l.id,
        'city_id': 'city-1',
        'code': l.code,
        'name': l.name,
        'color_hex': l.colorHex,
        'vehicle_type': l.vehicleKey,
        'estimated_minutes': l.estimatedMinutes,
        'fare_amount': l.fareAmount,
        'is_active': l.isActive,
        'display_order': l.displayOrder,
        'route_polyline': route
            ? {
                'points': l.roadPolyline,
                'stops_signature':
                    signature ?? SehiriciLineService.computeStopsSignature(l.stops),
                'source': 'osrm_stops',
              }
            : null,
        'sehirici_line_stops': [
          for (final s in l.stops)
            {
              'stop_id': s.stopId,
              'stop_order': s.stopOrder,
              'minutes_from_start': s.minutesFromStart,
              'distance_km': null,
              'sehirici_stops': {
                'name': s.name,
                'lat': s.lat,
                'lng': s.lng,
                'code': s.code,
                'address': s.address,
              },
            },
        ],
      };

  // ── HTTP ────────────────────────────────────────────────────

  Future<http.Response> handle(http.Request request) async {
    final path = request.url.path;
    Object? body;
    if (request.method != 'GET' && request.body.isNotEmpty) {
      try {
        body = jsonDecode(request.body);
      } catch (_) {
        body = request.body;
      }
    }
    if (request.method != 'GET' || path.contains('/rpc/')) {
      calls.add((method: request.method, path: path, body: body));
    }

    final fail = failPathContaining;
    if (fail != null && path.contains(fail)) {
      return _json(
        request,
        {'code': 'P0001', 'message': failMessage, 'details': null, 'hint': null},
        status: 400,
      );
    }

    // app_settings yazımı okumaya yansısın.
    if (request.method == 'POST' && path.endsWith('/app_settings')) {
      final rows = body is List ? body : [body];
      for (final row in rows) {
        if (row is Map && row['key'] is String) {
          settings[row['key'] as String] = row['value'];
        }
      }
      return _json(request, const []);
    }

    if (request.method == 'GET') {
      if (path.endsWith('/sehirici_cities')) return _json(request, cities);
      if (path.endsWith('/sehirici_lines')) {
        return _json(request, _byCity(lines, request));
      }
      if (path.endsWith('/sehirici_stops')) {
        return _json(request, _byCity(stops, request));
      }
      if (path.endsWith('/sehirici_drivers')) return _json(request, drivers);
      if (path.endsWith('/sehirici_marker_icons')) return _json(request, icons);
      if (path.endsWith('/app_settings')) {
        return _json(request, [
          for (final e in settings.entries) {'key': e.key, 'value': e.value},
        ]);
      }
    }
    // İkon kaydı yeni kimliği döndürür (istemci "as String" ile okur).
    if (path.endsWith('/rpc/admin_upsert_sehirici_marker_icon')) {
      return _json(request, 'ic-new');
    }
    // Diğer her şey (RPC, bilinmeyen tablo): boş başarı.
    return _json(request, path.contains('/rpc/') ? null : const []);
  }

  /// Sorgudaki `city_id=eq.X` süzgecini uygular (PostgREST `.eq('city_id', X)`).
  static List<Map<String, dynamic>> _byCity(
    List<Map<String, dynamic>> rows,
    http.Request request,
  ) {
    final filter = request.url.queryParameters['city_id'];
    if (filter == null || !filter.startsWith('eq.')) return rows;
    final id = filter.substring(3);
    return rows.where((r) => r['city_id'] == id).toList();
  }

  static http.Response _json(http.Request request, Object? data, {int status = 200}) =>
      http.Response(
        jsonEncode(data),
        status,
        request: request,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
}
