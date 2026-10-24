import 'dart:convert';

import 'package:cizreapp/core/models/post_model.dart';
import 'package:cizreapp/features/profile/screens/profile_link_screen.dart';
import 'package:cizreapp/features/social/screens/post_link_screen.dart';
import 'package:cizreapp/features/social/services/social_share_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Paylaşım linkleri (2026-10-23): gönderi/profil linki üretimi, gelen
/// linkin uygulama rotasına çevrilmesi, misafir önizleme ekranları.
/// Bu dosyada oturum YOK (misafir).

const _post = '33333333-3333-4333-8333-333333333333';

final List<http.Request> _requests = [];
Object? Function(http.Request req) _respond = (_) => <Object>[];

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

Map<String, dynamic> _postRow() => {
      'id': _post,
      'user_id': 'u1',
      'content': 'Cizre akşamları 🌇',
      'images': <String>[],
      'likes_count': 12,
      'comments_count': 3,
      'shares_count': 2,
      'is_active': true,
      'created_at': '2026-10-20T18:00:00Z',
      'updated_at': '2026-10-20T18:00:00Z',
      'username': 'ali',
      'full_name': 'Ali Yılmaz',
      'avatar_url': null,
      'author_profile_exists': true,
    };

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => '.',
    );
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://test.invalid',
      publishableKey: 'test-publishable-key',
      httpClient: MockClient((req) async {
        _requests.add(req);
        return http.Response(
          jsonEncode(_respond(req)),
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
  });

  setUp(() {
    _requests.clear();
    _respond = (_) => <Object>[];
  });

  group('SocialShareService linkleri', () {
    test('gönderi ve profil linki', () {
      expect(SocialShareService.postLink(_post), 'https://cizreapp.com/post/$_post');
      expect(SocialShareService.profileLink('@ali'), 'https://cizreapp.com/u/@ali');
      // Türkçe harfli kullanıcı adı yüzde kodlanır.
      expect(
        SocialShareService.profileLink('bilginbarkın'),
        'https://cizreapp.com/u/@bilginbark%C4%B1n',
      );
    });

    test('gelen link → uygulama rotası', () {
      String? route(String s) => SocialShareService.appRouteFor(Uri.parse(s));

      expect(route('https://cizreapp.com/post/$_post'), '/post/$_post');
      expect(route('https://www.cizreapp.com/post/${_post.toUpperCase()}/'), '/post/$_post');
      expect(route('cizreapp://post/$_post'), '/post/$_post');
      expect(route('https://cizreapp.com/u/@bilginbark%C4%B1n'), '/u/@bilginbarkın');
      expect(route('https://cizreapp.com/u/@ali'), '/u/@ali');
      expect(route('https://cizreapp.com/s/kebapci-ali'), '/s/kebapci-ali');

      // Bizim paylaşım linkimiz olmayanlar: doğrulama, başka alan adı, bozuk id.
      expect(route('https://cizreapp.com/verify?token=x'), isNull);
      expect(route('https://ornek.com/post/$_post'), isNull);
      expect(route('https://cizreapp.com/post/123'), isNull);
      expect(route('https://cizreapp.com/u/@'), isNull);
    });

    test('paylaşım metninde gönderi linki var', () {
      final post = Post.fromJson(_postRow());
      final text = SocialShareService.postShareText(post, authorName: 'Ali Yılmaz');
      expect(text, contains('Ali Yılmaz'));
      expect(text, contains('Cizre akşamları'));
      expect(text, contains('https://cizreapp.com/post/$_post'));
    });

    test('misafirde paylaşım sayılmaz (istek yok)', () async {
      expect(await SocialShareService().recordShare(_post), isNull);
      expect(_requests, isEmpty);
    });
  });

  group('PostLinkScreen (misafir)', () {
    testWidgets('önizleme + giriş çağrısı', (tester) async {
      _respond = (req) => req.url.path == '/rest/v1/rpc/public_post_by_id'
          ? [_postRow()]
          : <Object>[];

      await tester.pumpWidget(
        const MaterialApp(home: PostLinkScreen(postId: _post)),
      );
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      final rpc = _requests.where((r) => r.url.path == '/rest/v1/rpc/public_post_by_id');
      expect(rpc, hasLength(1));
      expect(jsonDecode(rpc.single.body), {'p_post_id': _post});
      expect(find.textContaining('Cizre akşamları'), findsOneWidget);
      expect(find.text('Ali Yılmaz'), findsOneWidget);
      expect(find.text('Giriş Yap'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('bulunamadı / gizli hesap', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: PostLinkScreen(postId: _post)),
      );
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      expect(find.text('Bu gönderi artık görüntülenemiyor'), findsOneWidget);
      expect(find.text('Ana sayfa'), findsOneWidget);
    });
  });

  group('ProfileLinkScreen (misafir)', () {
    testWidgets('profil kartı ve sayılar', (tester) async {
      _respond = (req) => req.url.path == '/rest/v1/rpc/public_profile_by_username'
          ? {
              'id': 'u1',
              'username': 'bilginbarkın',
              'full_name': 'Bilgin Barkın',
              'avatar_url': null,
              'bio': 'Cizre',
              'is_verified': true,
              'profile_is_public': false,
              'followers': 120,
              'following': 30,
              'posts': 7,
            }
          : <Object>[];

      await tester.pumpWidget(
        const MaterialApp(home: ProfileLinkScreen(username: 'bilginbarkın')),
      );
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      final rpc = _requests.single;
      expect(jsonDecode(rpc.body), {'p_username': 'bilginbarkın'});
      expect(find.text('Bilgin Barkın'), findsOneWidget);
      expect(find.text('120'), findsOneWidget);
      expect(find.text('Bu hesap gizli'), findsOneWidget);
      expect(find.text('Takip isteği için giriş yap'), findsOneWidget);
      expect(find.byIcon(Icons.verified), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('bulunamayan kullanıcı', (tester) async {
      _respond = (_) => null;
      await tester.pumpWidget(
        const MaterialApp(home: ProfileLinkScreen(username: 'yok_boyle')),
      );
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(find.text('Kullanıcı bulunamadı'), findsOneWidget);
    });
  });
}
