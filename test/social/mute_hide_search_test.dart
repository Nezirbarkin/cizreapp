import 'dart:convert';

import 'package:cizreapp/features/market/services/recent_searches_store.dart';
import 'package:cizreapp/features/social/services/muted_users_service.dart';
import 'package:cizreapp/features/social/services/post_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Sessize alma, gönderi gizleme, gönderi araması ve son aramalar.

const _me = '11111111-1111-4111-8111-111111111111';
final List<http.Request> _requests = [];
Object _nextBody = <Object>[];

class _MemoryAsyncStorage extends GotrueAsyncStorage {
  final Map<String, String> _items = {};

  @override
  Future<String?> getItem({required String key}) async => _items[key];

  @override
  Future<void> removeItem({required String key}) async => _items.remove(key);

  @override
  Future<void> setItem({required String key, required String value}) async => _items[key] = value;
}

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
          jsonEncode(_nextBody),
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
    _nextBody = <Object>[];
    MutedUsersService.instance.reset();
  });

  test('akış sunucuda süzülmüş görünümden, aynı sıralama ve aralıkla', () async {
    await PostService().getFeed(limit: 20, offset: 0);
    final feed = _requests.where((r) => r.url.path == '/rest/v1/feed_posts_with_profiles');
    expect(feed, hasLength(1));
    expect(
      feed.single.url.queryParameters['order'],
      'admin_pinned.desc.nullslast,created_at.desc.nullslast',
    );
    expect(_requests.where((r) => r.url.path == '/rest/v1/posts_with_profiles'), isEmpty);
  });

  test('gizle: tek idempotent upsert (sebepli); geri al: tek delete', () async {
    await PostService().hidePost('p1', reason: 'not_interested');
    final req = _requests.single;
    expect(req.method, 'POST');
    expect(req.url.path, '/rest/v1/hidden_posts');
    expect(req.url.queryParameters['on_conflict'], 'user_id,post_id');
    expect(jsonDecode(req.body), {'user_id': _me, 'post_id': 'p1', 'reason': 'not_interested'});

    _requests.clear();
    await PostService().unhidePost('p1');
    expect(_requests.single.method, 'DELETE');
    expect(_requests.single.url.queryParameters['post_id'], 'eq.p1');
  });

  test('gönderi araması: kısa sorgu istek atmaz; RPC gövdesi', () async {
    expect(await PostService().searchPosts('a'), isEmpty);
    expect(_requests, isEmpty);
    _nextBody = [
      {'id': 'p1', 'user_id': 'u1', 'content': 'kahve', 'created_at': '2026-10-24T10:00:00Z'},
    ];
    final posts = await PostService().searchPosts('  kahve ');
    expect(posts.single.id, 'p1');
    expect(_requests.single.url.path, '/rest/v1/rpc/search_posts');
    expect(jsonDecode(_requests.single.body), {'p_q': 'kahve', 'p_limit': 20});
  });

  test('sessize al: küme oturumda bir kez yüklenir, hikâyeler süzülür, olay yayınlanır', () async {
    _nextBody = [
      {'muted_id': 'x'},
    ];
    final svc = MutedUsersService.instance;
    await Future.wait([svc.ensureLoaded(), svc.ensureLoaded()]);
    await svc.ensureLoaded();
    expect(_requests.where((r) => r.url.path == '/rest/v1/muted_users'), hasLength(1));
    expect(svc.isMuted('x'), isTrue);
    expect(svc.filterStories(['x', 'y', 'x'], (s) => s), ['y']);

    _requests.clear();
    _nextBody = <Object>[];
    final events = <String>[];
    final sub = MutedUsersService.onUserMuted.listen(events.add);
    await svc.mute('y');
    await Future<void>.delayed(Duration.zero);
    expect(events, ['y']);
    expect(_requests.single.method, 'POST');
    expect(jsonDecode(_requests.single.body), {'muter_id': _me, 'muted_id': 'y'});
    await svc.unmute('y');
    expect(svc.isMuted('y'), isFalse);
    await sub.cancel();

    // Kendini sessize alamaz (istek yok).
    _requests.clear();
    await svc.mute(_me);
    expect(_requests, isEmpty);
  });

  test('son aramalar: en yeni önce, tekrar yok, en fazla 10, kullanıcı başına', () async {
    SharedPreferences.setMockInitialValues({});
    final store = RecentSearchesStore();
    await store.add('u1', 'kahve');
    await store.add('u1', 'çay');
    var list = await store.add('u1', 'KAHVE');
    expect(list, ['KAHVE', 'çay']);
    for (var i = 0; i < 12; i++) {
      list = await store.add('u1', 'sorgu $i');
    }
    expect(list, hasLength(10));
    expect(list.first, 'sorgu 11');
    expect(await store.load('u2'), isEmpty);
    expect(await store.add('u1', 'a'), hasLength(10)); // tek harf kaydedilmez
    list = await store.remove('u1', 'sorgu 11');
    expect(list.first, 'sorgu 10');
    await store.clear('u1');
    expect(await store.load('u1'), isEmpty);
  });
}
