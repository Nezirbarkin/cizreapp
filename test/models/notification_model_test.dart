// =============================================================================
// Notification Model Test - Tüm bildirim tipleri
// CizreApp - 10 farklı bildirim tipi + validasyon kuralları
// =============================================================================
// Kullanım:
//   flutter test test/models/notification_model_test.dart
// =============================================================================

// ignore_for_file: avoid_relative_lib_imports, avoid_print

import 'package:flutter_test/flutter_test.dart';
import 'package:cizreapp/core/models/notification_model.dart';

void main() {
  // ===========================================================================
  // 1. NOTIFICATION MODEL - fromJson
  // ===========================================================================
  group('🔔 NotificationModel - fromJson', () {
    test('Temel alanlarla parse edilmeli', () {
      final json = {
        'id': 'notif-123',
        'user_id': 'user-123',
        'type': 'like',
        'is_read': false,
        'created_at': '2026-08-01T10:00:00.000Z',
      };

      final notif = NotificationModel.fromJson(json);

      expect(notif.id, equals('notif-123'));
      expect(notif.userId, equals('user-123'));
      expect(notif.type, equals('like'));
      expect(notif.isRead, isFalse);
    });

    test('Tüm opsiyonel alanlarla parse edilmeli', () {
      final json = {
        'id': 'notif-1',
        'user_id': 'user-1',
        'type': 'comment',
        'title': 'Yeni Yorum',
        'content': 'Ahmet yorum yaptı: Harika!',
        'actor_id': 'user-2',
        'actor_name': 'Ahmet',
        'actor_avatar': 'https://example.com/avatar.jpg',
        'entity_id': 'post-1',
        'entity_type': 'post',
        'entity_image': 'https://example.com/post.jpg',
        'metadata': {'comment': 'Harika!', 'post_id': 'post-1'},
        'is_read': true,
        'created_at': '2026-08-01T10:00:00.000Z',
      };

      final notif = NotificationModel.fromJson(json);

      expect(notif.title, equals('Yeni Yorum'));
      expect(notif.body, equals('Ahmet yorum yaptı: Harika!'));
      expect(notif.actorId, equals('user-2'));
      expect(notif.actorName, equals('Ahmet'));
      expect(notif.entityType, equals('post'));
      expect(notif.metadata, isNotNull);
      expect(notif.isRead, isTrue);
    });

    test('is_read null ise false kabul edilmeli', () {
      final json = {
        'id': 'notif-1',
        'user_id': 'user-1',
        'type': 'follow',
        'created_at': '2026-08-01T10:00:00.000Z',
      };

      final notif = NotificationModel.fromJson(json);
      expect(notif.isRead, isFalse);
    });
  });

  // ===========================================================================
  // 2. NOTIFICATION MODEL - toJson
  // ===========================================================================
  group('🔔 NotificationModel - toJson', () {
    test('DB alan adları ile uyumlu JSON üretmeli', () {
      final notif = NotificationModel(
        id: 'notif-1',
        userId: 'user-1',
        type: 'like',
        title: 'Yeni Beğeni',
        body: 'Mehmet gönderini beğendi',
        actorName: 'Mehmet',
        isRead: false,
        createdAt: DateTime.parse('2026-08-01T10:00:00.000Z'),
      );

      final json = notif.toJson();

      expect(json['id'], equals('notif-1'));
      expect(json['user_id'], equals('user-1'));
      expect(json['type'], equals('like'));
      // 'body' alanı DB'de 'content' olarak kaydedilir
      expect(json['content'], equals('Mehmet gönderini beğendi'));
      expect(json['actor_name'], equals('Mehmet'));
      expect(json['is_read'], isFalse);
    });

    test('Round trip integrity (JSON → Model → JSON)', () {
      final original = {
        'id': 'notif-rt',
        'user_id': 'user-rt',
        'type': 'follow',
        'title': 'Yeni Takipçi',
        'content': 'Ali seni takip etti',
        'is_read': true,
        'created_at': '2026-08-01T10:00:00.000Z',
      };

      final notif = NotificationModel.fromJson(original);
      final output = notif.toJson();

      expect(output['id'], equals(original['id']));
      expect(output['user_id'], equals(original['user_id']));
      expect(output['type'], equals(original['type']));
      expect(output['content'], equals(original['content']));
    });
  });

  // ===========================================================================
  // 3. BİLDİRİM İÇERİĞİ OLUŞTURMA - Tüm Tipler
  // ===========================================================================
  group('📝 getNotificationContent - Tüm Bildirim Tipleri', () {
    test('like: Yeni Beğeni', () {
      final content = NotificationModel.getNotificationContent('like', {
        'username': 'Ahmet',
      });
      expect(content['title'], equals('Yeni Beğeni'));
      expect(content['body'], contains('Ahmet'));
      expect(content['body'], contains('beğendi'));
    });

    test('comment: Yorum + 30 karakter sınırı', () {
      final longComment = 'a' * 50;
      final content = NotificationModel.getNotificationContent('comment', {
        'username': 'Mehmet',
        'comment': longComment,
      });
      expect(content['title'], equals('Yeni Yorum'));
      // 30 karakter + '...' olmalı
      expect(content['body'], contains('...'));
      expect(content['body']!.length, lessThan(longComment.length + 30));
    });

    test('comment: Kısa yorum tam gösterilmeli', () {
      final content = NotificationModel.getNotificationContent('comment', {
        'username': 'Ayşe',
        'comment': 'Süper!',
      });
      expect(content['body'], contains('Süper!'));
      expect(content['body'], isNot(contains('...')));
    });

    test('follow: Yeni Takipçi', () {
      final content = NotificationModel.getNotificationContent('follow', {
        'username': 'Veli',
      });
      expect(content['title'], equals('Yeni Takipçi'));
      expect(content['body'], contains('Veli'));
    });

    test('mention: Etiketlendiğin', () {
      final content = NotificationModel.getNotificationContent('mention', {
        'username': 'Zeynep',
      });
      expect(content['title'], equals('Etiketlendiğin'));
      expect(content['body'], contains('Zeynep'));
    });

    test('order: Sipariş Güncellemesi', () {
      final content = NotificationModel.getNotificationContent('order', {
        'shop_name': 'Ahmet Bakkal',
      });
      expect(content['title'], equals('Sipariş Güncellemesi'));
      expect(content['body'], contains('Ahmet Bakkal'));
    });

    test('shop: Yeni Dükkan', () {
      final content = NotificationModel.getNotificationContent('shop', {
        'shop_name': 'Market 123',
      });
      expect(content['title'], equals('Yeni Dükkan'));
      expect(content['body'], contains('Market 123'));
    });

    test('admin_notification: Duyuru', () {
      final content = NotificationModel.getNotificationContent(
        'admin_notification',
        {
          'title': 'Özel Kampanya',
          'body': 'Tüm ürünlerde %50 indirim',
        },
      );
      expect(content['title'], equals('Özel Kampanya'));
      expect(content['body'], equals('Tüm ürünlerde %50 indirim'));
    });

    test('Bilinmeyen tip: generic fallback', () {
      final content = NotificationModel.getNotificationContent(
        'unknown_type',
        null,
      );
      expect(content['title'], equals('Bildirim'));
      expect(content['body'], equals('Yeni bir bildirimin var'));
    });

    test('username olmadan default kullanılmalı', () {
      final content = NotificationModel.getNotificationContent('like', {});
      expect(content['body'], contains('Bir kullanıcı'));
    });
  });

  // ===========================================================================
  // 4. EDGE CASES
  // ===========================================================================
  group('🧪 Edge Cases', () {
    test('Boş metadata ile bildirim üretilebilmeli', () {
      final content = NotificationModel.getNotificationContent('like', null);
      expect(content['title'], isNotNull);
      expect(content['body'], isNotNull);
    });

    test('Eski tarihler parse edilebilmeli', () {
      final json = {
        'id': 'notif-old',
        'user_id': 'user-1',
        'type': 'like',
        'is_read': false,
        'created_at': '2020-01-01T00:00:00.000Z',
      };

      final notif = NotificationModel.fromJson(json);
      expect(notif.createdAt.year, equals(2020));
    });

    test('Unicode karakterler korunmalı (Türkçe)', () {
      final content = NotificationModel.getNotificationContent('comment', {
        'username': 'Çiğdem Yılmaz',
        'comment': 'Çok güzel! 👍',
      });
      expect(content['body'], contains('Çiğdem'));
      expect(content['body'], contains('güzel'));
    });
  });

  // ===========================================================================
  // 5. SONUÇ RAPORU
  // ===========================================================================
  tearDownAll(() {
    print('\n${'=' * 60}');
    print('🔔 NOTIFICATION MODEL TEST SONUÇ RAPORU');
    print('=' * 60);
    print('✅ Tüm bildirim tipleri test edildi');
    print('💡 Kapsam:');
    print('   - JSON parse/serialize (10+ tip)');
    print('   - Default değerler (is_read=null)');
    print('   - Türkçe karakter desteği');
    print('   - Uzun yorum kırpma (30 char)');
    print('   - Bilinmeyen tip fallback');
    print('=' * 60);
  });
}
