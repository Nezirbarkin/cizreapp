import 'package:cizreapp/core/widgets/now_playing_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Admin > Loglar > Son Hatalar'da 30 günde onlarca ekrana dağılmış
/// "Looking up a deactivated widget's ancestor is unsafe" kayıtlarının kaynağı.
///
/// `late final AnimationController _c = AnimationController(vsync: this)`
/// TEMBELDİR: animasyonu hiç başlatılmayan (duraklatılmış müzik) bir parıltı
/// ya da ilerleme çubuğunda denetleyiciye ilk kez `dispose()` içinde
/// dokunuluyordu. O an yaratılan Ticker, TickerMode'u artık devre dışı kalmış
/// bağlamdan aradığı için istisna fırlatıyor, Flutter'ın o karedeki söküm
/// döngüsü yarıda kalıyor ve sökülmesi gereken Scaffold'lar
/// ScaffoldMessenger'da "zombi" kayıt olarak kalıyordu: bundan sonra HER
/// `showSnackBar` aynı hatayla düşüyordu (kaynağı bambaşka ekranlar görünür).
void main() {
  Widget host(Widget child) => MaterialApp(
    home: Scaffold(
      body: Center(child: SizedBox(width: 320, child: child)),
    ),
  );

  NowPlayingPanel panel({required bool playing, String track = 'Kısa ad'}) =>
      NowPlayingPanel(
        trackName: track,
        playing: playing,
        onPlayPause: () {},
        onPrevious: () {},
        onNext: () {},
      );

  Future<void> removePanel(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox())),
    );
  }

  testWidgets('duraklatılmış panel (animasyonsuz parıltı + çubuk) sökülürken '
      'hata vermez', (tester) async {
    await tester.pumpWidget(host(panel(playing: false)));
    await tester.pump(const Duration(milliseconds: 50));

    await removePanel(tester);

    expect(tester.takeException(), isNull);
  });

  testWidgets('çalan panel sökülürken hata vermez', (tester) async {
    await tester.pumpWidget(host(panel(playing: true)));
    await tester.pump(const Duration(milliseconds: 200));

    await removePanel(tester);

    expect(tester.takeException(), isNull);
  });

  testWidgets('sığmayan (kayan yazı) uzun ad ile sökülürken hata vermez', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        panel(
          playing: false,
          track: 'Çok uzun bir şarkı adı ' * 8,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    await removePanel(tester);

    expect(tester.takeException(), isNull);
  });

  testWidgets('duraklat → çal → duraklat geçişleri ve söküm hatasız', (
    tester,
  ) async {
    await tester.pumpWidget(host(panel(playing: false)));
    await tester.pumpWidget(host(panel(playing: true)));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(host(panel(playing: false)));
    await tester.pump(const Duration(milliseconds: 100));

    await removePanel(tester);

    expect(tester.takeException(), isNull);
  });
}
