import 'dart:async';
import 'dart:convert';

import 'package:cizreapp/core/navigation/app_navigator.dart';
import 'package:cizreapp/core/providers/favorites_provider.dart';
import 'package:cizreapp/core/providers/theme_provider.dart';
import 'package:cizreapp/features/auth/screens/login_screen_v2.dart';
import 'package:cizreapp/features/auth/screens/reset_password_screen.dart';
import 'package:cizreapp/features/auth/widgets/signing_out_view.dart';
import 'package:cizreapp/sehirici/providers/sehirici_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../helpers/test_fonts.dart';

/// Çıkış akışı (AppNavigator.signOutAndReset) ve ona bağlı gezinme kuralları.
///
/// Hata: çıkıştan sonra ekran KALICI olarak siyah kalıyordu. Yan menünün
/// kapanışı (settings_sidebar.dart `_close`) 300 ms'lik animasyonu bekleyip
/// `Navigator.of(context).pop()` çağırıyordu; bu çağrı kendi sayfasını değil
/// EN ÜSTTEKİ sayfayı kapatır. Çıkış yönlendirmesi o pencereye denk gelince
/// yeni açılan sayfa kapanıyor, eski sayfalar da zaten silinmek üzere
/// olduğundan Navigator tamamen boşalıyordu.

/// Sunucuya giden istekleri sırasıyla kaydeden sahte Supabase. [delay]
/// verilirse yanıtlar gecikir; böylece çıkış sürerken ekran görülebilir.
class _FakeServer {
  final List<String> calls = [];
  Duration delay = Duration.zero;

  MockClient client() => MockClient((req) async {
    final path = req.url.path;
    calls.add(path);
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    if (path.endsWith('/logout')) {
      return http.Response('', 204, request: req);
    }
    return http.Response(
      'null',
      200,
      request: req,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  });
}

late _FakeServer _server;

/// Bellek içi PKCE deposu. Varsayılan `SharedPreferencesGotrueAsyncStorage`
/// test ortamında hiç tamamlanmadığı için `signOut()` asılı kalıyordu.
class _MemoryAsyncStorage extends GotrueAsyncStorage {
  final Map<String, String> _items = {};

  @override
  Future<String?> getItem({required String key}) async => _items[key];

  @override
  Future<void> setItem({required String key, required String value}) async {
    _items[key] = value;
  }

  @override
  Future<void> removeItem({required String key}) async {
    _items.remove(key);
  }
}

/// Ağsız oturum: JWT olmayan erişim anahtarının süresi yoktur, yenilenmez.
Future<void> _signIn() async {
  await Supabase.instance.client.auth.recoverSession(
    jsonEncode({
      'access_token': 'test-access-token',
      'token_type': 'bearer',
      'refresh_token': 'test-refresh-token',
      'user': {
        'id': 'user-1',
        'aud': 'authenticated',
        'created_at': '2026-01-01T00:00:00Z',
        'app_metadata': <String, dynamic>{},
        'user_metadata': <String, dynamic>{},
      },
    }),
  );
}

/// Yan menünün ESKİ kapanışının birebir kopyası: animasyonu bekler, sonra
/// `Navigator.of(context).pop()` — kendi sayfasını değil en üsttekini kapatır.
/// Yeni çıkış akışı, düzeltilmemiş böyle bir widget'a karşı da sağlam olmalı.
class _LegacySidebar extends StatefulWidget {
  const _LegacySidebar();

  @override
  State<_LegacySidebar> createState() => _LegacySidebarState();
}

class _LegacySidebarState extends State<_LegacySidebar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _close() async {
    await _controller.reverse();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: Scaffold(
        backgroundColor: Colors.black54,
        body: Align(
          alignment: Alignment.centerRight,
          child: IconButton(
            tooltip: 'Kapat',
            icon: const Icon(Icons.close),
            onPressed: _close,
          ),
        ),
      ),
    );
  }
}

/// main.dart'taki rotaların sade kopyası: ana sayfa yerine hafif bir yer
/// tutucu, giriş ve şifre sıfırlama için gerçek ekranlar.
Future<void> _pumpApp(WidgetTester tester, {bool withSidebar = false}) async {
  tester.view.physicalSize = const Size(430, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: MaterialApp(
        navigatorKey: appNavigatorKey,
        home: const Scaffold(body: Center(child: Text('ANA SAYFA'))),
        routes: {
          '/login': (_) => const LoginScreenV2(),
          '/reset-password': (_) => const ResetPasswordScreen(),
        },
      ),
    ),
  );
  if (withSidebar) {
    // Yan menü, gerçek uygulamadaki gibi opak olmayan bir sayfa olarak açılır.
    appNavigatorKey.currentState!.push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.transparent,
        pageBuilder: (_, _, _) => const _LegacySidebar(),
      ),
    );
  }
  await tester.pumpAndSettle();
}

