import 'package:cizreapp/features/moderation/models/moderation_models.dart';
import 'package:cizreapp/features/moderation/screens/moderation_panel_screen.dart';
import 'package:cizreapp/features/moderation/services/moderation_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Görev 4.6 — Moderasyon Paneli: kapsam sekmeleri, şikayet/gönderi/ilan akışları.

final _now = DateTime.now();

class _FakeModeration extends ModerationService {
  final calls = <String>[];
  Object? failNext;

  List<ModReport> reportRows = [
    ModReport(
      kind: 'post',
      id: 'r1',
      status: 'pending',
      createdAt: _now.subtract(const Duration(minutes: 5)),
      reason: 'spam',
      description: 'Sürekli reklam',
      reporter: const ModPerson(id: 'u1', name: 'Ayşe'),
      postId: 'p1',
      postContent: 'Ucuz takipçi satılır!!!',
      postAuthorName: 'Mehmet',
    ),
    ModReport(
      kind: 'user',
      id: 'r2',
      status: 'reviewing',
      createdAt: _now.subtract(const Duration(hours: 2)),
      reason: 'harassment',
      reporter: const ModPerson(id: 'u2', name: 'Can'),
      targetUser: const ModPerson(id: 'u9', name: 'Kaba Kişi', username: 'kaba'),
    ),
  ];

  List<ModPost> postRows = [
    ModPost(
      id: 'p1',
      createdAt: _now.subtract(const Duration(minutes: 30)),
      content: 'Ucuz takipçi satılır!!!',
      openReports: 1,
      author: const ModPerson(id: 'a1', name: 'Mehmet', username: 'mehmet'),
    ),
  ];

  List<ModIlan> ilanRows = [
    ModIlan(
      id: 'i1',
      title: 'Satılık bisiklet',
      createdAt: _now.subtract(const Duration(days: 1)),
      price: 1250,
      city: 'Şırnak',
      district: 'Cizre',
      categoryName: 'Spor',
      paidFee: 10,
      owner: const ModPerson(id: 'o1', name: 'Veli'),
    ),
  ];

  void _maybeFail() {
    final error = failNext;
    if (error != null) {
      failNext = null;
      throw error;
    }
  }

  @override
  Future<ModReportsPage> reports({String status = 'open', int limit = 30, int offset = 0}) async {
    calls.add('reports:$status');
    final rows = status == 'open' ? reportRows.where((r) => r.isOpen).toList() : reportRows;
    return ModReportsPage(rows: rows, total: rows.length, open: reportRows.where((r) => r.isOpen).length);
  }

  @override
  Future<void> resolveReport(ModReport report, {required String status, String? response, bool hidePost = false}) async {
    calls.add('resolve:${report.id}:$status:${response ?? ''}:$hidePost');
    _maybeFail();
    reportRows = [
      for (final r in reportRows)
        r.id == report.id
            ? ModReport(kind: r.kind, id: r.id, status: status, createdAt: r.createdAt, reason: r.reason)
            : r,
    ];
  }

  @override
  Future<ModPostsPage> posts({String filter = 'recent', String? search, int limit = 30, int offset = 0}) async {
    calls.add('posts:$filter:${search?.trim() ?? ''}');
    final rows = filter == 'hidden' ? postRows.where((p) => !p.isActive).toList() : postRows;
    return ModPostsPage(rows: rows, total: rows.length);
  }

  @override
  Future<bool> setPostActive(String postId, bool active, {String? reason}) async {
    calls.add('post:$postId:$active:${reason ?? ''}');
    _maybeFail();
    postRows = [for (final p in postRows) p.id == postId ? p.copyWith(isActive: active) : p];
    return true;
  }

  @override
  Future<ModIlansPage> pendingIlanlar({int limit = 30, int offset = 0}) async {
    calls.add('ilanlar');
    return ModIlansPage(rows: ilanRows, total: ilanRows.length);
  }

