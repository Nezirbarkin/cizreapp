// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cizreapp/core/theme/app_map_style.dart' show AppMapStyle;
import 'package:cizreapp/core/utils/map_vehicle_painters.dart';
import 'package:cizreapp/sehirici/admin/sehirici_admin_kit.dart'
    show sehiriciFold, sehiriciUpper;
import 'package:cizreapp/sehirici/admin/sehirici_icon_editor_sheet.dart'
    show sehiriciIconKeyFromName;
import 'package:cizreapp/sehirici/models/sehirici_icon_models.dart';
import 'package:cizreapp/sehirici/models/sehirici_models.dart';
import 'package:cizreapp/sehirici/services/sehirici_city_service.dart';
import 'package:cizreapp/sehirici/services/sehirici_errors.dart';
import 'package:cizreapp/sehirici/services/sehirici_icon_catalog.dart';
import 'package:cizreapp/sehirici/services/sehirici_icon_service.dart';
import 'package:cizreapp/sehirici/services/sehirici_line_service.dart';
import 'package:cizreapp/sehirici/utils/sehirici_arrivals.dart';
import 'package:cizreapp/sehirici/widgets/sehirici_common_widgets.dart'
    show sehiriciColorHex, sehiriciOnColor, sehiriciParseColor;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Şehiriçi yönetim mantığı: modeller, ikon kataloğu, hata metinleri, Türkçe