/// Çıkışı başlatır ve bitene kadar ilerletir.
Future<void> _signOut(WidgetTester tester) async {
  unawaited(AppNavigator.signOutAndReset());
  await tester.pumpAndSettle();
}

/// Android geri tuşu: motorun `flutter/navigation` kanalına gönderdiği
/// `popRoute` mesajının aynısı.
Future<void> _systemBack(WidgetTester tester) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/navigation',
    const JSONMethodCodec().encodeMethodCall(const MethodCall('popRoute')),
    (_) {},
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // Gerçek glifler: Ahem test fontunda her harf tam kare olduğundan giriş
    // ekranındaki 'Beni hatırla' satırı yapay olarak taşıyordu.
    await loadTestFonts();
    SharedPreferences.setMockInitialValues({});
    _server = _FakeServer();
    await Supabase.initialize(
      url: 'https://test.invalid',
      publishableKey: 'test-publishable-key',
      httpClient: _server.client(),
      authOptions: FlutterAuthClientOptions(
        localStorage: const EmptyLocalStorage(),
        pkceAsyncStorage: _MemoryAsyncStorage(),
      ),
    );
  });

  setUp(() async {
    _server.delay = Duration.zero;
    await _signIn();
    _server.calls.clear();
  });

  group('AppNavigator.signOutAndReset', () {
    testWidgets(
      '"Çıkış yapılıyor…" perdesi anında açılır; sonunda yalnız Giriş ekranı kalır',
      (tester) async {
        await _pumpApp(tester, withSidebar: true);
        _server.delay = const Duration(seconds: 1);

        unawaited(AppNavigator.signOutAndReset());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        // Temizlik sürerken: perde görünür, altındaki sayfalar sökülmüştür,
        // oturum henüz açıktır (token RPC'si oturum ister).
        expect(find.byType(SigningOutView), findsOneWidget);
        expect(find.text('Çıkış yapılıyor…'), findsOneWidget);
        expect(find.text('ANA SAYFA'), findsNothing);
        expect(find.byType(_LegacySidebar), findsNothing);
        expect(Supabase.instance.client.auth.currentSession, isNotNull);

        await tester.pumpAndSettle();

        expect(find.byType(LoginScreenV2), findsOneWidget);
        expect(find.byType(SigningOutView), findsNothing);
        expect(appNavigatorKey.currentState!.canPop(), isFalse);
        expect(Supabase.instance.client.auth.currentSession, isNull);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Yan menü kapanırken gelen çıkış yönlendirmesi Navigator\'ı boşaltmaz',
      (tester) async {
        await _pumpApp(tester, withSidebar: true);

        // Kullanıcı "donmuş" menüyü kapatmak için X'e basar…
        await tester.tap(find.byTooltip('Kapat'));
        await tester.pump();
        // …ve tam o sırada çıkış akışı hedef sayfaya yönlendirir.
        await _signOut(tester);

        expect(find.byType(LoginScreenV2), findsOneWidget,
            reason: 'Navigator boşaldı → kalıcı siyah ekran');
        expect(appNavigatorKey.currentState!.canPop(), isFalse);
        expect(Supabase.instance.client.auth.currentSession, isNull);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('Perde, gecikmeli bir Navigator.pop() ile kapanmaz',
        (tester) async {
      await _pumpApp(tester);
      _server.delay = const Duration(seconds: 1);

      unawaited(AppNavigator.signOutAndReset());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Perde artık yığının tek sayfası; sıradan bir pop onu kapatsaydı
      // Navigator boşalırdı.
      appNavigatorKey.currentState!.pop();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(SigningOutView), findsOneWidget);

      await tester.pumpAndSettle();
      expect(find.byType(LoginScreenV2), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Çift dokunuş tek çıkış yapar', (tester) async {
      await _pumpApp(tester);

      unawaited(AppNavigator.signOutAndReset());
      unawaited(AppNavigator.signOutAndReset());
      await tester.pumpAndSettle();

      expect(
        _server.calls.where((c) => c.endsWith('/logout')).length,
        1,
      );
      expect(find.byType(LoginScreenV2), findsOneWidget);
      expect(appNavigatorKey.currentState!.canPop(), isFalse);
    });

    testWidgets('FCM token RPC\'si oturum kapanmadan önce çağrılır',
        (tester) async {
      await _pumpApp(tester);
      await _signOut(tester);

      final token = _server.calls.indexWhere(
        (c) => c.endsWith('/rpc/clear_my_fcm_token'),
      );
      final logout = _server.calls.indexWhere((c) => c.endsWith('/logout'));
      expect(token, isNot(-1), reason: 'token RPC\'si hiç çağrılmadı');
      expect(logout, isNot(-1));
      expect(token, lessThan(logout));
    });
  });

  group('AppNavigator.popIfCurrent', () {
    testWidgets('Üstte başka sayfa varken hiçbir şey kapatmaz',
        (tester) async {
      await _pumpApp(tester);
      final homeContext = tester.element(find.text('ANA SAYFA'));

      appNavigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Center(child: Text('ÜST'))),
        ),
      );
      await tester.pumpAndSettle();

      expect(AppNavigator.popIfCurrent(homeContext), isFalse);
      await tester.pumpAndSettle();
      expect(find.text('ÜST'), findsOneWidget);

      expect(AppNavigator.popIfCurrent(tester.element(find.text('ÜST'))),
          isTrue);
      await tester.pumpAndSettle();
      expect(find.text('ANA SAYFA'), findsOneWidget);
    });
  });

  group('Giriş ekranı (LoginScreenV2)', () {
    testWidgets(
      'Tek sayfayken "Misafir olarak devam et" misafir ana sayfaya götürür',
      (tester) async {
        await _pumpApp(tester);
        await _signOut(tester);

        await tester.tap(find.text('Misafir olarak devam et'));
        await tester.pumpAndSettle();

        expect(find.text('ANA SAYFA'), findsOneWidget);
        expect(find.byType(LoginScreenV2), findsNothing);
        expect(appNavigatorKey.currentState!.canPop(), isFalse);
      },
    );

    testWidgets(
      'Tek sayfayken Android geri tuşu uygulamayı kapatmaz, ana sayfaya gider',
      (tester) async {
        final platformCalls = <String>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            platformCalls.add(call.method);
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );

        await _pumpApp(tester);
        await _signOut(tester);
        await _systemBack(tester);

        expect(find.text('ANA SAYFA'), findsOneWidget);
        expect(platformCalls, isNot(contains('SystemNavigator.pop')));
      },
    );

    testWidgets(
      'Başka bir sayfanın üstündeyken "Misafir olarak devam et" geri döner',
      (tester) async {
        await _pumpApp(tester);
        appNavigatorKey.currentState!.pushNamed('/login');
        await tester.pumpAndSettle();

        await tester.tap(find.text('Misafir olarak devam et'));
        await tester.pumpAndSettle();

        expect(find.text('ANA SAYFA'), findsOneWidget);
        expect(appNavigatorKey.currentState!.canPop(), isFalse);
      },
    );
  });

  testWidgets(
    'Şifre sıfırlama ekranı tek sayfayken geri oku Giriş ekranına götürür',
    (tester) async {
      await _pumpApp(tester);
      appNavigatorKey.currentState!.pushNamedAndRemoveUntil(
        '/reset-password',
        (_) => false,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Geri'));
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreenV2), findsOneWidget);
      expect(find.byType(ResetPasswordScreen), findsNothing);
    },
  );

  group('Oturum kapanınca kullanıcı durumu', () {
    test('FavoritesProvider.resetForSignOut yalnız belleği temizler', () {
      final provider = FavoritesProvider()
        ..updateProductFavoritedCache({'urun-1': true})
        ..updatePostFavoritedCache({'gonderi-1': true});
      var notified = 0;
      provider.addListener(() => notified++);
      _server.calls.clear();

      provider.resetForSignOut();

      expect(provider.isProductFavorited('urun-1'), isFalse);
      expect(provider.isPostFavorited('gonderi-1'), isFalse);
      expect(provider.totalFavoritesCount, 0);
      expect(notified, 1);
      expect(_server.calls, isEmpty, reason: 'sunucudaki favoriler silinmemeli');
    });

    test('SehiriciProvider.clearUserState favori durakları bırakır', () async {
      final provider = SehiriciProvider();
      await provider.toggleFavorite('durak-1');
      expect(provider.favoriteStopIds, contains('durak-1'));

      provider.clearUserState();

      expect(provider.favoriteStopIds, isEmpty);
    });
  });
}
