import 'package:cizreapp/core/models/message_model.dart';
import 'package:flutter_test/flutter_test.dart';

/// Görev 3.1 — mesaj türü (text / image / location) ve ek verinin
/// ayrıştırılması. `content` her türde önizleme metnidir.
void main() {
  Map<String, dynamic> row({Object? type, Object? attachment, String content = 'x'}) => {
    'id': 'm1',
    'conversation_id': 'c1',
    'sender_id': 'u1',
    'content': content,
    'is_read': false,
    'created_at': '2026-09-28T10:00:00Z',
    'updated_at': '2026-09-28T10:00:00Z',
    'message_type': type,
    'attachment': attachment,
  };

  test('eski satır (tür sütunu yok) metin mesajıdır', () {
    final m = Message.fromMap(row()..remove('message_type')..remove('attachment'));
    expect(m.messageType, MessageType.text);
    expect(m.attachment, isNull);
    expect(m.isImage, isFalse);
    expect(m.isLocation, isFalse);
  });

  test('fotoğraf: yol, boyut, oran ve açıklama', () {
    final m = Message.fromMap(row(
      type: 'image',
      content: '📷 Akşam',
      attachment: {'path': 'a/b/c.jpg', 'w': 1080, 'h': 1440, 'caption': '  Akşam  '},
    ));
    expect(m.messageType, MessageType.image);
    expect(m.isImage, isTrue);
    expect(m.imagePath, 'a/b/c.jpg');
    expect((m.imageWidth, m.imageHeight), (1080, 1440));
    expect(m.imageAspectRatio, 0.75);
    expect(m.imageCaption, 'Akşam');
    expect(m.content, '📷 Akşam');
  });

  test('fotoğrafta ölçü yoksa oran null; boş açıklama null', () {
    final m = Message.fromMap(row(type: 'image', attachment: {'path': 'a/b/c.jpg', 'caption': '   '}));
    expect(m.imageAspectRatio, isNull);
    expect(m.imageCaption, isNull);
  });

  test('konum: enlem, boylam, adres (sayılar int de gelebilir)', () {
    final m = Message.fromMap(row(
      type: 'location',
      attachment: {'lat': 37.3256, 'lng': 42, 'label': 'Ali Bey, Cizre'},
    ));
    expect(m.isLocation, isTrue);
    expect(m.latitude, 37.3256);
    expect(m.longitude, 42.0);
    expect(m.locationLabel, 'Ali Bey, Cizre');
  });

  test('realtime yükünde jsonb metin olarak gelse de ayrıştırılır', () {
    final m = Message.fromMap(row(type: 'location', attachment: '{"lat":1.5,"lng":2.5}'));
    expect((m.latitude, m.longitude), (1.5, 2.5));
    expect(Message.fromMap(row(type: 'image', attachment: 'bozuk{')).attachment, isNull);
  });

  test('eksik ek verili tür gösterilemez; tanınmayan tür metne düşer', () {
    expect(Message.fromMap(row(type: 'image', attachment: {'w': 10})).isImage, isFalse);
    expect(Message.fromMap(row(type: 'location', attachment: {'lat': 1})).isLocation, isFalse);
    final future = Message.fromMap(row(type: 'sticker', content: '🎉 Çıkartma'));
    expect(future.messageType, MessageType.text);
    expect(future.content, '🎉 Çıkartma');
  });

  test('copyWith türü ve eki korur; geçici mesaj türüyle "gönderiliyor"', () {
    final m = Message.fromMap(row(type: 'image', attachment: {'path': 'a/b/c.jpg'}));
    final read = m.copyWith(isRead: true);
    expect(read.messageType, MessageType.image);
    expect(read.imagePath, 'a/b/c.jpg');

    final temp = Message.createTemp(
      conversationId: 'c1',
      senderId: 'u1',
      content: '📍 Konum',
      messageType: MessageType.location,
      attachment: {'lat': 1, 'lng': 2},
      replyToContent: 'selam',
    );
    expect(temp.id, startsWith('temp_'));
    expect(temp.messageStatus, 'sending');
    expect(temp.isLocation, isTrue);
    expect(temp.replyToContent, 'selam');
    expect(temp.createdAt.isUtc, isTrue);
  });

  test('MessageType veritabanı değerleri', () {
    expect(MessageType.values.map((t) => t.dbValue), ['text', 'image', 'location']);
    expect(MessageType.fromDb('image'), MessageType.image);
    expect(MessageType.fromDb(null), MessageType.text);
  });
}
