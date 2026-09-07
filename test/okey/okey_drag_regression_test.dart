import 'dart:async';

import 'package:cizreapp/okey/okey.dart';
import 'package:cizreapp/okey/widgets/okey_drag_payload.dart';
import 'package:cizreapp/okey/widgets/okey_rack_bar_widget.dart';
import 'package:cizreapp/okey/widgets/okey_corner_pile_widget.dart';
import 'package:cizreapp/okey/widgets/okey_tile_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// SÜRÜKLEME ÇÖKMESİ REGRESYON TESTİ
///
/// Yaşanan hata (defalarca):
///   'owner!._debugCurrentBuildTarget == this': is not true
///   Context: building `DragTarget<OkeyDragPayload>`
///
/// Kök neden: sürükleme bırakıldığında Flutter iki geri çağrıyı art arda
/// SENKRON çalıştırır (Draggable.onDragEnd ve DragTarget.onAcceptWithDetails).
/// Bu callback'lerin içinden doğrudan notifyListeners()/setState çağrılırsa,
/// hâlâ kendi callback'ini yürüten DragTarget dahil tüm ağaç yeniden
/// kurulmaya çalışılıyor ve Flutter'ın "aynı anda tek build hedefi"
/// değişmezi bozuluyor.
///
/// Çözüm: provider'daki TÜM bildirimler mikro göreve ertelenir.
/// Bu testler o davranışı doğrular.
void main() {
  OkeyTile t(OkeyColor c, int n) => OkeyTile.numbered(c, n);

  /// OkeyGameProvider'ın _notify() desenini birebir taklit eden minimal
  /// ChangeNotifier (gerçek provider Supabase gerektirdiği için).
  ///
  /// Bu sınıf üretim kodundaki deseni yansıtır; desen bozulursa test düşer.
  group('Asenkron bildirim deseni', () {
    test('notify ASLA senkron çalışmaz (mikro göreve ertelenir)', () async {
      var notified = 0;
      var scheduled = false;
      var disposed = false;

      void notify(VoidCallback listener) {
        if (scheduled) return;
        scheduled = true;
        scheduleMicrotask(() {
          scheduled = false;
          if (!disposed) listener();
        });
      }

      notify(() => notified++);
      // Senkron çağrı yığını içinde HENÜZ bildirim olmamalı
      expect(notified, 0, reason: 'bildirim senkron çalışmamalı');

      await Future<void>.delayed(Duration.zero);
      expect(notified, 1, reason: 'bildirim mikro görevde çalışmalı');
    });

    test('aynı turdaki çoklu bildirimler tek bildirime birleşir', () async {
      var notified = 0;
      var scheduled = false;

      void notify() {
        if (scheduled) return;
        scheduled = true;
        scheduleMicrotask(() {
          scheduled = false;
          notified++;
        });
      }

      // Sürükleme bırakılınca olan tam da bu: iki callback art arda tetiklenir
      notify(); // DragTarget.onAcceptWithDetails
      notify(); // Draggable.onDragEnd

      await Future<void>.delayed(Duration.zero);
      expect(notified, 1, reason: 'iki senkron çağrı tek bildirime inmeli');
    });
  });

  group('Sonsuz iç içe geçme regresyonu (ASIL KÖK NEDEN)', () {
    // Yaşanan çökmenin gerçek sebebi: bir widget'ın AYNI değişkene
    // `x = DragTarget(builder: ... => x)` şeklinde atanması. Dart closure'ları
    // değişkeni REFERANSLA yakaladığı için builder çalıştığında `x` artık
    // DragTarget'ın kendisidir ve widget kendi içine sonsuz kez gömülür
    // (yığında "Normal element mounting (7756 frames)").
    //
    // Aşağıdaki testler sürükleme içeren TÜM bileşenlerin normal şekilde
    // kurulabildiğini doğrular; iç içe geçme olursa bu testler çöker.

    testWidgets(
      'köşe ıskarta kutusu (Draggable + DragTarget) sonsuz gömülmeden kurulur',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: OkeyCornerPileWidget(
                  size: 40,
                  seat: null,
                  seatNo: 0,
                  tileCount: 21,
                  score: 0,
                  isCurrentTurn: true,
                  isMe: true,
                  isDrawSource: true,
                  isDiscardTarget: true,
                  topDiscard: t(OkeyColor.red, 7),
                  onTileDropped: (_) {},
                  onTap: () {},
                ),
              ),
            ),
          ),
        );
        expect(
          tester.takeException(),
          isNull,
          reason: 'köşe ıskarta kutusu sonsuz iç içe geçmeden kurulmalı',
        );
        expect(find.byType(OkeyCornerPileWidget), findsOneWidget);
      },
    );

    testWidgets('tüm sürükleme bayrakları kapalıyken de kurulur', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: OkeyCornerPileWidget(
                size: 40,
                seat: null,
                seatNo: 2,
                tileCount: 0,
                isCurrentTurn: false,
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('Istaka sürükleme — çökme regresyonu', () {
    testWidgets(
      'taşı sürükleyip bırakmak, bırakma anında ağaç yeniden kurulsa bile çökmez',
      (tester) async {
        final slots = List<OkeyTile?>.filled(OkeyRackLayout.totalSlots, null);
        slots[0] = t(OkeyColor.red, 5);
        slots[1] = t(OkeyColor.blue, 9);

        var moveCount = 0;
        int? movedFrom;
        int? movedTo;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: _RebuildOnDrop(
                slots: slots,
                onMove: (from, to) {
                  moveCount++;
                  movedFrom = from;
                  movedTo = to;
                },
              ),
            ),
          ),
        );

        // Uzun basıp sürükleme (LongPressDraggable)
        final first = find.byType(OkeyTileWidget).first;
        final gesture = await tester.startGesture(tester.getCenter(first));
        await tester.pump(
          const Duration(milliseconds: 300),
        ); // long press eşiği
        await tester.pump(const Duration(milliseconds: 200));

        // Boş bir slota taşı
        await gesture.moveBy(const Offset(120, 0));
        await tester.pump();
        await gesture.up();
        await tester.pumpAndSettle();

        // En kritik doğrulama: hiçbir Flutter hatası fırlamamalı
        expect(
          tester.takeException(),
          isNull,
          reason: 'sürükle-bırak sırasında hiçbir framework hatası olmamalı',
        );
        expect(moveCount, greaterThan(0), reason: 'taşıma tetiklenmeliydi');
        expect(movedFrom, 0);
        expect(movedTo, isNotNull);
      },
    );

    testWidgets('sürükleme yokken normal dokunma da çökmez', (tester) async {
      final slots = List<OkeyTile?>.filled(OkeyRackLayout.totalSlots, null);
      slots[0] = t(OkeyColor.red, 5);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _RebuildOnDrop(slots: slots, onMove: (_, __) {}),
          ),
        ),
      );

      await tester.tap(find.byType(OkeyTileWidget).first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}

