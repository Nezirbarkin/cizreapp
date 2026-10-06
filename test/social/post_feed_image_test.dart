import 'dart:convert';
import 'dart:io';

import 'package:cizreapp/core/models/post_model.dart';
import 'package:cizreapp/features/social/widgets/post_image_carousel.dart';
import 'package:cizreapp/features/social/widgets/social_post_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../helpers/test_fonts.dart';

/// Görev 2.8 — akışta fotoğraf büyük ve kenardan kenara: kart genişliğinde,
/// gönderinin çerçeve oranında; oran satırla geldiği için kart görsel inmeden
/// doğru boyda (akış zıplamaz).

class _MemoryAsyncStorage extends GotrueAsyncStorage {
  final Map<String, String> _items = {};

  @override
  Future<String?> getItem({required String key}) async => _items[key];

  @override
  Future<void> setItem({required String key, required String value}) async => _items[key] = value;

  @override
  Future<void> removeItem({required String key}) async => _items.remove(key);
}

Post _post({List<String> images = const ['https://x.invalid/1.jpg'], double? aspect}) => Post.fromJson({
  'id': 'p1',
  'user_id': 'u1',
  'content': 'Cizre akşamı',
  'images': images,
  'image_aspect_ratio': aspect,
  'created_at': '2026-09-28T10:00:00Z',
  'updated_at': '2026-09-28T10:00:00Z',
});

/// CachedNetworkImage'ın önbellek yöneticisi sökülünce bile ~10 sn'lik bir
/// temizlik zamanlayıcısı bırakır; test bitmeden sahte saat ilerletilir.
Future<void> _finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 30));
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadTestFonts();
    SharedPreferences.setMockInitialValues({});
    // CachedNetworkImage önbellek dizini için path_provider ister.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => Directory.systemTemp.path,
    );
    // Kart avatarı profil özelliklerini RPC'den okur: boş liste.
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

  Future<void> pumpIn(WidgetTester tester, Widget child, {double width = 390}) async {
    tester.view.physicalSize = Size(width, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: child),
        ),
      ),
    );
    await tester.pump();
  }

  group('PostImageCarousel', () {
    testWidgets('verilen genişliğin tamamında, çerçeve oranında', (tester) async {
      await pumpIn(
        tester,
        const SizedBox(
          width: 360,
          child: PostImageCarousel(imageUrls: ['https://x.invalid/1.jpg'], aspectRatio: 0.8),
        ),
      );
      expect(tester.getSize(find.byType(PostImageCarousel)), const Size(360, 450));
      expect(find.text('1/1'), findsNothing);
      await _finish(tester);
    });

    testWidgets('çoklu görselde sayfa göstergesi; boş adresler atlanır', (tester) async {
      await pumpIn(
        tester,
        const SizedBox(
          width: 360,
          child: PostImageCarousel(
            imageUrls: ['https://x.invalid/1.jpg', '', 'https://x.invalid/2.jpg'],
            aspectRatio: 4 / 3,
          ),
        ),
      );
      expect(tester.getSize(find.byType(PostImageCarousel)), const Size(360, 270));
      expect(find.text('1/2'), findsOneWidget);
      await _finish(tester);
    });
  });

  group('SocialPostCard', () {
    Widget card(Post post) => Padding(
      // Keşfet akışıyla aynı yan boşluk (SliverPadding 12).
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: SocialPostCard(
        post: post,
        fullName: 'Ayşe Yılmaz',
        username: 'ayse',
        avatarUrl: null,
        authorRole: AuthorRole.customer,
        isVerified: false,
        showPrivilegeBadges: false,
        onTap: () {},
        onAuthorTap: () {},
        onLike: () {},
        onComment: () {},
        onSend: () {},
        onSave: () {},
      ),
    );

    testWidgets('fotoğraf kenardan kenara: kartın iç genişliği kadar, kayıtlı oranda', (tester) async {
      await pumpIn(tester, card(_post(aspect: 0.8)));

      final cardRect = tester.getRect(find.byType(SocialPostCard));
      final imageRect = tester.getRect(find.byType(PostImageCarousel));
      // Kart 390 − 2×12 = 366 px; 1 px kenarlık dışında boşluk yok.
      expect(cardRect.width, 366);
      expect(imageRect.left, cardRect.left + 1);
      expect(imageRect.right, cardRect.right - 1);
      expect(imageRect.width, 364);
      expect(imageRect.height, 455); // 4:5 — eskiden sabit 240 px
      // Yazı ve aksiyonlar kenar boşluklu kalır.
      expect(tester.getRect(find.text('Cizre akşamı')).left, greaterThan(cardRect.left + 14));
      await _finish(tester);
    });

    testWidgets('oranı bilinmeyen eski gönderi kare çizilir', (tester) async {
      await pumpIn(tester, card(_post()));
      expect(tester.getSize(find.byType(PostImageCarousel)), const Size(364, 364));
      await _finish(tester);
    });

    testWidgets('çok uzun oran 4:5\'e sıkıştırılır', (tester) async {
      await pumpIn(tester, card(_post(aspect: 0.5625)));
      expect(tester.getSize(find.byType(PostImageCarousel)), const Size(364, 455));
      await _finish(tester);
    });

    testWidgets('fotoğrafsız gönderide görsel alanı yok', (tester) async {
      await pumpIn(tester, card(_post(images: const [], aspect: 0.8)));
      expect(find.byType(PostImageCarousel), findsNothing);
      expect(find.text('Cizre akşamı'), findsOneWidget);
      await _finish(tester);
    });
  });
}
