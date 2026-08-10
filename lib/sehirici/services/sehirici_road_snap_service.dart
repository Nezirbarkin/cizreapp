import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

import '../utils/sehirici_route_geometry.dart';

/// GPS veya seyrek çizim noktalarını gerçek yol geometrisine oturtur.
///
/// OSRM'nin `match` servisi sürüş izleri için, `route` servisi ise durak/admin
/// waypoint'leri için kullanılır. Başarısızlıkta kuş uçuşu çizgi üretmek yerine
/// boş liste döner; böylece bina üzerinden geçen hat yanlışlıkla kaydedilmez.
class SehiriciRoadSnapService {
  SehiriciRoadSnapService({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  static const String _baseUrl = 'https://router.project-osrm.org';
  static const int _maxCoordinates = 80;
  static const Duration _timeout = Duration(seconds: 15);

  /// Şoförün kronolojik GPS izini map matching ile geçtiği yollara oturtur.
  Future<List<LatLng>> matchDrivenPath(List<LatLng> trace) async {
    final input = _prepareCoordinates(trace);
    if (input.length < 2) return const [];

    final coordinates = _coordinateString(input);
    final radiuses = List.filled(input.length, '35').join(';');
    final uri = Uri.parse(
      '$_baseUrl/match/v1/driving/$coordinates'
      '?overview=full&geometries=geojson&steps=false&tidy=true'
      '&gaps=ignore&radiuses=$radiuses',
    );

    try {
      final response = await _client.get(uri).timeout(_timeout);
      if (response.statusCode != 200) return const [];
      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic> || body['code'] != 'Ok') {
        return const [];
      }

      final matchings = body['matchings'];
      if (matchings is! List || matchings.isEmpty) return const [];

      // gaps=ignore ile normalde tek matching gelir. Birden fazla geometriyi
      // doğrudan bağlamak arada bina üzerinden kiriş oluşturacağından reddet.
      if (matchings.length != 1 || matchings.first is! Map) return const [];
      final matching = Map<String, dynamic>.from(matchings.first as Map);
      final confidence = (matching['confidence'] as num?)?.toDouble() ?? 0;
      if (confidence < 0.35) return const [];

      final result = _decodeGeoJsonGeometry(matching['geometry']);
      return _isPlausible(input, result) ? result : const [];
    } catch (e) {
      debugPrint('Şehiriçi yol eşleme hatası: $e');
      return const [];
    }
  }

  /// Admin çizim/durak noktalarından, noktaların sırasını koruyan yol rotası
  /// üretir. Bu metot GPS map matching yerine waypoint routing kullanır.
  Future<List<LatLng>> routeThroughWaypoints(List<LatLng> waypoints) async {
    final input = _prepareCoordinates(waypoints);
    if (input.length < 2) return const [];

    final uri = Uri.parse(
      '$_baseUrl/route/v1/driving/${_coordinateString(input)}'
      '?overview=full&geometries=geojson&steps=false&continue_straight=true',
    );

    try {
      final response = await _client.get(uri).timeout(_timeout);
      if (response.statusCode != 200) return const [];
      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic> || body['code'] != 'Ok') {
        return const [];
      }
      final routes = body['routes'];
      if (routes is! List || routes.isEmpty || routes.first is! Map) {
        return const [];
      }
      final route = Map<String, dynamic>.from(routes.first as Map);
      final result = _decodeGeoJsonGeometry(route['geometry']);
      return _isPlausible(input, result) ? result : const [];
    } catch (e) {
      debugPrint('Şehiriçi yol rotası hatası: $e');
      return const [];
    }
  }

  static List<LatLng> _prepareCoordinates(List<LatLng> points) {
    final valid = <LatLng>[];
    for (final point in points) {
      if (!point.latitude.isFinite ||
          !point.longitude.isFinite ||
          point.latitude < -90 ||
          point.latitude > 90 ||
          point.longitude < -180 ||
          point.longitude > 180) {
        continue;
      }
      if (valid.isEmpty || pathLengthMeters([valid.last, point]) >= 2) {
        valid.add(point);
      }
    }
    if (valid.length <= _maxCoordinates) return valid;

    // URL sınırını aşmadan başlangıç/bitiş ve iz boyunca eşit aralıklı
    // örnekleri koru. Orijinal sıra değişmez.
    return List<LatLng>.generate(_maxCoordinates, (index) {
      final sourceIndex = (index * (valid.length - 1) / (_maxCoordinates - 1))
          .round();
      return valid[sourceIndex];
    });
  }

  static String _coordinateString(List<LatLng> points) =>
      points.map((point) => '${point.longitude},${point.latitude}').join(';');

  static List<LatLng> _decodeGeoJsonGeometry(dynamic geometry) {
    if (geometry is! Map) return const [];
    final coordinates = geometry['coordinates'];
    if (coordinates is! List) return const [];

    final result = <LatLng>[];
    for (final coordinate in coordinates) {
      if (coordinate is! List || coordinate.length < 2) continue;
      final lng = coordinate[0];
      final lat = coordinate[1];
      if (lat is! num || lng is! num) continue;
      final point = LatLng(lat.toDouble(), lng.toDouble());
      if (result.isEmpty || pathLengthMeters([result.last, point]) >= 0.5) {
        result.add(point);
      }
    }
    return result;
  }

  static bool _isPlausible(List<LatLng> input, List<LatLng> result) {
    if (input.length < 2 || result.length < 2) return false;
    final inputLength = pathLengthMeters(input);
    final resultLength = pathLengthMeters(result);
    if (inputLength <= 0 || resultLength <= 0) return false;

    // Yanlış şehir/yol eşleşmelerini ve aşırı dolambaçlı sonuçları engelle.
    if (resultLength < inputLength * 0.45 || resultLength > inputLength * 3.5) {
      return false;
    }
    final startGap = pathLengthMeters([input.first, result.first]);
    final endGap = pathLengthMeters([input.last, result.last]);
    return startGap <= 150 && endGap <= 150;
  }
}