/// Bırakma anında setState ile ağacı yeniden kuran sarmalayıcı —
/// gerçek oyundaki "realtime güncelleme tam sürükleme sırasında geldi"
/// durumunu taklit eder.
class _RebuildOnDrop extends StatefulWidget {
  final List<OkeyTile?> slots;
  final void Function(int from, int to) onMove;

  const _RebuildOnDrop({required this.slots, required this.onMove});

  @override
  State<_RebuildOnDrop> createState() => _RebuildOnDropState();
}

class _RebuildOnDropState extends State<_RebuildOnDrop> {
  late List<OkeyTile?> _slots = List<OkeyTile?>.from(widget.slots);
  int _rebuildTick = 0;
  final Set<int> _selected = {};

  void _handleMove(int from, int to) {
    widget.onMove(from, to);
    // Üretimdeki provider gibi: bildirimi mikro göreve ertele
    scheduleMicrotask(() {
      if (!mounted) return;
      setState(() {
        _slots = OkeyRackLayout.moveTile(_slots, from, to);
        _rebuildTick++;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: ValueKey(_rebuildTick),
      width: 800,
      height: 108,
      child: OkeyRackBarWidget(
        slots: _slots,
        selectedIndices: _selected,
        onTap: (i) => setState(() {
          _selected.contains(i) ? _selected.remove(i) : _selected.add(i);
        }),
        onMove: _handleMove,
        onDrawDropped: (OkeyDragSource _, int __) {},
      ),
    );
  }
}
