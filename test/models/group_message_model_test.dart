// =============================================================================
// Group Message Model Test - Grup mesajlaşma
// CizreApp - Grup içi mesaj gönderme/alma, yanıt, okunma durumu
// =============================================================================
// Kullanım:
//   flutter test test/models/group_message_model_test.dart
// =============================================================================

// ignore_for_file: avoid_relative_lib_imports, avoid_print

import 'package:flutter_test/flutter_test.dart';
import 'package:cizreapp/core/models/group_message_model.dart';

void main() {
  // ===========================================================================
  // 1. GROUP MESSAGE - fromMap
  // ===========================================================================
  group('👥 GroupMessage - fromMap', () {
    test('Temel alanlarla parse edilmeli', () {
      final map = {
        'id': 'msg-123',
        'group_id': 'group-1',
        'sender_id': 'user-1',
        'content': 'Merhaba grup!',
        'created_at': '2026-08-01T10:00:00.000Z',
        'updated_at': '2026-08-01T10:00:00.000Z',
      };

      final msg = GroupMessage.fromMap(map);

      expect(msg.id, equals('msg-123'));
      expect(msg.groupId, equals('group-1'));
      expect(msg.senderId, equals('user-1'));
      expect(msg.content, equals('Merhaba grup!'));
      expect(msg.isFailed, isFalse);
      expect(msg.isSending, isFalse);
    });

    test('Sender bilgisi (join) ile parse edilmeli', () {
      final map = {
        'id': 'msg-1',
        'group_id': 'group-1',
        'sender_id': 'user-1',
        'content': 'Test mesaj',
        'created_at': '2026-08-01T10:00:00.000Z',
        'updated_at': '2026-08-01T10:00:00.000Z',
        'sender': {
          'full_name': 'Ahmet Yılmaz',
          'avatar_url': 'https://example.com/avatar.jpg',
        },
      };

      final msg = GroupMessage.fromMap(map);

      expect(msg.senderName, equals('Ahmet Yılmaz'));
      expect(msg.senderAvatarUrl, equals('https://example.com/avatar.jpg'));
    });

    test('Reply (yanıt) bilgisi ile parse edilmeli', () {
      final map = {
        'id': 'msg-reply',
        'group_id': 'group-1',
        'sender_id': 'user-2',
        'content': 'Katılıyorum!',
        'created_at': '2026-08-01T11:00:00.000Z',
        'updated_at': '2026-08-01T11:00:00.000Z',
        'reply_to_id': 'msg-original',
        'reply_to_content': 'Ne düşünüyorsunuz?',
        'reply_to_sender_name': 'Ahmet',
      };

      final msg = GroupMessage.fromMap(map);

      expect(msg.replyToId, equals('msg-original'));
      expect(msg.replyToContent, equals('Ne düşünüyorsunuz?'));
      expect(msg.replyToSenderName, equals('Ahmet'));
    });

    test('read_by_count opsiyonel alan', () {
      final map = {
        'id': 'msg-1',
        'group_id': 'group-1',
        'sender_id': 'user-1',
        'content': 'Mesaj',
        'created_at': '2026-08-01T10:00:00.000Z',
        'updated_at': '2026-08-01T10:00:00.000Z',
        'read_by_count': 5,
      };

      final msg = GroupMessage.fromMap(map);
      expect(msg.readByCount, equals(5));
    });

    test('read_by_count yoksa 0 olmalı', () {
      final map = {
        'id': 'msg-1',
        'group_id': 'group-1',
        'sender_id': 'user-1',
        'content': 'Mesaj',
        'created_at': '2026-08-01T10:00:00.000Z',
        'updated_at': '2026-08-01T10:00:00.000Z',
      };

      final msg = GroupMessage.fromMap(map);
      expect(msg.readByCount, equals(0));
    });
  });

  // ===========================================================================
  // 2. MESSAGE STATUS (Gönderim durumu)
  // ===========================================================================
  group('📤 Message Status (Gönderim Durumu)', () {
    test('isFailed true ise status "failed" olmalı', () {
      final msg = GroupMessage(
        id: 'msg-1',
        groupId: 'group-1',
        senderId: 'user-1',
        content: 'Mesaj',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        isFailed: true,
        isSending: false,
      );

      expect(msg.messageStatus, equals('failed'));
    });

    test('isSending true ise status "sending" olmalı', () {
      final msg = GroupMessage(
        id: 'msg-1',
        groupId: 'group-1',
        senderId: 'user-1',
        content: 'Mesaj',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        isFailed: false,
        isSending: true,
      );

      expect(msg.messageStatus, equals('sending'));
    });

    test('Her iki flag false ise status "sent" olmalı', () {
      final msg = GroupMessage(
        id: 'msg-1',
        groupId: 'group-1',
        senderId: 'user-1',
        content: 'Mesaj',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(msg.messageStatus, equals('sent'));
    });

    test('Öncelik: failed > sending > sent', () {
      // Her iki flag de true ise failed öncelikli
      final msg = GroupMessage(
        id: 'msg-1',
        groupId: 'group-1',
        senderId: 'user-1',
        content: 'Mesaj',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        isFailed: true,
        isSending: true,
      );

      expect(msg.messageStatus, equals('failed'));
    });
  });

  // ===========================================================================
  // 3. READ BY ALL (Tüm üyeler okudu mu?)
  // ===========================================================================
  group('👀 isReadByAll - Tüm Üyeler Okudu mu?', () {
    test('Tek kişilik grup - readByCount > 0 ise true', () {
      final msg = GroupMessage(
        id: 'msg-1',
        groupId: 'group-1',
        senderId: 'user-1',
        content: 'Mesaj',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        readByCount: 1,
      );

      expect(msg.isReadByAll(1), isTrue);
    });

    test('Çok üyeli grup - tüm üyeler okumuşsa true', () {
      // 5 kişilik grup, 4 kişi okumuş (gönderen hariç)
      final msg = GroupMessage(
        id: 'msg-1',
        groupId: 'group-1',
        senderId: 'user-1',
        content: 'Mesaj',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        readByCount: 4,
      );

      expect(msg.isReadByAll(5), isTrue);
    });

    test('Çok üyeli grup - bazıları okumamışsa false', () {
      // 5 kişilik grup, 3 kişi okumuş
      final msg = GroupMessage(
        id: 'msg-1',
        groupId: 'group-1',
        senderId: 'user-1',
        content: 'Mesaj',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        readByCount: 3,
      );

      expect(msg.isReadByAll(5), isFalse);
    });

    test('Hiç kimse okumamışsa false', () {
      final msg = GroupMessage(
        id: 'msg-1',
        groupId: 'group-1',
        senderId: 'user-1',
        content: 'Mesaj',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        readByCount: 0,
      );

      expect(msg.isReadByAll(5), isFalse);
    });
  });

  // ===========================================================================
  // 4. CREATE TEMP (Geçici mesaj oluşturma - gönderim öncesi)
  // ===========================================================================
  group('🆕 createTemp - Geçici Mesaj', () {
    test('Geçici mesaj oluşturulmalı ve isSending=true olmalı', () {
      final tempMsg = GroupMessage.createTemp(
        groupId: 'group-1',
        senderId: 'user-1',
        content: 'Yeni mesaj',
      );

      expect(tempMsg.id, startsWith('temp_'));
      expect(tempMsg.isSending, isTrue);
      expect(tempMsg.isFailed, isFalse);
      expect(tempMsg.messageStatus, equals('sending'));
      expect(tempMsg.content, equals('Yeni mesaj'));
    });

    test('Reply bilgisi ile geçici mesaj oluşturulabilmeli', () {
      final tempMsg = GroupMessage.createTemp(
        groupId: 'group-1',
        senderId: 'user-2',
        content: 'Katılıyorum',
        replyToId: 'msg-1',
        replyToContent: 'Ne düşünüyorsun?',
        replyToSenderName: 'Ahmet',
      );

      expect(tempMsg.replyToId, equals('msg-1'));
      expect(tempMsg.replyToContent, equals('Ne düşünüyorsun?'));
      expect(tempMsg.replyToSenderName, equals('Ahmet'));
    });
  });

  // ===========================================================================
  // 5. COPY WITH
  // ===========================================================================
  group('📋 copyWith', () {
    test('isSending false olmalı (mesaj gönderildikten sonra)', () {
      final original = GroupMessage(
        id: 'msg-1',
        groupId: 'group-1',
        senderId: 'user-1',
        content: 'Mesaj',
        createdAt: DateTime.parse('2026-08-01T10:00:00.000Z'),
        updatedAt: DateTime.parse('2026-08-01T10:00:00.000Z'),
        isSending: true,
      );

      final sent = original.copyWith(
        isSending: false,
        isFailed: false,
      );

      expect(sent.isSending, isFalse);
      expect(sent.isFailed, isFalse);
      expect(sent.messageStatus, equals('sent'));
    });

    test('Send hatası durumu (isFailed=true)', () {
      final original = GroupMessage(
        id: 'msg-1',
        groupId: 'group-1',
        senderId: 'user-1',
        content: 'Mesaj',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        isSending: true,
      );

      final failed = original.copyWith(
        isSending: false,
        isFailed: true,
      );

      expect(failed.messageStatus, equals('failed'));
    });
  });

  // ===========================================================================
  // 6. EDGE CASES
  // ===========================================================================
  group('🧪 Edge Cases', () {
    test('Çok uzun mesaj (10000 karakter) parse edilebilmeli', () {
      final longContent = 'a' * 10000;
      final map = {
        'id': 'msg-long',
        'group_id': 'group-1',
        'sender_id': 'user-1',
        'content': longContent,
        'created_at': '2026-08-01T10:00:00.000Z',
        'updated_at': '2026-08-01T10:00:00.000Z',
      };

      final msg = GroupMessage.fromMap(map);
      expect(msg.content.length, equals(10000));
    });

    test('Boş içerikli mesaj parse edilebilmeli (silinen mesaj)', () {
      final map = {
        'id': 'msg-deleted',
        'group_id': 'group-1',
        'sender_id': 'user-1',
        'content': '',
        'created_at': '2026-08-01T10:00:00.000Z',
        'updated_at': '2026-08-01T10:00:00.000Z',
      };

      final msg = GroupMessage.fromMap(map);
      expect(msg.content, equals(''));
    });

    test('Türkçe + Emoji içerik', () {
      final map = {
        'id': 'msg-tr',
        'group_id': 'group-1',
        'sender_id': 'user-1',
        'content': 'Selam! Nasılsınız? 🎉🇹🇷',
        'created_at': '2026-08-01T10:00:00.000Z',
        'updated_at': '2026-08-01T10:00:00.000Z',
      };

      final msg = GroupMessage.fromMap(map);
      expect(msg.content, contains('Nasılsınız'));
      expect(msg.content, contains('🎉'));
      expect(msg.content, contains('🇹🇷'));
    });

    test('Mention içeren mesaj (@username)', () {
      final map = {
        'id': 'msg-mention',
        'group_id': 'group-1',
        'sender_id': 'user-1',
        'content': 'Merhaba @ahmet, sen ne düşünüyorsun?',
        'created_at': '2026-08-01T10:00:00.000Z',
        'updated_at': '2026-08-01T10:00:00.000Z',
      };

      final msg = GroupMessage.fromMap(map);
      expect(msg.content, contains('@ahmet'));
    });
  });

  // ===========================================================================
  // 7. SONUÇ RAPORU
  // ===========================================================================
  tearDownAll(() {
    print('\n${'=' * 60}');
    print('👥 GROUP MESSAGE MODEL TEST SONUÇ RAPORU');
    print('=' * 60);
    print('✅ Grup mesajlaşma modeli test edildi');
    print('💡 Kapsam:');
    print('   - JSON parse (sender join, reply, read count)');
    print('   - Status: failed / sending / sent');
    print('   - isReadByAll hesaplaması');
    print('   - createTemp (geçici mesaj)');
    print('   - copyWith (gönderim sonrası güncelleme)');
    print('   - Edge cases (uzun, boş, mention, emoji)');
    print('=' * 60);
  });
}
