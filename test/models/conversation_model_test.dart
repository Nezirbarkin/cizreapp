// =============================================================================
// Conversation Model Test - DM (Direct Message) Konuşmaları
// CizreApp - 1'e 1 mesajlaşma konuşma listesi
// =============================================================================
// Kullanım:
//   flutter test test/models/conversation_model_test.dart
// =============================================================================

// ignore_for_file: avoid_relative_lib_imports, avoid_print

import 'package:flutter_test/flutter_test.dart';
import 'package:cizreapp/core/models/conversation_model.dart';

void main() {
  // ===========================================================================
  // 1. CONVERSATION - fromMap
  // ===========================================================================
  group('💬 Conversation - fromMap', () {
    test('Temel alanlarla parse edilmeli', () {
      final map = {
        'id': 'conv-123',
        'user_id': 'user-1',
        'other_user_id': 'user-2',
        'created_at': '2026-08-01T10:00:00.000Z',
        'updated_at': '2026-08-01T10:00:00.000Z',
      };

      final conv = Conversation.fromMap(map);

      expect(conv.id, equals('conv-123'));
      expect(conv.userId, equals('user-1'));
      expect(conv.otherUserId, equals('user-2'));
      expect(conv.unreadCount, equals(0),
          reason: 'Default unread count 0 olmalı');
      expect(conv.lastMessage, isNull);
      expect(conv.lastMessageTime, isNull);
    });

    test('Son mesaj ve okunma durumu ile parse edilmeli', () {
      final map = {
        'id': 'conv-1',
        'user_id': 'user-1',
        'other_user_id': 'user-2',
        'last_message': 'Merhaba!',
        'last_message_time': '2026-08-01T15:30:00.000Z',
        'unread_count': 3,
        'created_at': '2026-08-01T10:00:00.000Z',
        'updated_at': '2026-08-01T15:30:00.000Z',
        'last_message_by_me': true,
        'last_message_read': true,
      };

      final conv = Conversation.fromMap(map);

      expect(conv.lastMessage, equals('Merhaba!'));
      expect(conv.lastMessageTime, isA<DateTime>());
      expect(conv.unreadCount, equals(3));
      expect(conv.lastMessageByMe, isTrue);
      expect(conv.lastMessageRead, isTrue);
    });

    test('Other user bilgisi (join) ile parse edilmeli', () {
      final map = {
        'id': 'conv-1',
        'user_id': 'user-1',
        'other_user_id': 'user-2',
        'other_user': {
          'id': 'user-2',
          'full_name': 'Ahmet Yılmaz',
          'avatar_url': 'https://example.com/avatar.jpg',
          'is_online': true,
        },
        'created_at': '2026-08-01T10:00:00.000Z',
        'updated_at': '2026-08-01T10:00:00.000Z',
      };

      final conv = Conversation.fromMap(map);

      expect(conv.otherUser, isNotNull);
      expect(conv.otherUser!['full_name'], equals('Ahmet Yılmaz'));
      expect(conv.otherUser!['is_online'], isTrue);
    });

    test('null last_message_time güvenli parse edilmeli', () {
      final map = {
        'id': 'conv-1',
        'user_id': 'user-1',
        'other_user_id': 'user-2',
        'last_message_time': null,
        'created_at': '2026-08-01T10:00:00.000Z',
        'updated_at': '2026-08-01T10:00:00.000Z',
      };

      final conv = Conversation.fromMap(map);
      expect(conv.lastMessageTime, isNull);
    });

    test('Default değerler doğru uygulanmalı', () {
      final map = {
        'id': 'conv-1',
        'user_id': 'user-1',
        'other_user_id': 'user-2',
        'created_at': '2026-08-01T10:00:00.000Z',
        'updated_at': '2026-08-01T10:00:00.000Z',
      };

      final conv = Conversation.fromMap(map);
      expect(conv.unreadCount, equals(0));
      expect(conv.lastMessageByMe, isFalse);
      expect(conv.lastMessageRead, isFalse);
    });
  });

  // ===========================================================================
  // 2. CONVERSATION - copyWith
  // ===========================================================================
  group('💬 Conversation - copyWith', () {
    test('Sadece belirtilen alanlar değişmeli', () {
      final original = Conversation(
        id: 'conv-1',
        userId: 'user-1',
        otherUserId: 'user-2',
        lastMessage: 'Eski mesaj',
        lastMessageTime: DateTime.parse('2026-08-01T10:00:00.000Z'),
        unreadCount: 2,
        createdAt: DateTime.parse('2026-08-01T09:00:00.000Z'),
        updatedAt: DateTime.parse('2026-08-01T10:00:00.000Z'),
      );

      final updated = original.copyWith(
        lastMessage: 'Yeni mesaj',
        unreadCount: 0,
      );

      expect(updated.id, equals(original.id));
      expect(updated.userId, equals(original.userId));
      expect(updated.otherUserId, equals(original.otherUserId));
      expect(updated.lastMessage, equals('Yeni mesaj'));
      expect(updated.unreadCount, equals(0));
    });

    test('Hiçbir parametre verilmezse orijinali dönmeli', () {
      final original = Conversation(
        id: 'conv-1',
        userId: 'user-1',
        otherUserId: 'user-2',
        createdAt: DateTime.parse('2026-08-01T10:00:00.000Z'),
        updatedAt: DateTime.parse('2026-08-01T10:00:00.000Z'),
      );

      final copy = original.copyWith();

      expect(copy.id, equals(original.id));
      expect(copy.userId, equals(original.userId));
      expect(copy.otherUserId, equals(original.otherUserId));
    });
  });

  // ===========================================================================
  // 3. EDGE CASES
  // ===========================================================================
  group('🧪 Edge Cases', () {
    test('Çok yüksek unread count (999+) parse edilebilmeli', () {
      final map = {
        'id': 'conv-spam',
        'user_id': 'user-1',
        'other_user_id': 'user-spam',
        'unread_count': 9999,
        'created_at': '2026-08-01T10:00:00.000Z',
        'updated_at': '2026-08-01T10:00:00.000Z',
      };

      final conv = Conversation.fromMap(map);
      expect(conv.unreadCount, equals(9999));
    });

    test('Türkçe karakterler korunmalı', () {
      final map = {
        'id': 'conv-tr',
        'user_id': 'user-1',
        'other_user_id': 'user-2',
        'last_message': 'Merhaba, nasılsın? Çok iyiyim!',
        'last_message_time': '2026-08-01T10:00:00.000Z',
        'created_at': '2026-08-01T10:00:00.000Z',
        'updated_at': '2026-08-01T10:00:00.000Z',
      };

      final conv = Conversation.fromMap(map);
      expect(conv.lastMessage, contains('nasılsın'));
      expect(conv.lastMessage, contains('Çok'));
    });

    test('Emoji içeren mesaj parse edilebilmeli', () {
      final map = {
        'id': 'conv-emoji',
        'user_id': 'user-1',
        'other_user_id': 'user-2',
        'last_message': 'Harika! 🎉👍✨',
        'last_message_time': '2026-08-01T10:00:00.000Z',
        'created_at': '2026-08-01T10:00:00.000Z',
        'updated_at': '2026-08-01T10:00:00.000Z',
      };

      final conv = Conversation.fromMap(map);
      expect(conv.lastMessage, contains('🎉'));
      expect(conv.lastMessage, contains('👍'));
    });

    test('Çok uzun mesaj (5000 karakter) parse edilebilmeli', () {
      final longMessage = 'a' * 5000;
      final map = {
        'id': 'conv-long',
        'user_id': 'user-1',
        'other_user_id': 'user-2',
        'last_message': longMessage,
        'last_message_time': '2026-08-01T10:00:00.000Z',
        'created_at': '2026-08-01T10:00:00.000Z',
        'updated_at': '2026-08-01T10:00:00.000Z',
      };

      final conv = Conversation.fromMap(map);
      expect(conv.lastMessage!.length, equals(5000));
    });
  });

  // ===========================================================================
  // 4. SONUÇ RAPORU
  // ===========================================================================
  tearDownAll(() {
    print('\n${'=' * 60}');
    print('💬 CONVERSATION MODEL TEST SONUÇ RAPORU');
    print('=' * 60);
    print('✅ DM konuşma modeli test edildi');
    print('💡 Kapsam:');
    print('   - JSON parse/serialize');
    print('   - Son mesaj + okunma durumu');
    print('   - Other user join (online status)');
    print('   - Default değerler');
    print('   - Türkçe + Emoji + uzun mesaj');
    print('=' * 60);
  });
}
