import 'dart:io';

import 'package:cizreapp/core/models/admin_notification_model.dart';
import 'package:cizreapp/core/services/admin_notification_service.dart';
import 'package:cizreapp/features/admin/screens/admin_notification_composer_screen.dart';
import 'package:cizreapp/features/admin/widgets/admin_notification_widgets.dart';
import 'package:cizreapp/features/admin/widgets/notifications_content_v2.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Supabase'e dokunmayan sahte servis: liste sabit, yazmalar kaydedilir.
class _FakeService extends AdminNotificationService {
  _FakeService(this.items);

  List<AdminNotification> items;
  final List<Map<String, dynamic>> sent = [];
  final List<Map<String, dynamic>> updated = [];
  final List<String> deleted = [];
  final List<String> sentNow = [];

  @override
  Future<List<AdminNotification>> history({int limit = 300}) async =>
      List.of(items);

  @override
  Future<List<AdminNotificationRecipient>> recipients(
    String campaignId, {
    String? filter,
    int limit = 100,
    int offset = 0,
  }) async {
    final all = [
      const AdminNotificationRecipient(
        userId: 'u1',
        fullName: 'Ayşe Kaya',
        username: 'ayse',
        role: 'customer',
        isRead: true,
      ),
      const AdminNotificationRecipient(
        userId: 'u2',
        fullName: 'Mehmet Demir',
        username: 'mehmet',
        role: 'seller',
        isRead: false,
      ),
    ];
    return switch (filter) {
      'read' => all.where((r) => r.isRead).toList(),
      'unread' => all.where((r) => !r.isRead).toList(),
      _ => all,
    };
  }

  @override
  Future<int> audienceCount(
    AdminNotifAudience audience, {
    List<String> userIds = const [],
  }) async => switch (audience) {
    AdminNotifAudience.personal => userIds.length,
    AdminNotifAudience.sellers => 12,
    _ => 170,
  };

  @override
  Future<AdminNotifSendResult> send({
    required AdminNotifAudience audience,
    required String title,
    required String content,
    required String iconType,
    List<String> userIds = const [],
    DateTime? scheduledFor,
  }) async {
    sent.add({
      'audience': audience,
      'title': title,
      'content': content,
      'icon': iconType,
      'userIds': userIds,
      'scheduledFor': scheduledFor,
    });
    return AdminNotifSendResult(
      campaignId: 'new',
      isScheduled: scheduledFor != null,
      recipientCount: audience == AdminNotifAudience.personal
          ? userIds.length
          : 12,
      scheduledFor: scheduledFor,
    );
  }

  @override
  Future<void> update(
    String campaignId, {
    required String title,
    required String content,
    required String iconType,
    DateTime? scheduledFor,
    bool renotify = false,
  }) async {
    updated.add({
      'id': campaignId,
      'title': title,
      'content': content,
      'icon': iconType,
      'renotify': renotify,
    });
  }

  @override
  Future<int> delete(List<String> campaignIds) async {
    deleted.addAll(campaignIds);
    items = items.where((n) => !campaignIds.contains(n.id)).toList();
    return campaignIds.length;
  }

  @override
  Future<AdminNotifSendResult> sendNow(String campaignId) async {
    sentNow.add(campaignId);
    return AdminNotifSendResult(
      campaignId: campaignId,
      isScheduled: false,
      recipientCount: 170,
    );
  }

  @override
  Future<List<AdminNotifUser>> searchUsers(String query, {int limit = 30}) async =>
      const [
        AdminNotifUser(id: 'u1', fullName: 'Ayşe Kaya', username: 'ayse', role: 'customer'),
        AdminNotifUser(id: 'u2', fullName: 'Mehmet Demir', username: 'mehmet', role: 'seller'),
      ];
}

final _now = DateTime.now();

