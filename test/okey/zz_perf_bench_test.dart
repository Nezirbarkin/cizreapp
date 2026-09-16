// GEÇİCİ ÖLÇÜM DOSYASI — optimizasyon öncesi/sonrası karşılaştırma.
import 'package:cizreapp/okey/engine/okey_rack_layout.dart';
import 'package:cizreapp/okey/engine/okey_tile.dart';
import 'package:cizreapp/okey/models/okey_models.dart';
import 'package:cizreapp/okey/widgets/okey_rack_bar_widget.dart';
import 'package:cizreapp/okey/widgets/okey_tile_widget.dart';
import 'package:cizreapp/okey/widgets/okey_board_widget.dart';
import 'package:cizreapp/okey/widgets/okey_table_metrics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

int _countElements(Element root) {
  var n = 0;
  void visit(Element e) {
    n++;
    e.visitChildren(visit);
  }

  visit(root);
  return n;
}

int _countRenderObjects(RenderObject root) {
  var n = 0;
  void visit(RenderObject r) {
    n++;
    r.visitChildren(visit);
  }

  visit(root);
  return n;
}

List<OkeyTile?> _fullRack() {
  final slots = List<OkeyTile?>.filled(OkeyRackLayout.totalSlots, null);
  var placed = 0;
  for (var i = 0; i < slots.length && placed < 21; i++) {
    if (i % 6 == 5) continue;
    slots[i] = OkeyTile.numbered(
      OkeyColor.values[placed % 4],
      (placed % 13) + 1,
    );
    placed++;
  }
  return slots;
}

void main() {
  testWidgets('TEK TAŞ — element/render nesne sayısı', (tester) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: OkeyTileWidget(
            tile: OkeyTile.numbered(OkeyColor.red, 13),
            width: 40,
            height: 54,
          ),
        ),
      ),
    );
    final el = tester.element(find.byType(OkeyTileWidget));
    final ro = tester.renderObject(find.byType(OkeyTileWidget));
    debugPrint('TILE elements=${_countElements(el)} render=${_countRenderObjects(ro)}');
  });

  testWidgets('ISTAKA — element/render + yeniden kurma süresi', (tester) async {
    tester.view.physicalSize = const Size(892, 412);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    var selected = <int>{3};
    late StateSetter setter;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              setter = setState;
              return SizedBox(
                height: 130,
                child: OkeyRackPanel(
                  rack: OkeyRackBarWidget(
                    metrics: OkeyTableMetrics.from(
                      BoxConstraints.tight(const Size(892, 412)),
                    ),
                    showChrome: false,
                    slots: _fullRack(),
                    selectedIndices: selected,
                    processableIndices: const {1, 2},
                    completeMeldSlots: const {0, 1, 2},
                    hiddenOkeySlots: const {6},
                    onTap: (_) {},
                    onMove: (_, _) {},
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );

    final el = tester.element(find.byType(OkeyRackPanel));
    final ro = tester.renderObject(find.byType(OkeyRackPanel));
    debugPrint('RACK elements=${_countElements(el)} render=${_countRenderObjects(ro)}');

    // Yeniden kurma süresi: 200 tur seçim değiştir + pump.
    final sw = Stopwatch()..start();
    for (var i = 0; i < 200; i++) {
      setter(() => selected = {i % 32});
      await tester.pump(const Duration(milliseconds: 16));
    }
    sw.stop();
    debugPrint('RACK 200 rebuild = ${sw.elapsedMilliseconds} ms');
  });

  testWidgets('MASA PERLERİ — element/render', (tester) async {
    tester.view.physicalSize = const Size(892, 412);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final melds = [
      for (var i = 0; i < 6; i++)
        OkeyTableMeld(
          id: i,
          matchId: 'm',
          laidBySeat: i % 4,
          meldType: 'run',
          tiles: [
            OkeyTile.numbered(OkeyColor.values[i % 4], 3),
            OkeyTile.numbered(OkeyColor.values[i % 4], 4),
            OkeyTile.numbered(OkeyColor.values[i % 4], 5),
          ],
        ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OkeyBoardWidget(melds: melds, tileWidth: 22, tileHeight: 30),
        ),
      ),
    );
    final el = tester.element(find.byType(OkeyBoardWidget));
    final ro = tester.renderObject(find.byType(OkeyBoardWidget));
    debugPrint('BOARD elements=${_countElements(el)} render=${_countRenderObjects(ro)}');
  });
}
