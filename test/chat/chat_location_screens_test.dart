// ignore_for_file: depend_on_referenced_packages

import 'package:cizreapp/features/chat/screens/chat_location_picker_screen.dart';
import 'package:cizreapp/features/chat/screens/chat_location_viewer_screen.dart';
import 'package:cizreapp/features/chat/services/chat_location_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';

import '../helpers/fake_google_maps_platform.dart';
import '../helpers/test_fonts.dart';

/// Görev 3.1 — konum gönderme ve paylaşılan konumu görme ekranları.

class _FakeLocationService extends ChatLocationService {
  _FakeLocationService({this.fix});

  final ({double latitude, double longitude})? fix;
  final List<(double, double)> geocoded = [];

  @override
  Future<({double latitude, double longitude})?> currentLocation(BuildContext context) async => fix;

  @override
  Future<String?> reverseGeocode(double latitude, double longitude) async {
    geocoded.add((latitude, longitude));
    return 'Adres ${latitude.toStringAsFixed(3)}';
  }
}

void main() {
  late FakeGoogleMapsPlatform maps;

  setUpAll(loadTestFonts);

  setUp(() {
    maps = FakeGoogleMapsPlatform();
    GoogleMapsFlutterPlatform.instance = maps;
  });

  group('ChatLocationPickerScreen', () {
    Future<ChatLocationPick? Function()> open(WidgetTester tester, ChatLocationService service) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      ChatLocationPick? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async => result = await Navigator.push<ChatLocationPick>(
                    context,
                    MaterialPageRoute(builder: (_) => ChatLocationPickerScreen(service: service)),
                  ),
                  child: const Text('aç'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('aç'));
      await tester.pumpAndSettle();
      return () => result;
    }

    testWidgets('anlık konumda açılır, adresi bulur, seçimi döndürür', (tester) async {
      final service = _FakeLocationService(fix: (latitude: 37.33, longitude: 42.19));
      final result = await open(tester, service);
      await tester.pump(const Duration(milliseconds: 500)); // adres gecikmesi
      await tester.pump();

      expect(maps.camera.target, const LatLng(37.33, 42.19));
      expect(find.text('Adres 37.330'), findsOneWidget);
      expect(find.text('37.33000, 42.19000'), findsOneWidget);
      expect(find.textContaining('Konumun alınamadı'), findsNothing);

      await tester.tap(find.text('Bu Konumu Gönder'));
      await tester.pumpAndSettle();
      final pick = result()!;
      expect((pick.latitude, pick.longitude, pick.label), (37.33, 42.19, 'Adres 37.330'));
      expect(pick.toAttachment(), {'lat': 37.33, 'lng': 42.19, 'label': 'Adres 37.330'});
    });

    testWidgets('harita kaydırılınca iğnenin yeni yeri ve adresi gönderilir', (tester) async {
      final service = _FakeLocationService(fix: (latitude: 37.33, longitude: 42.19));
      final result = await open(tester, service);
      await tester.pump(const Duration(milliseconds: 500));

      maps.panTo(const LatLng(37.34, 42.2));
      await tester.pump();
      expect(find.text('Adres aranıyor…'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      expect(find.text('Adres 37.340'), findsOneWidget);
      expect(service.geocoded.last, (37.34, 42.2));

      await tester.tap(find.text('Bu Konumu Gönder'));
      await tester.pumpAndSettle();
      expect((result()!.latitude, result()!.longitude, result()!.label), (37.34, 42.2, 'Adres 37.340'));
    });

    testWidgets('adres aranırken gönderilirse eski adres iliştirilmez', (tester) async {
      final service = _FakeLocationService(fix: (latitude: 37.33, longitude: 42.19));
      final result = await open(tester, service);
      await tester.pump(const Duration(milliseconds: 500));
      maps.panTo(const LatLng(37.4, 42.3));
      await tester.pump();

      await tester.tap(find.text('Bu Konumu Gönder'));
      await tester.pumpAndSettle();
      expect(result()!.label, isNull);
      expect(result()!.latitude, 37.4);
    });

    testWidgets('konum alınamazsa uyarı; Cizre merkezinden seçilebilir', (tester) async {
      final result = await open(tester, _FakeLocationService());
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.textContaining('Konumun alınamadı'), findsOneWidget);
      await tester.tap(find.text('Bu Konumu Gönder'));
      await tester.pumpAndSettle();
      expect(
        (result()!.latitude, result()!.longitude),
        (ChatLocationService.defaultLatitude, ChatLocationService.defaultLongitude),
      );
    });
  });

  group('ChatLocationViewerScreen', () {
    Future<List<Uri>> open(WidgetTester tester, {bool launchWorks = true}) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final opened = <Uri>[];
      await tester.pumpWidget(
        MaterialApp(
          home: ChatLocationViewerScreen(
            latitude: 37.3256,
            longitude: 42.192,
            label: 'Ali Bey, Cizre',
            title: 'Ayşe konumu',
            launcher: (uri) async {
              opened.add(uri);
              return launchWorks;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      return opened;
    }

    testWidgets('iğne paylaşılan noktada; yol tarifi ve harita bağlantıları', (tester) async {
      final opened = await open(tester);
      expect(find.text('Ayşe konumu'), findsOneWidget);
      expect(find.text('Ali Bey, Cizre'), findsOneWidget);
      expect(maps.markers[const MarkerId('shared-location')]?.position, const LatLng(37.3256, 42.192));
      expect(maps.camera.target, const LatLng(37.3256, 42.192));

      await tester.tap(find.text('Yol Tarifi'));
      await tester.tap(find.text('Haritada Aç'));
      await tester.pump();
      expect(opened, [
        ChatLocationService.directionsUri(37.3256, 42.192),
        ChatLocationService.searchUri(37.3256, 42.192),
      ]);
    });

    testWidgets('harita uygulaması açılamazsa kullanıcıya söylenir', (tester) async {
      await open(tester, launchWorks: false);
      await tester.tap(find.text('Yol Tarifi'));
      await tester.pump();
      expect(find.text('Harita uygulaması açılamadı.'), findsOneWidget);
    });
  });
}
