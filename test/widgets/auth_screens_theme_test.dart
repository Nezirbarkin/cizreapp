import 'package:cizreapp/core/providers/theme_provider.dart';
import 'package:cizreapp/features/auth/screens/login_screen_v2.dart';
import 'package:cizreapp/features/auth/screens/register_screen_v2.dart';
import 'package:cizreapp/features/auth/widgets/auth_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Auth ekranları renklerini `ThemeProvider.primaryColor` ve aktif
/// parlaklıktan türetir. Bu testler o bağın kopmadığını doğrular: ekranlar
/// hem açık hem koyu temada, üç marka renginin hepsiyle hatasız çizilmeli.
///
/// Eskiden giriş ekranı turkuaz (#1ABC9C), kayıt ekranı mavi (#3498DB) sabit
/// koddu ve arka plan her zaman açıktı.
Widget _host({
  required Widget child,
  required Color brand,
  required Brightness brightness,
}) {
  return ChangeNotifierProvider<ThemeProvider>(
    create: (_) => ThemeProvider()..setTheme(brand),
    child: MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: child,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  for (final brand in ThemeProvider.availableThemes) {
    for (final brightness in Brightness.values) {
      final label =
          '${brand.toARGB32().toRadixString(16)} / ${brightness.name}';

      testWidgets('giriş ekranı $label temasında çizilir', (tester) async {
        await tester.pumpWidget(
          _host(
            child: const LoginScreenV2(),
            brand: brand,
            brightness: brightness,
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(find.text('Tekrar hoş geldin'), findsOneWidget);
        expect(find.text('Giriş yap'), findsOneWidget);
      });

      testWidgets('kayıt ekranı $label temasında çizilir', (tester) async {
        await tester.pumpWidget(
          _host(
            child: const RegisterScreenV2(),
            brand: brand,
            brightness: brightness,
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
        // İlk adım: ilerleme çubuğu ve bilgi alanları.
        expect(find.text('Hesap oluştur'), findsOneWidget);
        expect(find.text('Adım 1 / 3 — Bilgilerin'), findsOneWidget);
        expect(find.text('Devam et'), findsOneWidget);
      });
    }
  }

  testWidgets('palet koyu temada koyu yüzey ve açılmış vurgu verir', (
    tester,
  ) async {
    Future<AuthPalette> paletteFor(Brightness brightness) async {
      late AuthPalette captured;
      await tester.pumpWidget(
        _host(
          brand: const Color(0xFFD91A73),
          brightness: brightness,
          // Key olmadan Builder elemanı yeniden kullanılır ve kapanış
          // değişkeni güncellenmez.
          child: Builder(
            key: ValueKey(brightness),
            builder: (context) {
              captured = AuthPalette.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      // MaterialApp temayı AnimatedTheme ile geçiriyor; tek kare sonra
      // hala eski tema okunur.
      await tester.pumpAndSettle();
      return captured;
    }

    final light = await paletteFor(Brightness.light);
    final dark = await paletteFor(Brightness.dark);

    expect(light.sheet, Colors.white);
    expect(dark.sheet.computeLuminance(), lessThan(0.1));
    // Koyu zeminde okunabilirlik için vurgu markadan daha açık olmalı.
    expect(
      dark.accent.computeLuminance(),
      greaterThan(light.accent.computeLuminance()),
    );
  });

  group('AuthOtpInput', () {
    late List<TextEditingController> controllers;
    late List<FocusNode> focusNodes;

    setUp(() {
      controllers = List.generate(6, (_) => TextEditingController());
      focusNodes = List.generate(6, (_) => FocusNode());
    });

    tearDown(() {
      for (final c in controllers) {
        c.dispose();
      }
      for (final f in focusNodes) {
        f.dispose();
      }
    });

    Widget host() => _host(
      brand: const Color(0xFFD91A73),
      brightness: Brightness.light,
      child: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: AuthOtpInput(controllers: controllers, focusNodes: focusNodes),
        ),
      ),
    );

    testWidgets('320 piksel genişlikte taşmaz', (tester) async {
      // Eski tasarımda kutular sabit 45px + spaceBetween idi ve bu genişlikte
      // taşıyordu.
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(host());
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(TextField), findsNWidgets(6));
    });

    testWidgets('yapıştırılan kod kutulara dağıtılır', (tester) async {
      await tester.pumpWidget(host());
      await tester.pump();

      await tester.enterText(find.byType(TextField).first, '483920');
      await tester.pump();

      expect(controllers.map((c) => c.text).toList(), <String>[
        '4',
        '8',
        '3',
        '9',
        '2',
        '0',
      ]);
    });

    testWidgets('rakam olmayan karakterler ayıklanır', (tester) async {
      await tester.pumpWidget(host());
      await tester.pump();

      await tester.enterText(find.byType(TextField).first, '12-34 56');
      await tester.pump();

      expect(controllers.map((c) => c.text).join(), '123456');
    });
  });

  testWidgets('kayıt akışı ikinci adıma geçer ve onaysız ilerlemez', (
    tester,
  ) async {
    // Varsayilan 800x600 test yuzeyinde adim 1 butonu ekran disinda kaliyor.
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _host(
        child: const RegisterScreenV2(),
        brand: const Color(0xFFD91A73),
        brightness: Brightness.light,
      ),
    );
    await tester.pump();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Kullanıcı adı'),
      'deneme.kullanici',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Ad soyad'),
      'Deneme Kullanıcı',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'E-posta'),
      'deneme@example.com',
    );
    await tester.pump();

    await tester.tap(find.text('Devam et'));
    await tester.pumpAndSettle();

    expect(find.text('Adım 2 / 3 — Şifre ve onaylar'), findsOneWidget);

    // KVKK ve Kullanım Koşulları işaretlenmeden gönderim düğmesi kapalı olmalı.
    final sendButton = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Doğrulama kodu gönder'),
    );
    expect(sendButton.onPressed, isNull);
    expect(
      find.text('Devam etmek için her iki onayı da işaretle.'),
      findsOneWidget,
    );

    // Her iki onay da işaretlenince düğme açılmalı.
    await tester.tap(find.byType(Checkbox).first);
    await tester.tap(find.byType(Checkbox).last);
    await tester.pump();

    final enabled = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Doğrulama kodu gönder'),
    );
    expect(enabled.onPressed, isNotNull);
  });
}