List<AdminNotification> _sample() => [
  AdminNotification(
    id: 'sch',
    title: 'Hafta sonu kampanyası',
    content: 'Cumartesi 20:00\'de başlayan kampanyayı kaçırmayın.',
    iconType: 'campaign',
    audience: AdminNotifAudience.customers,
    isScheduled: true,
    scheduledFor: _now.add(const Duration(hours: 3)),
    createdAt: _now,
    recipientCount: 0,
    readCount: 0,
    liveCount: 0,
    createdByName: 'Yönetici',
  ),
  AdminNotification(
    id: 'v1',
    title: 'Yeni sürüm yayında',
    content: 'CizreApp\'in yeni sürümü mağazalarda. Güncelleyerek yeni özellikleri hemen kullan.',
    iconType: 'update',
    audience: AdminNotifAudience.allUsers,
    isScheduled: false,
    sentAt: _now.subtract(const Duration(hours: 2)),
    recipientCount: 175,
    readCount: 42,
    liveCount: 175,
    createdByName: 'Yönetici',
  ),
  AdminNotification(
    id: 'v2',
    title: 'Satıcı komisyon güncellemesi',
    content: 'Eylül ayı komisyon oranları güncellendi.',
    iconType: 'discount',
    audience: AdminNotifAudience.sellers,
    isScheduled: false,
    sentAt: _now.subtract(const Duration(days: 1)),
    editedAt: _now.subtract(const Duration(hours: 20)),
    recipientCount: 12,
    readCount: 9,
    liveCount: 11,
    createdByName: 'Yönetici',
  ),
  AdminNotification(
    id: 'p1',
    title: 'Siparişiniz hakkında',
    content: 'Siparişiniz kuryeye teslim edildi.',
    iconType: 'info',
    audience: AdminNotifAudience.personal,
    isScheduled: false,
    sentAt: _now.subtract(const Duration(days: 3)),
    recipientCount: 1,
    readCount: 1,
    liveCount: 1,
    recipientNames: const ['Ayşe Kaya'],
    createdByName: 'Yönetici',
  ),
  AdminNotification(
    id: 'p2',
    title: 'Kurye toplantısı',
    content: 'Yarın 10:00\'da toplantı var.',
    iconType: 'event',
    audience: AdminNotifAudience.personal,
    isScheduled: false,
    sentAt: _now.subtract(const Duration(days: 10)),
    recipientCount: 5,
    readCount: 2,
    liveCount: 5,
    recipientNames: const ['Ali Veli', 'Mehmet Demir', 'Zeynep'],
    createdByName: 'Yönetici',
  ),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    // CachedNetworkImage (AdminAvatar) önbellek dizini için path_provider ister.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => Directory.systemTemp.path,
        );
  });

  void bigScreen(WidgetTester t, {Size size = const Size(800, 2200)}) {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = size;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
  }

  Future<void> openList(WidgetTester t, _FakeService svc) async {
    bigScreen(t);
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(body: NotificationsContentV2(service: svc)),
      ),
    );
    await t.pumpAndSettle();
  }

  Future<void> closeList(WidgetTester t) async {
    // Periyodik yenileme zamanlayıcısı dispose ile iptal olsun.
    await t.pumpWidget(const SizedBox());
  }

  /// Composer'ı bir rotada açar; kapanış sonucunu döndüren getter verir.
  Future<String? Function()> openComposer(
    WidgetTester t,
    _FakeService svc, {
    AdminNotifComposerMode mode = AdminNotifComposerMode.create,
    AdminNotification? source,
  }) async {
    bigScreen(t);
    String? result;
    var closed = false;
    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await Navigator.push<String>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AdminNotificationComposerScreen(
                      mode: mode,
                      source: source,
                      service: svc,
                    ),
                  ),
                );
                closed = true;
              },
              child: const Text('aç'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('aç'));
    await t.pumpAndSettle();
    return () => closed ? (result ?? '<null>') : null;
  }

  group('liste', () {
    testWidgets('istatistik, gruplar ve kartlar çizilir', (t) async {
      await openList(t, _FakeService(_sample()));

      expect(find.text('Bildirim merkezi'), findsOneWidget);
      expect(find.text('Yeni bildirim'), findsOneWidget);
      // Okunma oranı: (42+9+1+2) / (175+12+1+5) = %28 (zamanlanmış hariç).
      expect(find.text('%28'), findsOneWidget);

      for (final g in ['ZAMANLANMIŞ', 'BUGÜN', 'DÜN', 'BU HAFTA', 'DAHA ÖNCE']) {
        expect(find.text(g), findsOneWidget, reason: g);
      }
      expect(find.byType(AdminNotifCard), findsNWidgets(5));
      expect(find.text('Düzenlendi'), findsOneWidget);
      expect(find.text('Zamanlandı'), findsOneWidget);
      // Kişiye özel etiketi alıcı adını ve fazlalığı gösterir.
      expect(find.text('Ali Veli, Mehmet Demir +3 kişi'), findsOneWidget);
      await closeList(t);
    });

    testWidgets('filtre ve arama', (t) async {
      await openList(t, _FakeService(_sample()));

      await t.tap(find.textContaining('Kişiye özel ·'));
      await t.pumpAndSettle();
      expect(find.byType(AdminNotifCard), findsNWidgets(2));
      expect(find.text('Yeni sürüm yayında'), findsNothing);

      await t.tap(find.textContaining('Tümü ·'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField).first, 'komisyon');
      await t.pumpAndSettle();
      expect(find.byType(AdminNotifCard), findsOneWidget);
      expect(find.text('Satıcı komisyon güncellemesi'), findsOneWidget);

      await t.enterText(find.byType(TextField).first, 'yokböyleşey');
      await t.pumpAndSettle();
      expect(find.text('Bu filtreye uyan bildirim yok'), findsOneWidget);
      await closeList(t);
    });

    testWidgets('kart menüsünden silme onayla çalışır', (t) async {
      final svc = _FakeService(_sample());
      await openList(t, svc);

      final card = find.ancestor(
        of: find.text('Yeni sürüm yayında'),
        matching: find.byType(AdminNotifCard),
      );
      await t.tap(
        find.descendant(of: card, matching: find.byIcon(Icons.more_vert_rounded)),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Sil'));
      await t.pumpAndSettle();
      expect(find.text('Bildirim silinsin mi?'), findsOneWidget);

      // Vazgeç: hiçbir şey silinmez.
      await t.tap(find.text('Vazgeç'));
      await t.pumpAndSettle();
      expect(svc.deleted, isEmpty);

      await t.tap(
        find.descendant(of: card, matching: find.byIcon(Icons.more_vert_rounded)),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Sil'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, 'Sil'));
      await t.pumpAndSettle();

      expect(svc.deleted, ['v1']);
      expect(find.text('Yeni sürüm yayında'), findsNothing);
      expect(find.byType(AdminNotifCard), findsNWidgets(4));
      await closeList(t);
    });

    testWidgets('uzun basınca çoklu seçim ve toplu silme', (t) async {
      final svc = _FakeService(_sample());
      await openList(t, svc);

      await t.longPress(find.text('Yeni sürüm yayında'));
      await t.pumpAndSettle();
      expect(find.text('1 seçildi'), findsOneWidget);

      await t.tap(find.text('Satıcı komisyon güncellemesi'));
      await t.pumpAndSettle();
      expect(find.text('2 seçildi'), findsOneWidget);

      // Başlıktaki düğme FilledButton.icon (alt sınıf) olduğu için ikonuyla bulunur.
      await t.tap(find.byIcon(Icons.delete_outline_rounded));
      await t.pumpAndSettle();
      expect(find.text('2 bildirim silinsin mi?'), findsOneWidget);
      await t.tap(find.widgetWithText(FilledButton, 'Sil'));
      await t.pumpAndSettle();

      expect(svc.deleted.toSet(), {'v1', 'v2'});
      expect(find.byType(AdminNotifCard), findsNWidgets(3));
      expect(find.textContaining('seçildi'), findsNothing);
      await closeList(t);
    });

    testWidgets('zamanlanmışı şimdi gönder', (t) async {
      final svc = _FakeService(_sample());
      await openList(t, svc);

      final card = find.ancestor(
        of: find.text('Hafta sonu kampanyası'),
        matching: find.byType(AdminNotifCard),
      );
      await t.tap(
        find.descendant(of: card, matching: find.byIcon(Icons.more_vert_rounded)),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Şimdi gönder'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, 'Gönder'));
      await t.pumpAndSettle();

      expect(svc.sentNow, ['sch']);
      await closeList(t);
    });

    testWidgets('detay sayfası alıcıları listeler, Düzenle composer açar', (t) async {
      await openList(t, _FakeService(_sample()));

      await t.tap(find.text('Satıcı komisyon güncellemesi'));
      await t.pumpAndSettle();
      expect(find.text('Mesajın tamamı'), findsOneWidget);
      expect(find.text('Mehmet Demir'), findsOneWidget);
      expect(find.text('Okudu'), findsWidgets);
      expect(find.text('Okumadı'), findsWidgets);

      await t.tap(find.text('Düzenle'));
      await t.pumpAndSettle();
      expect(find.text('Bildirimi düzenle'), findsOneWidget);
      await t.pageBack();
      await t.pumpAndSettle();
      await closeList(t);
    });

    testWidgets('boş liste ilk bildirimi önerir', (t) async {
      await openList(t, _FakeService(const []));
      expect(find.text('İlk bildiriminizi gönderin'), findsOneWidget);
      await closeList(t);
    });
  });

  group('composer', () {
    testWidgets('toplu gönderim: onay sorar, doğru parametrelerle gönderir', (t) async {
      final svc = _FakeService(const []);
      final result = await openComposer(t, svc);

      await t.enterText(find.byType(TextField).at(0), 'Yeni komisyon');
      await t.enterText(find.byType(TextField).at(1), 'Komisyon oranları güncellendi.');
      await t.tap(find.text('Satıcılar'));
      await t.pumpAndSettle();
      expect(find.text('≈ 12 kişiye ulaşacak'), findsOneWidget);

      await t.tap(find.byIcon(Icons.send_rounded));
      await t.pumpAndSettle();
      expect(find.text('Bildirimi gönder?'), findsOneWidget);
      expect(svc.sent, isEmpty);

      await t.tap(find.text('Gönder').last);
      await t.pumpAndSettle();

      expect(svc.sent, hasLength(1));
      final s = svc.sent.single;
      expect(s['audience'], AdminNotifAudience.sellers);
      expect(s['title'], 'Yeni komisyon');
      expect(s['icon'], 'announcement');
      expect(s['scheduledFor'], isNull);
      expect(result(), '12 kişiye gönderildi');
    });

    testWidgets('şablon başlığı, mesajı ve ikonu doldurur', (t) async {
      final svc = _FakeService(const []);
      await openComposer(t, svc);

      await t.tap(find.text('Yeni sürüm'));
      await t.pumpAndSettle();

      final title = t.widget<TextField>(find.byType(TextField).at(0));
      expect(title.controller!.text, 'Yeni sürüm yayında');
      // Önizleme aynı metni gösterir.
      expect(find.text('Yeni sürüm yayında'), findsWidgets);
    });

    testWidgets('boş başlıkla gönderilemez', (t) async {
      final svc = _FakeService(const []);
      await openComposer(t, svc);

      await t.tap(find.byIcon(Icons.send_rounded));
      await t.pumpAndSettle();
      expect(find.text('Bildirim başlığını yazın.'), findsOneWidget);
      expect(svc.sent, isEmpty);
    });

    testWidgets('kişiye özel: alıcı seçmeden gönderilemez, seçince tek kişiye gider', (t) async {
      final svc = _FakeService(const []);
      final result = await openComposer(t, svc);

      await t.enterText(find.byType(TextField).at(0), 'Merhaba');
      await t.enterText(find.byType(TextField).at(1), 'Size özel bir mesaj.');
      await t.tap(find.text('Kişiye özel'));
      await t.pumpAndSettle();

      await t.tap(find.byIcon(Icons.send_rounded));
      await t.pumpAndSettle();
      expect(find.text('En az bir alıcı seçin.'), findsOneWidget);

      await t.tap(find.text('Ayşe Kaya'));
      await t.pumpAndSettle();
      expect(find.text('1 kişi seçildi'), findsOneWidget);

      await t.tap(find.byIcon(Icons.send_rounded));
      await t.pumpAndSettle();

      // Tek kişiye onay sorulmaz.
      expect(svc.sent, hasLength(1));
      expect(svc.sent.single['audience'], AdminNotifAudience.personal);
      expect(svc.sent.single['userIds'], ['u1']);
      expect(result(), '1 kişiye gönderildi');
    });

    testWidgets('zamanlı gönderim: gelecekteki zamanla çağrılır', (t) async {
      final svc = _FakeService(const []);
      final result = await openComposer(t, svc);

      await t.enterText(find.byType(TextField).at(0), 'Kampanya');
      await t.enterText(find.byType(TextField).at(1), 'Yarın başlıyor.');
      await t.tap(find.text('Zamanla'));
      await t.pumpAndSettle();
      await t.tap(find.text('1 saat sonra'));
      await t.pumpAndSettle();

      await t.tap(find.byIcon(Icons.schedule_send_rounded));
      await t.pumpAndSettle();
      expect(find.text('Bildirimi zamanla?'), findsOneWidget);
      await t.tap(find.text('Zamanla').last);
      await t.pumpAndSettle();

      final at = svc.sent.single['scheduledFor'] as DateTime;
      expect(at.isAfter(DateTime.now().add(const Duration(minutes: 50))), isTrue);
      expect(result(), startsWith('Zamanlandı: '));
    });

    testWidgets('düzenleme: alıcılar kilitli, yeniden bildir ile kaydeder', (t) async {
      final svc = _FakeService(_sample());
      final source = _sample()[1]; // gönderilmiş, herkes
      final result = await openComposer(
        t,
        svc,
        mode: AdminNotifComposerMode.edit,
        source: source,
      );

      expect(find.text('Bildirimi düzenle'), findsOneWidget);
      expect(find.textContaining('alıcıları değiştirilemez'), findsOneWidget);
      // Hedef kitle seçici yok.
      expect(find.text('Kime gidecek?'), findsNothing);

      await t.enterText(find.byType(TextField).at(0), 'Yeni sürüm hazır');
      await t.tap(find.byType(Switch));
      await t.pumpAndSettle();
      await t.tap(find.text('Kaydet'));
      await t.pumpAndSettle();

      expect(svc.updated, hasLength(1));
      expect(svc.updated.single['id'], 'v1');
      expect(svc.updated.single['title'], 'Yeni sürüm hazır');
      expect(svc.updated.single['renotify'], isTrue);
      expect(result(), 'Bildirim güncellendi ve yeniden gönderildi');
    });

    testWidgets('tekrar gönder: eski içerik ön dolu gelir', (t) async {
      final svc = _FakeService(_sample());
      await openComposer(
        t,
        svc,
        mode: AdminNotifComposerMode.duplicate,
        source: _sample()[2],
      );
      expect(find.text('Tekrar gönder'), findsOneWidget);
      final title = t.widget<TextField>(find.byType(TextField).at(0));
      expect(title.controller!.text, 'Satıcı komisyon güncellemesi');
    });
  });

  test('audienceLabel: kişiye özel etiketleri', () {
    AdminNotification p(List<String> names, int count) => AdminNotification(
      id: 'x',
      title: 't',
      content: 'c',
      iconType: 'info',
      audience: AdminNotifAudience.personal,
      isScheduled: false,
      recipientCount: count,
      readCount: 0,
      liveCount: count,
      recipientNames: names,
    );
    expect(p(['Ayşe'], 1).audienceLabel, 'Ayşe');
    expect(p(['Ayşe', 'Ali'], 2).audienceLabel, 'Ayşe, Ali');
    expect(p(['Ayşe', 'Ali', 'Veli'], 9).audienceLabel, 'Ayşe, Ali +7 kişi');
    expect(p(const [], 4).audienceLabel, '4 kişi');
    expect(p(const [], 0).audienceLabel, 'Kişiye özel');
  });
}
