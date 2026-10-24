import 'dart:convert';

import 'package:cizreapp/core/models/post_model.dart';
import 'package:cizreapp/features/social/screens/story_viewer_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Hikâye ilerleme çubuğu (2026-10-23): çubuk denetleyicinin değerini yalnız
/// build sırasında okuyordu ve hiçbir şey yeniden çizim istemediği için 0'da
/// kalıyordu. Artık her karede akıyor; süre dolunca sonraki hikâyeye geçiyor.

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

const _me = 'user-me';

Story _textStory(String id) => Story.fromJson({
      'id': id,
      'user_id': 'someone',
      'image_url': null,
      'media_type': 'text',
      'text_content': 'Merhaba $id',
      'background': null,
      'views_count': 0,
      'likes_count': 0,
      'created_at': '2026-10-23T10:00:00+00:00',
      'expires_at': '2099-01-01T00:00:00+00:00',
      'is_pinned': false,
      'admin_pinned': false,
      'profiles': {'username': 'ali', 'full_name': 'Ali', 'avatar_url': null},
    });

double _currentProgress(WidgetTester tester) {
  // Yalnız gösterilen hikâyenin çubuğu LinearProgressIndicator'dır.
  final bar = tester.widget<LinearProgressIndicator>(
    find.byType(LinearProgressIndicator),
  );
  return bar.value ?? -1;
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://test.invalid',
      publishableKey: 'test-publishable-key',
      httpClient: MockClient(
        (req) async => http.Response(
          jsonEncode(<Object>[]),
          200,
          request: req,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
      authOptions: FlutterAuthClientOptions(
        localStorage: const EmptyLocalStorage(),
        pkceAsyncStorage: _MemoryAsyncStorage(),
      ),
    );
    await Supabase.instance.client.auth.recoverSession(
      jsonEncode({
        'access_token': 'token',
        'token_type': 'bearer',
        'refresh_token': 'refresh',
        'user': {
          'id': _me,
          'aud': 'authenticated',
          'created_at': '2026-01-01T00:00:00Z',
          'app_metadata': <String, dynamic>{},
          'user_metadata': <String, dynamic>{},
        },
      }),
    );
  });

  testWidgets('çubuk zamanla dolar, süre bitince sonraki hikâye', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: StoryViewerScreen(stories: [_textStory('s1'), _textStory('s2')]),
      ),
    );
    await tester.pump();

    expect(find.text('Merhaba s1'), findsOneWidget);
    final start = _currentProgress(tester);
    expect(start, lessThan(0.1));

    await tester.pump(const Duration(milliseconds: 2500));
    final middle = _currentProgress(tester);
    expect(middle, closeTo(0.5, 0.1), reason: 'çubuk 5 sn içinde dolmalı');

    // Süre dolunca sayfa geçişi (300 ms) + yeni hikâyenin çubuğu baştan.
    await tester.pump(const Duration(milliseconds: 2600));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Merhaba s2'), findsOneWidget);
    expect(_currentProgress(tester), lessThan(0.2));

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 50));
  });
}
