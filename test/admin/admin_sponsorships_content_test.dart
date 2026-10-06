import 'package:cizreapp/core/models/sponsorship_model.dart';
import 'package:cizreapp/features/admin/services/admin_sponsorship_service.dart';
import 'package:cizreapp/features/admin/widgets/admin_sponsorships_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Görev 4.2 — Admin > Öne Çıkarma ekranı: başvuru onay/ret, yayındakini
/// iptal, paket yönetimi ve iki genel anahtar.

String _iso(DateTime value) => value.toUtc().toIso8601String();

Map<String, dynamic> _row(
  String id, {
  required String shop,
  String placement = 'shop_list',
  String status = 'pending',
  double price = 30,
  int days = 1,
  String package = 'Günlük',
  String? product,
  DateTime? starts,
  DateTime? ends,
  bool running = false,
  bool queued = false,
  String? note,
}) => {
  'id': id,
  'shop_id': 'shop-$id',
  'shop_name': shop,
  'product_id': product == null ? null : 'product-$id',
  'product_name': product,
  'placement': placement,
  'package_name': package,
  'duration_days': days,
  'price_paid': price,
  'status': status,
  'starts_at': starts == null ? null : _iso(starts),
  'ends_at': ends == null ? null : _iso(ends),
  'created_at': _iso(DateTime.now().subtract(const Duration(minutes: 5))),
  'created_by_name': 'Ayşe Yılmaz',
  'reviewed_at': status == 'pending' ? null : _iso(DateTime.now()),
  'review_note': note,
  'is_running': running,
  'is_queued': queued,
};

class _FakeSponsorshipService extends AdminSponsorshipService {
  _FakeSponsorshipService() {
    final now = DateTime.now();
    pending.addAll([
      _row('p1', shop: 'Cizre Kebap'),
      _row(
        'p2',
        shop: 'Dicle Market',
        placement: 'product_discount',
        product: 'Çay 1 kg',
        price: 15,
      ),
    ]);
    active.addAll([
      _row(
        'a1',
        shop: 'Botan Pide',
        status: 'active',
        price: 150,
        days: 7,
        package: 'Haftalık',
        starts: now.subtract(const Duration(days: 2)),
        ends: now.add(const Duration(days: 5)),
        running: true,
      ),
      _row(
        'a2',
        shop: 'Botan Pide',
        status: 'active',
        price: 150,
        days: 7,
        package: 'Haftalık',
        starts: now.add(const Duration(days: 5)),
        ends: now.add(const Duration(days: 12)),
        queued: true,
      ),
    ]);
    history.add(_row('h1', shop: 'Eski Dükkan', status: 'rejected', note: 'Görsel uygun değil'));
  }

  final calls = <String>[];
  final pending = <Map<String, dynamic>>[];
  final active = <Map<String, dynamic>>[];
  final history = <Map<String, dynamic>>[];
  bool enabled = true;
  bool requiresApproval = true;
  int failFetches = 0;
  Object? failNext;

  List<AdminSponsorPackage> packages = const [
    AdminSponsorPackage(
      id: 'k1',
      placement: SponsorPlacement.shopList,
      name: 'Günlük',
      durationDays: 1,
      price: 30,
      isActive: true,
    ),
    AdminSponsorPackage(
      id: 'k2',
      placement: SponsorPlacement.shopList,
      name: 'Haftalık',
      durationDays: 7,
      price: 150,
      isActive: true,
      sortOrder: 1,
    ),
  ];

  void _maybeFail() {
    final error = failNext;
    if (error != null) {
      failNext = null;
      throw error;
    }
  }

  List<Map<String, dynamic>> _list(String status) => switch (status) {
    'pending' => pending,
    'active' => active,
    _ => history,
  };

  @override
  Future<AdminSponsorshipPage> fetch(String status, {int limit = 50, int offset = 0}) async {
    calls.add('fetch:$status');
    if (failFetches > 0) {
      failFetches--;
      throw const PostgrestException(message: 'Sunucuya ulaşılamadı');
    }
    final rows = _list(status);
    return AdminSponsorshipPage.fromJson({
      'total': rows.length,
      'rows': rows.skip(offset).take(limit).toList(),
      'summary': {
        'pending': pending.length,
        'running': active.where((r) => r['is_running'] == true).length,
        'queued': active.where((r) => r['is_queued'] == true).length,
        'revenue_30d': 245.5,
      },
      'settings': {'enabled': enabled, 'requires_approval': requiresApproval},
    });
  }

