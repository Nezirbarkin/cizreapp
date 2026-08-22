import 'dart:convert';
import 'dart:math' as math;

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

  /// OSRM'nin tek istekte kabul ettiği koordinat sayısı (URL uzunluğu sınırı).
  static const int _maxCoordinates = 80;

  /// İz bu sayıdan uzunsa parça parça eşlenir. Üst sınır, tek bir "rota çek"
  /// eyleminin OSRM'ye atacağı istek sayısını makul tutar.
  static const int _maxChunks = 14;

  static const Duration _timeout = Duration(seconds: 15);

  /// Şoförün kronolojik GPS izini map matching ile geçtiği yollara oturtur.
  ///
  /// İz [_maxCoordinates]'i aşarsa **parçalara bölünüp** her parça ayrı
  /// eşlenir ve sonuçlar uç uca eklenir.
  ///
  /// Bu, "rota her tarafa çizgi çekiyor" hatasının kök nedeniydi: eskiden uzun
  /// izler tek isteğe sığsın diye 80 noktaya *indeks bazlı* seyreltiliyordu.
  /// 2 saatlik bir vardiyada bu, noktalar arası ~750 m demek; OSRM böyle seyrek
  /// bir izde hangi yoldan gidildiğini bilemez, `gaps=ignore` da onu her şeyi
  /// tek parçaya bağlamaya zorlar — sonuç, şehrin yarısını dolaşan bir çizgi.
  /// Parçalı eşlemede noktalar arası gerçek aralık (~10 sn'lik sürüş) korunur.
  Future<List<LatLng>> matchDrivenPath(List<LatLng> trace) async {
    final input = _prepareCoordinates(trace);
    if (input.length < 2) return const [];

    final chunks = _chunkForMatching(input);
    final result = <LatLng>[];
    for (final chunk in chunks) {
      final matched = await _matchChunk(chunk);
      // Tek bir parça eşleşmezse yarım rota kaydetmektense hiç kaydetme:
      // eksik parçanın uçlarını birleştirmek bina üzerinden kiriş çizerdi.
      if (matched.length < 2) return const [];
      for (final point in matched) {
        if (result.isEmpty || pathLengthMeters([result.last, point]) >= 0.5) {
          result.add(point);
        }
      }
    }
    // Bütünsel makullük: eşlenmiş yol, sürülen izden çok daha uzun olamaz.
    return _isPlausible(input, result, maxLengthRatio: 1.8)
        ? result
        : const [];
  }

  /// Tek bir koordinat penceresini OSRM `match` ile yola oturtur.
  Future<List<LatLng>> _matchChunk(List<LatLng> input) async {
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
      return _isPlausible(input, result, maxLengthRatio: 1.8)
          ? result
          : const [];
    } catch (e) {
      debugPrint('Şehiriçi yol eşleme hatası: $e');
      return const [];
    }
  }

  /// İzi, ardışık parçaların uçları çakışacak şekilde böler. Çakışma olmadan
  /// parçaların birleştiği yerde kopukluk (ve dolayısıyla kiriş) oluşurdu.
  static List<List<LatLng>> _chunkForMatching(List<LatLng> input) {
    if (input.length <= _maxCoordinates) return [input];
    final chunks = <List<LatLng>>[];
    var start = 0;
    while (start < input.length - 1 && chunks.length < _maxChunks) {
      final end = math.min(start + _maxCoordinates, input.length);
      chunks.add(input.sublist(start, end));
      if (end >= input.length) break;
      start = end - 1; // bir nokta çakışsın
    }
    return chunks;
  }

  /// Admin çizim/durak noktalarından, noktaların sırasını koruyan yol rotası
  /// üretir. Bu metot GPS map matching yerine waypoint routing kullanır.
  Future<List<LatLng>> routeThroughWaypoints(List<LatLng> waypoints) async {
    final input = _prepareWaypoints(waypoints);
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

  /// GPS izini geçerli, makul aralıklı koordinatlara indirger.
  ///
  /// Seyreltme **mesafeye** göredir, indekse göre DEĞİL: duruş bulutları
  /// (araç beklerken biriken onlarca yakın nokta) atılır ama hareket hâlindeki
  /// noktalar olduğu gibi korunur. Eskiden burada indeks bazlı örnekleme vardı
  /// ve izin geometrisini yok ediyordu — bkz. [matchDrivenPath] açıklaması.
  ///
  /// Parçalı eşleme bütçesini aşacak kadar uzun izlerde (çok turlu vardiya)
  /// aralık, bütçeye sığana dek kademeli olarak büyütülür; böylece seyreltme
  /// hâlâ *uzamsal* olarak düzgün kalır.
  ///
  /// SADECE sürüş izleri için. Durak/waypoint listesi [_prepareWaypoints]'ten
  /// geçer: orada "ışınlanma" filtresi uzak durakları eleyeceği için zararlı.
  static List<LatLng> _prepareCoordinates(List<LatLng> points) {
    // Bir parça iki uçta çakıştığı için her parça net (_maxCoordinates - 1)
    // nokta ilerletir.
    const budget = _maxChunks * (_maxCoordinates - 1);
    var spacing = 12.0;
    var trace = sanitizeGpsTrace(points, minSpacingMeters: spacing);
    while (trace.length > budget && spacing < 400) {
      spacing *= 1.8;
      trace = sanitizeGpsTrace(points, minSpacingMeters: spacing);
    }
    return trace;
  }

  /// Admin durak/çizim noktalarını doğrular. GPS temizliği UYGULANMAZ:
  /// duraklar arası mesafe kilometrelerce olabilir ve `sanitizeGpsTrace`'in
  /// ışınlanma filtresi bunları aykırı sanıp hattan düşürürdü.
  static List<LatLng> _prepareWaypoints(List<LatLng> points) {
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
      // Üst üste binen noktalar OSRM'de gereksiz waypoint üretir.
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

  /// [maxLengthRatio]: sonucun girdiye göre kabul edilen en büyük uzunluk oranı.
  ///
  /// Varsayılan 3.5, **waypoint routing** içindir: girdi duraklar arası kuş
  /// uçuşu çizgidir, gerçek yol doğal olarak çok daha uzun olur.
  /// **Map matching**'de ise girdi zaten sürülen izdir; eşlenen yol ondan
  /// kayda değer biçimde uzun olamaz. Orada 3.5'e izin vermek, şehrin yarısını
  /// dolaşan hatalı eşleşmelerin "makul" sayılıp kaydedilmesine yol açıyordu.
  static bool _isPlausible(
    List<LatLng> input,
    List<LatLng> result, {
    double maxLengthRatio = 3.5,
  }) {
    if (input.length < 2 || result.length < 2) return false;
    final inputLength = pathLengthMeters(input);
    final resultLength = pathLengthMeters(result);
    if (inputLength <= 0 || resultLength <= 0) return false;

    // Yanlış şehir/yol eşleşmelerini ve aşırı dolambaçlı sonuçları engelle.
    if (resultLength < inputLength * 0.45 ||
        resultLength > inputLength * maxLengthRatio) {
      return false;
    }
    final startGap = pathLengthMeters([input.first, result.first]);
    final endGap = pathLengthMeters([input.last, result.last]);
    return startGap <= 150 && endGap <= 150;
  }
}
