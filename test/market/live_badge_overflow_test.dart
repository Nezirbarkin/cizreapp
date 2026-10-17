import 'package:cizreapp/features/market/widgets/live_stream_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Canlı hata kaydı (2026-10-15): "A RenderFlex overflowed by 24 pixels on
/// the right" — live_stream_widgets.dart LiveBadge, dar ana sayfa kartında.
void main() {
  Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('dar alanda süre + izleyici rozeti taşmaz', (tester) async {
    await tester.pumpWidget(host(
      const Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 90,
          child: Row(
            children: [
              Flexible(
                child: LiveBadge(
                  elapsed: Duration(hours: 2, minutes: 15, seconds: 9),
                  viewers: 12345,
                ),
              ),
            ],
          ),
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
    expect(find.textContaining('CANLI'), findsOneWidget);
    expect(find.text('12345'), findsOneWidget);
  });

  testWidgets('Positioned(left/top) içinde (sınırsız genişlik) çalışır',
      (tester) async {
    await tester.pumpWidget(host(
      const SizedBox(
        width: 200,
        height: 120,
        child: Stack(
          children: [
            Positioned(left: 6, top: 6, child: LiveBadge(viewers: 7)),
          ],
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
    final size = tester.getSize(find.byType(LiveBadge));
    expect(size.width, greaterThan(40));
  });
}
