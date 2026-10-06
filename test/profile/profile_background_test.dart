import 'dart:convert';
import 'dart:io';

import 'package:cizreapp/features/profile/services/profile_background_service.dart';
import 'package:cizreapp/features/profile/widgets/profile_background_picker_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Görev 2.7 — hazır profil arka planları: liste tablodan gelir, URL'ler
/// herkese açık kovadan kurulur, seçim kapağı profil RPC'siyle ayarlar
/// (dosya kopyalanmaz); seçici tema çipleriyle süzer.

final List<http.Request> _requests = [];

SupabaseClient _client({bool fail = false}) => SupabaseClient(
  'https://test.invalid',
  'test-key',
  // Widget testinin sahte saatinde bekleyen token yenileme zamanlayıcısı kalmasın.
  authOptions: const AuthClientOptions(autoRefreshToken: false),
  httpClient: MockClient((req) async {
    _requests.add(req);
    if (fail) {
      return http.Response(jsonEncode({'message': 'boom'}), 500, request: req, headers: {'content-type': 'application/json'});
    }
    final Object body = switch (req.url.pathSegments.last) {
      'profile_background_presets' => [
        {'code': 'bg_01', 'name': 'Pastel Rüya', 'category': 'Gradyan', 'image_path': 'presets/bg_01.jpg', 'thumb_path': 'thumbs/bg_01.jpg'},
        {'code': 'bg_06', 'name': 'Pembe Şafak', 'category': 'Gün Batımı', 'image_path': 'presets/bg_06.jpg', 'thumb_path': 'thumbs/bg_06.jpg'},
        {'code': 'bg_07', 'name': 'Turuncu Akşam', 'category': 'Gün Batımı', 'image_path': 'presets/bg_07.jpg', 'thumb_path': 'thumbs/bg_07.jpg'},
      ],
      _ => <String, dynamic>{},
    };
    return http.Response(jsonEncode(body), 200, request: req, headers: {'content-type': 'application/json; charset=utf-8'});
  }),
);

/// CachedNetworkImage'ın önbellek yöneticisi sökülünce bile ~10 sn'lik bir
/// temizlik zamanlayıcısı bırakır; test bitmeden sahte saat ilerletilir.
Future<void> _finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 30));
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    // CachedNetworkImage önbellek dizini için path_provider ister.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => Directory.systemTemp.path,
    );
  });

  setUp(() {
    _requests.clear();
    ProfileBackgroundService.clearCache();
  });

  group('ProfileBackgroundService', () {
    test('liste tek istekle, sıralı; URL\'ler herkese açık kovadan kurulur', () async {
      final presets = await ProfileBackgroundService(client: _client()).fetchPresets();

      expect(_requests, hasLength(1));
      final url = _requests.single.url;
      expect(url.path, '/rest/v1/profile_background_presets');
      expect(url.queryParameters['select'], 'code,name,category,image_path,thumb_path');
      expect(url.queryParameters['order'], 'sort_order.asc.nullslast');

      expect(presets.map((p) => p.code), ['bg_01', 'bg_06', 'bg_07']);
      expect(
        presets.first.imageUrl,
        'https://test.invalid/storage/v1/object/public/profile-backgrounds/presets/bg_01.jpg',
      );
      expect(
        presets.first.thumbUrl,
        'https://test.invalid/storage/v1/object/public/profile-backgrounds/thumbs/bg_01.jpg',
      );
    });

    test('liste oturumda önbellekte kalır; zorla tazelenebilir', () async {
      final service = ProfileBackgroundService(client: _client());
      await service.fetchPresets();
      await service.fetchPresets();
      expect(_requests, hasLength(1));

      await service.fetchPresets(forceRefresh: true);
      expect(_requests, hasLength(2));
    });

    test('kapak uygulanırken dosya kopyalanmaz: profil RPC\'si URL ile çağrılır', () async {
      final service = ProfileBackgroundService(client: _client());
      final preset = (await service.fetchPresets()).first;
      _requests.clear();

      await service.applyAsCover(preset);

      expect(_requests.single.url.path, '/rest/v1/rpc/update_my_public_profile');
      expect(jsonDecode(_requests.single.body), {'p_cover_url': preset.imageUrl});
    });
  });

  group('ProfileBackgroundPickerSheet', () {
    Future<ProfileBackgroundPreset?> Function() open(
      WidgetTester tester,
      ProfileBackgroundService service, {
      String? selectedUrl,
    }) {
      ProfileBackgroundPreset? picked;
      return () async {
        tester.view.physicalSize = const Size(420, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () async => picked = await showProfileBackgroundPicker(
                    context,
                    selectedUrl: selectedUrl,
                    service: service,
                  ),
                  child: const Text('aç'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('aç'));
        await tester.pumpAndSettle();
        return picked;
      };
    }

    testWidgets('tema çipleri süzer; seçilen arka plan döner', (tester) async {
      final service = ProfileBackgroundService(client: _client());
      ProfileBackgroundPreset? picked;
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async => picked = await showProfileBackgroundPicker(context, service: service),
                child: const Text('aç'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('aç'));
      await tester.pumpAndSettle();

      expect(find.text('Hazır Arka Plan Seç'), findsOneWidget);
      expect(find.text('Tümü (3)'), findsOneWidget);
      expect(find.text('Gradyan'), findsOneWidget);
      expect(find.text('Gün Batımı'), findsOneWidget);
      expect(find.text('Pastel Rüya'), findsOneWidget);

      await tester.tap(find.text('Gün Batımı'));
      await tester.pumpAndSettle();
      expect(find.text('Pastel Rüya'), findsNothing);
      expect(find.text('Pembe Şafak'), findsOneWidget);

      await tester.tap(find.text('Turuncu Akşam'));
      await tester.pumpAndSettle();
      expect(picked?.code, 'bg_07');
      expect(find.text('Hazır Arka Plan Seç'), findsNothing);
      await _finish(tester);
    });

    testWidgets('mevcut kapak işaretli gelir', (tester) async {
      final service = ProfileBackgroundService(client: _client());
      final presets = await service.fetchPresets();
      await open(tester, service, selectedUrl: presets[1].imageUrl)();

      expect(find.byIcon(Icons.check), findsOneWidget);
      await _finish(tester);
    });

    testWidgets('yüklenemezse hata ve "Tekrar dene"', (tester) async {
      final service = ProfileBackgroundService(client: _client(fail: true));
      await open(tester, service)();

      expect(find.text('Arka planlar yüklenemedi.'), findsOneWidget);
      expect(find.text('Tekrar dene'), findsOneWidget);
      await _finish(tester);
    });
  });
}
