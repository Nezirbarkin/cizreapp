import 'package:cizreapp/okey/engine/okey_rack_layout.dart';
import 'package:cizreapp/okey/engine/okey_tile.dart';
import 'package:cizreapp/okey/widgets/okey_rack_bar_widget.dart';
import 'package:cizreapp/okey/widgets/okey_table_metrics.dart';
import 'package:cizreapp/okey/widgets/okey_tile_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

List<OkeyTile?> _fullRack() {
  final slots = List<OkeyTile?>.filled(OkeyRackLayout.totalSlots, null);
  var placed = 0;
  for (var i = 0; i < slots.length && placed < 21; i++) {
    if (i % 6 == 5) continue;
    slots[i] = OkeyTile.numbered(
        OkeyColor.values[placed % 4], (placed % 13) + 1);
    placed++;
  }
  return slots;
}

Future<int> _bench(WidgetTester t, Widget Function() build, int rounds) async {
  var tick = 0;
  late StateSetter setter;
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: StatefulBuilder(builder: (c, s) {
        setter = s;
        return KeyedSubtree(key: ValueKey(tick ~/ 100000), child: build());
      }),
    ),
  ));
  final sw = Stopwatch()..start();
  for (var i = 0; i < rounds; i++) {
    setter(() => tick++);
    await t.pump();
  }
  sw.stop();
  return sw.elapsedMicroseconds;
}

void main() {
  final slots = _fullRack();
  final m = OkeyTableMetrics.from(BoxConstraints.tight(const Size(892, 412)));

  Widget bar({bool chrome = false}) => OkeyRackBarWidget(
        metrics: m,
        showChrome: chrome,
        slots: slots,
        selectedIndices: const {3},
        onTap: (_) {},
        onMove: (_, _) {},
      );

  testWidgets('ISTAKA KATMANLARI', (t) async {
    t.view.physicalSize = const Size(892, 412);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);

    final cases = <String, Widget Function()>{
      'sade 21 taş': () => SizedBox(
            height: 60,
            child: Row(children: [
              for (var i = 0; i < 32; i++)
                Expanded(
                    child: slots[i] == null
                        ? const SizedBox()
                        : OkeyTileWidget(
                            tile: slots[i]!,
                            small: true,
                            tight: true,
                            width: 26,
                            height: 56,
                            animateSelection: true)),
            ]),
          ),
      'ıstaka çubuğu': () => SizedBox(height: 130, child: bar()),
      'panel + çubuk': () =>
          SizedBox(height: 130, child: OkeyRackPanel(rack: bar())),
    };

    // ISINMA: ilk turda JIT derlemesi ölçüme karışıyor.
    for (final f in cases.values) {
      await _bench(t, f, 30);
    }
    for (final e in cases.entries) {
      final us = await _bench(t, e.value, 200);
      debugPrint('${e.key.padRight(16)} 200 rebuild = ${(us / 1000).round()} ms'
          '  (${(us / 200000).toStringAsFixed(2)} ms/kare)');
    }
  });
}
