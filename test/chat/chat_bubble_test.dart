import 'package:cizreapp/core/models/message_model.dart';
import 'package:cizreapp/features/chat/widgets/chat_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_fonts.dart';

/// Görev 2.3 — WhatsApp/Telegram tarzı sohbet balonları: gün ayraçları,
/// öbekleme, kuyruk, saat + okundu tikleri.
Message _msg(String sender, DateTime at, {String content = 'selam', String? sharedPostId}) =>
    Message(
      id: '${sender}_${at.microsecondsSinceEpoch}',
      conversationId: 'conv-1',
      senderId: sender,
      content: content,
      createdAt: at,
      updatedAt: at,
      sharedPostId: sharedPostId,
    );

void main() {
  setUpAll(loadTestFonts);

  group('ChatDayLabel (Türkiye saati)', () {
    // 27 Eylül 2026 Pazar, 12:00 Türkiye (09:00 UTC).
    final now = DateTime.utc(2026, 9, 27, 9);

    test('Bugün / Dün / gün adı / bu yıl / önceki yıl', () {
      expect(ChatDayLabel.format(DateTime.utc(2026, 9, 27, 6), now: now), 'Bugün');
      expect(ChatDayLabel.format(DateTime.utc(2026, 9, 26, 12), now: now), 'Dün');
      expect(ChatDayLabel.format(DateTime.utc(2026, 9, 24, 12), now: now), 'Perşembe');
      expect(ChatDayLabel.format(DateTime.utc(2026, 9, 1, 12), now: now), '1 Eylül');
      expect(ChatDayLabel.format(DateTime.utc(2025, 12, 31, 12), now: now), '31 Aralık 2025');
    });

    test('gece 00:00–03:00 arası Türkiye gününe sayılır (UTC gününe değil)', () {
      final lateNightTr = DateTime.utc(2026, 9, 26, 22, 30); // 27 Eylül 01:30 TR
      expect(ChatDayLabel.format(lateNightTr, now: now), 'Bugün');
      expect(ChatDayLabel.sameDay(lateNightTr, DateTime.utc(2026, 9, 27, 8)), isTrue);
      expect(ChatDayLabel.sameDay(lateNightTr, DateTime.utc(2026, 9, 26, 20)), isFalse);
    });

    test('mesaj saati Türkiye saatiyle SS:DD', () {
      expect(ChatDayLabel.time(DateTime.utc(2026, 9, 27, 9, 5)), '12:05');
      expect(ChatDayLabel.time(DateTime.utc(2026, 9, 26, 21, 7)), '00:07');
    });
  });

  group('ChatGrouping', () {
    final t = DateTime.utc(2026, 9, 27, 9);

    test('aynı kişi, 5 dk içinde → aynı öbek', () {
      expect(ChatGrouping.joins(_msg('a', t), _msg('a', t.add(const Duration(minutes: 4)))), isTrue);
    });

    test('farklı kişi, uzun ara, gün değişimi ya da paylaşım kartı → ayrı öbek', () {
      expect(ChatGrouping.joins(_msg('a', t), _msg('b', t)), isFalse);
      expect(ChatGrouping.joins(_msg('a', t), _msg('a', t.add(const Duration(minutes: 6)))), isFalse);
      final beforeMidnightTr = DateTime.utc(2026, 9, 26, 20, 58);
      final afterMidnightTr = DateTime.utc(2026, 9, 26, 21, 1);
      expect(ChatGrouping.joins(_msg('a', beforeMidnightTr), _msg('a', afterMidnightTr)), isFalse);
      expect(ChatGrouping.joins(_msg('a', t), _msg('a', t, sharedPostId: 'post-1')), isFalse);
    });
  });

  group('ChatBubbleShape', () {
    const rect = Rect.fromLTWH(0, 0, 100, 40);

    test('kuyruk gönderen tarafının alt köşesinden dışarı uzanır', () {
      final mineTail = const ChatBubbleShape(isMine: true, tail: true).getOuterPath(rect).getBounds();
      final mineNoTail = const ChatBubbleShape(isMine: true, tail: false).getOuterPath(rect).getBounds();
      expect(mineTail.right, closeTo(100, 0.01));
      expect(mineNoTail.right, closeTo(100 - ChatBubbleShape.tailWidth, 0.01));
      expect(mineTail.left, closeTo(0, 0.01));

      final theirsTail = const ChatBubbleShape(isMine: false, tail: true).getOuterPath(rect).getBounds();
      final theirsNoTail = const ChatBubbleShape(isMine: false, tail: false).getOuterPath(rect).getBounds();
      expect(theirsTail.left, closeTo(0, 0.01));
      expect(theirsNoTail.left, closeTo(ChatBubbleShape.tailWidth, 0.01));
      expect(theirsTail.right, closeTo(100, 0.01));
    });
  });

  group('ChatStatusTicks', () {
    Future<Icon> ticks(WidgetTester tester, String status) async {
      await tester.pumpWidget(
        MaterialApp(home: Center(child: ChatStatusTicks(status: status))),
      );
      return tester.widget<Icon>(find.byType(Icon));
    }

    testWidgets('saat = gönderiliyor, tek tik = gönderildi, mavi çift tik = okundu', (tester) async {
      expect((await ticks(tester, 'sending')).icon, Icons.schedule);
      expect((await ticks(tester, 'sent')).icon, Icons.done);
      final read = await ticks(tester, 'read');
      expect(read.icon, Icons.done_all);
      expect(read.color, ChatPalette.readTick);
      final failed = await ticks(tester, 'failed');
      expect(failed.icon, Icons.error_outline);
      expect(failed.color, ChatPalette.failed);
    });
  });

  group('ChatBubble', () {
    Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(padding: const EdgeInsets.all(16), child: child),
        ),
      ),
    );

    ChatBubbleShape shapeOf(WidgetTester tester) {
      final box = tester.widget<DecoratedBox>(
        find.descendant(of: find.byType(ChatBubble), matching: find.byType(DecoratedBox)).first,
      );
      return (box.decoration as ShapeDecoration).shape as ChatBubbleShape;
    }

    testWidgets('kendi mesajım: yazı, saat ve durum tiki; öbeğin sonuysa kuyruk', (tester) async {
      await pump(
        tester,
        const ChatBubble(text: 'Merhaba', time: '12:05', isMine: true, status: 'read'),
      );

      // Satır sonunda saat için ayrılan boşluk bir yer tutucudur (WidgetSpan).
      expect(find.textContaining('Merhaba', findRichText: true), findsOneWidget);
      expect(find.text('12:05'), findsOneWidget);
      expect(find.byIcon(Icons.done_all), findsOneWidget);
      final shape = shapeOf(tester);
      expect(shape.isMine, isTrue);
      expect(shape.tail, isTrue);
    });

    testWidgets('karşı tarafın mesajında tik yok; öbeğin ortasında kuyruk yok', (tester) async {
      await pump(
        tester,
        const ChatBubble(
          text: 'Nasılsın?',
          time: '12:06',
          isMine: false,
          joinsAbove: true,
          joinsBelow: true,
        ),
      );

      expect(find.byType(ChatStatusTicks), findsNothing);
      final shape = shapeOf(tester);
      expect(shape.isMine, isFalse);
      expect(shape.tail, isFalse);
      expect(shape.joinsAbove, isTrue);
    });

    testWidgets('kısa mesajda saat yazıyla AYNI satırda (balon tek satır)', (tester) async {
      await pump(tester, const ChatBubble(text: 'Tamam', time: '12:05', isMine: true, status: 'sent'));
      final short = tester.getSize(find.byType(DecoratedBox).first).height;

      await pump(
        tester,
        const ChatBubble(
          text: 'Bu mesaj epey uzun, birkaç satıra yayılıyor ve saat de en alttaki satırın sonunda duruyor.',
          time: '12:05',
          isMine: true,
          status: 'sent',
        ),
      );
      final long = tester.getSize(find.byType(DecoratedBox).first).height;

      expect(short, lessThan(44));
      expect(long, greaterThan(short + 15));
    });

    testWidgets('yanıt alıntısı balonun içinde', (tester) async {
      await pump(
        tester,
        const ChatBubble(
          text: 'Evet, geliyorum',
          time: '12:07',
          isMine: false,
          replySenderName: 'Ayşe',
          replyContent: 'Akşam geliyor musun?',
        ),
      );

      expect(find.byType(ChatReplyQuote), findsOneWidget);
      expect(find.text('Ayşe'), findsOneWidget);
      expect(find.text('Akşam geliyor musun?'), findsOneWidget);
    });

    testWidgets('gün hapı ve desenli zemin çizilir', (tester) async {
      await pump(
        tester,
        const SizedBox(
          height: 200,
          child: ChatWallpaper(child: ChatDayPill(label: 'Bugün')),
        ),
      );

      expect(find.text('Bugün'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
