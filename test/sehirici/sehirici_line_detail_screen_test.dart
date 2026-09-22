// ignore_for_file: depend_on_referenced_packages, deprecated_member_use

import 'package:cizreapp/sehirici/providers/sehirici_provider.dart';
import 'package:cizreapp/sehirici/screens/sehirici_line_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../helpers/sehirici_test_data.dart';

/// Regresyon: `SehiriciLineDetailScreen`'in `CustomScrollView.slivers` listesi.
///
/// Her öğe bir Sliver ÜRETMELİ (SliverAppBar/SliverToBoxAdapter/SliverList).
/// Bunlardan biri sıradan bir kutu widget'ı (ör. Padding/Row döneren bir
/// StatelessWidget) olarak SARMALANMADAN eklenirse, `flutter analyze` bunu
/// YAKALAMAZ (`slivers` salt `List<Widget>`dir) — yalnız çalışma zamanında,
/// gerçek durak listesiyle (SliverList dalı devrede) "A RenderViewport
/// expected a child of type RenderSliver but received a child of type
/// RenderErrorBox" ile çöker. Bu test o çökmeyi durak listesi doluyken
/// yakalar.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://test.supabase.co',
      anonKey: 'test-anon-key',
      httpClient: MockClient((request) async => http.Response(
            '[]',
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          )),
    );
  });

  tearDown(() async {
    // ensureRealtimeWatching() (initState) bir kanal açabilir; test bitince
    // bekleyen bağlantı/zamanlayıcı kalmasın.
    await Supabase.instance.client
        .removeAllChannels()
        .timeout(const Duration(seconds: 5), onTimeout: () => const []);
  });

  testWidgets(
    'duraklu bir hat: çökmeden çizilir, başlık ve tüm duraklar görünür',
    (tester) async {
      // SliverList tembel kurulur: yalnız görünür alandaki öğeler çizilir.
      // 6 durağın hepsi kaydırmadan görünsün diye ekranı yeterince uzun tut.
      tester.view.physicalSize = const Size(390, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final line = SehiriciTestData.lineBlue(); // 6 durak.
      await tester.pumpWidget(
        ChangeNotifierProvider<SehiriciProvider>.value(
          value: SehiriciProvider(),
          child: MaterialApp(
            home: SehiriciLineDetailScreen(line: line),
          ),
        ),
      );
      await tester.pump();
      // SliverAppBar'ın genişleme animasyonu + olası async kareler.
      await tester.pump(const Duration(milliseconds: 300));

      // Asıl regresyon kontrolü: hiçbir yerde yakalanmamış istisna yok.
      expect(tester.takeException(), isNull);

      expect(find.text('4A — Merkez – Hastane'), findsOneWidget);
      expect(find.text('Duraklar ve Tahmini Varış'), findsOneWidget);
      expect(find.text('${line.stops.length} durak'), findsOneWidget);
      for (final stop in line.stops) {
        expect(find.text(stop.name), findsOneWidget, reason: stop.name);
      }
    },
  );

  testWidgets('durağı olmayan hat: boş durum çökmeden çizilir', (tester) async {
    final empty = SehiriciTestData.lineBlue().copyWith(stops: const []);
    await tester.pumpWidget(
      ChangeNotifierProvider<SehiriciProvider>.value(
        value: SehiriciProvider(),
        child: MaterialApp(home: SehiriciLineDetailScreen(line: empty)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
    expect(find.text('Bu hatta henüz durak eklenmemiş.'), findsOneWidget);
  });
}
