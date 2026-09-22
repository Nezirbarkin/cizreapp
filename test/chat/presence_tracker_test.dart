import 'dart:async';

import 'package:cizreapp/features/chat/models/chat_presence.dart';
import 'package:cizreapp/features/chat/services/presence_tracker.dart';
import 'package:cizreapp/features/chat/services/user_presence_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Sunucuyu taklit eder: cevabı ve çağrı sayısını test belirler.
class _FakeService implements UserPresenceService {
  ChatPresenceSettings settings = const ChatPresenceSettings();
  UserPresence? next;
  int fetches = 0;
  PresenceContext? lastContext;

  @override
  Future<ChatPresenceSettings> loadSettings({bool force = false}) async => settings;

  @override
  Future<UserPresence?> fetchOne(
    String userId, {
    PresenceContext context = PresenceContext.chat,
  }) async {
    fetches++;
    lastContext = context;
    return next;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Canlı presence akışını taklit eder.
class _Live {
  final controller = StreamController<List<String>>.broadcast();
  final Set<String> online = {};

  void set(Iterable<String> ids) {
    online
      ..clear()
      ..addAll(ids);
    controller.add(online.toList());
  }
}

// 21 Eylül 2026 Pazartesi 15:00 Türkiye saati
final DateTime _now = DateTime.utc(2026, 9, 21, 12, 0);

PresenceTracker _tracker(
  _FakeService service,
  _Live live, {
  PresenceContext context = PresenceContext.chat,
  Duration refreshEvery = const Duration(seconds: 90),
  Duration settleDelay = const Duration(seconds: 2),
}) {
  return PresenceTracker(
    'peer',
    context: context,
    service: service,
    liveStream: live.controller.stream,
    liveIsOnline: live.online.contains,
    refreshEvery: refreshEvery,
    settleDelay: settleDelay,
    clock: () => _now,
  );
}

void main() {
  testWidgets('sunucu "çevrimiçi" derse etiket "çevrimiçi"', (tester) async {
    final service = _FakeService()
      ..next = const UserPresence(userId: 'peer', canSeeOnline: true, online: true);
    final tracker = _tracker(service, _Live());
    await tracker.start();
    expect(tracker.isOnline, isTrue);
    expect(tracker.label, 'çevrimiçi');
    expect(tracker.lastSeen, isNull, reason: 'çevrimiçiyken son görülme gösterilmez');
    tracker.dispose();
  });

  testWidgets('çevrimdışıysa son görülme etiketi', (tester) async {
    final service = _FakeService()
      ..next = UserPresence(
        userId: 'peer',
        canSeeOnline: true,
        lastSeen: DateTime.utc(2026, 9, 20, 18, 10), // dün 21:10 TR
      );
    final tracker = _tracker(service, _Live());
    await tracker.start();
    expect(tracker.isOnline, isFalse);
    expect(tracker.label, 'son görülme dün 21:10');
    tracker.dispose();
  });

  testWidgets('sunucu göremezsin derse (engel/hayalet/gizli) canlı akışta görünse de HİÇBİR ŞEY gösterilmez', (tester) async {
    final service = _FakeService()..next = const UserPresence.hidden('peer');
    final live = _Live()..online.add('peer');
    final tracker = _tracker(service, live);
    await tracker.start();
    expect(tracker.isOnline, isFalse);
    expect(tracker.label, isNull);
    live.set(['peer']); // akış yine "çevrimiçi" diyor
    await tester.pump();
    expect(tracker.label, isNull, reason: 'akış sunucunun kararını ezemez');
    tracker.dispose();
  });

  testWidgets('sunucu son görülmeyi gizlediyse (null) ama çevrimiçini serbest bırakmışsa yalnız çevrimiçi görünür', (tester) async {
    final service = _FakeService()
      ..next = const UserPresence(userId: 'peer', canSeeOnline: true, online: false);
    final live = _Live();
    final tracker = _tracker(service, live);
    await tracker.start();
    expect(tracker.label, isNull, reason: 'çevrimdışı ve son görülme yok');

    live.set(['peer']);
    await tester.pump();
    expect(tracker.label, 'çevrimiçi', reason: 'canlı akış, izin varsa çevrimiçi gösterir');
    tracker.dispose();
  });

  testWidgets('canlı akış çevrimiçi→çevrimdışı: rozet hemen düşer, sunucu 2 sn sonra yenilenir', (tester) async {
    final service = _FakeService()
      ..next = UserPresence(
        userId: 'peer',
        canSeeOnline: true,
        online: true,
        lastSeen: DateTime.utc(2026, 9, 21, 11, 59, 30),
      );
    final live = _Live()..online.add('peer');
    final tracker = _tracker(service, live);
    await tracker.start();
    expect(tracker.label, 'çevrimiçi');
    expect(service.fetches, 1);

    // Peer arka plana gitti; sunucu cevabı henüz "online=true" (bayat).
    live.set([]);
    await tester.pump();
    expect(tracker.isOnline, isFalse, reason: 'bayat sunucu cevabı çevrimiçi göstermeye devam etmez');
    expect(service.fetches, 1, reason: 'yenileme hemen değil, kısa bir gecikmeyle');

    // Sunucudaki son görülme güncellendi.
    service.next = UserPresence(
      userId: 'peer',
      canSeeOnline: true,
      lastSeen: DateTime.utc(2026, 9, 21, 11, 59, 58),
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(service.fetches, 2);
    expect(tracker.label, 'son görülme az önce');
    tracker.dispose();
  });

  testWidgets('kısa kopukluk: akış hızlıca geri gelirse "çevrimiçi" kalır', (tester) async {
    final service = _FakeService()
      ..next = const UserPresence(userId: 'peer', canSeeOnline: true, online: true);
    final live = _Live()..online.add('peer');
    final tracker = _tracker(service, live);
    await tracker.start();
    live.set([]);
    await tester.pump(const Duration(milliseconds: 300));
    live.set(['peer']);
    await tester.pump();
    expect(tracker.label, 'çevrimiçi');
    tracker.dispose();
  });

  testWidgets('başka kullanıcıların akış olayları yok sayılır (gereksiz yenileme yok)', (tester) async {
    final service = _FakeService()
      ..next = const UserPresence(userId: 'peer', canSeeOnline: true, online: true);
    final live = _Live()..online.add('peer');
    final tracker = _tracker(service, live);
    await tracker.start();
    var notified = 0;
    tracker.addListener(() => notified++);

    live.set(['peer', 'someone-else']);
    live.set(['peer', 'someone-else', 'third']);
    await tester.pump(const Duration(seconds: 5));
    expect(notified, 0, reason: 'peer durumu değişmedi');
    expect(service.fetches, 1);
    tracker.dispose();
  });

  testWidgets('periyodik yenileme aralıkla yeniden sorar; dispose sonrası durur', (tester) async {
    final service = _FakeService()
      ..next = const UserPresence(userId: 'peer', canSeeOnline: true, online: true);
    final tracker = _tracker(
      service,
      _Live(),
      refreshEvery: const Duration(seconds: 90),
    );
    await tracker.start();
    expect(service.fetches, 1);
    await tester.pump(const Duration(seconds: 91));
    expect(service.fetches, 2);
    await tester.pump(const Duration(seconds: 90));
    expect(service.fetches, 3);

    tracker.dispose();
    await tester.pump(const Duration(minutes: 10));
    expect(service.fetches, 3, reason: 'dispose sonrası ağ isteği yok');
  });

  testWidgets('göreli metin ağ isteği olmadan zamanla yenilenir', (tester) async {
    var clockNow = _now;
    final service = _FakeService()
      ..next = UserPresence(
        userId: 'peer',
        canSeeOnline: true,
        lastSeen: _now.subtract(const Duration(minutes: 1)),
      );
    final tracker = PresenceTracker(
      'peer',
      service: service,
      liveStream: const Stream<List<String>>.empty(),
      liveIsOnline: (_) => false,
      tickEvery: const Duration(seconds: 30),
      clock: () => clockNow,
    );
    await tracker.start();
    expect(tracker.label, 'son görülme 1 dk önce');
    var notified = 0;
    tracker.addListener(() => notified++);

    clockNow = _now.add(const Duration(minutes: 4));
    await tester.pump(const Duration(seconds: 31));
    expect(notified, greaterThan(0));
    expect(tracker.label, 'son görülme 5 dk önce');
    expect(service.fetches, 1, reason: 'yalnız yeniden çizim; sunucu sorulmadı');
    tracker.dispose();
  });

  testWidgets('yönetici bu bağlamda hiçbir durumu göstermiyorsa sunucuya SORULMAZ', (tester) async {
    final service = _FakeService()
      ..settings = const ChatPresenceSettings(online: false, lastSeen: false)
      ..next = const UserPresence(userId: 'peer', canSeeOnline: true, online: true);
    final tracker = _tracker(service, _Live());
    await tracker.start();
    expect(service.fetches, 0);
    expect(tracker.label, isNull);
    expect(tracker.isLoaded, isTrue);
    tracker.dispose();
  });

  testWidgets('yalnız profil bağlamı kapalıysa profilde sorulmaz, sohbette sorulur', (tester) async {
    final service = _FakeService()
      ..settings = const ChatPresenceSettings(online: false, lastSeenInProfile: false)
      ..next = UserPresence(userId: 'peer', canSeeOnline: true, lastSeen: _now);

    final profile = _tracker(service, _Live(), context: PresenceContext.profile);
    await profile.start();
    expect(service.fetches, 0);
    profile.dispose();

    final chat = _tracker(service, _Live(), context: PresenceContext.chat);
    await chat.start();
    expect(service.fetches, 1);
    expect(service.lastContext, PresenceContext.chat);
    chat.dispose();
  });

  testWidgets('bağlam sunucuya iletilir', (tester) async {
    final service = _FakeService()..next = UserPresence(userId: 'peer', canSeeOnline: true, lastSeen: _now);
    final tracker = _tracker(service, _Live(), context: PresenceContext.profile);
    await tracker.start();
    expect(service.lastContext, PresenceContext.profile);
    tracker.dispose();
  });

  testWidgets('sunucu cevap vermezse (hata) güvenli taraf: hiçbir şey gösterilmez; sonraki başarılı yenileme düzeltir', (tester) async {
    final service = _FakeService()..next = null;
    final tracker = _tracker(service, _Live());
    await tracker.start();
    expect(tracker.isLoaded, isTrue);
    expect(tracker.label, isNull);

    service.next = const UserPresence(userId: 'peer', canSeeOnline: true, online: true);
    await tracker.refresh();
    expect(tracker.label, 'çevrimiçi');

    // Sonradan bir hata gelirse son bilinen değer korunur (titreme yok).
    service.next = null;
    await tracker.refresh();
    expect(tracker.label, 'çevrimiçi');
    tracker.dispose();
  });

  testWidgets('start ikinci kez çağrılırsa tekrar kurmaz', (tester) async {
    final service = _FakeService()
      ..next = const UserPresence(userId: 'peer', canSeeOnline: true, online: true);
    final tracker = _tracker(service, _Live());
    await tracker.start();
    await tracker.start();
    expect(service.fetches, 1);
    tracker.dispose();
  });

  testWidgets('dispose start bitmeden çağrılırsa hata vermez', (tester) async {
    final service = _FakeService()
      ..next = const UserPresence(userId: 'peer', canSeeOnline: true, online: true);
    final tracker = _tracker(service, _Live());
    final starting = tracker.start();
    tracker.dispose();
    await starting;
    await tester.pump(const Duration(minutes: 5));
    expect(service.fetches, lessThanOrEqualTo(1));
  });
}
