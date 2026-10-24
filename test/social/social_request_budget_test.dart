import 'dart:convert';

import 'package:cizreapp/features/social/services/post_service.dart';
import 'package:cizreapp/features/social/services/story_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Sosyal ekranların istek bütçesi (2026-10-23 performans turu):
/// * ana sayfa + Keşfet aynı anda hikâye isteyince ağ isteği paylaşılır,
/// * hikâye görüntüleme kaydı tek istek (eskiden oku + ekle),
/// * hikâye görüntülemeleri/tepkileri yalnız son 25 saatten okunur,
/// * profil gönderileri sayfalı, yorumlar üst sınırlı.

const _me = '11111111-1111-4111-8111-111111111111';

final List<http.Request> _requests = [];

class _MemoryAsyncStorage extends GotrueAsyncStorage {
  final Map<String, String> _items = {};

  @override
  Future<String?> getItem({required String key}) async => _items[key];

  @override
  Future<void> removeItem({required String key}) async => _items.remove(key);

  @override
  Future<void> setItem({required String key, required String value}) async =>
      _items[key] = value;
}

Iterable<http.Request> _to(String table) =>
    _requests.where((r) => r.url.path == '/rest/v1/$table');

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://test.invalid',
      publishableKey: 'test-publishable-key',
      httpClient: MockClient((req) async {
        _requests.add(req);
        return http.Response(
          jsonEncode(<Object>[]),
          200,
          request: req,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
      authOptions: FlutterAuthClientOptions(
        localStorage: const EmptyLocalStorage(),
        pkceAsyncStorage: _MemoryAsyncStorage(),
        autoRefreshToken: false,
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

  setUp(() {
    _requests.clear();
    StoryService.invalidateShared();
  });

  test('aynı anda iki ekran hikâye isterse tek istek seti', () async {
    await Future.wait([
      StoryService().getStories(),
      StoryService().getStories(),
    ]);
    expect(_to('stories'), hasLength(1));
    expect(_to('story_views'), hasLength(1));
    expect(_to('story_likes'), hasLength(1));

    // Görüntülemeler/tepkiler yalnız son 25 saatten.
    expect(_to('story_views').single.url.queryParameters['created_at'], startsWith('gte.'));
    expect(_to('story_likes').single.url.queryParameters['created_at'], startsWith('gte.'));

    // Zorla yenileme ağa gider.
    await StoryService().getStories(forceRefresh: true);
    expect(_to('stories'), hasLength(2));
  });

  test('hikâye görüntüleme kaydı tek istek', () async {
    await StoryService().viewStory('s1', _me);

    expect(_requests, hasLength(1));
    final req = _requests.single;
    expect(req.method, 'POST');
    expect(req.url.path, '/rest/v1/story_views');
    expect(req.url.queryParameters['on_conflict'], 'story_id,viewer_id');
    expect(req.headers['Prefer'], contains('resolution=ignore-duplicates'));
  });

  test('profil gönderileri sayfalı; sabitlenen başta', () async {
    await PostService().getUserPosts('u1', offset: 24);

    final q = _requests.single.url.queryParameters;
    expect(q['offset'], '24');
    expect(q['limit'], '${PostService.userPostsPageSize}');
    expect(q['order'], startsWith('is_pinned.desc'));
  });

  test('yorumlar üst sınırlı', () async {
    await PostService().getComments('p1');
    expect(_requests.single.url.queryParameters['limit'], '300');
  });
}
