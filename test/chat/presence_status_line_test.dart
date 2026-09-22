import 'dart:async';

import 'package:cizreapp/features/chat/models/chat_presence.dart';
import 'package:cizreapp/features/chat/services/presence_tracker.dart';
import 'package:cizreapp/features/chat/services/user_presence_service.dart';
import 'package:cizreapp/features/chat/widgets/presence_status_line.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeService implements UserPresenceService {
  UserPresence? next;

  @override
  Future<ChatPresenceSettings> loadSettings({bool force = false}) async =>
      const ChatPresenceSettings();

  @override
  Future<UserPresence?> fetchOne(
    String userId, {
    PresenceContext context = PresenceContext.chat,
  }) async => next;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final DateTime _now = DateTime.utc(2026, 9, 21, 12, 0);

/// Bir durum değişikliğinin animasyonu, değişikliğin İLK karesinde %0'dadır ve
/// giden çocuk geçiş bitince BİR SONRAKİ karede kaldırılır: bu yüzden üç adım —
/// kareyi kur, süreyi ilerlet, kaldırmayı işle.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pump();
}

Future<PresenceTracker> _tracker(_FakeService service, {StreamController<List<String>>? live}) async {
  final tracker = PresenceTracker(
    'peer',
    service: service,
    liveStream: (live ?? StreamController<List<String>>.broadcast()).stream,
    liveIsOnline: (_) => false,
    clock: () => _now,
  );
  await tracker.start();
  return tracker;
}

Widget _host(Widget child, {Color background = const Color(0xFF6D28D9)}) {
  return MaterialApp(
    home: Scaffold(
      backgroundColor: background,
      body: Center(child: child),
    ),
  );
}

