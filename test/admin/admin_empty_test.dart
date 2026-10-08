import 'package:cizreapp/features/admin/widgets/admin_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Admin > Loglar > Son Hatalar: "RenderFlex overflowed by 81 pixels on the
/// bottom" (admin_ui.dart, AdminEmpty). Boş/hata durumu sabit bir Column'du;
/// kısa bir alanda (klavye açık, yatay telefon, uzun hata metni) taşıyordu.
void main() {
  const longError =
      'ClientException with SocketException: Failed host lookup: '
      "'xsbukxkgtmdyickknqzf.supabase.co' (OS Error: No address associated "
      'with hostname, errno = 7), uri=https://xsbukxkgtmdyickknqzf.supabase.co/'
      'rest/v1/rpc/admin_activity_logs_list';

  Widget empty() => AdminEmpty(
    icon: Icons.error_outline,
    title: 'Kayıtlar yüklenemedi',
    subtitle: longError,
    action: FilledButton.icon(
      onPressed: () {},
      icon: const Icon(Icons.refresh),
      label: const Text('Tekrar dene'),
    ),
  );

  testWidgets('kısa alanda taşmaz, kaydırılabilir', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SizedBox(height: 120, child: empty())),
      ),
    );

    expect(tester.takeException(), isNull);
    // Düğmeye kaydırarak ulaşılabilir.
    await tester.scrollUntilVisible(
      find.text('Tekrar dene'),
      60,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text('Tekrar dene'), findsOneWidget);
  });

  testWidgets('geniş alanda içerik ortalanır (eski görünüm korunur)', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: SizedBox.expand(child: empty()))),
    );

    expect(tester.takeException(), isNull);
    final center = tester.getCenter(find.byIcon(Icons.error_outline));
    final screen = tester.getSize(find.byType(Scaffold));
    // İkon, içerik bloğunun üst yarısında; blok ekranın ortasında.
    expect((center.dx - screen.width / 2).abs() < 1, isTrue);
    expect(center.dy < screen.height / 2, isTrue);
  });

  testWidgets('sınırsız yükseklikte (ListView içinde) hata vermez', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ListView(children: [empty()])),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Kayıtlar yüklenemedi'), findsOneWidget);
  });

  testWidgets('diyalog içinde (intrinsic ölçü) hata vermez', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => AlertDialog(content: empty()),
              ),
              child: const Text('aç'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('aç'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Kayıtlar yüklenemedi'), findsOneWidget);
  });
}
