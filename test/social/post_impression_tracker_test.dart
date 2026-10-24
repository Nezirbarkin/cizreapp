import 'package:cizreapp/features/social/services/post_impression_tracker.dart';
import 'package:cizreapp/features/social/widgets/impression_probe.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Akışta görülme sayacı: istemci toplar, günde bir kez ve toplu gönderir.
void main() {
  group('PostImpressionTracker', () {
    late List<List<String>> sent;
    late PostImpressionTracker tracker;

    setUp(() {
      sent = [];
      tracker = PostImpressionTracker(
        sender: (ids) async => sent.add(List.of(ids)),
        currentUserId: () => 'me',
        debounce: const Duration(seconds: 4),
        batchSize: 3,
      );
    });

    testWidgets('debounce sonunda tek istek; kendi gönderisi ve tekrar atlanır', (t) async {
      tracker.markSeen('a', authorId: 'x');
      tracker.markSeen('a', authorId: 'x');
      tracker.markSeen('own', authorId: 'me');
      tracker.markSeen('b', authorId: 'y');
      expect(sent, isEmpty);

      await t.pump(const Duration(seconds: 4));
      expect(sent, [
        ['a', 'b'],
      ]);

      // Aynı gün yeniden görülen gönderi bir daha gönderilmez.
      tracker.markSeen('a', authorId: 'x');
      await t.pump(const Duration(seconds: 5));
      expect(sent, hasLength(1));
    });

    testWidgets('parti dolunca beklemeden gönderir; flush kalanları yollar', (t) async {
      for (final id in ['1', '2', '3', '4']) {
        tracker.markSeen(id, authorId: 'x');
      }
      await t.pump();
      expect(sent.first, ['1', '2', '3']);
      await tracker.flush();
      expect(sent.last, ['4']);
      await t.pump(const Duration(seconds: 5));
      expect(sent, hasLength(2));
    });

    testWidgets('hata olursa sonraki görülmede yeniden denenir', (t) async {
      var fail = true;
      final flaky = PostImpressionTracker(
        sender: (ids) async {
          if (fail) throw Exception('ağ');
          sent.add(ids);
        },
        currentUserId: () => 'me',
      );
      flaky.markSeen('a', authorId: 'x');
      await flaky.flush();
      expect(sent, isEmpty);
      fail = false;
      flaky.markSeen('a', authorId: 'x');
      await flaky.flush();
      expect(sent, [
        ['a'],
      ]);
    });

    test('misafir ve kapalı izleyici kayıt tutmaz', () {
      final guest = PostImpressionTracker(sender: (_) async {}, currentUserId: () => null);
      guest.markSeen('a', authorId: 'x');
      expect(guest.pending, isEmpty);

      tracker.enabled = false;
      tracker.markSeen('a', authorId: 'x');
      expect(tracker.pending, isEmpty);
    });
  });

  group('ImpressionProbe', () {
    testWidgets('yalnız ekranda yarısı görünen öğeler sayılır; kaydırma bitince yenileri', (t) async {
      t.view.physicalSize = const Size(400, 600);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final seen = <String>[];

      await t.pumpWidget(
        MaterialApp(
          home: ListView.builder(
            itemCount: 20,
            itemBuilder: (_, i) => ImpressionProbe(
              id: 'p$i',
              onSeen: () => seen.add('p$i'),
              child: SizedBox(height: 250, child: Text('kart $i')),
            ),
          ),
        ),
      );
      await t.pump();
      // 600 px: p0 (0-250), p1 (250-500) tam; p2 (500-750) %40 → sayılmaz.
      expect(seen, ['p0', 'p1']);

      await t.drag(find.byType(ListView), const Offset(0, -500));
      await t.pumpAndSettle();
      expect(seen, containsAll(['p2', 'p3']));
      expect(seen.where((s) => s == 'p0'), hasLength(1));
    });

    testWidgets('arka plandaki sekmede (TickerMode kapalı) sayılmaz', (t) async {
      final seen = <String>[];
      await t.pumpWidget(
        MaterialApp(
          home: TickerMode(
            enabled: false,
            child: ListView(
              children: [
                ImpressionProbe(
                  id: 'p0',
                  onSeen: () => seen.add('p0'),
                  child: const SizedBox(height: 100),
                ),
              ],
            ),
          ),
        ),
      );
      await t.pump();
      expect(seen, isEmpty);
    });
  });
}
