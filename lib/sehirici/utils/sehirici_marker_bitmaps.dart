import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

import '../../core/utils/map_marker_icons.dart';
import '../models/sehirici_icon_models.dart';

/// Çözülmüş bir harita ikonu: bitmap + yerleşim bilgileri.
class SehiriciResolvedMarker {
  final BitmapDescriptor bitmap;

  /// Marker'ın yerleşim noktası (0..1). Araçlar merkez (0.5), levha/iğne alt-orta (1.0).
  final Offset anchor;

  /// Aracın yüksekliğinin yarısı (dp): üstündeki etiket bu kadar yukarıda durur.
  final double halfHeight;

  /// Simgenin yarı genişliği (dp): yanındaki durak adı etiketinin boşluğu.
  final double halfWidth;

  /// Alt-ortadan yerleşen durak simgelerinde, simgenin "gövde ortası"nın
  /// koordinattan yüksekliği (dp); durak adı bu yükseklikte hizalanır. Merkezden
  /// yerleşen simgelerde 0.
  final double labelLift;

  const SehiriciResolvedMarker({
    required this.bitmap,
    required this.anchor,
    required this.halfHeight,
    this.halfWidth = 0,
    this.labelLift = 0,
  });
}

/// Kütüphane ikonlarını (hazır çizim ya da yüklenmiş görsel) harita
/// bitmap'ine çevirir.
///
/// Yüklenmiş görsel indirilemez / çözümlenemezse HAZIR ÇİZİME düşer: admin
/// bozuk bir dosya yükleyince harita boş kalmaz.
class SehiriciMarkerBitmaps {
  const SehiriciMarkerBitmaps._();

  /// Yüklenmiş araç görselinin uzun kenarı (dp).
  static const double vehicleImageLongSide = 80;

  static final Map<String, Uint8List> _bytes = {};
  static final Map<String, Future<Uint8List?>> _pending = {};

  /// Görsel indirici; testlerde sahte bayt vermek için değiştirilir.
  static Future<Uint8List?> Function(String url) imageLoader = _download;

  static Future<Uint8List?> _download(String url) async {
    final client = http.Client();
    try {
      final response =
          await client.get(Uri.parse(url)).timeout(const Duration(seconds: 12));
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) return null;
      return response.bodyBytes;
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  /// Önbelleği boşaltır (testler).
  static void clearCache() {
    _bytes.clear();
    _pending.clear();
  }

  static Future<Uint8List?> _load(String url) {
    final cached = _bytes[url];
    if (cached != null) return Future.value(cached);
    return _pending[url] ??= imageLoader(url).then((data) {
      _pending.remove(url);
      if (data != null) _bytes[url] = data;
      return data;
    });
  }

  /// Bir hattın aracı için bitmap. [scale] uzaktan bakışta ikonu küçültür.
  static Future<SehiriciResolvedMarker> vehicle(
    SehiriciMarkerIcon icon,
    Color lineColor, {
    double scale = 1,
  }) async {
    final effective = scale * icon.scale;
    if (icon.hasImage) {
      final data = await _load(icon.imageUrl!);
      if (data != null) {
        final bitmap = await MapMarkerIcons.vehicleFromImage(
          bytes: data,
          cacheKey: icon.imageCacheKey,
          rotationDegrees: icon.imageRotation,
          scale: effective,
          longSide: vehicleImageLongSide,
        );
        if (bitmap != null) {
          return SehiriciResolvedMarker(
            bitmap: bitmap,
            anchor: const Offset(0.5, 0.5),
            halfHeight: vehicleImageLongSide * effective / 2 + 1,
          );
        }
      }
    }
    final shape = icon.vehicleShape;
    return SehiriciResolvedMarker(
      bitmap: await MapMarkerIcons.vehicle(
        shape: shape,
        color: lineColor,
        scale: effective,
      ),
      anchor: const Offset(0.5, 0.5),
      halfHeight: MapMarkerIcons.labelGapFor(shape, scale: effective),
    );
  }

  /// Durak bitmap'i. Uzaktan bakışta ([MapStopDetail.far]) yüklenmiş görsel
  /// yerine sade nokta çizilir — küçük ölçekte görsel okunmaz ve 24 durak
  /// birbirini örter.
  static Future<SehiriciResolvedMarker> stop(
    SehiriciMarkerIcon icon, {
    MapStopDetail detail = MapStopDetail.near,
    MapStopState state = MapStopState.normal,
    List<Color> lineColors = const [],
    bool isStart = false,
    bool isEnd = false,
    double scale = 1,
  }) async {
    final effective = scale * icon.scale;
    if (icon.hasImage && detail != MapStopDetail.far) {
      final data = await _load(icon.imageUrl!);
      if (data != null) {
        final long = detail == MapStopDetail.near ? 44.0 : 34.0;
        final bitmap = await MapMarkerIcons.stopFromImage(
          bytes: data,
          cacheKey: icon.imageCacheKey,
          rotationDegrees: icon.imageRotation,
          scale: effective * (state == MapStopState.selected ? 1.18 : 1),
          longSide: long,
        );
        if (bitmap != null) {
          return SehiriciResolvedMarker(
            bitmap: bitmap,
            anchor: Offset(0.5, icon.anchorBottom ? 1.0 : 0.5),
            halfHeight: long * effective / 2,
            halfWidth: long * effective / 2,
            labelLift: icon.anchorBottom ? long * effective * 0.5 : 0,
          );
        }
      }
    }
    final style = detail == MapStopDetail.far ? MapStopStyle.dot : icon.stopStyle;
    final size = MapMarkerIcons.stopSize(style, detail, scale: effective);
    return SehiriciResolvedMarker(
      bitmap: await MapMarkerIcons.stop(
        style: style,
        detail: detail,
        state: state,
        lineColors: lineColors,
        isStart: isStart,
        isEnd: isEnd,
        scale: effective,
      ),
      anchor: Offset(0.5, style.anchorY),
      halfHeight: size.height / 2,
      halfWidth: size.width / 2,
      labelLift: style.anchorY >= 1.0 ? size.height * 0.62 : 0,
    );
  }
}
