// ignore_for_file: depend_on_referenced_packages, deprecated_member_use

import 'dart:convert';

import 'package:cizreapp/sehirici/admin/sehirici_admin_controller.dart';
import 'package:cizreapp/sehirici/admin/sehirici_admin_kit.dart';
import 'package:cizreapp/sehirici/services/sehirici_road_snap_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../helpers/sehirici_admin_harness.dart';

/// Admin durak ekleme kolaylıkları: sokak adından otomatik ad ve kaldığı
/// yerden numara ("Yafes Cad. 1, 2 …"), hattın son durağından devam,
/// gri durağa dokunarak hatta bağlama, formda hatlara bağlama ve
/// "Ekle ve devam et".
void main() {
  final h = SehiriciAdminHarness()..register();

  const yafes = LatLng(37.3320, 42.1900);
  const yafes2 = LatLng(37.3324, 42.1906);
  const silopi = LatLng(37.3360, 42.1980);

  void addStreets() {
    h.streets
      ..add((at: yafes, street: 'Yafes Caddesi', neighborhood: 'Nur', others: ['Temiz Sokak']))
      ..add((at: silopi, street: 'Silopi Caddesi', neighborhood: 'Konak', others: const []));
  }

  void addStop(String id, String name, double lat, double lng) {
    h.backend.stops.add({
      'id': id,
      'name': name,
      'code': null,
      'lat': lat,
      'lng': lng,
      'address': null,
      'is_active': true,
      'city_id': 'city-1',
    });
  }

  /// OSRM yerine geçen sahte yol servisi: istenen noktalardan geçen düz rota.
  SehiriciAdminController controllerWithRoads() {
    return SehiriciAdminController(
      roadSnapService: SehiriciRoadSnapService(
        client: MockClient((req) async {
          final coords = req.url.pathSegments.last.split(';').map((c) {
            final p = c.split(',');
            return [double.parse(p[0]), double.parse(p[1])];
          }).toList();
          return http.Response(
            jsonEncode({
              'code': 'Ok',
              'routes': [
                {
                  'geometry': {'type': 'LineString', 'coordinates': coords},
                },
              ],
            }),
            200,
            request: req,
          );
        }),
      ),
    );
  }

  Future<void> tapMapAt(WidgetTester tester, LatLng position) async {
    h.platform.tapMap(position);
    await tester.pump();
    await tester.pump();
  }

  Iterable<String> markerIds(String prefix) => h.platform.markers.keys
      .map((k) => k.value)
      .where((v) => v.startsWith(prefix));

  List<Map> upserts() => h.backend
      .rpcCalls('admin_upsert_sehirici_stop')
      .map((c) => c.body! as Map)
      .toList();

  List<String> lineRows(String lineId) {
    final call = h.backend
        .rpcCalls('admin_set_sehirici_line_stops')
        .lastWhere((c) => (c.body! as Map)['p_line_id'] == lineId);
    return [
      for (final r in ((call.body! as Map)['p_stops'] as List).cast<Map>())
        r['stop_id'] as String,
    ];
  }

  Future<void> openMultiPicker(WidgetTester tester, {SehiriciAdminController? controller}) async {
    await h.pumpAdmin(tester, tab: 2, controller: controller);
    await h.openSheet(tester, find.text('Haritadan çoklu'));
    await h.settle(tester, rounds: 4);
  }

  // ════════════════════════════════════════════════════════════
  group('Duraklar sekmesi · haritadan çoklu', () {
    h.adminTest('ad sokaktan gelir, numara kaldığı yerden sürer, adres dolar',
        (tester) async {
      addStreets();
      addStop('s10', 'Yafes Cad. 1', 37.3335, 42.1885);
      await openMultiPicker(tester);

      await tapMapAt(tester, yafes);
      await tapMapAt(tester, yafes2);
      await tapMapAt(tester, silopi);
      await h.settle(tester, rounds: 4);

      // Şehirde "Yafes Cad. 1" var → 2, 3; Silopi'de ilk durak → 1.
      expect(find.text('Yafes Cad. 2'), findsOneWidget);
      expect(find.text('Yafes Cad. 3'), findsOneWidget);
      expect(find.text('Silopi Cad. 1'), findsOneWidget);
      await h.snapshot(tester, 'admin_30_multi_street_names');

      await tester.tap(find.text('3 durağı ekle'));
      await tester.pump();
      await h.settle(tester, rounds: 6);

      final created = upserts();
      expect(created.map((p) => p['p_name']),
          ['Yafes Cad. 2', 'Yafes Cad. 3', 'Silopi Cad. 1']);
      expect(created.map((p) => p['p_address']),
          ['Nur Mah., Yafes Cad.', 'Nur Mah., Yafes Cad.', 'Konak Mah., Silopi Cad.']);
      expect(h.backend.rpcCalls('admin_set_sehirici_line_stops'), isEmpty,
          reason: 'hat seçilmedi');
      expect(find.text('3 durak eklendi.'), findsOneWidget);
      // Liste yenilendi; doğal sırada (… 2 < … 3; "10" olsa da sonda kalırdı).
      await tester.enterText(find.byType(TextField).first, 'yafes');
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Yafes Cad. 3'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Yafes Cad. 2')).dy,
        lessThan(tester.getTopLeft(find.text('Yafes Cad. 3')).dy),
      );

      // Devam: seçici son eklenen durağın yanında açılır, numara 4'ten sürer.
      await h.openSheet(tester, find.text('Haritadan çoklu'));
      await h.settle(tester, rounds: 4);
      expect(h.platform.camera.target, silopi);
      await tapMapAt(tester, const LatLng(37.3316, 42.1895));
      await h.settle(tester, rounds: 3);
      expect(find.text('Yafes Cad. 4'), findsOneWidget);
    });

    h.adminTest('elle ad değiştirmek diğer pinin numarasını kaydırmaz; öneri menüsü',
        (tester) async {
      addStreets();
      await openMultiPicker(tester);
      await tapMapAt(tester, yafes);
      await tapMapAt(tester, yafes2);
      await h.settle(tester, rounds: 3);
      expect(find.text('Yafes Cad. 1'), findsOneWidget);
      expect(find.text('Yafes Cad. 2'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, 'Yafes Cad. 1'), 'Belediye Önü');
      await tester.pump();
      expect(find.text('Yafes Cad. 2'), findsOneWidget, reason: 'numara yerinde kalır');

      // İkinci pin için yakındaki diğer sokak.
      await tester.tap(find.byTooltip('Ad önerileri').at(1));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Temiz Sk. 1'), findsOneWidget);
      expect(find.text('Nur Mah. 1'), findsOneWidget);
      expect(find.text('Durak 1'), findsOneWidget);
      await tester.tap(find.text('Temiz Sk. 1'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.widgetWithText(TextField, 'Temiz Sk. 1'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Belediye Önü'), findsOneWidget);
    });

    h.adminTest('sokak bulunamazsa "Durak N" — yine kaldığı yerden', (tester) async {
      addStop('s10', 'Durak 15', 37.3335, 42.1885);
      addStop('s11', 'Durak 18', 37.3340, 42.1890);
      await openMultiPicker(tester);
      await tapMapAt(tester, yafes);
      await h.settle(tester, rounds: 3);
      expect(find.text('Durak 19'), findsOneWidget);
    });

    h.adminTest('hat seçilmeden mevcut durağa çok yakın dokunuş reddedilir',
        (tester) async {
      await openMultiPicker(tester);
      // Otogar (s1) tam üstü.
      await tapMapAt(tester, const LatLng(37.3268, 42.1885));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('çok yakın bir durak zaten var: Otogar'),
          findsOneWidget);
      expect(markerIds('picked_'), isEmpty);
      // Uyarı süresi dolunca kalkar (bekleyen zamanlayıcı bırakmamak için).
      await tester.pump(const Duration(seconds: 5));
    });

    h.adminTest('"Hatta da ekle": hat durakları numaralı, yeni durak sondan sürer, '
        'gri durak bağlanır', (tester) async {
      addStreets();
      await openMultiPicker(tester, controller: controllerWithRoads());

      await tester.tap(find.byKey(const ValueKey('sehirici-picker-line')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Merkez – Hastane').last);
      await tester.pump();
      await h.settle(tester, rounds: 4);

      expect(markerIds('line_'), hasLength(6), reason: '4A durakları sabit, numaralı');
      expect(markerIds('existing_'), hasLength(3), reason: 's7, s8, s9 gri');
      expect(find.text('Hatta 6 durak · 0 yeni'), findsOneWidget);
      expect(find.textContaining('6. durağından devam edin'), findsOneWidget);

      await tapMapAt(tester, yafes);
      h.platform.tapMarker('existing_s9'); // Eski Terminal
      await tester.pump();
      await tester.pump();
      await h.settle(tester, rounds: 3);

      expect(find.text('Yafes Cad. 1'), findsOneWidget);
      expect(find.text('7'), findsOneWidget, reason: 'numara hattın 6. durağından sürer');
      expect(find.text('8'), findsOneWidget);
      expect(find.text('Mevcut durak · hatta bağlanır'), findsOneWidget);
      expect(h.platform.polylines.keys.map((k) => k.value),
          containsAll(['line_existing', 'picked_order']));
      // Son hat durağından yeni kısma bağlanan çizgi.
      final fresh = h.platform.polylines.values
          .firstWhere((p) => p.polylineId.value == 'picked_order');
      expect(fresh.points.first, const LatLng(37.3296, 42.1951));
      expect(fresh.points, hasLength(3));
      await h.snapshot(tester, 'admin_31_multi_continue_line');

      await tester.tap(find.text('2 durağı ekle'));
      await tester.pump();
      await h.settle(tester, rounds: 8);

      final created = upserts();
      expect(created, hasLength(1), reason: 'yalnız yeni durak oluşturulur');
      expect(created.single['p_name'], 'Yafes Cad. 1');
      expect(lineRows('L1'),
          ['s1', 's2', 's3', 's4', 's5', 's6', created.single['p_id'], 's9']);
      // 4A'nın kayıtlı rotası yeni sırayla yenilendi.
      final route = h.backend.rpcCalls('cache_sehirici_route_polyline').toList();
      expect(route, hasLength(1));
      expect((route.single.body! as Map)['p_line_id'], 'L1');
      expect(find.textContaining('4A hattının sonuna 2 durak bağlandı.'), findsOneWidget);
    });
  });

  // ════════════════════════════════════════════════════════════
  group('Hat durak düzenleyicisi · haritada devam', () {
    h.adminTest('dolu hatta "Haritada devam et": hat durakları sabit, yeni ad sokaktan',
        (tester) async {
      addStreets();
      await h.pumpAdmin(tester, tab: 1);
      final opener = find.widgetWithText(SehiriciCardAction, 'Duraklar').first;
      await tester.ensureVisible(opener);
      await tester.pump();
      await h.openSheet(tester, opener);
      expect(find.text('Haritada devam et'), findsOneWidget);
      await h.openSheet(tester, find.text('Haritada devam et'));
      await h.settle(tester, rounds: 4);

      expect(markerIds('line_'), hasLength(6));
      // Kamera hattın son durağında (Üniversite) açılır.
      expect(h.platform.camera.target, const LatLng(37.3296, 42.1951));
      await tapMapAt(tester, yafes);
      await h.settle(tester, rounds: 3);
      expect(find.text('Yafes Cad. 1'), findsOneWidget);
      expect(find.text('7'), findsOneWidget);

      await tester.tap(find.text('1 durağı ekle'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Yafes Cad. 1'), findsOneWidget);
      expect(find.text('Kaydet · 7 durak'), findsOneWidget);
      await tester.tap(find.text('Kaydet · 7 durak'));
      await tester.pump();
      await h.settle(tester, rounds: 6);
      final created = upserts();
      expect(created.single['p_name'], 'Yafes Cad. 1');
      expect(created.single['p_address'], 'Nur Mah., Yafes Cad.');
      expect(lineRows('L1').last, created.single['p_id']);
    });
  });

  // ════════════════════════════════════════════════════════════
  group('Durak formu', () {
    Future<void> openNewStop(WidgetTester tester, {SehiriciAdminController? controller}) async {
      await h.pumpAdmin(tester, tab: 2, controller: controller);
      await h.openSheet(tester, find.text('Yeni Durak'));
    }

    Future<void> pickOnMap(WidgetTester tester, LatLng at) async {
      await h.openSheet(tester, find.text('Haritadan seç'));
      await h.settle(tester, rounds: 3);
      await tapMapAt(tester, at);
      await h.settle(tester, rounds: 3);
      await tester.tap(find.text('Bu konumu kullan'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await h.settle(tester, rounds: 3);
    }

    Finder field(String text) => find.widgetWithText(TextFormField, text);

    h.adminTest('konum seçilince ad + adres sokaktan; öneri çipleri', (tester) async {
      addStreets();
      addStop('s10', 'Yafes Cad. 1', 37.3335, 42.1885);
      await openNewStop(tester);
      expect(find.text('Ekle ve devam et'), findsOneWidget);

      await h.openSheet(tester, find.text('Haritadan seç'));
      await h.settle(tester, rounds: 3);
      await tapMapAt(tester, yafes);
      await h.settle(tester, rounds: 3);
      // Tek seçim alt şeridi pinin sokağını gösterir.
      expect(find.text('Yafes Cad.'), findsOneWidget);
      await tester.tap(find.text('Bu konumu kullan'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await h.settle(tester, rounds: 3);

      expect(field('Yafes Cad. 2'), findsOneWidget);
      expect(field('Nur Mah., Yafes Cad.'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Temiz Sk. 1'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Durak 1'), findsOneWidget);
      await h.snapshot(tester, 'admin_32_stop_form_street_name');

      await tester.tap(find.widgetWithText(ChoiceChip, 'Temiz Sk. 1'));
      await tester.pump();
      expect(field('Temiz Sk. 1'), findsOneWidget);

      await tester.tap(find.text('Durağı Ekle'));
      await tester.pump();
      await h.settle(tester, rounds: 6);
      expect(upserts().single['p_name'], 'Temiz Sk. 1');
      expect(find.text('“Temiz Sk. 1” eklendi.'), findsOneWidget);
    });

    h.adminTest('hatlara bağla: en uygun sıraya girer, önizleme gösterilir',
        (tester) async {
      await openNewStop(tester, controller: controllerWithRoads());
      await tester.enterText(field('Enlem'), '37.3273');
      await tester.enterText(field('Boylam'), '42.1906');
      await tester.enterText(field('Durak adı'), 'Belediye Arkası');
      await tester.pump();

      final chip = find.byKey(const ValueKey('stop-line-L1'));
      await tester.ensureVisible(chip);
      await tester.pump();
      await tester.tap(chip);
      await tester.pump();
      expect(find.text('4A: 3. durak olur (Belediye ile Çarşı arası)'), findsOneWidget);
      await h.snapshot(tester, 'admin_33_stop_form_lines');

      await tester.tap(find.text('Durağı Ekle'));
      await tester.pump();
      await h.settle(tester, rounds: 8);

      final id = upserts().single['p_id'];
      expect(lineRows('L1'), ['s1', 's2', id, 's3', 's4', 's5', 's6']);
      expect(
        h.backend.rpcCalls('admin_set_sehirici_line_stops')
            .where((c) => (c.body! as Map)['p_line_id'] != 'L1'),
        isEmpty,
      );
      expect(h.backend.rpcCalls('cache_sehirici_route_polyline'), hasLength(1));
      expect(find.textContaining('4A hattına bağlandı.'), findsOneWidget);
    });

    h.adminTest('mevcut durağı bir hattan çıkarmak yalnız o hattı yazar', (tester) async {
      await h.pumpAdmin(tester, tab: 2, controller: controllerWithRoads());
      await h.openSheet(tester, find.text('Belediye').first);
      expect(find.text('Durağı Düzenle'), findsOneWidget);

      final chip = find.byKey(const ValueKey('stop-line-L2'));
      await tester.ensureVisible(chip);
      await tester.pump();
      await tester.tap(chip);
      await tester.pump();
      expect(find.text('Kaydet · hatlar'), findsOneWidget);

      await tester.tap(find.text('Kaydet · hatlar'));
      await tester.pump();
      await h.settle(tester, rounds: 8);
      expect(lineRows('L2'), ['s3', 's7', 's8']);
      expect(
        h.backend.rpcCalls('admin_set_sehirici_line_stops')
            .where((c) => (c.body! as Map)['p_line_id'] == 'L1'),
        isEmpty,
      );
      expect(find.textContaining('7B hattından çıkarıldı.'), findsOneWidget);
    });

    h.adminTest('"Ekle ve devam et": form boşalır, harita son duraktan açılır, numara sürer',
        (tester) async {
      addStreets();
      await openNewStop(tester);
      await pickOnMap(tester, yafes);
      expect(field('Yafes Cad. 1'), findsOneWidget);

      await tester.tap(find.text('Ekle ve devam et'));
      await tester.pump();
      await h.settle(tester, rounds: 6);
      // Sayfa açık, form boş, başarı şeridi.
      expect(find.text('Yeni Durak'), findsWidgets);
      expect(find.textContaining('“Yafes Cad. 1” eklendi.'), findsOneWidget);
      expect(field('Yafes Cad. 1'), findsNothing);
      await h.snapshot(tester, 'admin_34_stop_form_continue');

      await h.openSheet(tester, find.text('Haritadan seç'));
      await h.settle(tester, rounds: 3);
      expect(h.platform.camera.target, yafes, reason: 'son eklenen duraktan devam');
      await tapMapAt(tester, yafes2);
      await h.settle(tester, rounds: 3);
      await tester.tap(find.text('Bu konumu kullan'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await h.settle(tester, rounds: 3);
      expect(field('Yafes Cad. 2'), findsOneWidget);

      await tester.tap(find.text('Durağı Ekle'));
      await tester.pump();
      await h.settle(tester, rounds: 6);
      final created = upserts();
      expect(created.map((p) => p['p_name']), ['Yafes Cad. 1', 'Yafes Cad. 2']);
      expect(created[0]['p_id'], isNot(created[1]['p_id']), reason: 'iki ayrı durak');
      expect(find.text('“Yafes Cad. 2” eklendi.'), findsOneWidget);
    });
  });
}
