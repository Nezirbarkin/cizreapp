import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cizreapp/core/widgets/lazy_tab_stack.dart';

/// Kaç kez kuruldu / atıldı ve son TickerMode değerini kaydeden sekme.
class _Probe extends StatefulWidget {
  const _Probe({required this.id, required this.log});
  final int id;
  final Map<int, _Stats> log;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _Stats {
  int inits = 0;
  int disposes = 0;
  bool tickersEnabled = true;
}

class _ProbeState extends State<_Probe> {
  @override
  void initState() {
    super.initState();
    widget.log.putIfAbsent(widget.id, _Stats.new).inits++;
  }

  @override
  void dispose() {
    widget.log[widget.id]!.disposes++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    widget.log[widget.id]!.tickersEnabled = TickerMode.of(context);
    return Text('tab-${widget.id}', textDirection: TextDirection.ltr);
  }
}

void main() {
  late Map<int, _Stats> log;
  late int index;
  late DateTime now;
  late void Function(int) select;

  // 0 ve 2 korunur; 1 korunmaz.
  Future<void> pumpStack(WidgetTester tester) async {
    log = {};
    index = 0;
    now = DateTime(2026, 1, 1, 12);
    final screens = <int, Widget>{
      for (var i = 0; i < 3; i++) i: _Probe(id: i, log: log),
    };
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: StatefulBuilder(
          builder: (context, setState) {
            select = (i) => setState(() => index = i);
            return LazyTabStack(
              index: index,
              count: 3,
              retained: const {0, 2},
              maxAway: const Duration(minutes: 5),
              clock: () => now,
              tabBuilder: (i) => screens[i]!,
            );
          },
        ),
      ),
    );
  }

  testWidgets('yalnızca ilk sekme kurulur, diğerleri tembel', (tester) async {
    await pumpStack(tester);
    expect(log.keys, [0]);
    expect(log[0]!.inits, 1);
  });

  testWidgets('korunan sekme geçişte atılmaz, tekrar kurulmaz', (tester) async {
    await pumpStack(tester);

    select(2);
    await tester.pump();
    select(0);
    await tester.pump();
    select(2);
    await tester.pump();
    select(0);
    await tester.pump();

    expect(log[0]!.inits, 1, reason: 'sekme 0 hiç yeniden kurulmamalı');
    expect(log[0]!.disposes, 0);
    expect(log[2]!.inits, 1, reason: 'sekme 2 bir kez kurulup korunmalı');
    expect(log[2]!.disposes, 0);
  });

  testWidgets('korunmayan sekme her girişte yeniden kurulur', (tester) async {
    await pumpStack(tester);

    select(1);
    await tester.pump();
    select(0);
    await tester.pump();
    select(1);
    await tester.pump();

    expect(log[1]!.inits, 2);
    expect(log[1]!.disposes, 1, reason: 'ayrılınca atılmalı');
  });

  testWidgets('gizli korunan sekmenin ticker\'ları durur', (tester) async {
    await pumpStack(tester);
    select(2);
    await tester.pump();

    expect(log[2]!.tickersEnabled, isTrue);
    // Sekme 0 arkada yaşıyor ama görünmüyor.
    select(1);
    await tester.pump();
    select(2);
    await tester.pump();
    expect(log[0]!.tickersEnabled, isFalse);
    expect(log[2]!.tickersEnabled, isTrue);
  });

  testWidgets('5 dakikadan uzun ayrı kalınan korunan sekme sıfırdan kurulur',
      (tester) async {
    await pumpStack(tester);

    select(2);
    await tester.pump();
    expect(log[0]!.inits, 1);

    now = now.add(const Duration(minutes: 6));
    select(0);
    await tester.pump();

    expect(log[0]!.inits, 2, reason: 'bayat kopya yeniden kurulmalı');
    expect(log[0]!.disposes, 1);
  });

  testWidgets('5 dakikadan kısa ayrılıkta durum korunur', (tester) async {
    await pumpStack(tester);

    select(2);
    await tester.pump();
    now = now.add(const Duration(minutes: 4));
    select(0);
    await tester.pump();

    expect(log[0]!.inits, 1);
    expect(log[0]!.disposes, 0);
  });
}
