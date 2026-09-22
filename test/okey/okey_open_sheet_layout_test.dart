import 'package:cizreapp/okey/widgets/okey_open_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// "AÇ" seçim kartı bir `SingleChildScrollView` içindeki `Column`da durur:
/// yükseklik SINIRSIZDIR. İki seçeneği yan yana koyan `Row`un
/// `crossAxisAlignment: stretch` kullanması bu bağlamda "BoxConstraints forces
/// an infinite height" + "RenderBox was not laid out" üretiyordu (canlı hata
/// kayıtları, okey_open_sheet.dart:49). Kart açılabilmeli ve hata vermemeli.
void main() {
  Future<void> open(WidgetTester t, {required bool isOpen}) async {
    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => OkeyOpenSheet.show(
                  context,
                  seriesReady: true,
                  seriesBadge: '3 per',
                  seriesBlockedReason: null,
                  onSeries: () {},
                  pairsReady: false,
                  pairsBadge: '2/5',
                  pairsBlockedReason: 'En az 5 çift gerekir',
                  onPairs: () {},
                  points: 40,
                  requiredPoints: 101,
                  isOpen: isOpen,
                ),
                child: const Text('aç'),
              ),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('aç'));
    await t.pumpAndSettle();
  }

  testWidgets('baraj geçilmemişken kart hatasız açılır', (t) async {
    await open(t, isOpen: false);
    expect(t.takeException(), isNull);
    expect(find.text('SERİ AÇ'), findsOneWidget);
    expect(find.text('ÇİFT AÇ'), findsOneWidget);
  });

  testWidgets('el açıkken de kart hatasız açılır', (t) async {
    await open(t, isOpen: true);
    expect(t.takeException(), isNull);
    expect(find.text('SERİ AÇ'), findsOneWidget);
  });
}
