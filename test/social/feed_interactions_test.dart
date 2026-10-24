import 'dart:convert';

import 'package:cizreapp/core/models/post_model.dart';
import 'package:cizreapp/features/social/screens/post_detail_screen.dart';
import 'package:cizreapp/features/social/services/post_report_service.dart';
import 'package:cizreapp/features/social/services/post_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Akış etkileşimleri (2026-10-23 hata turu):
/// * beğeni tekrar edilebilir: zaten beğenilmişse ON CONFLICT DO NOTHING
///   (düz INSERT tekil kısıta çarpıp kalbi geri söndürüyordu),
/// * kaydetme ekranın istediği duruma gider (oku-sonra-yaz yarışı yok),
/// * detay ekranı kapanırken yalnız değişen sayaçları döndürür,
/// * kendi gönderini şikâyet edemezsin; aynı anda iki şikâyet "duplicate".

const _me = '11111111-1111-4111-8111-111111111111';
const _post = '33333333-3333-4333-8333-333333333333';

final List<http.Request> _requests = [];
Object? Function(http.Request req) _respond = (_) => <Object>[];
int Function(http.Request req) _status = (_) => 200;

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
        final body = _respond(req);
        return http.Response(
          body == null ? '' : jsonEncode(body),
          _status(req),
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
    _respond = (_) => <Object>[];
    _status = (_) => 200;
  });

  group('PostService', () {
    test('beğeni: tek upsert, çakışmada hiçbir şey yapma', () async {
      await PostService().likePost(_post, _me);

      final likes = _to('post_likes').toList();
      expect(likes, hasLength(1));
      expect(likes.single.method, 'POST');
      expect(likes.single.url.queryParameters['on_conflict'], 'post_id,user_id');
      expect(likes.single.headers['Prefer'], contains('resolution=ignore-duplicates'));
      expect(jsonDecode(likes.single.body), {'post_id': _post, 'user_id': _me});
    });

    test('kaydet: istenen duruma gider, okuma yapmaz', () async {
      await PostService().setPostSaved(_post, true);
      await PostService().setPostSaved(_post, false);

      final reqs = _to('post_favorites').toList();
      expect(reqs.map((r) => r.method), ['POST', 'DELETE']);
      expect(reqs.first.headers['Prefer'], contains('resolution=ignore-duplicates'));
      expect(reqs.first.url.queryParameters['on_conflict'], 'user_id,post_id');
      expect(reqs.last.url.queryParameters['post_id'], 'eq.$_post');
      expect(reqs.last.url.queryParameters['user_id'], 'eq.$_me');
    });
  });

  group('PostDetailResult', () {
    test('yalnız sayaçları yamar', () {
      final post = Post.fromJson({
        'id': _post,
        'user_id': _me,
        'content': 'merhaba',
        'likes_count': 3,
        'comments_count': 1,
        'created_at': '2026-10-01T10:00:00Z',
      });
      const result = PostDetailResult(
        postId: _post,
        isLiked: true,
        likesCount: 4,
        commentsCount: 2,
        likeChanged: true,
        commentsChanged: true,
      );
      final patched = result.applyTo(post);
      expect(patched.likesCount, 4);
      expect(patched.commentsCount, 2);
      expect(patched.content, 'merhaba');
      expect(patched.id, _post);
    });
  });

  group('PostReportService', () {
    test('kendi gönderisi: own_post, ekleme yok', () async {
      _respond = (req) => switch (req.url.path) {
            '/rest/v1/posts' => [
                {'user_id': _me},
              ],
            _ => <Object>[],
          };

      final result = await PostReportService().reportPost(
        reportedPostId: _post,
        reason: 'spam',
      );

      expect(result, 'own_post');
      expect(_to('post_reports').where((r) => r.method == 'POST'), isEmpty);
    });

    test('tekil kısıt yarışı: duplicate', () async {
      _respond = (req) => switch ((req.url.path, req.method)) {
            ('/rest/v1/post_reports', 'POST') => {
                'code': '23505',
                'message': 'duplicate key value violates unique constraint',
                'details': null,
                'hint': null,
              },
            ('/rest/v1/posts', _) => [
                {'user_id': 'someone-else'},
              ],
            _ => <Object>[],
          };
      _status = (req) => req.method == 'POST' ? 409 : 200;

      final result = await PostReportService().reportPost(
        reportedPostId: _post,
        reason: 'spam',
      );

      expect(result, 'duplicate');
    });
  });
}
