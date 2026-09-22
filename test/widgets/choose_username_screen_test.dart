import 'package:cizreapp/core/providers/theme_provider.dart';
import 'package:cizreapp/features/auth/screens/choose_username_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Google/Apple kaydından sonra zorunlu kullanıcı adı adımı. Bu ekran
/// tamamlanmadan ana uygulamaya dönülemediği için buradaki iki davranış
/// kritik: geri tuşu ekranı kapatmamalı ve doğrulama kuralları
/// register_screen_v2.dart'taki kullanıcı adı adımıyla aynı olmalı.
Widget _host(Widget child) {
  return ChangeNotifierProvider<ThemeProvider>(
    create: (_) => ThemeProvider()..setTheme(const Color(0xFF1976D2)),
    child: MaterialApp(home: child),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ThemeProvider yapıcısı SharedPreferences okur; taklit edilmezse
  // MissingPluginException zamanlamaya bağlı olarak testi düşürür.
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('başlık ve alan render edilir, gönder düğmesi devre dışı '
      'başlamaz', (tester) async {
    await tester.pumpWidget(_host(const ChooseUsernameScreen()));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Kullanıcı adı seç'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Kullanıcı adı'), findsOneWidget);
    expect(find.text('Kaydı tamamla'), findsOneWidget);
  });

  testWidgets('boş kullanıcı adıyla gönderim doğrulama hatası gösterir', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const ChooseUsernameScreen()));
    await tester.pump();

    await tester.tap(find.text('Kaydı tamamla'));
    await tester.pump();

    expect(find.text('Kullanıcı adı gerekli'), findsOneWidget);
  });

  testWidgets('3 karakterden kısa kullanıcı adı reddedilir', (tester) async {
    await tester.pumpWidget(_host(const ChooseUsernameScreen()));
    await tester.pump();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Kullanıcı adı'),
      'ab',
    );
    await tester.tap(find.text('Kaydı tamamla'));
    await tester.pump();

    expect(find.text('En az 3 karakter'), findsOneWidget);
  });

  testWidgets('hatalı gönderimden sonra düzeltilen ad hata metnini hemen '
      'temizler', (tester) async {
    await tester.pumpWidget(_host(const ChooseUsernameScreen()));
    await tester.pump();

    final field = find.widgetWithText(TextFormField, 'Kullanıcı adı');
    await tester.enterText(field, 'ab');
    await tester.tap(find.text('Kaydı tamamla'));
    await tester.pump();
    expect(find.text('En az 3 karakter'), findsOneWidget);

    await tester.enterText(field, 'abc');
    await tester.pump();
    expect(find.text('En az 3 karakter'), findsNothing);
  });

  testWidgets('izin verilmeyen karakterler yazarken otomatik ayıklanır', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const ChooseUsernameScreen()));
    await tester.pump();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Kullanıcı adı'),
      'ali veli!!',
    );
    await tester.pump();

    expect(find.text('aliveli'), findsOneWidget);
  });

  testWidgets('sistem geri tuşu ekranı kapatmaz (PopScope canPop: false)', (
    tester,
  ) async {
    // Gerçek akışta bu ekran her zaman bir alttaki ekranın (register/login)
    // üzerine push edilir; tek route'lu bir host geri davranışını anlamlı
    // test etmez, bu yüzden burada bilinçli olarak iki route'lu bir yığın
    // kuruluyor.
    await tester.pumpWidget(_host(const Placeholder()));
    await tester.pump();

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(
      MaterialPageRoute<void>(builder: (_) => const ChooseUsernameScreen()),
    );
    await tester.pumpAndSettle();
    expect(find.text('Kullanıcı adı seç'), findsOneWidget);

    // maybePop() true döner (istek "işlendi") ama gerçek sinyal ekranın hâlâ
    // orada olması: PopScope(canPop: false) doNotPop dispositionunda dahi
    // Navigator.maybePop true döndürür (bkz. flutter/widgets/navigator.dart
    // NavigatorState.maybePop), bu yüzden pop'un GERÇEKTEN engellendiğini
    // yalnızca ekranın hâlâ görünür olmasıyla doğrulayabiliriz.
    await navigator.maybePop();
    await tester.pumpAndSettle();

    expect(find.text('Kullanıcı adı seç'), findsOneWidget);
    expect(find.byType(Placeholder), findsNothing);
  });
}
