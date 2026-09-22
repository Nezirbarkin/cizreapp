import 'package:cizreapp/okey/admin/okey_admin_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// `OkeyStatStrip` YATAY ListView'dir; çocuklara sınırsız genişlik verir.
///
/// `OkeyStatCard` içinde `Row > Expanded` ve `SizedBox(width: infinity)` var.
/// Şerit kartı sınırlamazsa Ayarlar/Botlar sekmeleri her açılışta
/// "RenderFlex children have non-zero flex but incoming width constraints are
/// unbounded" + "RenderBox was not laid out" fırlatıyordu (canlı hata
/// kayıtları, okey_admin_widgets.dart:55/59).
void main() {
  testWidgets('kartlar sınırsız yatay genişlikte hatasız çizilir', (t) async {
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OkeyStatStrip(
            cards: [
              OkeyStatCard(
                icon: Icons.account_balance_wallet,
                label: 'Toplam Kazanç',
                value: '1234567',
                gradient: [Colors.green.shade400, Colors.green.shade700],
              ),
              OkeyStatCard(
                icon: Icons.smart_toy,
                label: 'Bot Payı (ödenen) — çok uzun bir etiket',
                value: '-42',
                gradient: [Colors.red.shade400, Colors.red.shade700],
              ),
            ],
          ),
        ),
      ),
    );

    expect(t.takeException(), isNull);
    expect(find.text('Toplam Kazanç'), findsOneWidget);
    expect(find.text('1234567'), findsOneWidget);
  });

  testWidgets('büyütülmüş sistem yazı boyutunda taşmaz', (t) async {
    await t.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
          child: Scaffold(
            body: OkeyStatStrip(
              cards: [
                OkeyStatCard(
                  icon: Icons.meeting_room,
                  label: 'Oda Ücretleri',
                  value: '98765',
                  gradient: [Colors.blue.shade400, Colors.blue.shade700],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(t.takeException(), isNull);
  });

  testWidgets('kart yatay kaydırılan şeritte sabit genişlik alır', (t) async {
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OkeyStatStrip(
            cards: [
              OkeyStatCard(
                icon: Icons.today,
                label: 'Bugün',
                value: '7',
                gradient: [Colors.teal.shade400, Colors.teal.shade700],
              ),
            ],
          ),
        ),
      ),
    );

    final size = t.getSize(find.byType(OkeyStatCard));
    expect(size.width, isNot(double.infinity));
    expect(size.width, greaterThan(100));
  });
}
