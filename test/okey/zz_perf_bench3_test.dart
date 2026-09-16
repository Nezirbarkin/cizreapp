import 'package:cizreapp/okey/engine/okey_rack_layout.dart';
import 'package:cizreapp/okey/engine/okey_tile.dart';
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

Future<void> _bench(WidgetTester t, String label, Widget Function() build) async {
  t.view.physicalSize = const Size(892, 412);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
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
  for (var i = 0; i < 200; i++) {
    setter(() => tick++);
    await t.pump();
  }
  sw.stop();
  debugPrint('$label 200 rebuild = ${sw.elapsedMilliseconds} ms');
}

void main() {
  final slots = _fullRack();

  Widget tiles({bool animate = false}) => SizedBox(
        height: 60,
        child: Row(
          children: [
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
                        animateSelection: animate,
                      ),
              ),
          ],
        ),
      );

  testWidgets('A) 32 taş, sade', (t) => _bench(t, 'A sade taşlar', () => tiles()));

  testWidgets('B) 32 taş + AnimatedContainer',
      (t) => _bench(t, 'B animasyonlu taşlar', () => tiles(animate: true)));

  testWidgets('C) 32 taş + GestureDetector', (t) => _bench(t, 'C +gesture', () {
        return SizedBox(
          height: 60,
          child: Row(children: [
            for (var i = 0; i < 32; i++)
              Expanded(
                child: GestureDetector(
                  onTap: () {},
                  onDoubleTap: () {},
                  child: slots[i] == null
                      ? const SizedBox()
                      : OkeyTileWidget(
                          tile: slots[i]!,
                          small: true,
                          tight: true,
                          width: 26,
                          height: 56,
                          animateSelection: true),
                ),
              ),
          ]),
        );
      }));

  testWidgets('D) 32 taş + gesture + Draggable + DragTarget',
      (t) => _bench(t, 'D +drag', () {
            return SizedBox(
              height: 60,
              child: Row(children: [
                for (var i = 0; i < 32; i++)
                  Expanded(
                    child: DragTarget<int>(
                      onWillAcceptWithDetails: (_) => true,
                      builder: (c, cand, rej) => Draggable<int>(
                        data: i,
                        feedback: const SizedBox(width: 26, height: 56),
                        childWhenDragging: const SizedBox(),
                        child: GestureDetector(
                          onTap: () {},
                          onDoubleTap: () {},
                          child: slots[i] == null
                              ? const SizedBox()
                              : OkeyTileWidget(
                                  tile: slots[i]!,
                                  small: true,
                                  tight: true,
                                  width: 26,
                                  height: 56,
                                  animateSelection: true),
                        ),
                      ),
                    ),
                  ),
              ]),
            );
          }));
}
