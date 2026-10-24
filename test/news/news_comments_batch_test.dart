import 'dart:convert';

import 'package:cizreapp/features/news/services/news_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Haber yorumları (2026-10-23 performans turu): yorum sayısından bağımsız
/// en fazla 2 istek (yorumlar + beğenilerim). Eskiden her ana yorum için
/// ayrı beğeni + ayrı yanıt sorgusu sırayla bekleniyordu; ayrıca yanıtlar
/// model nesnesi olarak verildiği için yanıtlı ilk yorumda liste boşalıyordu.

const _me = '11111111-1111-4111-8111-111111111111';
const _news = 'news-1';

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

Map<String, dynamic> _comment(String id, {String? parent, required String at}) => {
      'id': id,
      'news_id': _news,
      'user_id': _me,
      'user_name': 'Nezir',
      'parent_id': parent,
      'content': 'yorum $id',
      'is_hidden': false,
      'is_pinned': false,
      'like_count': 0,
      'created_at': at,
      'updated_at': at,
    };

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://test.invalid',
      publishableKey: 'test-publishable-key',
      httpClient: MockClient((req) async {
        _requests.add(req);
        final Object body = switch (req.url.path) {
          // Sunucu sıralaması: yeniden eskiye (yanıtlar dahil).
          '/rest/v1/news_comments' => [
              _comment('r2', parent: 'c1', at: '2026-10-23T12:03:00Z'),
              _comment('c2', at: '2026-10-23T12:02:00Z'),
              _comment('r1', parent: 'c1', at: '2026-10-23T12:01:00Z'),
              _comment('c1', at: '2026-10-23T12:00:00Z'),
            ],
          '/rest/v1/news_comment_likes' => [
              {'comment_id': 'c1'},
              {'comment_id': 'r2'},
            ],
          _ => <Object>[],
        };
        return http.Response(
          jsonEncode(body),
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

  test('iki istek; yanıtlar gruplu ve sıralı, beğeniler doğru', () async {
    final comments = await NewsService().getComments(_news);

    expect(_requests, hasLength(2));
    final likesReq = _requests.firstWhere(
      (r) => r.url.path == '/rest/v1/news_comment_likes',
    );
    expect(likesReq.url.queryParameters['news_comments.news_id'], 'eq.$_news');

    expect(comments.map((c) => c.id), ['c2', 'c1']);
    final c1 = comments.last;
    expect(c1.isLikedByUser, isTrue);
    expect(c1.replies.map((r) => r.id), ['r1', 'r2']);
    expect(c1.replies.last.isLikedByUser, isTrue);
    expect(comments.first.isLikedByUser, isFalse);
  });
}