/// yardımcılar, varış hesabı ve servislerin sunucuya gönderdiği parametreler.
/// Ağ yok: Supabase istemcisi sahte HTTP istemcisiyle kurulur.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ── Sahte sunucu ────────────────────────────────────────────
  final requests = <http.Request>[];

  SupabaseClient makeClient(
    http.Response Function(http.Request request) respond,
  ) {
    return SupabaseClient(
      'https://test.supabase.co',
      'anon-key',
      httpClient: MockClient((req) async {
        requests.add(req);
        return respond(req);
      }),
    );
  }

  http.Response json(http.Request req, Object? body, {int status = 200}) =>
      http.Response(
        jsonEncode(body),
        status,
        request: req,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );

  http.Response pgError(http.Request req, String code, String message) => json(
        req,
        {'code': code, 'message': message, 'details': null, 'hint': null},
        status: 400,
      );

  Map<String, dynamic> lastBody() =>
      jsonDecode(requests.last.body) as Map<String, dynamic>;

  setUp(requests.clear);

  // ════════════════════════════════════════════════════════════
  group('SehiriciLine.fromJson: rota ve araç anahtarı', () {
    test('route_polyline noktaları, imza ve kaynak okunur', () {
      final line = SehiriciLine.fromJson({
        'id': 'L1',
        'code': '4A',
        'name': 'Merkez',
        'vehicle_type': 'taksi',
        'route_polyline': {
          'points': [
            [37.1, 42.1],
            [37.2, 42.2],
            [37.3], // bozuk satır: atılır
          ],
          'stops_signature': 'abc123',
          'source': 'osrm_stops',
        },
      });
      expect(line.roadPolyline, [
        [37.1, 42.1],
        [37.2, 42.2],
      ]);
      expect(line.routeSignature, 'abc123');
      expect(line.routeSource, 'osrm_stops');
      expect(line.hasRoute, isTrue);
    });

    test('özel araç türü ham anahtar olarak taşınır (enum bilmese bile)', () {
      final line = SehiriciLine.fromJson({
        'id': 'L1',
        'code': 'S1',
        'name': 'Servis',
        'vehicle_type': 'servis_araci',
      });
      expect(line.vehicleKey, 'servis_araci');
      expect(line.vehicleType, SehiriciVehicleType.other);
    });

    test('eski enum türü anahtar olarak enum adını verir', () {
      final line = SehiriciLine.fromJson(
          {'id': 'L1', 'code': '1', 'name': 'x', 'vehicle_type': 'bus'});
      expect(line.vehicleKey, 'bus');
      final none = SehiriciLine.fromJson({'id': 'L2', 'code': '2', 'name': 'y'});
      expect(none.vehicleKeyRaw, isNull);
      expect(none.vehicleKey, none.vehicleType.name);
    });

    test('rotası olmayan / temizlenmiş hat hasRoute=false', () {
      expect(
        SehiriciLine.fromJson({'id': 'a', 'code': '1', 'name': 'x'}).hasRoute,
        isFalse,
      );
      final cleared = SehiriciLine.fromJson({
        'id': 'b',
        'code': '2',
        'name': 'y',
        'route_polyline': {'points': [], 'source': 'cleared'},
      });
      expect(cleared.hasRoute, isFalse);
      expect(cleared.routeSource, 'cleared');
      final one = SehiriciLine.fromJson({
        'id': 'c',
        'code': '3',
        'name': 'z',
        'route_polyline': {
          'points': [
            [37.1, 42.1]
          ],
        },
      });
      expect(one.hasRoute, isFalse, reason: 'tek nokta çizgi değildir');
    });

    test('copyWith durakları değiştirir, rota üst bilgisini korur', () {
      final line = SehiriciLine.fromJson({
        'id': 'L1',
        'code': '4A',
        'name': 'Merkez',
        'route_polyline': {
          'points': [
            [1.0, 1.0],
            [2.0, 2.0],
          ],
          'stops_signature': 'sig',
        },
      });
      final next = line.copyWith(stops: const [
        SehiriciLineStop(
            stopId: 's1', stopOrder: 0, minutesFromStart: 0, name: 'A', lat: 1, lng: 1),
      ]);
      expect(next.stops, hasLength(1));
      expect(next.routeSignature, 'sig');
      expect(next.roadPolyline, line.roadPolyline);
    });
  });

  // ════════════════════════════════════════════════════════════
  group('SehiriciMarkerIcon', () {
    test('fromJson varsayılanları ve boş görsel adresi', () {
      final icon = SehiriciMarkerIcon.fromJson({
        'id': 'i1',
        'kind': 'vehicle',
        'key': 'taksi',
        'label': 'Taksi',
        'image_url': '   ',
      });
      expect(icon.kind, SehiriciIconKind.vehicle);
      expect(icon.isActive, isTrue);
      expect(icon.isDefault, isFalse);
      expect(icon.scale, 1.0);
      expect(icon.tintWithLineColor, isTrue);
      expect(icon.imageUrl, isNull, reason: 'boşluk = görsel yok');
      expect(icon.hasImage, isFalse);
    });

    test('yerleşik liste: her türden TAM BİR varsayılan, anahtarlar benzersiz',
        () {
      const all = SehiriciMarkerIcon.builtinDefaults;
      for (final kind in SehiriciIconKind.values) {
        expect(all.where((i) => i.kind == kind && i.isDefault), hasLength(1),
            reason: '$kind için tek varsayılan');
      }
      final keys = all.map((i) => '${i.kind.name}:${i.key}').toList();
      expect(keys.toSet(), hasLength(keys.length));
    });

    test('yerleşik çizim adları gerçek çizimlere karşılık gelir', () {
      for (final icon in SehiriciMarkerIcon.builtinDefaults) {
        if (icon.isVehicle) {
          expect(MapVehicleShape.fromKey(icon.builtinShape), isNotNull,
              reason: '${icon.key}: ${icon.builtinShape}');
        } else {
          expect(MapStopStyle.fromKey(icon.builtinShape), isNotNull,
              reason: '${icon.key}: ${icon.builtinShape}');
        }
      }
    });

    test('bilinmeyen çizim adı güvenli varsayılana düşer', () {
      const v = SehiriciMarkerIcon(
          id: 'x', kind: SehiriciIconKind.vehicle, key: 'k', label: 'K', builtinShape: 'uzay');
      const s = SehiriciMarkerIcon(
          id: 'y', kind: SehiriciIconKind.stop, key: 'k', label: 'K', builtinShape: 'uzay');
      expect(v.vehicleShape, MapVehicleShape.car);
      expect(s.stopStyle, MapStopStyle.sign);
    });

    test('görsel önbellek anahtarı sürüme bağlı; clearImage görseli kaldırır', () {
      final a = SehiriciMarkerIcon.fromJson({
        'id': 'i',
        'kind': 'stop',
        'key': 'stop_x',
        'label': 'X',
        'image_url': 'https://x/y.png',
        'image_path': 'icons/y.png',
        'updated_at': '2026-09-21T10:00:00Z',
      });
      final b = SehiriciMarkerIcon.fromJson({
        'id': 'i',
        'kind': 'stop',
        'key': 'stop_x',
        'label': 'X',
        'image_url': 'https://x/y.png',
        'updated_at': '2026-09-21T11:00:00Z',
      });
      expect(a.imageCacheKey, isNot(b.imageCacheKey));
      final cleared = a.copyWith(clearImage: true);
      expect(cleared.imageUrl, isNull);
      expect(cleared.imagePath, isNull);
      expect(cleared.hasImage, isFalse);
    });
  });

  // ════════════════════════════════════════════════════════════
  group('SehiriciIconCatalog', () {
    Map<String, dynamic> row(String id, String kind, String key,
            {bool isDefault = false, bool active = true, String? shape}) =>
        {
          'id': id,
          'kind': kind,
          'key': key,
          'label': key.toUpperCase(),
          'builtin_shape': shape ?? (kind == 'vehicle' ? 'minibus' : 'sign'),
          'is_default': isDefault,
          'is_active': active,
          'sort_order': 10,
        };

    test('bilinmeyen / boş anahtar varsayılan araca düşer', () {
      final catalog = SehiriciIconCatalog();
      expect(catalog.resolveVehicle('minibus').key, 'minibus');
      expect(catalog.resolveVehicle('yok_boyle_bir_sey').key, 'other');
      expect(catalog.resolveVehicle(null).key, 'other');
      expect(catalog.stopIcon.key, 'stop_sign');
    });

    test('seed katalogu değiştirir, sürümü artırır ve dinleyicileri uyarır', () {
      final catalog = SehiriciIconCatalog();
      var notified = 0;
      catalog.addListener(() => notified++);
      final before = catalog.revision;
      catalog.seed([
        SehiriciMarkerIcon.fromJson(row('t', 'vehicle', 'taksi', isDefault: true)),
        SehiriciMarkerIcon.fromJson(
            row('p', 'stop', 'stop_pin', isDefault: true, shape: 'pin')),
      ]);
      expect(catalog.revision, before + 1);
      expect(notified, 1);
      expect(catalog.resolveVehicle('minibus').key, 'taksi',
          reason: 'anahtar yoksa yeni varsayılan');
      expect(catalog.stopIcon.key, 'stop_pin');
      catalog.seed(const []);
      expect(catalog.all, SehiriciMarkerIcon.builtinDefaults,
          reason: 'boş liste yerleşik listeye döner');
    });

    test('yükleme başarısızsa yerleşik liste kalır ve hata fırlatmaz', () async {
      final client = makeClient((r) => pgError(r, '42P01', 'relation does not exist'));
      final catalog =
          SehiriciIconCatalog(serviceFactory: () => SehiriciIconService(client: client));
      await catalog.ensureLoaded();
      expect(catalog.isLoaded, isFalse);
      expect(catalog.all, SehiriciMarkerIcon.builtinDefaults);
    });

    test('başarılı yükleme katalogu doldurur; süre dolana dek yeniden okumaz',
        () async {
      final client = makeClient((r) => json(r, [
            row('t', 'vehicle', 'taksi', isDefault: true),
            row('p', 'stop', 'stop_pin', isDefault: true),
          ]));
      final catalog =
          SehiriciIconCatalog(serviceFactory: () => SehiriciIconService(client: client));
      await catalog.ensureLoaded();
      expect(catalog.isLoaded, isTrue);
      expect(catalog.vehicles.map((i) => i.key), ['taksi']);
      expect(requests, hasLength(1));

      await catalog.ensureLoaded();
      expect(requests, hasLength(1), reason: 'TTL içinde önbellekten');
      await catalog.refresh();
      expect(requests, hasLength(2), reason: 'admin değiştirince zorla okunur');
    });

    test('eşzamanlı istekler tek ağ çağrısında birleşir', () async {
      final client = makeClient((r) => json(r, [row('t', 'vehicle', 'taksi')]));
      final catalog =
          SehiriciIconCatalog(serviceFactory: () => SehiriciIconService(client: client));
      await Future.wait([
        catalog.ensureLoaded(),
        catalog.ensureLoaded(),
        catalog.ensureLoaded(),
      ]);
      expect(requests, hasLength(1));
    });

    test('boş yanıt yerleşik listeyi silmez', () async {
      final client = makeClient((r) => json(r, []));
      final catalog =
          SehiriciIconCatalog(serviceFactory: () => SehiriciIconService(client: client));
      await catalog.ensureLoaded();
      expect(catalog.all, SehiriciMarkerIcon.builtinDefaults);
    });
  });

  // ════════════════════════════════════════════════════════════
  group('sehiriciErrorMessage', () {
    test('Postgres benzersizlik hataları anlaşılır metne çevrilir', () {
      String m(String constraint) => sehiriciErrorMessage(PostgrestException(
          message: 'duplicate key value violates unique constraint "$constraint"',
          code: '23505'));
      expect(m('sehirici_lines_city_id_code_key'),
          'Bu hat kodu bu şehirde zaten kullanılıyor.');
      expect(m('sehirici_cities_name_key'), 'Bu ada sahip bir şehir zaten var.');
      expect(m('sehirici_cities_slug_key'),
          'Bu bağlantı adı (slug) başka bir şehirde kullanılıyor.');
      expect(m('sehirici_drivers_profile_id_key'),
          'Bu kullanıcı zaten şoför olarak kayıtlı.');
      expect(m('baska_bir_kisit'), 'Bu kayıt zaten var.');
    });

    test('yetki, eksik işlev ve yabancı anahtar', () {
      expect(sehiriciErrorMessage(PostgrestException(message: 'x', code: '42501')),
          'Bu işlem için yetkiniz yok.');
      expect(sehiriciErrorMessage(PostgrestException(message: 'x', code: 'PGRST202')),
          contains('eksik işlev'));
      expect(sehiriciErrorMessage(PostgrestException(message: 'x', code: '23503')),
          contains('başka kayıtlar'));
    });

    test('RAISE EXCEPTION metni olduğu gibi gösterilir', () {
      expect(
        sehiriciErrorMessage(
            PostgrestException(message: '  Hat kodu boş olamaz ', code: 'P0001')),
        'Hat kodu boş olamaz',
      );
    });

    test('depolama, zaman aşımı, bağlantı ve genel hatalar', () {
      expect(sehiriciErrorMessage(const StorageException('Payload too large')),
          'Görsel çok büyük (en fazla 1 MB).');
      expect(sehiriciErrorMessage(const StorageException('invalid mime type')),
          'Yalnızca PNG, WebP veya JPEG görsel yüklenebilir.');
      expect(sehiriciErrorMessage(const StorageException('new row violates row-level security')),
          'Görsel yükleme yetkiniz yok.');
      expect(sehiriciErrorMessage(TimeoutException('x')), contains('zaman aşımı'));
      expect(sehiriciErrorMessage(Exception('SocketException: Failed host lookup')),
          contains('Bağlantı hatası'));
      expect(sehiriciErrorMessage(Exception('bir şey ters gitti')),
          'bir şey ters gitti');
      expect(sehiriciErrorMessage(const SehiriciAdminException('Şu olmaz')), 'Şu olmaz');
    });
  });

  // ════════════════════════════════════════════════════════════
  group('Türkçe yardımcılar', () {
    test('büyük harf: i → İ, ı → I', () {
      expect(sehiriciUpper('harita'), 'HARİTA');
      expect(sehiriciUpper('ışık'), 'IŞIK');
      expect(sehiriciUpper('şoförler'), 'ŞOFÖRLER');
      expect(sehiriciUpper('Canlı harita'), 'CANLI HARİTA');
    });

    test('arama sadeleştirme büyük/küçük ve aksan duyarsız', () {
      expect(sehiriciFold('Çarşı İstasyon'), 'carsi istasyon');
      expect(sehiriciFold('ŞIRNAK'), 'sirnak');
      expect(sehiriciFold('Üniversite').contains(sehiriciFold('UNI')), isTrue);
    });

    test('ikon anahtarı addan üretilir', () {
      expect(sehiriciIconKeyFromName('Taksi'), 'taksi');
      expect(sehiriciIconKeyFromName('Servis Aracı'), 'servis_araci');
      expect(sehiriciIconKeyFromName('  Şehir Turu! '), 'sehir_turu');
      expect(sehiriciIconKeyFromName('1. Hat'), 'x_1_hat',
          reason: 'harfle başlamalı');
      expect(sehiriciIconKeyFromName('!!!'), '');
      expect(sehiriciIconKeyFromName('a' * 60), hasLength(28));
    });

    test('şehir bağlantı adı (slug)', () {
      expect(SehiriciCityService.slugify('Şırnak Merkez'), 'sirnak-merkez');
      expect(SehiriciCityService.slugify('İstanbul'), 'istanbul');
      expect(SehiriciCityService.slugify('  Cizre  '), 'cizre');
      expect(SehiriciCityService.slugify('###'), 'sehir');
    });

    test('renk yardımcıları', () {
      expect(sehiriciColorHex(const Color(0xFF1976D2)), '#1976D2');
      expect(sehiriciColorHex(const Color(0xFF0000FF)), '#0000FF');
      expect(sehiriciParseColor('#e53935'), const Color(0xFFE53935));
      expect(sehiriciParseColor('bozuk'), const Color(0xFF1976D2));
      expect(sehiriciParseColor(null, fallback: Colors.red), Colors.red);
      expect(sehiriciOnColor(Colors.white), const Color(0xFF111827));
      expect(sehiriciOnColor(const Color(0xFF1976D2)), Colors.white);
    });
  });

  // ════════════════════════════════════════════════════════════
  group('Varış hesabı', () {
    SehiriciLine line() => const SehiriciLine(
          id: 'L1',
          code: '4A',
          name: 'Merkez',
          stops: [
            SehiriciLineStop(stopId: 's1', stopOrder: 0, minutesFromStart: 0, name: 'A', lat: 37.3268, lng: 42.1885),
            SehiriciLineStop(stopId: 's2', stopOrder: 1, minutesFromStart: 3, name: 'B', lat: 37.3271, lng: 42.1899),
            SehiriciLineStop(stopId: 's3', stopOrder: 2, minutesFromStart: 6, name: 'C', lat: 37.3275, lng: 42.1913),
            SehiriciLineStop(stopId: 's4', stopOrder: 3, minutesFromStart: 10, name: 'D', lat: 37.3281, lng: 42.1926),
          ],
        );

    SehiriciActiveTrip trip({
      String? next = 's3',
      int? eta = 2,
      SehiriciTripStatus status = SehiriciTripStatus.active,
      String id = 't1',
    }) =>
        SehiriciActiveTrip(
          tripId: id,
          lineId: 'L1',
          lineCode: '4A',
          lineName: 'Merkez',
          lineColor: '#1976D2',
          currentLat: 37.3272,
          currentLng: 42.1905,
          nextStopId: next,
          etaMinutes: eta,
          status: status,
        );

    test('ilerideki durak: sıradakine kalan + aradaki süre', () {
      final a = computeStopArrival(line: line(), trip: trip(), stopId: 's4');
      expect(a.passed, isFalse);
      expect(a.minutes, 2 + (10 - 6));
    });

    test('sıradaki durağın kendisi: yalnız kalan süre', () {
      final a = computeStopArrival(line: line(), trip: trip(), stopId: 's3');
      expect(a.minutes, 2);
    });

    test('geçilmiş durak', () {
      final a = computeStopArrival(line: line(), trip: trip(), stopId: 's2');
      expect(a.passed, isTrue);
      expect(a.minutes, isNull);
    });

    test('sıradaki durak bilinmiyorsa kuş uçuşu tahmin', () {
      final a = computeStopArrival(
          line: line(), trip: trip(next: null, eta: null), stopId: 's4');
      expect(a.passed, isFalse);
      expect(a.minutes, isNotNull);
      expect(a.minutes, greaterThan(0));
    });

    test('durak hatta yoksa hesaplanamaz', () {
      final a = computeStopArrival(line: line(), trip: trip(), stopId: 'yok');
      expect(a.minutes, isNull);
      expect(a.passed, isFalse);
    });

    test('sıralama: en yakın önce; mola, hesaplanamayan ve geçenler sonda', () {
      final l = line();
      final list = arrivalsForStop(stopId: 's4', lines: [l], trips: [
        trip(id: 'gecmis', next: 's4', eta: 9), // hedefin kendisi: 9+0 dk
        trip(id: 'yakin', next: 's3', eta: 1), // 1 + 4 = 5 dk
        trip(id: 'mola', next: 's3', eta: 1, status: SehiriciTripStatus.paused),
      ]);
      expect(list.map((a) => a.trip.tripId), ['yakin', 'gecmis', 'mola']);
      expect(list.last.onBreak, isTrue);
    });

    test('varış metni', () {
      expect(formatArrivalMinutes(0), 'Şimdi');
      expect(formatArrivalMinutes(-3), 'Şimdi');
      expect(formatArrivalMinutes(5), '5 dk');
      expect(formatArrivalMinutes(60), '1 sa');
      expect(formatArrivalMinutes(65), '1 sa 5 dk');
    });
  });

  // ════════════════════════════════════════════════════════════
  group('Harita stili (AppMapStyle)', () {
    const featureTypes = {
      'administrative', 'administrative.country', 'administrative.land_parcel',
      'administrative.locality', 'administrative.neighborhood',
      'administrative.province', 'landscape', 'landscape.man_made',
      'landscape.natural', 'poi', 'poi.attraction', 'poi.business',
      'poi.government', 'poi.medical', 'poi.park', 'poi.place_of_worship',
      'poi.school', 'poi.sports_complex', 'road', 'road.arterial',
      'road.highway', 'road.local', 'transit', 'water',
    };
    const elementTypes = {
      'all', 'geometry', 'geometry.fill', 'geometry.stroke', 'labels',
      'labels.icon', 'labels.text', 'labels.text.fill', 'labels.text.stroke',
    };
    const stylerKeys = {
      'color', 'visibility', 'weight', 'hue', 'saturation', 'lightness',
      'gamma', 'invert_lightness',
    };

    for (final entry in {
      'açık': AppMapStyle.light,
      'koyu': AppMapStyle.dark,
    }.entries) {
      test('${entry.key}: geçerli JSON ve Google stil şeması', () {
        final rules = (jsonDecode(entry.value) as List).cast<Map<String, dynamic>>();
        expect(rules, isNotEmpty);
        for (final rule in rules) {
          expect(rule.keys.toSet().difference({'featureType', 'elementType', 'stylers'}),
              isEmpty, reason: '$rule');
          final feature = rule['featureType'] as String?;
          if (feature != null) expect(featureTypes, contains(feature));
          final element = rule['elementType'] as String?;
          if (element != null) expect(elementTypes, contains(element));
          final stylers = (rule['stylers'] as List).cast<Map<String, dynamic>>();
          expect(stylers, isNotEmpty);
          for (final s in stylers) {
            expect(s, hasLength(1), reason: 'her styler tek anahtar: $s');
            final key = s.keys.single;
            expect(stylerKeys, contains(key));
            final value = s[key];
            if (key == 'color') {
              expect(value, matches(RegExp(r'^#[0-9a-fA-F]{6}$')), reason: '$rule');
            }
            if (key == 'visibility') {
              expect(['on', 'off', 'simplified'], contains(value));
            }
          }
        }
      });

      test('${entry.key}: toplu taşıma durakları gizli (durakları biz çizeriz)', () {
        final rules = (jsonDecode(entry.value) as List).cast<Map<String, dynamic>>();
        final transit = rules.where((r) => r['featureType'] == 'transit');
        expect(transit, isNotEmpty);
        expect(
          transit.any((r) => (r['stylers'] as List).any(
              (s) => (s as Map)['visibility'] == 'off')),
          isTrue,
        );
      });
    }
  });
  // ════════════════════════════════════════════════════════════
  group('Servisler: sunucuya giden parametreler', () {
    test('saveLine: değerler kırpılır, tür anahtarı ve sıra iletilir', () async {
      final service = SehiriciLineService(
        client: makeClient((r) => json(r, null)),
      );
      final id = await service.saveLine(
        cityId: 'city-1',
        code: '  4A ',
        name: ' Merkez – Hastane ',
        colorHex: '#1976D2',
        vehicleKey: 'servis_araci',
        estimatedMinutes: 22,
        fareAmount: 12.5,
      );
      expect(requests.last.url.path, endsWith('/rpc/admin_upsert_sehirici_line'));
      final body = lastBody();
      expect(body['p_id'], id);
      expect(body['p_code'], '4A');
      expect(body['p_name'], 'Merkez – Hastane');
      expect(body['p_vehicle_type'], 'servis_araci');
      expect(body['p_estimated_minutes'], 22);
      expect(body['p_fare_amount'], 12.5);
      expect(body['p_display_order'], isNull, reason: 'null = mevcut sıra korunur');
      expect(body['p_is_active'], isTrue);
    });

    test('saveLine: kod çakışması Türkçe istisna olur', () async {
      final service = SehiriciLineService(
        client: makeClient((r) => pgError(
              r,
              '23505',
              'duplicate key value violates unique constraint '
                  '"sehirici_lines_city_id_code_key"',
            )),
      );
      await expectLater(
        service.saveLine(
          cityId: 'c',
          code: '4A',
          name: 'x',
          colorHex: '#000000',
          vehicleKey: 'bus',
        ),
        throwsA(isA<SehiriciAdminException>().having(
            (e) => e.message, 'message', 'Bu hat kodu bu şehirde zaten kullanılıyor.')),
      );
    });

    test('setLineStopsOrThrow: eksik alanlar 0 ile tamamlanır', () async {
      final service =
          SehiriciLineService(client: makeClient((r) => json(r, null)));
      await service.setLineStopsOrThrow('L1', [
        {'stop_id': 's1', 'stop_order': 0},
        {'stop_id': 's2', 'stop_order': 1, 'minutes_from_start': 4, 'distance_km': 1.2},
      ]);
      expect(requests.last.url.path, endsWith('/rpc/admin_set_sehirici_line_stops'));
      final body = lastBody();
      expect(body['p_line_id'], 'L1');
      final stops = (body['p_stops'] as List).cast<Map>();
      expect(stops.first['minutes_from_start'], 0);
      expect(stops.first['distance_km'], 0);
      expect(stops.last['minutes_from_start'], 4);
      expect(stops.last['distance_km'], 1.2);
    });

    test('saveStop: boş ad ve geçersiz konum ağa çıkmadan reddedilir', () async {
      final service = SehiriciLineService(client: makeClient((r) => json(r, null)));
      await expectLater(
        service.saveStop(cityId: 'c', name: '  ', lat: 37, lng: 42),
        throwsA(isA<SehiriciAdminException>()),
      );
      await expectLater(
        service.saveStop(cityId: 'c', name: 'A', lat: 137, lng: 42),
        throwsA(isA<SehiriciAdminException>()),
      );
      expect(requests, isEmpty);
      await service.saveStop(
          cityId: 'c', name: 'A', lat: 37, lng: 42, address: 'Cd. 5', code: 'A01');
      final body = lastBody();
      expect(body['p_address'], 'Cd. 5', reason: 'adres artık kaybolmaz');
      expect(body['p_code'], 'A01');
    });

    test('saveCity: doğrulama hataları ağa çıkmadan döner', () async {
      final service = SehiriciCityService(client: makeClient((r) => json(r, null)));
      SehiriciCity city({String name = 'Cizre', double lat = 37.3, double lng = 42.2, int zoom = 14}) =>
          SehiriciCity(
              id: '', name: name, slug: '', centerLat: lat, centerLng: lng, zoomLevel: zoom);
      for (final bad in [
        city(name: '  '),
        city(lat: 0, lng: 0),
        city(lat: 95),
        city(zoom: 2),
        city(zoom: 25),
      ]) {
        await expectLater(service.saveCity(bad), throwsA(isA<SehiriciAdminException>()));
      }
      expect(requests, isEmpty);
    });

    test('saveCity: bağlantı adı istemcide üretilir', () async {
      final service = SehiriciCityService(client: makeClient((r) => json(r, null)));
      final id = await service.saveCity(const SehiriciCity(
          id: '', name: 'Şırnak Merkez', slug: '', centerLat: 37.5, centerLng: 42.4, zoomLevel: 13));
      final body = lastBody();
      expect(body['p_id'], id);
      expect(body['p_slug'], 'sirnak-merkez');
      expect(body['p_name'], 'Şırnak Merkez');
    });

    test('updateSettingOrThrow: değer DÜZ metin olarak yazılır', () async {
      final service = SehiriciCityService(client: makeClient((r) => json(r, [])));
      await service.updateSettingOrThrow('sehirici_module_enabled', 'true');
      expect(requests.last.method, 'POST');
      expect(requests.last.url.path, endsWith('/app_settings'));
      final body = lastBody();
      expect(body['key'], 'sehirici_module_enabled');
      expect(body['value'], 'true', reason: "'\"true\"' (çift tırnaklı) DEĞİL");
    });

    test('saveIcon: parametreler eşlenir ve kimlik döner', () async {
      final service = SehiriciIconService(
        client: makeClient((r) => json(r, 'ic-42')),
      );
      final id = await service.saveIcon(const SehiriciMarkerIconDraft(
        kind: SehiriciIconKind.vehicle,
        key: 'taksi',
        label: 'Taksi',
        builtinShape: 'taxi',
        scale: 1.2,
        sortOrder: 60,
      ));
      expect(id, 'ic-42');
      final body = lastBody();
      expect(requests.last.url.path,
          endsWith('/rpc/admin_upsert_sehirici_marker_icon'));
      expect(body['p_kind'], 'vehicle');
      expect(body['p_key'], 'taksi');
      expect(body['p_builtin_shape'], 'taxi');
      expect(body['p_image_url'], isNull);
      expect(body['p_scale'], 1.2);
      expect(body['p_sort_order'], 60);
      expect(body['p_id'], isNull, reason: 'yeni ikon');
    });

    test('saveIcon: sunucu reddi Türkçe istisna olur', () async {
      final service = SehiriciIconService(
        client: makeClient((r) => pgError(r, 'P0001', 'Bu anahtar zaten kullanılıyor')),
      );
      await expectLater(
        service.saveIcon(const SehiriciMarkerIconDraft(
            kind: SehiriciIconKind.stop, key: 'stop_x', label: 'X')),
        throwsA(isA<SehiriciAdminException>().having(
            (e) => e.message, 'message', 'Bu anahtar zaten kullanılıyor')),
      );
    });

    test('uploadImage: boş, büyük ve desteklenmeyen dosyalar reddedilir', () async {
      final service = SehiriciIconService(client: makeClient((r) => json(r, null)));
      await expectLater(
        service.uploadImage(bytes: Uint8List(0), fileName: 'a.png', key: 'k'),
        throwsA(isA<SehiriciAdminException>()),
      );
      await expectLater(
        service.uploadImage(
            bytes: Uint8List(SehiriciIconService.maxImageBytes + 1),
            fileName: 'a.png',
            key: 'k'),
        throwsA(isA<SehiriciAdminException>()
            .having((e) => e.message, 'message', contains('1 MB'))),
      );
      await expectLater(
        service.uploadImage(bytes: Uint8List(10), fileName: 'a.gif', key: 'k'),
        throwsA(isA<SehiriciAdminException>()
            .having((e) => e.message, 'message', contains('PNG'))),
      );
      expect(requests, isEmpty, reason: 'hiçbiri ağa çıkmamalı');
    });
  });
}
