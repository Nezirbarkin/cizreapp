import 'package:cizreapp/okey/providers/okey_points_provider.dart';
import 'package:cizreapp/okey/widgets/okey_coin_rain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// ÇİP YAĞMURU — kullanıcı isteği, 2026-09-08: "bonus al basınca çip yağmuru
/// olsun".
///
/// Testin koruduğu üç şey:
///
///  1. Ekrana GİRERKEN yağmur başlamaz. Sinyal oturum boyunca artan bir
///     sayaç; lobiye geri dönen oyuncu dakikalar önce aldığı bonusun
///     yağmurunu ikinci kez görmemeli.
///  2. Sinyal artınca yağmur başlar (kazanç NEREDEN gelirse gelsin — saatlik
///     bonus, reklam ödülü).
///  3. Yağmur biter ve katman ağaçtan çekilir; masanın üstünde asılı kalmaz.
///
/// ## Neden sahte bir provider
///
/// Gerçek [OkeyPointsProvider.claimHourlyGift] sunucuya gider. Sinyali
/// testte üretmek için yalnız getter'ı geçersiz kılıyoruz — katmanın gördüğü
/// tek şey zaten o.
class _FakePoints extends OkeyPointsProvider {
  int _signal = 0;

  @override
  int get coinRainSignal => _signal;

  void win() {
    _signal++;
    notifyListeners();
  }
}

Widget _host(OkeyPointsProvider points) => ChangeNotifierProvider.value(
  value: points,
  child: const MaterialApp(
    home: Scaffold(
      body: OkeyCoinRain(child: Center(child: Text('masa'))),
    ),
  ),
);

void main() {
  group('Çip yağmuru', () {
    late _FakePoints points;

    setUp(() {
      points = _FakePoints();
      // Provider bir saniyelik geri sayım zamanlayıcısı kuruyor; test
      // sonunda kapatılmazsa "A Timer is still pending" hatası verir.
      addTearDown(points.dispose);
    });

    testWidgets('ekrana girerken yağmur YOK', (tester) async {
      await tester.pumpWidget(_host(points));
      await tester.pump();

      expect(find.text('masa'), findsOneWidget);
      expect(find.byKey(OkeyCoinRain.rainKey), findsNothing);
    });

    testWidgets('kazanç sinyali gelince çipler düşer', (tester) async {
      await tester.pumpWidget(_host(points));
      await tester.pump();

      points.win();
      // Bir kare: provider bildirimi build'e ulaşır ve kare sonunda animasyon
      // başlar (build sırasında başlatılmaz — bkz. OkeyCoinRain._start).
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));

      expect(find.byKey(OkeyCoinRain.rainKey), findsOneWidget);
      expect(tester.takeException(), isNull);
      // Yağmur ekranı YUTMAZ: altındaki masa hâlâ orada ve dokunulabilir.
      expect(find.text('masa'), findsOneWidget);
      expect(
        find.ancestor(
          of: find.byKey(OkeyCoinRain.rainKey),
          matching: find.byType(IgnorePointer),
        ),
        findsWidgets,
      );
    });

    testWidgets('yağmur biter ve katman ağaçtan çekilir', (tester) async {
      await tester.pumpWidget(_host(points));
      await tester.pump();

      points.win();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.byKey(OkeyCoinRain.rainKey), findsOneWidget);

      // Animasyon 2,3 saniye; fazlasıyla ilerletiyoruz.
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();

      expect(find.byKey(OkeyCoinRain.rainKey), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('ikinci kazanç yağmuru YENİDEN başlatır', (tester) async {
      await tester.pumpWidget(_host(points));
      await tester.pump();

      points.win();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(seconds: 3));
      expect(find.byKey(OkeyCoinRain.rainKey), findsNothing);

      // Saatlik bonustan sonra reklam ödülü: aynı ekranda ikinci kazanç.
      points.win();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));

      expect(find.byKey(OkeyCoinRain.rainKey), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
