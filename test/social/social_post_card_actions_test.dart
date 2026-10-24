import 'dart:convert';

import 'package:cizreapp/core/models/post_model.dart';
import 'package:cizreapp/features/social/widgets/social_post_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../helpers/test_fonts.dart';

/// Gönderi kartı istatistikleri (X tarzı): sayılar düğmelerde, sağda
/// görüntülenme çipi; dar ekranda büyük sayılarla taşma yok; "düzenlendi".

class _MemoryAsyncStorage extends GotrueAsyncStorage {
  final Map<String, String> _items = {};

  @override
  Future<String?> getItem({required String key}) async => _items[key];

  @override
  Future<void> setItem({required String key, required String value}) async => _items[key] = value;

  @override
  Future<void> removeItem({required String key}) async => _items.remove(key);
}

Post _post({int views = 0, String? editedAt, int likes = 0, int comments = 0, int shares = 0}) =>
    Post.fromJson({
      'id': 'p1',
      'user_id': 'u1',
      'content': 'Cizre akşamı',
      'images': const <String>[],
      'likes_count': likes,
      'comments_count': comments,
      'shares_count': shares,
      'views_count': views,
      'edited_at': editedAt,
      'created_at': '2026-09-28T10:00:00Z',
      'updated_at': '2026-09-28T10:00:00Z',
    });

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadTestFonts();
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
        autoRefreshToken: false,
      ),
    );
  });

  Future<void> pumpCard(
    WidgetTester tester,
    Post post, {
    double width = 390,
    VoidCallback? onViewsTap,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SocialPostCard(
              post: post,
              fullName: 'Ayşe Kaya',
              username: 'ayse',
              avatarUrl: null,
              authorRole: AuthorRole.unknown,
              isVerified: false,
              showPrivilegeBadges: false,
              onTap: () {},
              onAuthorTap: () {},
              onLike: () {},
              onComment: () {},
              onSend: () {},
              onSave: () {},
              onShare: () {},
              onViewsTap: onViewsTap,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('görüntülenme çipi sayı varken görünür, yokken gizli', (tester) async {
    await pumpCard(tester, _post(views: 1250));
    expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
    expect(find.text('1,2B'), findsOneWidget);
    expect(find.text('Cizre akşamı'), findsOneWidget);

    await pumpCard(tester, _post());
    expect(find.byIcon(Icons.visibility_outlined), findsNothing);
  });

  testWidgets('sahibine 0 iken de görünür ve dokununca istatistik açılır', (tester) async {
    var tapped = 0;
    await pumpCard(tester, _post(), onViewsTap: () => tapped++);
    expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
    await tester.tap(find.byIcon(Icons.visibility_outlined));
    // Kartın çift dokunma tanıyıcısı tekli dokunmayı zaman aşımına kadar bekletir.
    await tester.pump(const Duration(milliseconds: 400));
    expect(tapped, 1);
  });

  for (final width in [320.0, 360.0]) {
    testWidgets('$width dp: büyük sayılarla aksiyon satırı taşmaz', (tester) async {
      await pumpCard(
        tester,
        _post(views: 2345678, likes: 98765, comments: 45678, shares: 12345),
        width: width,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('2,3Mn'), findsOneWidget);
      expect(find.text('98,7B'), findsOneWidget);
      expect(find.byIcon(Icons.bookmark_border), findsOneWidget);
    });
  }

  testWidgets('düzenlenmiş gönderide "düzenlendi" yazar', (tester) async {
    await pumpCard(tester, _post(editedAt: '2026-09-29T08:00:00Z'));
    expect(find.text('· düzenlendi'), findsOneWidget);

    await pumpCard(tester, _post());
    expect(find.text('· düzenlendi'), findsNothing);
  });

  test('Post: views_count / edited_at / post_stats embed', () {
    final p = _post(views: 7, editedAt: '2026-09-29T08:00:00Z');
    expect(p.viewsCount, 7);
    expect(p.editedAt, DateTime.utc(2026, 9, 29, 8));
    final round = Post.fromJson(p.toJson());
    expect(round.viewsCount, 7);
    expect(round.editedAt, p.editedAt);
    expect(p.copyWith(viewsCount: 9).viewsCount, 9);

    final embedded = Post.fromJson({
      'id': 'p2',
      'user_id': 'u1',
      'post_stats': {'views_count': 42},
      'created_at': '2026-09-28T10:00:00Z',
    });
    expect(embedded.viewsCount, 42);
    final embeddedList = Post.fromJson({
      'id': 'p3',
      'user_id': 'u1',
      'post_stats': [
        {'views_count': 3},
      ],
      'created_at': '2026-09-28T10:00:00Z',
    });
    expect(embeddedList.viewsCount, 3);
    expect(Post.fromJson({'id': 'p4', 'created_at': '2026-09-28T10:00:00Z'}).viewsCount, 0);
  });
}
