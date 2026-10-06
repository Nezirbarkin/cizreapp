// ignore_for_file: depend_on_referenced_packages

import 'package:cizreapp/sehirici/admin/sehirici_admin_overview_tab.dart' show SehiriciAdminTabs;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/sehirici_admin_harness.dart';

/// Görev 3.10 — Admin > Şehiriçi > Duraklar: seçim modu ve toplu silme.
void main() {
  final h = SehiriciAdminHarness()..register();

  Future<void> openStops(WidgetTester tester) async {
    await h.pumpAdmin(tester, tab: SehiriciAdminTabs.stops, height: 1600);
  }

  h.adminTest('seç → iki durak → sil: onayda etkilenen hatlar, tek RPC, liste yenilenir', (tester) async {
    await openStops(tester);
    expect(find.text('Eski Terminal'), findsOneWidget);

    await tester.tap(find.text('Seç'));
    await tester.pump();
    expect(find.text('0 durak seçili'), findsOneWidget);
    final deleteButton = find.ancestor(of: find.text('Sil'), matching: find.byWidgetPredicate((w) => w is FilledButton));
    expect(tester.widget<FilledButton>(deleteButton).onPressed, isNull, reason: 'seçim yokken kapalı');

    await tester.tap(find.text('Eski Terminal')); // hatsız
    await tester.tap(find.text('Belediye')); // 4A ve 7B'de
    await tester.pump();
    expect(find.text('2 durak seçili'), findsOneWidget);

    await tester.tap(deleteButton);
    await h.settle(tester, rounds: 3);
    expect(find.text('2 durak silinsin mi?'), findsOneWidget);
    expect(find.textContaining('2 hatta kullanılıyor (4A, 7B)'), findsOneWidget);

    await tester.tap(find.text('2 Durağı Sil'));
    await tester.pump();
    await h.settle(tester, rounds: 8);

    final call = h.backend.rpcCalls('admin_delete_sehirici_stops').single;
    expect(((call.body! as Map)['p_ids'] as List).toSet(), {'s9', 's2'});
    expect(find.text('2 durak silindi; 2 hattın durak sırası güncellendi.'), findsOneWidget);
    expect(find.text('Eski Terminal'), findsNothing);
    expect(find.text('Seç'), findsOneWidget, reason: 'silince seçim modu kapanır');
  });

  h.adminTest('uzun basış seçimi açar; tümünü seç / kaldır; vazgeçince seçim temizlenir', (tester) async {
    await openStops(tester);
    await tester.longPress(find.text('Otogar'));
    await tester.pump();
    expect(find.text('1 durak seçili'), findsOneWidget);

    await tester.tap(find.text('Tümünü seç'));
    await tester.pump();
    expect(find.text('9 durak seçili'), findsOneWidget);
    await tester.tap(find.text('Seçimi kaldır'));
    await tester.pump();
    expect(find.text('0 durak seçili'), findsOneWidget);

    await tester.tap(find.text('Kaymakamlık'));
    await tester.pump();
    await tester.tap(find.byTooltip('Seçimi kapat'));
    await tester.pump();
    expect(find.text('Seç'), findsOneWidget);
    expect(h.backend.rpcCalls('admin_delete_sehirici_stops'), isEmpty);
  });

  h.adminTest('sunucu hatası: mesaj gösterilir, seçim korunur', (tester) async {
    await openStops(tester);
    h.backend.failPathContaining = 'admin_delete_sehirici_stops';
    h.backend.failMessage = 'Tek seferde en fazla 500 durak silinebilir';
    await tester.tap(find.text('Seç'));
    await tester.pump();
    await tester.tap(find.text('Eski Terminal'));
    await tester.pump();
    await tester.tap(find.ancestor(of: find.text('Sil'), matching: find.byWidgetPredicate((w) => w is FilledButton)));
    await h.settle(tester, rounds: 3);
    await tester.tap(find.text('1 Durağı Sil'));
    await tester.pump();
    await h.settle(tester, rounds: 6);
    expect(find.text('Tek seferde en fazla 500 durak silinebilir'), findsOneWidget);
    expect(find.text('1 durak seçili'), findsOneWidget);
  });
}