  @override
  Future<double> review(String id, {required bool approve, String? note}) async {
    calls.add('review:$id:$approve:${note ?? ''}');
    _maybeFail();
    final row = pending.firstWhere((r) => r['id'] == id);
    pending.remove(row);
    if (approve) {
      final now = DateTime.now();
      active.add({
        ...row,
        'status': 'active',
        'starts_at': _iso(now),
        'ends_at': _iso(now.add(const Duration(days: 1))),
        'is_running': true,
      });
      return 0;
    }
    history.add({...row, 'status': 'rejected', 'review_note': note});
    return (row['price_paid'] as num).toDouble();
  }

  @override
  Future<double> cancel(String id, {required bool refund, String? note}) async {
    calls.add('cancel:$id:$refund:${note ?? ''}');
    _maybeFail();
    final row = active.firstWhere((r) => r['id'] == id);
    active.remove(row);
    history.add({...row, 'status': 'cancelled', 'is_running': false, 'is_queued': false});
    return refund ? 107.14 : 0;
  }

  @override
  Future<List<AdminSponsorPackage>> fetchPackages() async {
    calls.add('packages');
    return List.of(packages);
  }

  @override
  Future<void> savePackage({
    String? id,
    required SponsorPlacement placement,
    required String name,
    required int durationDays,
    required double price,
    required bool isActive,
    int sortOrder = 0,
  }) async {
    calls.add('save:${id ?? 'new'}:${placement.dbValue}:$name:$durationDays:$price:$isActive:$sortOrder');
    _maybeFail();
    packages = [
      ...packages.where((p) => p.id != id),
      AdminSponsorPackage(
        id: id ?? 'k${packages.length + 1}',
        placement: placement,
        name: name,
        durationDays: durationDays,
        price: price,
        isActive: isActive,
        sortOrder: sortOrder,
      ),
    ];
  }

  @override
  Future<void> setPackageActive(String id, bool active) async {
    calls.add('active:$id:$active');
    packages = [
      for (final p in packages)
        p.id == id
            ? AdminSponsorPackage(
                id: p.id,
                placement: p.placement,
                name: p.name,
                durationDays: p.durationDays,
                price: p.price,
                isActive: active,
                sortOrder: p.sortOrder,
              )
            : p,
    ];
  }

  @override
  Future<void> deletePackage(String id) async {
    calls.add('delete:$id');
    packages = packages.where((p) => p.id != id).toList();
  }

  @override
  Future<void> setFlag(String key, bool value) async {
    calls.add('flag:$key:$value');
    if (key == 'sponsorship_enabled') {
      enabled = value;
    } else {
      requiresApproval = value;
    }
  }
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<_FakeSponsorshipService> _pump(
  WidgetTester tester, {
  _FakeSponsorshipService? service,
  Size size = const Size(900, 1600),
  double textScale = 1,
}) async {
  final fake = service ?? _FakeSponsorshipService();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(body: AdminSponsorshipsContent(service: fake)),
    ),
  );
  await _settle(tester);
  return fake;
}

Future<void> _openTab(WidgetTester tester, String label) async {
  await tester.tap(find.widgetWithText(Tab, label));
  await _settle(tester);
}

