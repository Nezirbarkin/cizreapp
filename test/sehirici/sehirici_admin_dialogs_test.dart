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

/// Hat durak düzenleyicisi, haritadan konum seçici ve rota çizim ekranı.
void main() {
  final h = SehiriciAdminHarness()..register();

  /// OSRM yerine geçen sahte yol servisi: istenen noktalardan geçen düz bir
  /// rota döner (ok=false ise sunucu hatası).
  SehiriciAdminController controllerWithRoads({bool ok = true}) {
    return SehiriciAdminController(
      roadSnapService: SehiriciRoadSnapService(
        client: MockClient((req) async {
          if (!ok) return http.Response('{}', 500, request: req);
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
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      ),
    );
  }

  Future<void> openStopsEditor(
    WidgetTester tester, {
    int card = 0,
    SehiriciAdminController? controller,
  }) async {
    await h.pumpAdmin(tester, tab: 1, controller: controller);
    final opener = find.widgetWithText(SehiriciCardAction, 'Duraklar').at(card);
    // Liste tembel ve kaydırmalı: ekran dışındaki karta dokunmak boşa gider.
    await tester.ensureVisible(opener);
    await tester.pump();
    await h.openSheet(tester, opener);
  }

  /// Haritaya dokunur: olay bir akıştan gelir, iki kare sonra ekrana yansır.
  Future<void> tapMapAt(WidgetTester tester, LatLng position) async {
    h.platform.tapMap(position);
    await tester.pump();
    await tester.pump();
  }

  Iterable<Map> rowsOf(Object? body) =>
      ((body! as Map)['p_stops'] as List).cast<Map>();

  Future<void> saveEditor(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pump();
    await h.settle(tester, rounds: 6);
  }

  // ════════════════════════════════════════════════════════════
  group('Hat durak düzenleyicisi', () {
    h.adminTest('duraklar sırayla, mesafe ve süreyle listelenir', (tester) async {
      await openStopsEditor(tester);
      expect(find.text('4A · Duraklar'), findsOneWidget);
      expect(find.textContaining('6 durak ·'), findsOneWidget);
      for (final name in ['Otogar', 'Belediye', 'Çarşı', 'Üniversite']) {
        expect(find.text(name), findsOneWidget);
      }
      // İlk durak "Başlangıç"; sonrakiler önceki duraktan ve toplam mesafeyi yazar.
      expect(find.text('Başlangıç'), findsOneWidget);
      expect(find.textContaining('toplam'), findsWidgets);
      // Değişiklik yokken kaydet kapalı.
      expect(find.text('Değişiklik yok'), findsOneWidget);
      await h.snapshot(tester, 'admin_16_stops_editor');
    });

    h.adminTest('boş hatta boş durum ve iki ekleme yolu gösterilir', (tester) async {
      await openStopsEditor(tester, card: 2);
      expect(find.text('Bu hatta henüz durak yok'), findsOneWidget);
      expect(find.text('Haritadan yeni'), findsWidgets);
      expect(find.text('Durak ekle'), findsWidgets);
      await h.snapshot(tester, 'admin_17_stops_editor_empty');
    });

    h.adminTest('durak çıkarınca Kaydet açılır; atomik RPC + rota yenileme',
        (tester) async {
      await openStopsEditor(tester, controller: controllerWithRoads());
      await tester.tap(find.byTooltip('Duraktan çıkar').at(1)); // Belediye
      await tester.pump();

      expect(find.text('Kaydet · 5 durak'), findsOneWidget);
      expect(find.textContaining('yeniden oluştur'), findsOneWidget);
      expect(find.text('Belediye'), findsNothing);
      await h.snapshot(tester, 'admin_18_stops_editor_dirty');

      await saveEditor(tester, 'Kaydet · 5 durak');

      final calls = h.backend.rpcCalls('admin_set_sehirici_line_stops').toList();
      expect(calls, hasLength(1), reason: 'tek işlemde yazılır');
      final params = calls.single.body! as Map;
      expect(params['p_line_id'], 'L1');
      final rows = rowsOf(params).toList();
      expect(rows.map((r) => r['stop_id']), ['s1', 's3', 's4', 's5', 's6']);
      expect(rows.map((r) => r['stop_order']), [0, 1, 2, 3, 4]);
      // Mesafe ve süre hat başından itibaren artar.
      final km = rows.map((r) => (r['distance_km'] as num).toDouble()).toList();
      expect(km.first, 0);
      for (var i = 1; i < km.length; i++) {
        expect(km[i], greaterThan(km[i - 1]));
      }
      // Rota da yeniden üretildi.
      final route = h.backend.rpcCalls('cache_sehirici_route_polyline').toList();
      expect(route, hasLength(1));
      expect((route.single.body! as Map)['p_line_id'], 'L1');
      // Sayfa kapandı, hat sekmesi bildirim verdi.
      expect(find.text('Kaydet · 5 durak'), findsNothing);
      expect(find.text('Duraklar güncellendi.'), findsOneWidget);
    });

    h.adminTest('rota yenilenemezse duraklar yine de kaydedilir ve uyarılır',
        (tester) async {
      await openStopsEditor(tester, controller: controllerWithRoads(ok: false));
      await tester.tap(find.byTooltip('Duraktan çıkar').first);
      await tester.pump();
      await saveEditor(tester, 'Kaydet · 5 durak');

      expect(h.backend.rpcCalls('admin_set_sehirici_line_stops'), hasLength(1));
      expect(h.backend.rpcCalls('cache_sehirici_route_polyline'), isEmpty);
      expect(find.textContaining('Duraklar kaydedildi ama rota yenilenemedi'),
          findsOneWidget);
      // Sayfa açık; tek düğme "Kapat".
      expect(find.text('Kapat'), findsWidgets);
      expect(find.text('Vazgeç'), findsNothing);

      await tester.tap(find.text('Kapat').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.textContaining('Duraklar kaydedildi ama'), findsNothing);
    });

    h.adminTest('sunucu hatası sayfada gösterilir; eski duraklar korunur',
        (tester) async {
      await openStopsEditor(tester);
      await tester.tap(find.byTooltip('Duraktan çıkar').first);
      await tester.pump();
      h.backend
        ..failPathContaining = '/rpc/admin_set_sehirici_line_stops'
        ..failMessage = 'Bu hat değiştirilemez';
      await saveEditor(tester, 'Kaydet · 5 durak');

      expect(find.textContaining('Bu hat değiştirilemez'), findsWidgets);
      // Hâlâ düzenlenebilir ve yeniden denenebilir.
      expect(find.text('Kaydet · 5 durak'), findsOneWidget);
    });

    h.adminTest('kaydedilmemiş değişiklikle kapatmak onay ister', (tester) async {
      await openStopsEditor(tester);
      await tester.tap(find.byTooltip('Duraktan çıkar').first);
      await tester.pump();

      await tester.tap(find.byTooltip('Kapat').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Değişiklikler atılsın mı?'), findsOneWidget);

      // Vazgeç: düzenleme sürer.
      await tester.tap(find.text('Vazgeç').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Kaydet · 5 durak'), findsOneWidget);

      // Atıp çık: sayfa kapanır, hiçbir şey yazılmaz.
      await tester.tap(find.byTooltip('Kapat').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Atıp Çık'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Kaydet · 5 durak'), findsNothing);
      expect(h.backend.rpcCalls('admin_set_sehirici_line_stops'), isEmpty);
    });

    h.adminTest('sırayı ters çevir + kaydet', (tester) async {
      await openStopsEditor(tester);
      await tester.tap(find.byTooltip('Sırayı ters çevir'));
      await tester.pump();
      expect(
        tester.getTopLeft(find.text('Üniversite')).dy,
        lessThan(tester.getTopLeft(find.text('Otogar')).dy),
      );
      await saveEditor(tester, 'Kaydet · 6 durak');
      final rows = rowsOf(h.backend.rpcCalls('admin_set_sehirici_line_stops')
              .single
              .body)
          .toList();
      expect(rows.first['stop_id'], 's6');
      expect(rows.last['stop_id'], 's1');
    });

    h.adminTest('hazır duraklardan ekleme: arama ve dokunma sırası', (tester) async {
      await openStopsEditor(tester);
      await h.openSheet(tester, find.text('Durak ekle'));
      expect(find.text('Hazır duraklardan ekle'), findsOneWidget);
      // Altta editör de görünür kalır; arama yalnız seçici sayfasında yapılır.
      final picker = find.byType(SehiriciSheetScaffold);
      Finder inPicker(String text) =>
          find.descendant(of: picker, matching: find.text(text));
      // 4A'da olmayan: Kaymakamlık (s7), Sanayi Sitesi (s8), Eski Terminal (s9).
      expect(inPicker('Kaymakamlık'), findsOneWidget);
      expect(inPicker('Sanayi Sitesi'), findsOneWidget);
      expect(inPicker('Eski Terminal'), findsOneWidget);
      expect(inPicker('Otogar'), findsNothing, reason: 'zaten hatta');
      await h.snapshot(tester, 'admin_19_stop_picker');

      // Arama: Türkçe karakter duyarsız.
      await tester.enterText(find.byType(TextField).last, 'termi');
      await tester.pump(const Duration(milliseconds: 300));
      expect(inPicker('Eski Terminal'), findsOneWidget);
      expect(inPicker('Kaymakamlık'), findsNothing);
      await tester.enterText(find.byType(TextField).last, '');
      await tester.pump(const Duration(milliseconds: 300));

      // Önce Sanayi Sitesi, sonra Kaymakamlık: sıra dokunma sırasıdır.
      await tester.tap(inPicker('Sanayi Sitesi'));
      await tester.pump();
      await tester.tap(inPicker('Kaymakamlık'));
      await tester.pump();
      expect(find.text('2 durak seçildi'), findsOneWidget);
      await tester.tap(find.text('2 durağı ekle'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.text('Kaydet · 8 durak'), findsOneWidget);
      await saveEditor(tester, 'Kaydet · 8 durak');
      final ids = rowsOf(h.backend.rpcCalls('admin_set_sehirici_line_stops')
              .single
              .body)
          .map((r) => r['stop_id'])
          .toList();
      expect(ids, ['s1', 's2', 's3', 's4', 's5', 's6', 's8', 's7']);
    });
  });

  // ════════════════════════════════════════════════════════════
  group('Haritadan konum seçici', () {
    /// Boş hat + haritadan yeni durak akışını açar.
    Future<void> openMapPicker(WidgetTester tester) async {
      await openStopsEditor(tester, card: 2);
      await h.openSheet(tester, find.text('Haritadan yeni').first);
      await h.settle(tester, rounds: 6);
    }

    h.adminTest('mevcut duraklar gri nokta, yeni pinler numaralı; adlar düzenlenir',
        (tester) async {
      await openMapPicker(tester);
      expect(find.text('Haritadan Çoklu Durak'), findsOneWidget);
      // 9 mevcut durak referans olarak çizilir.
      expect(
        h.platform.markers.keys.where((k) => k.value.startsWith('existing_')),
        hasLength(9),
      );

            await tapMapAt(tester, const LatLng(37.3320, 42.1900));
            await tapMapAt(tester, const LatLng(37.3330, 42.1930));
      await h.settle(tester, rounds: 4);

      expect(h.platform.markers.keys.map((k) => k.value),
          containsAll(['picked_0', 'picked_1']));
      // Sırayı gösteren çizgi (beyaz zemin + renkli).
      expect(h.platform.polylines.keys.map((k) => k.value),
          containsAll(['picked_order_casing', 'picked_order']));
      expect(find.text('Durak 1'), findsOneWidget);
      expect(find.text('Durak 2'), findsOneWidget);
      await h.snapshot(tester, 'admin_20_location_picker');

      await tester.enterText(find.widgetWithText(TextField, 'Durak 1'), 'Yeni Durak A');
      await tester.pump();
      await tester.tap(find.text('2 durağı ekle'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      // Editöre döndü: iki "Yeni" durak; kaydedilene kadar sunucuya yazılmadı.
      expect(find.text('Yeni Durak A'), findsOneWidget);
      expect(find.text('Yeni'), findsNWidgets(2));
      expect(h.backend.rpcCalls('admin_upsert_sehirici_stop'), isEmpty);
      expect(find.text('Kaydet · 2 durak'), findsOneWidget);
      await h.snapshot(tester, 'admin_21_stops_editor_new_stops');

      await saveEditor(tester, 'Kaydet · 2 durak');

      final created = h.backend.rpcCalls('admin_upsert_sehirici_stop').toList();
      expect(created, hasLength(2));
      final createdParams = created.map((c) => c.body! as Map).toList();
      expect(createdParams.map((p) => p['p_name']), ['Yeni Durak A', 'Durak 2']);
      expect(createdParams.every((p) => p['p_city_id'] == 'city-1'), isTrue);
      final linked = rowsOf(h.backend.rpcCalls('admin_set_sehirici_line_stops')
              .single
              .body)
          .map((r) => r['stop_id'])
          .toList();
      expect(linked, createdParams.map((p) => p['p_id']).toList(),
          reason: 'hatta, az önce oluşturulan duraklar oluşturulma sırasıyla');
    });

    h.adminTest('mevcut durağa çok yakın dokunuş reddedilir', (tester) async {
      await openMapPicker(tester);
      // Otogar (s1) tam üstü.
            await tapMapAt(tester, const LatLng(37.3268, 42.1885));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('çok yakın bir durak zaten var: Otogar'),
          findsOneWidget);
      expect(h.platform.markers.keys.where((k) => k.value.startsWith('picked_')),
          isEmpty);
      // Uyarı süresi dolunca kalkar (bekleyen zamanlayıcı bırakmamak için).
      await tester.pump(const Duration(seconds: 5));
    });

    h.adminTest('vazgeçince editör değişmeden kalır', (tester) async {
      await openMapPicker(tester);
            await tapMapAt(tester, const LatLng(37.3320, 42.1900));
      await tester.tap(find.text('Vazgeç').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Bu hatta henüz durak yok'), findsOneWidget);
      expect(find.text('Değişiklik yok'), findsOneWidget);
    });
  });

  // ════════════════════════════════════════════════════════════
  group('Rota çizim ekranı', () {
    Future<void> openDrawDialog(WidgetTester tester, {int card = 0}) async {
      await h.pumpAdmin(tester, tab: 1);
      await tester.tap(find.text('Rota').at(card));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      await h.openSheet(tester, find.text('Haritada elle çiz'));
      await h.settle(tester, rounds: 6);
    }

    Iterable<String> ids(String prefix) => h.platform.markers.keys
        .map((k) => k.value)
        .where((v) => v.startsWith(prefix));

    h.adminTest('rota noktaları küçük noktalar, duraklar numaralı iğne', (tester) async {
      await openDrawDialog(tester);
      expect(find.text('Rota çiz'), findsOneWidget);
      expect(find.text('11 nokta'), findsOneWidget);
      expect(ids('pt_'), hasLength(11));
      expect(ids('stop_'), hasLength(6));
      expect(h.platform.polylines.keys.map((k) => k.value),
          containsAll(['admin_route_casing', 'admin_route']));
      // Kaydet: değişiklik yokken kapalı.
      expect(find.text('Değişiklik yok'), findsOneWidget);
      await h.snapshot(tester, 'admin_22_route_draw');
    });

    h.adminTest('çok noktalı rotada işaretçi sayısı sınırlanır (harita boğulmaz)',
        (tester) async {
      // 600 noktalı bir rota: eskiden 600 ayrı varsayılan pin çiziliyordu.
      final points = [
        for (var i = 0; i < 600; i++) [37.3268 + i * 0.00005, 42.1885 + i * 0.00008],
      ];
      (h.backend.lines[0]['route_polyline'] as Map)['points'] = points;
      await openDrawDialog(tester);

      expect(find.text('600 nokta'), findsOneWidget);
      final markers = ids('pt_').toList();
      expect(markers.length, lessThanOrEqualTo(165));
      expect(markers, containsAll(['pt_0', 'pt_599']), reason: 'uçlar hep görünür');
      // Çizgi yine tüm noktalardan geçer.
      final line = h.platform.polylines.values
          .firstWhere((p) => p.polylineId.value == 'admin_route');
      expect(line.points, hasLength(600));
    });

    h.adminTest('haritaya dokunmak nokta ekler; kaydetmek rotayı yazar', (tester) async {
      await openDrawDialog(tester);
            await tapMapAt(tester, const LatLng(37.3300, 42.1960));

      expect(find.text('12 nokta'), findsOneWidget);
      expect(find.text('Rotayı kaydet'), findsOneWidget);
      await tester.tap(find.text('Rotayı kaydet'));
      await tester.pump();
      await h.settle(tester, rounds: 6);

      final calls = h.backend.rpcCalls('cache_sehirici_route_polyline').toList();
      expect(calls, hasLength(1));
      final polyline = (calls.single.body! as Map)['p_polyline'] as Map;
      expect((polyline['points'] as List), hasLength(12));
      expect(polyline['source'], 'manual');
      // Ekran kapandı, hat sekmesi haber verdi.
      expect(find.text('Rota çiz'), findsNothing);
      expect(find.text('4A rotası güncellendi.'), findsOneWidget);
    });

    h.adminTest('değişiklikle kapatmak onay ister', (tester) async {
      await openDrawDialog(tester);
            await tapMapAt(tester, const LatLng(37.3300, 42.1960));
      await tester.tap(find.byTooltip('Kapat').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Değişiklikler atılsın mı?'), findsOneWidget);
      await tester.tap(find.text('Atıp Çık'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Rota çiz'), findsNothing);
      expect(h.backend.rpcCalls('cache_sehirici_route_polyline'), isEmpty);
    });

    h.adminTest('geri al ve temizle noktaları azaltır', (tester) async {
      await openDrawDialog(tester);
      await tester.tap(find.text('Geri al'));
      await tester.pump();
      expect(find.text('10 nokta'), findsOneWidget);
      await tester.tap(find.text('Temizle'));
      await tester.pump();
      expect(find.text('0 nokta'), findsOneWidget);
      expect(find.text('Henüz nokta yok'), findsOneWidget);
    });
  });
}