  @override
  Future<void> reviewIlan(String ilanId, {required bool approve, String? reason}) async {
    calls.add('ilan:$ilanId:$approve:${reason ?? ''}');
    _maybeFail();
    ilanRows = [for (final i in ilanRows) if (i.id != ilanId) i];
  }
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<_FakeModeration> _pump(
  WidgetTester tester, {
  Set<ModerationScope> scopes = const {ModerationScope.reports, ModerationScope.content, ModerationScope.ilanlar},
  ModerationAccess? access,
  Size size = const Size(700, 1400),
  double textScale = 1,
}) async {
  final fake = _FakeModeration();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: ModerationPanelScreen(
        service: fake,
        access: access ?? ModerationAccess(scopes: scopes),
        liveTabBuilder: (_) => const Center(child: Text('CANLI SEKME')),
      ),
    ),
  );
  await _settle(tester);
  return fake;
}

Future<void> _openTab(WidgetTester tester, String label) async {
  await tester.tap(find.descendant(of: find.byType(TabBar), matching: find.text(label)));
  await _settle(tester);
}

void main() {
  testWidgets('yalnız yetkili alanların sekmeleri; yetki yoksa açıklama', (tester) async {
    await _pump(tester, scopes: {ModerationScope.ilanlar, ModerationScope.live});
    expect(find.widgetWithText(Tab, 'İlanlar'), findsOneWidget);
    expect(find.widgetWithText(Tab, 'Canlı yayınlar'), findsOneWidget);
    expect(find.widgetWithText(Tab, 'Şikayetler'), findsNothing);
    await _openTab(tester, 'Canlı yayınlar');
    expect(find.text('CANLI SEKME'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await _pump(tester, scopes: const {});
    expect(find.text('Moderatör yetkin yok'), findsOneWidget);
  });

  testWidgets('kategori sınırı: ilgili sekmenin üstünde yetkili kategoriler yazar', (tester) async {
    await _pump(
      tester,
      access: const ModerationAccess(
        scopes: {ModerationScope.reports, ModerationScope.ilanlar, ModerationScope.live},
        ilanCategories: [ModCategory(id: 'c1', name: 'Emlak'), ModCategory(id: 'c2', name: 'Vasıta')],
        shopCategories: [],
      ),
    );
    expect(find.byKey(const ValueKey('mod-categories-reports')), findsNothing, reason: 'şikayetler kategorisiz');

    await _openTab(tester, 'İlanlar');
    expect(find.text('Yalnız şu ilan kategorileri: Emlak, Vasıta'), findsOneWidget);
    expect(find.text('Satılık bisiklet'), findsOneWidget, reason: 'liste sunucuda süzülür, sekme yine çalışır');

    await _openTab(tester, 'Canlı yayınlar');
    expect(find.text('Sana atanmış mağaza kategorisi kalmadı; yönetimle iletişime geç.'), findsOneWidget);
    expect(find.text('CANLI SEKME'), findsOneWidget);
  });

  testWidgets('Şikayetler: sonuçlandır + gönderiyi gizle; incelemeye al; reddet', (tester) async {
    final fake = await _pump(tester);

    expect(fake.calls.first, 'reports:open');
    expect(find.text('Açık · 2'), findsOneWidget);
    expect(find.text('Ucuz takipçi satılır!!!'), findsOneWidget);
    expect(find.text('Kaba Kişi · @kaba'), findsOneWidget);

    // Gönderi şikayeti: sonuçlandır (gizle kutusu varsayılan işaretli)
    await tester.tap(find.widgetWithText(FilledButton, 'Sonuçlandır').first);
    await _settle(tester);
    expect(find.text('Şikayet sonuçlandırılsın mı?'), findsOneWidget);
    expect(tester.widget<CheckboxListTile>(find.byKey(const ValueKey('mod-note-checkbox'))).value, isTrue);
    await tester.enterText(find.byKey(const ValueKey('mod-note')), 'Spam içerik');
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.widgetWithText(FilledButton, 'Sonuçlandır')));
    await _settle(tester);
    expect(fake.calls, contains('resolve:r1:resolved:Spam içerik:true'));
    expect(find.text('Sonuçlandırıldı ve gönderi gizlendi'), findsOneWidget);

    // Kullanıcı şikayeti (inceleniyor): reddet — gizle seçeneği yok
    await tester.tap(find.widgetWithText(OutlinedButton, 'Reddet').first);
    await _settle(tester);
    expect(find.byKey(const ValueKey('mod-note-checkbox')), findsNothing);
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.widgetWithText(FilledButton, 'Reddet')));
    await _settle(tester);
    expect(fake.calls, contains('resolve:r2:rejected::false'));
    expect(find.text('Bekleyen şikayet yok'), findsOneWidget);
  });

  testWidgets('Şikayetler: İçerik yetkisi yoksa gizleme seçeneği gösterilmez', (tester) async {
    final fake = await _pump(tester, scopes: {ModerationScope.reports});
    await tester.tap(find.text('İncelemeye al').first);
    await _settle(tester);
    expect(fake.calls, contains('resolve:r1:reviewing::false'));
    await tester.tap(find.widgetWithText(FilledButton, 'Sonuçlandır').first);
    await _settle(tester);
    expect(find.byKey(const ValueKey('mod-note-checkbox')), findsNothing);
  });

  testWidgets('İçerik: gizle (nedenli) ve süzgeç', (tester) async {
    final fake = await _pump(tester);
    await _openTab(tester, 'İçerik');

    expect(fake.calls, contains('posts:recent:'));
    expect(find.text('1 açık şikayet'), findsOneWidget);
    await tester.tap(find.text('Gizle'));
    await _settle(tester);
    expect(find.text('Gönderi gizlensin mi?'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('mod-note')), 'Reklam');
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.widgetWithText(FilledButton, 'Gizle')));
    await _settle(tester);
    expect(fake.calls, contains('post:p1:false:Reklam'));
    expect(find.text('Geri aç'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('mod-filter-hidden')));
    await _settle(tester);
    expect(fake.calls, contains('posts:hidden:'));
    await tester.tap(find.text('Geri aç'));
    await _settle(tester);
    expect(fake.calls, contains('post:p1:true:'));
    expect(find.text('Gönderi yeniden yayında'), findsOneWidget);
  });

  testWidgets('İlanlar: ret nedeni zorunlu; onay onaylı', (tester) async {
    final fake = await _pump(tester);
    await _openTab(tester, 'İlanlar');

    expect(find.text('Satılık bisiklet'), findsOneWidget);
    expect(find.text('Cizre, Şırnak'), findsOneWidget);
    expect(find.text('Ücret ödendi: ₺10'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Reddet'));
    await _settle(tester);
    expect(find.textContaining('bakiyesine iade edilir'), findsOneWidget);
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.widgetWithText(FilledButton, 'Reddet')));
    await _settle(tester);
    expect(find.text('Bu alan gerekli'), findsOneWidget);
    expect(fake.calls.where((c) => c.startsWith('ilan:')), isEmpty);
    await tester.tap(find.text('Vazgeç'));
    await _settle(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Onayla'));
    await _settle(tester);
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.widgetWithText(FilledButton, 'Onayla')));
    await _settle(tester);
    expect(fake.calls, contains('ilan:i1:true:'));
    expect(find.text('İlan yayına alındı'), findsOneWidget);
    expect(find.text('Onay bekleyen ilan yok'), findsOneWidget);
  });

  testWidgets('sunucu hatası anlaşılır gösterilir', (tester) async {
    final fake = await _pump(tester);
    fake.failNext = const PostgrestException(message: 'x', hint: 'MOD_REPORT_NOT_FOUND');
    await tester.tap(find.text('İncelemeye al').first);
    await _settle(tester);
    expect(find.text('Şikayet bulunamadı (silinmiş olabilir).'), findsOneWidget);
  });

  testWidgets('dar ekran + büyük yazı: sekmeler taşmaz', (tester) async {
    await _pump(tester, size: const Size(320, 640), textScale: 1.6);
    expect(tester.takeException(), isNull);
    for (final tab in ['İçerik', 'İlanlar']) {
      await tester.drag(find.byType(TabBar), const Offset(-150, 0));
      await tester.pump();
      await _openTab(tester, tab);
      expect(tester.takeException(), isNull, reason: tab);
    }
  });
}
