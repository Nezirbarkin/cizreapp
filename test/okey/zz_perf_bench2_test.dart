import 'package:cizreapp/okey/engine/okey_rack_layout.dart';
import 'package:cizreapp/okey/engine/okey_tile.dart';
import 'package:cizreapp/okey/widgets/okey_rack_bar_widget.dart';
import 'package:cizreapp/okey/widgets/okey_tile_widget.dart';
import 'package:cizreapp/okey/widgets/okey_table_metrics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
  testWidgets('ISTAKA — AYNI durumla 200 rebuild (animasyon yok)', (t) async {
    t.view.physicalSize = const Size(892, 412);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    var tick = 0;
    late StateSetter setter;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(builder: (c, s) {
          setter = s;
          tick;
          return SizedBox(
            height: 130,
            child: OkeyRackPanel(
              rack: OkeyRackBarWidget(
                metrics: OkeyTableMetrics.from(
                    BoxConstraints.tight(const Size(892, 412))),
                showChrome: false,
                slots: _fullRack(),
                selectedIndices: const {3},
                onTap: (_) {},
                onMove: (_, _) {},
              ),
            ),
          );
        }),
      ),
    ));
    final sw = Stopwatch()..start();
    for (var i = 0; i < 200; i++) {
      setter(() => tick++);
      await t.pump();
    }
    sw.stop();
    debugPrint('RACK 200 SABIT rebuild = ${sw.elapsedMilliseconds} ms');
  });

  testWidgets('TEK TAŞ — 2000 build+paint', (t) async {
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));
    var tick = 0;
    late StateSetter setter;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: StatefulBuilder(builder: (c, s) {
            setter = s;
            return OkeyTileWidget(
              key: ValueKey(tick % 2),
              tile: OkeyTile.numbered(OkeyColor.red, 13),
              width: 40,
              height: 54,
            );
          }),
        ),
      ),
    ));
    final sw = Stopwatch()..start();
    for (var i = 0; i < 400; i++) {
      setter(() => tick++);
      await t.pump();
    }
    sw.stop();
    debugPrint('TILE 400 remount = ${sw.elapsedMilliseconds} ms');
  });
}
