import 'package:cizreapp/core/services/analytics_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// `AnalyticsService._extractOrigin` regresyon testleri.
///
/// Admin panelindeki "Son Hatalar" listesinde her satirin altinda gosterilen
/// `origin` alani buradan uretiliyor. Bozuldugunda hata kayitlari gorunmeye
/// devam eder ama HANGI DOSYADAN geldikleri kaybolur — sessiz bir kayip
/// oldugu icin testle korunuyor.
void main() {
  group('extractOrigin', () {
    test('yigin izindeki ilk uygulama karesini dosya:satir olarak dondurur', () {
      final stack = StackTrace.fromString(
        '#0      _AssertionError._doThrowNew (dart:core-patch/errors_patch.dart:51:61)\n'
        '#1      Element._debugCheckStateIsActiveForAncestorLookup '
        '(package:flutter/src/widgets/framework.dart:4695:9)\n'
        '#2      _BarState.initState '
        '(package:cizreapp/core/widgets/now_playing_panel.dart:780:12)\n',
      );

      expect(
        AnalyticsService.extractOriginForTest(stack, null),
        'core/widgets/now_playing_panel.dart:780',
      );
    });

    test('framework kareleri kaynak sayilmaz', () {
      final stack = StackTrace.fromString(
        '#0      RenderFlex.performLayout '
        '(package:flutter/src/rendering/flex.dart:1010:11)\n',
      );

      expect(AnalyticsService.extractOriginForTest(stack, null), isNull);
    });

    test('yigin izi yoksa tani metnindeki kaynak konumu kullanilir', () {
      const diagnostics =
          'Incorrect use of ParentDataWidget.\n'
          'The relevant error-causing widget was:\n'
          '  OkeyBarajBadge '
          'file:///C:/Users/x/cizreapp/lib/okey/widgets/okey_baraj_badge.dart:52:7\n';

      expect(
        AnalyticsService.extractOriginForTest(null, diagnostics),
        'okey/widgets/okey_baraj_badge.dart:52',
      );
    });

    test('kaynak konumu cikarilmissa hic olmazsa widget adi dondurulur', () {
      // Release/profil derlemesinde `_describeCreationLocation` null doner ve
      // tani metninde dosya yolu bulunmaz; eskiden bu durumda origin tamamen
      // bos kaliyor, admin panelinde "hangi ekran?" sorusu cevapsiz kaliyordu.
      const diagnostics =
          'Null check operator used on a null value\n'
          'The relevant error-causing widget was:\n'
          '  FeedPostCard null\n';

      expect(
        AnalyticsService.extractOriginForTest(null, diagnostics),
        'widget: FeedPostCard',
      );
    });

    test('hicbir ipucu yoksa null doner', () {
      expect(AnalyticsService.extractOriginForTest(null, null), isNull);
      expect(AnalyticsService.extractOriginForTest(null, ''), isNull);
    });

    test('hatayi loglayan altyapi kareleri atlanir, cagiran kaynak olur', () {
      // `AppErrorHandler.handleError(e)` yigin izi vermeyince `StackTrace.current`
      // kullaniliyor; ilk uygulama karesi handler'in kendisidir.
      final stack = StackTrace.fromString(
        '#0      AppErrorHandler._logError '
        '(package:cizreapp/core/utils/app_error_handler.dart:203:5)\n'
        '#1      AppErrorHandler.processError '
        '(package:cizreapp/core/utils/app_error_handler.dart:195:5)\n'
        '#2      _SocialScreenState._loadData '
        '(package:cizreapp/features/social/screens/social_screen.dart:262:30)\n',
      );

      expect(
        AnalyticsService.extractOriginForTest(stack, null),
        'features/social/screens/social_screen.dart:262',
      );
    });
  });

  group('messageRemainder', () {
    test('mesajin iki nokta ustunden sonraki ayrintisini korur', () {
      // AppLogger.error('Error getting unread count: $e') -> `error:` bos,
      // ayrinti yalnizca mesajda. Tip normalizasyonu bunu atiyordu.
      expect(
        AnalyticsService.messageRemainderForTest(
          '❌ Error getting unread count: PostgrestException(code: 42501)',
        ),
        'PostgrestException(code: 42501)',
      );
    });

    test('iki nokta yoksa ya da baslik cok kisaysa null doner', () {
      expect(
        AnalyticsService.messageRemainderForTest('sendMessage RPC ERROR'),
        isNull,
      );
      expect(AnalyticsService.messageRemainderForTest('Hata: x'), isNull);
    });

    test('bos ayrinti null sayilir', () {
      expect(
        AnalyticsService.messageRemainderForTest('Error getting ghost mode:  '),
        isNull,
      );
    });
  });
}
