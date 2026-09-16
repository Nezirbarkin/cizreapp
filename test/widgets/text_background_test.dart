import 'package:cizreapp/core/models/post_model.dart';
import 'package:cizreapp/core/widgets/text_background.dart';
import 'package:cizreapp/features/profile/widgets/profile_post_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Post _post({
  required String id,
  String? content,
  String? background,
  List<String> images = const [],
}) {
  final now = DateTime(2026, 9, 9);
  return Post(
    id: id,
    userId: 'u1',
    content: content,
    images: images,
    background: background,
    createdAt: now,
    updatedAt: now,
  );
}

Widget _grid(List<Post> posts) {
  return MaterialApp(
    home: Scaffold(
      body: CustomScrollView(
        slivers: [
          ProfilePostGrid(
            posts: posts,
            likedPostIds: const <String>{},
            onTap: (_) {},
          ),
        ],
      ),
    ),
  );
}

void main() {
  group('TextBackground kataloğu', () {
    test('kimlikler benzersiz ve DB CHECK deseniyle uyumlu', () {
      final ids = kTextBackgrounds.map((b) => b.id).toList();
      expect(ids.toSet().length, ids.length, reason: 'yinelenen kimlik var');

      // posts_background_slug_check / stories_background_slug_check ile aynı
      // desen: küçük harf, rakam, alt çizgi ve en fazla 32 karakter.
      final pattern = RegExp(r'^[a-z0-9_]{1,32}$');
      for (final id in ids) {
        expect(pattern.hasMatch(id), isTrue, reason: 'geçersiz kimlik: $id');
      }
    });

    test('bilinmeyen kimlik sade çizime düşer, varsayılan ise düşmez', () {
      expect(textBackgroundById(null), isNull);
      expect(textBackgroundById(''), isNull);
      expect(textBackgroundById('boyle_bir_zemin_yok'), isNull);
      expect(textBackgroundOrDefault('boyle_bir_zemin_yok'),
          kTextBackgrounds.first);
      expect(textBackgroundById('sunset')?.label, 'Gun Batimi');
    });

    test('punto uzun metinde küçülür ve sınırların dışına taşmaz', () {
      final short = textBackgroundFontSize('Merhaba', 300);
      final long = textBackgroundFontSize('a' * 400, 300);
      expect(short, greaterThan(long));
      expect(long, greaterThanOrEqualTo(11.0));
      expect(short, lessThanOrEqualTo(46.0));
    });
  });

  group('ProfilePostGrid metin kareleri', () {
    testWidgets('arka plan seçilmemiş metin gönderisi SADE çizilir',
        (tester) async {
      await tester.pumpWidget(_grid([_post(id: 'p1', content: 'Sade yazı')]));

      expect(find.text('Sade yazı'), findsOneWidget);
      // Sade karede zemin çizen widget hiç kurulmaz.
      expect(find.byType(TextBackgroundCanvas), findsNothing);
    });

    testWidgets('arka planlı metin gönderisi zeminiyle çizilir',
        (tester) async {
      await tester.pumpWidget(
        _grid([_post(id: 'p2', content: 'Renkli yazı', background: 'sunset')]),
      );

      expect(find.text('Renkli yazı'), findsOneWidget);
      final canvas = tester.widget<TextBackgroundCanvas>(
        find.byType(TextBackgroundCanvas),
      );
      expect(canvas.background.id, 'sunset');
    });

    testWidgets('bilinmeyen arka plan kimliği sade kareye düşer',
        (tester) async {
      await tester.pumpWidget(
        _grid([_post(id: 'p3', content: 'Yazı', background: 'yok_boyle')]),
      );

      expect(find.byType(TextBackgroundCanvas), findsNothing);
      expect(find.text('Yazı'), findsOneWidget);
    });
  });

  group('Post modeli', () {
    test('görselli gönderide arka plan düşürülür', () {
      final post = Post.fromJson({
        'id': 'p4',
        'user_id': 'u1',
        'content': 'Görselli',
        'images': ['https://example.com/a.jpg'],
        'background': 'sunset',
        'created_at': '2026-09-09T00:00:00Z',
        'updated_at': '2026-09-09T00:00:00Z',
      });

      expect(post.background, isNull);
    });

    test('görselsiz gönderide arka plan korunur', () {
      final post = Post.fromJson({
        'id': 'p5',
        'user_id': 'u1',
        'content': 'Metin',
        'images': <String>[],
        'background': 'ocean',
        'created_at': '2026-09-09T00:00:00Z',
        'updated_at': '2026-09-09T00:00:00Z',
      });

      expect(post.background, 'ocean');
    });
  });

  group('Story modeli', () {
    test('metin hikayesi image_url NULL ile parse edilir', () {
      final story = Story.fromJson({
        'id': 's1',
        'user_id': 'u1',
        'image_url': null,
        'media_type': 'text',
        'text_content': 'Merhaba',
        'background': 'grape',
        'created_at': '2026-09-09T00:00:00Z',
        'expires_at': '2026-09-10T00:00:00Z',
      });

      expect(story.isText, isTrue);
      expect(story.isVideo, isFalse);
      expect(story.imageUrl, '');
      expect(story.textContent, 'Merhaba');
      expect(story.background, 'grape');
    });
  });
}