void main() {
  testWidgets('çevrimiçi: nokta + "çevrimiçi"', (tester) async {
    final tracker = await _tracker(
      _FakeService()..next = const UserPresence(userId: 'peer', canSeeOnline: true, online: true),
    );
    await tester.pumpWidget(
      _host(PresenceStatusLine(userId: 'peer', tracker: tracker)),
    );
    await _settle(tester);
    expect(find.text('çevrimiçi'), findsOneWidget);
    tracker.dispose();
  });

  testWidgets('çevrimdışı: "son görülme …"; saat simgesi isteğe bağlı', (tester) async {
    final tracker = await _tracker(
      _FakeService()
        ..next = UserPresence(
          userId: 'peer',
          canSeeOnline: true,
          lastSeen: DateTime.utc(2026, 9, 20, 18, 10),
        ),
    );
    await tester.pumpWidget(
      _host(PresenceStatusLine(userId: 'peer', tracker: tracker)),
    );
    await _settle(tester);
    expect(find.text('son görülme dün 21:10'), findsOneWidget);
    expect(find.byIcon(Icons.schedule_rounded), findsNothing);

    await tester.pumpWidget(
      _host(
        PresenceStatusLine(userId: 'peer', tracker: tracker, showClockIcon: true),
      ),
    );
    await _settle(tester);
    expect(find.byIcon(Icons.schedule_rounded), findsOneWidget);
    tracker.dispose();
  });

  testWidgets('gösterilecek bir şey yoksa hiçbir metin ve yer kaplamaz', (tester) async {
    final tracker = await _tracker(_FakeService()..next = const UserPresence.hidden('peer'));
    await tester.pumpWidget(
      _host(PresenceStatusLine(userId: 'peer', tracker: tracker)),
    );
    await _settle(tester);
    expect(find.byType(Text), findsNothing);
    final size = tester.getSize(find.byType(PresenceStatusLine));
    expect(size.height, 0);
    tracker.dispose();
  });

  testWidgets('yazıyor: diğer her şeyin önüne geçer ve bitince geri döner', (tester) async {
    final tracker = await _tracker(
      _FakeService()..next = const UserPresence(userId: 'peer', canSeeOnline: true, online: true),
    );
    final typing = ValueNotifier<bool>(false);
    await tester.pumpWidget(
      _host(PresenceStatusLine(userId: 'peer', tracker: tracker, typing: typing)),
    );
    await _settle(tester);
    expect(find.text('çevrimiçi'), findsOneWidget);
    expect(find.text('yazıyor'), findsNothing);

    typing.value = true;
    await _settle(tester);
    expect(find.text('yazıyor'), findsOneWidget);
    expect(find.text('çevrimiçi'), findsNothing);

    typing.value = false;
    await _settle(tester);
    expect(find.text('çevrimiçi'), findsOneWidget);
    expect(find.text('yazıyor'), findsNothing);

    // yazıyor animasyonu dispose'da zamanlayıcı sızdırmamalı
    typing.value = true;
    await _settle(tester);
    await tester.pumpWidget(const SizedBox());
    tracker.dispose();
    typing.dispose();
  });

  testWidgets('yazıyor, sunucu hiçbir durum göstermese bile görünür (yazıyor ayrı özellik)', (tester) async {
    final tracker = await _tracker(_FakeService()..next = const UserPresence.hidden('peer'));
    final typing = ValueNotifier<bool>(true);
    await tester.pumpWidget(
      _host(PresenceStatusLine(userId: 'peer', tracker: tracker, typing: typing)),
    );
    await _settle(tester);
    expect(find.text('yazıyor'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    tracker.dispose();
    typing.dispose();
  });

  testWidgets('tracker değişince (yeni sohbet) yeni tracker kullanılır', (tester) async {
    final first = await _tracker(
      _FakeService()..next = const UserPresence(userId: 'peer', canSeeOnline: true, online: true),
    );
    final second = await _tracker(
      _FakeService()
        ..next = UserPresence(
          userId: 'peer',
          canSeeOnline: true,
          lastSeen: DateTime.utc(2026, 9, 21, 11, 30),
        ),
    );
    await tester.pumpWidget(_host(PresenceStatusLine(userId: 'peer', tracker: first)));
    await _settle(tester);
    expect(find.text('çevrimiçi'), findsOneWidget);

    await tester.pumpWidget(_host(PresenceStatusLine(userId: 'peer', tracker: second)));
    await _settle(tester);
    expect(find.text('son görülme 30 dk önce'), findsOneWidget);
    expect(find.text('çevrimiçi'), findsNothing);
    first.dispose();
    second.dispose();
  });

  testWidgets('açık zeminde (profil) ve koyu zeminde (başlık) okunaklı renkler', (tester) async {
    final tracker = await _tracker(
      _FakeService()..next = const UserPresence(userId: 'peer', canSeeOnline: true, online: true),
    );

    Color? textColor() =>
        tester.widget<Text>(find.text('çevrimiçi')).style?.color;

    await tester.pumpWidget(
      _host(PresenceStatusLine(userId: 'peer', tracker: tracker)),
    );
    await _settle(tester);
    final onDark = textColor()!;
    expect(onDark.computeLuminance(), greaterThan(0.6), reason: 'koyu zeminde açık renk');

    await tester.pumpWidget(
      _host(
        PresenceStatusLine(
          userId: 'peer',
          tracker: tracker,
          style: PresenceLineStyle.onLight,
        ),
        background: Colors.white,
      ),
    );
    await _settle(tester);
    final onLight = textColor()!;
    expect(onLight.computeLuminance(), lessThan(0.4), reason: 'beyaz zeminde koyu renk');
    tracker.dispose();
  });

  testWidgets('uzun metin taşmaz (dar başlıkta üç nokta)', (tester) async {
    final tracker = await _tracker(
      _FakeService()
        ..next = UserPresence(
          userId: 'peer',
          canSeeOnline: true,
          lastSeen: DateTime.utc(2026, 9, 19, 9, 0), // Cumartesi 12:00
        ),
    );
    await tester.pumpWidget(
      _host(SizedBox(width: 60, child: PresenceStatusLine(userId: 'peer', tracker: tracker))),
    );
    await _settle(tester);
    expect(tester.takeException(), isNull);
    tracker.dispose();
  });
}
