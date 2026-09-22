import 'package:cizreapp/core/models/seller_announcement_model.dart';
import 'package:cizreapp/core/services/seller_announcement_service.dart';
import 'package:cizreapp/features/seller/widgets/seller_announcements_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeService extends SellerAnnouncementService {
  _FakeService(this.items, {this.failDismiss = false});

  final List<SellerAnnouncement> items;
  final bool failDismiss;
  final dismissed = <String>[];
  final seen = <String>[];

  @override
  Future<List<SellerAnnouncement>> fetchMine() async => items;

  @override
  Future<void> markSeen(List<String> ids) async => seen.addAll(ids);

  @override
  Future<void> dismiss(String id) async {
    if (failDismiss) throw Exception('sunucu hatası');
    dismissed.add(id);
  }
}

SellerAnnouncement _a(
  String id,
  AnnouncementType type, {
  bool dismissible = true,
  bool isNew = false,
  String? label,
  AnnouncementTarget? target,
}) =>
    SellerAnnouncement(
      id: id,
      type: type,
      title: 'Başlık $id',
      message: 'Mesaj $id',
      isDismissible: dismissible,
      isNew: isNew,
      actionLabel: label,
      actionTarget: target,
    );

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  group('SellerAnnouncementsSection', () {
    testWidgets('kart yoksa hiç yer kaplamaz', (t) async {
      await t.pumpWidget(_host(SellerAnnouncementsSection(
        service: _FakeService(const []),
        onAction: (_) {},
      )));
      await t.pumpAndSettle();
      expect(find.text('Yönetimden duyurular'), findsNothing);
    });

    testWidgets('en fazla 2 kart açık, kalanı "+N duyuru daha" ile açılır',
        (t) async {
      final svc = _FakeService([
        _a('1', AnnouncementType.urgent, dismissible: false),
        _a('2', AnnouncementType.promo),
        _a('3', AnnouncementType.info),
        _a('4', AnnouncementType.ok),
      ]);
      await t.pumpWidget(
          _host(SellerAnnouncementsSection(service: svc, onAction: (_) {})));
      await t.pumpAndSettle();

      expect(find.text('Başlık 1'), findsOneWidget);
      expect(find.text('Başlık 2'), findsOneWidget);
      expect(find.text('Başlık 3'), findsNothing);
      expect(find.text('+2 duyuru daha'), findsOneWidget);

      await t.tap(find.text('+2 duyuru daha'));
      await t.pumpAndSettle();
      expect(find.text('Başlık 4'), findsOneWidget);
      expect(find.text('Daha az göster'), findsOneWidget);
    });

    testWidgets('acil kartın kapatma düğmesi yoktur, diğerlerinin vardır',
        (t) async {
      final svc = _FakeService([
        _a('1', AnnouncementType.urgent, dismissible: false),
        _a('2', AnnouncementType.info),
      ]);
      await t.pumpWidget(
          _host(SellerAnnouncementsSection(service: svc, onAction: (_) {})));
      await t.pumpAndSettle();
      // Yalnızca ikinci kartta "Kapat" düğmesi var.
      expect(find.byTooltip('Kapat'), findsOneWidget);
      expect(find.text('Önemli'), findsOneWidget);
    });

    testWidgets('kapatınca kart kalkar ve sunucuya yazılır', (t) async {
      final svc = _FakeService([_a('1', AnnouncementType.info)]);
      await t.pumpWidget(
          _host(SellerAnnouncementsSection(service: svc, onAction: (_) {})));
      await t.pumpAndSettle();

      await t.tap(find.byTooltip('Kapat'));
      await t.pumpAndSettle();

      expect(find.text('Başlık 1'), findsNothing);
      expect(svc.dismissed, ['1']);
    });

    testWidgets('kapatma başarısız olursa kart geri gelir', (t) async {
      final svc =
          _FakeService([_a('1', AnnouncementType.info)], failDismiss: true);
      await t.pumpWidget(
          _host(SellerAnnouncementsSection(service: svc, onAction: (_) {})));
      await t.pumpAndSettle();

      await t.tap(find.byTooltip('Kapat'));
      await t.pumpAndSettle();

      expect(find.text('Başlık 1'), findsOneWidget);
      expect(find.text('Duyuru kapatılamadı, tekrar deneyin'), findsOneWidget);
    });

    testWidgets('yeni kartlar görüldü işaretlenir', (t) async {
      final svc = _FakeService([
        _a('1', AnnouncementType.info, isNew: true),
        _a('2', AnnouncementType.info),
      ]);
      await t.pumpWidget(
          _host(SellerAnnouncementsSection(service: svc, onAction: (_) {})));
      await t.pumpAndSettle();
      expect(svc.seen, ['1']);
    });

    testWidgets('eylem butonu onAction çağırır', (t) async {
      SellerAnnouncement? tapped;
      final svc = _FakeService([
        _a('1', AnnouncementType.promo,
            label: 'Ürünlerim', target: AnnouncementTarget.products),
      ]);
      await t.pumpWidget(_host(SellerAnnouncementsSection(
        service: svc,
        onAction: (a) => tapped = a,
      )));
      await t.pumpAndSettle();

      await t.tap(find.text('Ürünlerim'));
      expect(tapped?.id, '1');
      expect(tapped?.actionTarget, AnnouncementTarget.products);
    });
  });

  group('SellerAnnouncement modeli', () {
    test('acil kart kapatılabilir kaydedilmez', () {
      const a = SellerAnnouncement(
        type: AnnouncementType.urgent,
        title: 'x',
        message: 'y',
        isDismissible: true,
      );
      expect(a.toDbPayload()['is_dismissible'], false);
    });

    test('eylem yoksa üç eylem alanı birlikte null olur', () {
      const a = SellerAnnouncement(title: 'x', message: 'y', actionLabel: '  ');
      final p = a.toDbPayload();
      expect(p['action_label'], isNull);
      expect(p['action_target'], isNull);
      expect(p['action_url'], isNull);
    });

    test('bağlantı yalnızca url hedefinde yazılır', () {
      const withUrl = SellerAnnouncement(
        title: 'x',
        message: 'y',
        actionLabel: 'Git',
        actionTarget: AnnouncementTarget.url,
        actionUrl: ' https://a.com ',
      );
      expect(withUrl.toDbPayload()['action_url'], 'https://a.com');

      const other = SellerAnnouncement(
        title: 'x',
        message: 'y',
        actionLabel: 'Git',
        actionTarget: AnnouncementTarget.shopSettings,
        actionUrl: 'https://a.com',
      );
      expect(other.toDbPayload()['action_target'], 'shop_settings');
      expect(other.toDbPayload()['action_url'], isNull);
    });

    test('mağaza listesi yalnızca "belirli mağazalar" hedefinde gider', () {
      const all = SellerAnnouncement(
        title: 'x',
        message: 'y',
        shopIds: ['a', 'b'],
      );
      expect(all.toDbPayload()['shop_ids'], isEmpty);

      const some = SellerAnnouncement(
        title: 'x',
        message: 'y',
        audience: AnnouncementAudience.shops,
        shopIds: ['a', 'b'],
      );
      expect(some.toDbPayload()['shop_ids'], ['a', 'b']);
    });

    test('yayın durumu tarihlere göre hesaplanır', () {
      final now = DateTime(2026, 9, 20, 12);
      SellerAnnouncement s({
        bool published = true,
        DateTime? start,
        DateTime? end,
      }) =>
          SellerAnnouncement(
            title: 'x',
            message: 'y',
            isPublished: published,
            startsAt: start,
            endsAt: end,
          );

      expect(s(published: false).statusAt(now), AnnouncementStatus.draft);
      expect(s(start: DateTime(2026, 9, 21)).statusAt(now),
          AnnouncementStatus.scheduled);
      expect(s(end: DateTime(2026, 9, 19)).statusAt(now),
          AnnouncementStatus.ended);
      expect(s(start: DateTime(2026, 9, 1), end: DateTime(2026, 9, 30))
              .statusAt(now),
          AnnouncementStatus.live);
    });

    test('sunucu satırı okunur, bilinmeyen anahtar güvenli varsayılana düşer',
        () {
      final a = SellerAnnouncement.fromJson({
        'id': 'i',
        'type': 'bilinmiyor',
        'title': 't',
        'message': 'm',
        'action_target': 'shop_settings',
        'action_label': 'Aç',
        'seen_count': 3,
      });
      expect(a.type, AnnouncementType.info);
      expect(a.actionTarget, AnnouncementTarget.shopSettings);
      expect(a.audience, AnnouncementAudience.all);
      expect(a.seenCount, 3);
      expect(a.hasAction, isTrue);
    });
  });
}
