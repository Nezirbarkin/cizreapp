// =============================================================================
// Sosyal Modeller — Birim Testleri
// Post, PostComment, Story, StoryView, AuthorRole, firstNonEmpty
// =============================================================================
// Kullanım: flutter test test/models/social_models_test.dart
// Bu testler pure-Dart'tır, plugin/backend gerektirmez; Supabase JSON sözleşmesi
// ile birebir uyumlu parse davranışını doğrular.
// =============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:cizreapp/core/models/post_model.dart';

void main() {
  // ===========================================================================
  // AuthorRole
  // ===========================================================================
  group('👤 AuthorRole', () {
    test('fromString — geçerli değerler', () {
      expect(AuthorRole.fromString('customer'), AuthorRole.customer);
      expect(AuthorRole.fromString('seller'), AuthorRole.seller);
      expect(AuthorRole.fromString('admin'), AuthorRole.admin);
      expect(AuthorRole.fromString('courier'), AuthorRole.courier);
      expect(AuthorRole.fromString('driver'), AuthorRole.driver);
    });

    test('fromString — null / bilinmeyen → unknown', () {
      expect(AuthorRole.fromString(null), AuthorRole.unknown);
      expect(AuthorRole.fromString(''), AuthorRole.unknown);
      expect(AuthorRole.fromString('hacker'), AuthorRole.unknown);
    });

    test('displayLabel — Türkçe etiketler', () {
      expect(AuthorRole.customer.displayLabel, 'Kullanıcı');
      expect(AuthorRole.seller.displayLabel, 'Satıcı');
      expect(AuthorRole.courier.displayLabel, 'Kurye');
      expect(AuthorRole.driver.displayLabel, 'Sürücü');
      expect(AuthorRole.admin.displayLabel, 'Admin');
      expect(AuthorRole.unknown.displayLabel, 'Bilinmeyen');
    });

    test('isStaff — yalnızca görevli roller', () {
      expect(AuthorRole.customer.isStaff, isFalse);
      expect(AuthorRole.unknown.isStaff, isFalse);
      expect(AuthorRole.seller.isStaff, isTrue);
      expect(AuthorRole.courier.isStaff, isTrue);
      expect(AuthorRole.driver.isStaff, isTrue);
      expect(AuthorRole.admin.isStaff, isTrue);
    });
  });

  // ===========================================================================
  // firstNonEmpty — null/boş/whitespace kurtarıcı
  // ===========================================================================
  group('🔤 firstNonEmpty', () {
    test('ilk null olmayan dolu değeri döner', () {
      expect(firstNonEmpty([null, '', '  ', 'Ali', 'Veli']), 'Ali');
    });

    test('tümü boşsa fallback döner', () {
      expect(firstNonEmpty([null, '', '   ']), 'Bilinmeyen Kullanıcı');
      expect(firstNonEmpty([null, '', '   '], fallback: 'Anonim'), 'Anonim');
    });

    test('liste boşsa fallback döner', () {
      expect(firstNonEmpty(const []), 'Bilinmeyen Kullanıcı');
    });

    test('whitespace kırpması doğru çalışır', () {
      expect(firstNonEmpty(['   ']), 'Bilinmeyen Kullanıcı');
      expect(firstNonEmpty([' x ']), ' x ');
    });
  });

  // ===========================================================================
  // Post
  // ===========================================================================
  group('📝 Post', () {
    final baseJson = {
      'id': 'post-1',
      'user_id': 'user-1',
      'content': 'Merhaba dünya',
      'images': <String>['https://cdn/a.jpg', 'https://cdn/b.jpg'],
      'image_url': null,
      'location': 'Cizre',
      'latitude': 37.33,
      'longitude': 42.19,
      'likes_count': 12,
      'comments_count': 3,
      'shares_count': 1,
      'is_active': true,
      'is_pinned': false,
      'admin_pinned': true,
      'created_at': '2026-01-01T10:00:00.000Z',
      'updated_at': '2026-01-01T10:05:00.000Z',
    };

    test('fromJson — view\'dan gelen düz alanlar doğru parse edilir', () {
      final json = {
        ...baseJson,
        // posts_with_profiles view sütunları:
        'username': 'ahmet',
        'full_name': 'Ahmet Yılmaz',
        'avatar_url': 'https://cdn/avatar.jpg',
        'role': 'seller',
        'is_verified': true,
      };
      final post = Post.fromJson(json);
      expect(post.id, 'post-1');
      expect(post.userId, 'user-1');
      expect(post.content, 'Merhaba dünya');
      expect(post.images, ['https://cdn/a.jpg', 'https://cdn/b.jpg']);
      expect(post.likesCount, 12);
      expect(post.commentsCount, 3);
      expect(post.sharesCount, 1);
      expect(post.isActive, isTrue);
      expect(post.isPinned, isFalse);
      expect(post.adminPinned, isTrue);
      expect(post.authorUsername, 'ahmet');
      expect(post.authorFullName, 'Ahmet Yılmaz');
      expect(post.authorAvatarUrl, 'https://cdn/avatar.jpg');
      expect(post.authorRole, AuthorRole.seller);
      expect(post.authorIsVerified, isTrue);
      expect(post.authorProfileExists, isTrue);
      expect(post.createdAt.year, 2026);
    });

    test('fromJson — author_* alanları (cache restore)', () {
      final post = Post.fromJson({
        ...baseJson,
        'author_username': 'mehmet',
        'author_full_name': 'Mehmet',
        'author_avatar_url': 'https://x.jpg',
        'author_role': 'admin',
        'author_is_verified': false,
      });
      expect(post.authorUsername, 'mehmet');
      expect(post.authorRole, AuthorRole.admin);
      expect(post.authorIsVerified, isFalse);
    });

    test('fromJson — legacy image_url → images fallback', () {
      final post = Post.fromJson({
        ...baseJson,
        'images': <String>[],
        'image_url': 'https://cdn/legacy.jpg',
      });
      expect(post.images, ['https://cdn/legacy.jpg']);
      expect(post.imageUrl, 'https://cdn/legacy.jpg');
    });

    test('fromJson — user_id null ise boş string (orphan post korunur)', () {
      final post = Post.fromJson({...baseJson, 'user_id': null});
      expect(post.userId, '');
      // authorProfileExists default true kalır (UI "Bilinmeyen" fallback'i)
    });

    test('fromJson — opsiyonel alanlar default değer alır', () {
      final post = Post.fromJson({
        'id': 'p',
        'user_id': 'u',
        'created_at': '2026-01-01T00:00:00.000Z',
        'updated_at': '2026-01-01T00:00:00.000Z',
      });
      expect(post.content, isNull);
      expect(post.images, isEmpty);
      expect(post.likesCount, 0);
      expect(post.commentsCount, 0);
      expect(post.sharesCount, 0);
      expect(post.isActive, isTrue);
      expect(post.isPinned, isFalse);
      expect(post.adminPinned, isFalse);
      expect(post.authorRole, AuthorRole.unknown);
      expect(post.authorProfileExists, isTrue);
    });

    test('copyWith — seçici güncelleme', () {
      final post = Post.fromJson(baseJson);
      final updated = post.copyWith(
        likesCount: 99,
        isPinned: true,
        authorIsVerified: true,
      );
      expect(updated.id, post.id);
      expect(updated.likesCount, 99);
      expect(updated.isPinned, isTrue);
      expect(updated.authorIsVerified, isTrue);
      // değişmeyen alanlar
      expect(updated.commentsCount, post.commentsCount);
      expect(updated.userId, post.userId);
    });

    test('toJson — round-trip uyumu', () {
      final post = Post.fromJson({
        ...baseJson,
        'username': 'x',
        'full_name': 'X',
        'avatar_url': 'https://x/a.jpg',
        'role': 'customer',
        'is_verified': true,
      });
      final json = post.toJson();
      final restored = Post.fromJson(json);
      expect(restored.id, post.id);
      expect(restored.userId, post.userId);
      expect(restored.content, post.content);
      expect(restored.images, post.images);
      expect(restored.likesCount, post.likesCount);
      expect(restored.authorUsername, post.authorUsername);
      expect(restored.authorRole, post.authorRole);
      expect(restored.authorIsVerified, post.authorIsVerified);
    });
  });

  // ===========================================================================
  // PostComment
  // ===========================================================================
  group('💬 PostComment', () {
    test('fromJson / toJson — round-trip', () {
      final json = {
        'id': 'c1',
        'post_id': 'p1',
        'user_id': 'u1',
        'content': 'Güzel post!',
        'created_at': '2026-01-01T10:00:00.000Z',
        'updated_at': '2026-01-01T10:01:00.000Z',
      };
      final c = PostComment.fromJson(json);
      expect(c.id, 'c1');
      expect(c.postId, 'p1');
      expect(c.userId, 'u1');
      expect(c.content, 'Güzel post!');

      final out = c.toJson();
      expect(out['id'], 'c1');
      expect(out['content'], 'Güzel post!');
      expect(out['created_at'], '2026-01-01T10:00:00.000Z');
    });
  });

  // ===========================================================================
  // Story
  // ===========================================================================
  group('📸 Story', () {
    final now = DateTime.now();
    Story makeStory({
      String id = 's1',
      String userId = 'u1',
      String mediaType = 'image',
      int likesCount = 0,
      int viewsCount = 0,
      bool isLikedByCurrentUser = false,
      bool isViewedByCurrentUser = false,
      bool isPinned = false,
      DateTime? expiresAt,
      String? username,
      String? fullName,
      String? avatarUrl,
    }) {
      return Story(
        id: id,
        userId: userId,
        imageUrl: 'https://cdn/story.jpg',
        mediaType: mediaType,
        likesCount: likesCount,
        viewsCount: viewsCount,
        isLikedByCurrentUser: isLikedByCurrentUser,
        isViewedByCurrentUser: isViewedByCurrentUser,
        isPinned: isPinned,
        createdAt: now.subtract(const Duration(hours: 1)),
        expiresAt: expiresAt ?? now.add(const Duration(hours: 23)),
        username: username,
        fullName: fullName,
        avatarUrl: avatarUrl,
      );
    }

    test('isExpired — expiresAt geçmişse true', () {
      final s = makeStory(expiresAt: now.subtract(const Duration(minutes: 1)));
      expect(s.isExpired, isTrue);
    });

    test('isExpired — gelecekteyse false', () {
      final s = makeStory(expiresAt: now.add(const Duration(hours: 1)));
      expect(s.isExpired, isFalse);
    });

    test('isVideo / isImage — mediaType doğru çözülür', () {
      expect(makeStory(mediaType: 'video').isVideo, isTrue);
      expect(makeStory(mediaType: 'image').isImage, isTrue);
      // default
      expect(
        Story(
          id: 'x',
          userId: 'u',
          imageUrl: 'u',
          createdAt: now,
          expiresAt: now.add(const Duration(hours: 1)),
        ).isImage,
        isTrue,
      );
    });

    test('displayUrl — video için thumbnail, image için imageUrl', () {
      final v = Story(
        id: 's',
        userId: 'u',
        imageUrl: 'https://cdn/v.mp4',
        thumbnailUrl: 'https://cdn/v.jpg',
        mediaType: 'video',
        createdAt: now,
        expiresAt: now.add(const Duration(hours: 1)),
      );
      expect(v.displayUrl, 'https://cdn/v.jpg');

      final i = Story(
        id: 's',
        userId: 'u',
        imageUrl: 'https://cdn/i.jpg',
        mediaType: 'image',
        createdAt: now,
        expiresAt: now.add(const Duration(hours: 1)),
      );
      expect(i.displayUrl, 'https://cdn/i.jpg');
    });

    test('copyWith — beğeni toggle simülasyonu', () {
      final s = makeStory(likesCount: 5, isLikedByCurrentUser: false);
      final liked = s.copyWith(likesCount: 6, isLikedByCurrentUser: true);
      expect(liked.likesCount, 6);
      expect(liked.isLikedByCurrentUser, isTrue);
      // geri alma
      final unliked = liked.copyWith(
        likesCount: 5,
        isLikedByCurrentUser: false,
      );
      expect(unliked.likesCount, 5);
      expect(unliked.isLikedByCurrentUser, isFalse);
    });

    test('fromJson / toJson — view round-trip', () {
      final json = {
        'id': 's1',
        'user_id': 'u1',
        'image_url': 'https://cdn/s.jpg',
        'media_type': 'image',
        'views_count': 42,
        'likes_count': 7,
        'created_at': now.subtract(const Duration(hours: 2)).toIso8601String(),
        'expires_at': now.add(const Duration(hours: 22)).toIso8601String(),
        'is_viewed_by_current_user': true,
        'is_liked_by_current_user': false,
        'is_pinned': true,
        'admin_pinned': false,
        'username': 'ali',
        'full_name': 'Ali Veli',
        'avatar_url': 'https://cdn/ali.jpg',
      };
      final s = Story.fromJson(json);
      expect(s.id, 's1');
      expect(s.userId, 'u1');
      expect(s.isImage, isTrue);
      expect(s.isPinned, isTrue);
      expect(s.adminPinned, isFalse);
      expect(s.isViewedByCurrentUser, isTrue);
      expect(s.isLikedByCurrentUser, isFalse);
      expect(s.username, 'ali');
      expect(s.fullName, 'Ali Veli');

      final out = s.toJson();
      expect(out['id'], 's1');
      expect(out['is_pinned'], isTrue);
      expect(out['username'], 'ali');
    });
  });

  // ===========================================================================
  // StoryView
  // ===========================================================================
  group('👁️ StoryView', () {
    test('fromJson / toJson — round-trip', () {
      final json = {
        'id': 'sv-1',
        'story_id': 's-1',
        'viewer_id': 'u-2',
        'created_at': '2026-01-01T12:00:00.000Z',
      };
      final v = StoryView.fromJson(json);
      expect(v.id, 'sv-1');
      expect(v.storyId, 's-1');
      expect(v.viewerId, 'u-2');
      expect(v.createdAt.hour, 12);
      expect(v.toJson()['story_id'], 's-1');
    });
  });
}