void main() {
  testWidgets('Başvurular: özet kutuları, sekme sayısı ve bekleyen kartlar', (tester) async {
    final fake = await _pump(tester);

    expect(fake.calls.first, 'fetch:pending');
    expect(find.widgetWithText(Tab, 'Başvurular (2)'), findsOneWidget);
    expect(find.text('Cizre Kebap'), findsOneWidget);
    expect(find.text('Dicle Market'), findsOneWidget);
    expect(find.text('Ürün: Çay 1 kg'), findsOneWidget);
    expect(find.text('Onay bekliyor'), findsNWidgets(2));
    expect(find.text('Satın alan: Ayşe Yılmaz'), findsNWidgets(2));
    // Özet: bekleyen 2, gelir ₺245,50
    expect(find.text('2'), findsOneWidget);
    expect(find.text('₺245,50'), findsOneWidget);
    expect(find.text('Onayla'), findsNWidgets(2));
    expect(find.text('Reddet'), findsNWidgets(2));
  });

  testWidgets('Onayla: onay penceresi, RPC ve liste yeniden okunur', (tester) async {
    final fake = await _pump(tester);

    await tester.tap(find.text('Onayla').first);
    await _settle(tester);
    expect(find.text('Öne çıkarma onaylansın mı?'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Onayla'));
    await _settle(tester);

    expect(fake.calls, contains('review:p1:true:'));
    expect(find.text('Onaylandı — Cizre Kebap öne çıkarıldı'), findsOneWidget);
    expect(fake.calls.where((c) => c == 'fetch:pending').length, 2, reason: 'karardan sonra yeniden okunur');
    expect(find.widgetWithText(Tab, 'Başvurular (1)'), findsOneWidget);
    expect(find.text('Onayla'), findsOneWidget);
  });

  testWidgets('Reddet: vazgeçilirse çağrı yok; not kırpılır, iade bildirilir', (tester) async {
    final fake = await _pump(tester);

    await tester.tap(find.text('Reddet').first);
    await _settle(tester);
    expect(find.text('Başvuru reddedilsin mi?'), findsOneWidget);
    await tester.tap(find.text('Vazgeç'));
    await _settle(tester);
    expect(fake.calls.where((c) => c.startsWith('review')), isEmpty);

    await tester.tap(find.text('Reddet').first);
    await _settle(tester);
    expect(find.textContaining('₺30 satıcının bakiyesine iade edilir'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('sponsorship-note')), '  Görsel uygun değil ');
    await tester.tap(find.widgetWithText(FilledButton, 'Reddet'));
    await _settle(tester);

    expect(fake.calls, contains('review:p1:false:Görsel uygun değil'));
    expect(find.text('Reddedildi — ₺30 bakiyeye iade edildi'), findsOneWidget);
  });

  testWidgets('Hata: sonuçlanmış başvuru mesajı gösterilir, liste yenilenir', (tester) async {
    final fake = await _pump(tester);
    fake.failNext = const PostgrestException(message: 'x', hint: 'SPONSORSHIP_NOT_PENDING');

    await tester.tap(find.text('Onayla').first);
    await _settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Onayla'));
    await _settle(tester);

    expect(find.text('Bu başvuru zaten sonuçlanmış.'), findsOneWidget);
    expect(fake.calls.where((c) => c == 'fetch:pending').length, 2);
  });

  testWidgets('Liste okunamazsa hata ve "Tekrar dene"', (tester) async {
    final fake = _FakeSponsorshipService()..failFetches = 1;
    await _pump(tester, service: fake);

    expect(find.text('Liste alınamadı'), findsOneWidget);
    expect(find.text('Sunucuya ulaşılamadı'), findsOneWidget);
    await tester.tap(find.text('Tekrar dene'));
    await _settle(tester);
    expect(find.text('Cizre Kebap'), findsOneWidget);
  });

  testWidgets('Yayında: süren ve sıradaki; iade tahmini, iadesiz iptal', (tester) async {
    final fake = await _pump(tester);
    await _openTab(tester, 'Yayında');

    expect(fake.calls, contains('fetch:active'));
    expect(find.text('Botan Pide'), findsNWidgets(2));
    expect(find.text('İptal et'), findsNWidgets(2));
    expect(find.textContaining('kaldı'), findsOneWidget, reason: 'sürende kalan süre yazar');
    expect(find.textContaining('Başlayacak:'), findsOneWidget);

    // Sıradaki: tamamı iade edilir
    await tester.tap(find.text('İptal et').last);
    await _settle(tester);
    expect(find.text('Tamamı: ₺150'), findsOneWidget);
    await tester.tap(find.text('Vazgeç'));
    await _settle(tester);

    // Süren: kalan süre kadarı (5/7 × 150 ≈ 107,14); iade kapatılır
    await tester.tap(find.text('İptal et').first);
    await _settle(tester);
    expect(find.text('Öne çıkarma iptal edilsin mi?'), findsOneWidget);
    expect(find.textContaining('Kalan süre kadarı: yaklaşık ₺107,1'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('sponsorship-refund')));
    await _settle(tester);
    expect(find.text('Ücret iade edilmez'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('sponsorship-note')), 'Kural ihlali');
    await tester.tap(find.widgetWithText(FilledButton, 'İptal et'));
    await _settle(tester);

    expect(fake.calls, contains('cancel:a1:false:Kural ihlali'));
    expect(find.text('İptal edildi (iade yok)'), findsOneWidget);
    expect(find.text('İptal et'), findsOneWidget, reason: 'iptal edilen listeden düştü');
  });

  testWidgets('Geçmiş: sonuç ve not görünür, işlem düğmesi yok', (tester) async {
    await _pump(tester);
    await _openTab(tester, 'Geçmiş');

    expect(find.text('Eski Dükkan'), findsOneWidget);
    expect(find.text('Reddedildi'), findsOneWidget);
    expect(find.text('Not: Görsel uygun değil'), findsOneWidget);
    expect(find.text('İptal et'), findsNothing);
    expect(find.text('Onayla'), findsNothing);
  });

  testWidgets('Paketler: vitrine göre listelenir; yeni paket formu doğrular', (tester) async {
    final fake = await _pump(tester);
    await _openTab(tester, 'Paketler');

    expect(fake.calls, contains('packages'));
    for (final placement in SponsorPlacement.values) {
      expect(find.text(placement.label), findsOneWidget);
    }
    expect(find.text('7 gün · ₺150 · günlük ₺21,43'), findsOneWidget);
    expect(find.text('Bu vitrinde paket yok — satıcılar satın alamaz.'), findsNWidgets(3));

    await tester.tap(find.byKey(const ValueKey('add-package-shop_list')));
    await _settle(tester);
    expect(find.text('Yeni paket'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Kaydet'));
    await _settle(tester);
    expect(find.text('Paket adı gerekli'), findsOneWidget);
    expect(find.text('Süre 1–90 gün olmalı'), findsOneWidget);
    expect(find.text('Geçerli bir fiyat girin (en çok 2 ondalık)'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('package-name')), '  Aylık ');
    await tester.enterText(find.byKey(const ValueKey('package-days')), '91');
    await tester.enterText(find.byKey(const ValueKey('package-price')), '1.234,5');
    await tester.tap(find.widgetWithText(FilledButton, 'Kaydet'));
    await _settle(tester);
    expect(find.text('Süre 1–90 gün olmalı'), findsOneWidget);
    expect(find.text('Geçerli bir fiyat girin (en çok 2 ondalık)'), findsOneWidget);
    expect(fake.calls.where((c) => c.startsWith('save')), isEmpty);

    await tester.enterText(find.byKey(const ValueKey('package-days')), '30');
    await tester.enterText(find.byKey(const ValueKey('package-price')), '499,90');
    await tester.tap(find.widgetWithText(FilledButton, 'Kaydet'));
    await _settle(tester);

    expect(fake.calls, contains('save:new:shop_list:Aylık:30:499.9:true:0'));
    expect(find.text('Paket eklendi'), findsOneWidget);
    expect(find.text('30 gün · ₺499,90 · günlük ₺16,66'), findsOneWidget);
  });

  testWidgets('Paketler: düzenleme mevcut değerleri doldurur; pasifleştirme ve onaylı silme', (tester) async {
    final fake = await _pump(tester);
    await _openTab(tester, 'Paketler');

    // Düzenle
    await tester.tap(
      find.descendant(of: find.byKey(const ValueKey('package-k2')), matching: find.byType(PopupMenuButton<String>)),
    );
    await _settle(tester);
    await tester.tap(find.text('Düzenle'));
    await _settle(tester);
    expect(find.text('Paketi düzenle'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Haftalık'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('package-price')), '175');
    await tester.tap(find.widgetWithText(FilledButton, 'Kaydet'));
    await _settle(tester);
    expect(fake.calls, contains('save:k2:shop_list:Haftalık:7:175.0:true:1'));
    expect(find.text('Paket güncellendi'), findsOneWidget);

    // Pasifleştir
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('package-k1')), matching: find.byType(Switch)));
    await _settle(tester);
    expect(fake.calls, contains('active:k1:false'));
    expect(find.text('Pasif — satıcılar görmez'), findsOneWidget);

    // Sil (onaylı)
    await tester.tap(
      find.descendant(of: find.byKey(const ValueKey('package-k1')), matching: find.byType(PopupMenuButton<String>)),
    );
    await _settle(tester);
    await tester.tap(find.text('Sil'));
    await _settle(tester);
    expect(find.text('Paket silinsin mi?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Sil'));
    await _settle(tester);
    expect(fake.calls, contains('delete:k1'));
    expect(find.byKey(const ValueKey('package-k1')), findsNothing);
  });

  testWidgets('Ayarlar: anahtarlar yazılır; onay kapalıyken bekleyen uyarısı', (tester) async {
    final fake = await _pump(tester);
    await _openTab(tester, 'Ayarlar');

    final approval = find.byKey(const ValueKey('flag-sponsorship-approval'));
    expect(tester.widget<SwitchListTile>(approval).value, isTrue);
    expect(find.textContaining('onayınızı bekler'), findsOneWidget);

    await tester.tap(approval);
    await _settle(tester);
    expect(fake.calls, contains('flag:sponsorship_requires_approval:false'));
    expect(find.text('Yeni satın alımlar hemen yayına girecek'), findsOneWidget);
    expect(tester.widget<SwitchListTile>(approval).value, isFalse);
    expect(find.text('2 başvuru hâlâ onay bekliyor; Başvurular sekmesinden sonuçlandırın.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('flag-sponsorship-enabled')));
    await _settle(tester);
    expect(fake.calls, contains('flag:sponsorship_enabled:false'));
    expect(find.text('Öne çıkarma satışı kapatıldı'), findsOneWidget);
    expect(find.textContaining('yeni öne çıkarma satın alamaz'), findsOneWidget);
  });

  testWidgets('Dar ekran + büyük yazı: sekmeler ve pencereler taşmaz', (tester) async {
    await _pump(tester, size: const Size(320, 568), textScale: 1.6);
    expect(tester.takeException(), isNull);

    // Küçük ekranda kartın düğmeleri görünür alanın altında kalır.
    await tester.ensureVisible(find.text('Reddet').first);
    await _settle(tester);
    await tester.tap(find.text('Reddet').first);
    await _settle(tester);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Vazgeç'));
    await _settle(tester);

    for (final tab in ['Yayında', 'Geçmiş', 'Paketler', 'Ayarlar']) {
      await tester.drag(find.byType(TabBar), const Offset(-200, 0));
      await tester.pump();
      await _openTab(tester, tab);
      expect(tester.takeException(), isNull, reason: tab);
    }

    await _openTab(tester, 'Paketler');
    await tester.tap(find.byKey(const ValueKey('add-package-shop_list')));
    await _settle(tester);
    expect(tester.takeException(), isNull);
  });

  test('fiyat ayrıştırma: virgül/nokta, en çok 2 ondalık, numeric(10,2) sınırı', () {
    expect(parseSponsorPrice('150'), 150);
    expect(parseSponsorPrice('12,50'), 12.5);
    expect(parseSponsorPrice('12.5'), 12.5);
    expect(parseSponsorPrice(' 0 '), 0);
    expect(parseSponsorPrice('12,345'), isNull);
    expect(parseSponsorPrice('1.234,50'), isNull);
    expect(parseSponsorPrice('-5'), isNull);
    expect(parseSponsorPrice(''), isNull);
    expect(parseSponsorPrice('12345678'), isNull);
    expect(parseSponsorPrice('9999999,99'), 9999999.99);
  });

  test('iptal iadesi tahmini: başlamadıysa tamamı, sürüyorsa kalan oranı', () {
    final now = DateTime.utc(2026, 9, 28, 12);
    AdminSponsorshipRow row(DateTime? starts, DateTime? ends) => AdminSponsorshipRow(
      id: 'x',
      shopId: 's',
      shopName: 'Dükkan',
      placement: SponsorPlacement.shopList,
      packageName: 'Haftalık',
      durationDays: 7,
      pricePaid: 140,
      status: SponsorshipStatus.active,
      createdAt: now,
      startsAt: starts,
      endsAt: ends,
    );
    expect(
      estimateSponsorshipRefund(row(now.add(const Duration(days: 1)), now.add(const Duration(days: 8))), now: now),
      140,
    );
    expect(
      estimateSponsorshipRefund(
        row(now.subtract(const Duration(days: 2)), now.add(const Duration(days: 5))),
        now: now,
      ),
      100,
    );
    expect(estimateSponsorshipRefund(row(now.subtract(const Duration(days: 7)), now), now: now), 0);
    expect(estimateSponsorshipRefund(row(null, null), now: now), 0);
  });
}
