import 'package:cizreapp/kullaniciozellikler/admin/user_features_admin_content.dart';
import 'package:cizreapp/kullaniciozellikler/models/profile_feature.dart';
import 'package:cizreapp/kullaniciozellikler/services/profile_feature_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_fonts.dart';

/// Görev 2.5 — Admin > Kullanıcı Özellikleri yeniden tasarım: iki mod
/// (Kullanıcıya Ver / Katalog Yönetimi), kullanıcı seçilince kimlik kartı +
/// profildeki özellikler + katalogdan "Profile ver"; katalog modunda etiketli
/// ayarlar; tür çipleri ve canlı arama.

ProfileFeature _feature(
  String id,
  String name, {
  String kind = 'effect',
  bool claimable = false,
  bool enabled = true,
  int? monthly,
}) => ProfileFeature.fromMap({
  'feature_id': id,
  'code': id,
  'kind': kind,
  'name': name,
  'description': '$name açıklaması',
  'renderer_key': 'none',
  'primary_color': '#7E57C2',
  'is_user_claimable': claimable,
  'is_enabled': enabled,
  'points_price_monthly': monthly,
});

class _FakeService extends ProfileFeatureService {
  _FakeService() : super();

  final users = const [
    ProfileFeatureUser(id: 'u1', username: 'ayse', fullName: 'Ayşe Yılmaz'),
    ProfileFeatureUser(id: 'u2', username: 'mehmet', fullName: 'Mehmet Kaya'),
  ];
  List<ProfileFeature> catalog = [
    _feature('f1', 'Işıltı', claimable: true),
    _feature('f2', 'Alev Çerçeve', kind: 'avatar_effect', monthly: 150),
    _feature('f3', 'Mavi Tik', kind: 'badge'),
  ];
  Map<String, List<ProfileFeature>> assignments = {
    'u1': [_feature('f2', 'Alev Çerçeve', kind: 'avatar_effect')],
  };

  final catalogQueries = <({String? kind, String search})>[];
  final assigned = <({String userId, String featureId, DateTime? expiresAt})>[];
  final claimableCalls = <({String featureId, bool claimable})>[];

  @override
  Future<List<ProfileFeatureUser>> searchUsers(String search) async => users
      .where((u) => search.isEmpty || u.username.contains(search.toLowerCase()))
      .toList();

  @override
  Future<List<ProfileFeature>> getCatalog({String? kind, String? search}) async {
    catalogQueries.add((kind: kind, search: search ?? ''));
    return catalog
        .where((f) => kind == null || f.kind.name == _kindName(kind))
        .toList();
  }

  static String _kindName(String kind) => switch (kind) {
    'avatar_effect' => 'avatarEffect',
    'cover_effect' => 'coverEffect',
    _ => kind,
  };

  @override
  Future<List<ProfileFeature>> getAdminAssignments(String userId) async =>
      assignments[userId] ?? const [];

  @override
  Future<void> assign({
    required String userId,
    required String featureId,
    DateTime? expiresAt,
  }) async {
    assigned.add((userId: userId, featureId: featureId, expiresAt: expiresAt));
    final feature = catalog.firstWhere((f) => f.id == featureId);
    assignments[userId] = [...?assignments[userId], feature];
  }

  @override
  Future<void> setCatalogClaimable({
    required String featureId,
    required bool claimable,
    int? durationDays,
  }) async {
    claimableCalls.add((featureId: featureId, claimable: claimable));
    catalog = [
      for (final f in catalog)
        f.id == featureId
            ? _feature(f.id, f.name, kind: f.kind == ProfileFeatureKind.avatarEffect ? 'avatar_effect' : 'effect', claimable: claimable)
            : f,
    ];
  }
}

Future<void> _pump(WidgetTester tester, _FakeService service, {Size size = const Size(420, 900)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: UserFeaturesAdminContent(service: service)),
    ),
  );
  // Önizlemeler sürekli canlandığı için pumpAndSettle kullanılmaz.
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(loadTestFonts);

  testWidgets('mobil: önce kullanıcı seçilir; seçince kimlik kartı, profildeki özellikler ve katalog', (tester) async {
    final service = _FakeService();
    await _pump(tester, service);

    expect(find.text('Kullanıcıya Ver'), findsOneWidget);
    expect(find.text('Katalog Yönetimi'), findsOneWidget);
    expect(find.text('Kullanıcı seçin'), findsOneWidget);
    expect(find.text('Profile ver'), findsNothing, reason: 'kullanıcı seçmeden katalog yok');

    await tester.tap(find.text('Ayşe Yılmaz'));
    await _settle(tester);

    expect(find.text('@ayse'), findsWidgets);
    expect(find.text('Değiştir'), findsOneWidget);
    expect(find.text('Profildeki özellikler'), findsOneWidget);
    expect(find.text('Katalogdan özellik ver'), findsOneWidget);
    // f2 profilde → "Profilde", diğerleri → "Profile ver".
    expect(find.text('Profilde'), findsOneWidget);
    expect(find.text('Profile ver'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('"Profile ver" → süre seçilir → servis çağrılır, özellik profile eklenir', (tester) async {
    final service = _FakeService();
    await _pump(tester, service);
    await tester.tap(find.text('Ayşe Yılmaz'));
    await _settle(tester);

    await tester.tap(find.text('Profile ver').first);
    await _settle(tester);
    await tester.tap(find.text('30 gün'));
    await _settle(tester);

    expect(service.assigned, hasLength(1));
    expect(service.assigned.single.userId, 'u1');
    expect(service.assigned.single.featureId, 'f1');
    final days = service.assigned.single.expiresAt!.difference(DateTime.now()).inHours / 24;
    expect(days, closeTo(30, 0.1));
    expect(find.text('Profilde'), findsNWidgets(2));
  });

  testWidgets('"Değiştir" kullanıcı seçimine döner', (tester) async {
    final service = _FakeService();
    await _pump(tester, service);
    await tester.tap(find.text('Ayşe Yılmaz'));
    await _settle(tester);

    await tester.tap(find.text('Değiştir'));
    await _settle(tester);

    expect(find.text('Kullanıcı seçin'), findsOneWidget);
    expect(find.text('Mehmet Kaya'), findsOneWidget);
  });

  testWidgets('katalog yönetimi: etiketli ayarlar; ücretsiz anahtarı servise gider', (tester) async {
    final service = _FakeService();
    await _pump(tester, service);

    await tester.tap(find.text('Katalog Yönetimi'));
    await _settle(tester);

    expect(find.text('Kullanıcılara ücretsiz açık'), findsNWidgets(2), reason: 'tik hariç');
    expect(find.text('Tik/rozetler yalnızca admin tarafından verilir.'), findsOneWidget);
    expect(find.text('Aylık 150 puan'), findsOneWidget);
    expect(find.text('Sipariş kilidi yok'), findsOneWidget, reason: 'yalnız avatar/kapak efekti');

    // İkinci ücretsizi aç (sınır 2). Anahtarlar kart sırasıyla: Işıltı, Alev.
    await tester.tap(find.byType(Switch).at(1));
    await _settle(tester);
    expect(service.claimableCalls.single, (featureId: 'f2', claimable: true));
  });

  testWidgets('ücretsiz sınırı doluyken üçüncüsü açılmaz, uyarı gösterilir', (tester) async {
    final service = _FakeService()
      ..catalog = [
        _feature('f1', 'Işıltı', claimable: true),
        _feature('f4', 'Kar Tanesi', claimable: true),
        _feature('f5', 'Yıldız Tozu'),
      ];
    await _pump(tester, service);
    await tester.tap(find.text('Katalog Yönetimi'));
    await _settle(tester);

    final third = find.byType(Switch).at(2); // Yıldız Tozu
    await tester.ensureVisible(third);
    await _settle(tester);
    await tester.tap(third);
    await _settle(tester);

    expect(service.claimableCalls, isEmpty);
    expect(find.textContaining('En fazla 2 özellik ücretsiz açılabilir'), findsOneWidget);
  });

  testWidgets('tür çipi ve canlı arama kataloğu sunucudan süzer', (tester) async {
    final service = _FakeService();
    await _pump(tester, service);
    await tester.tap(find.text('Katalog Yönetimi'));
    await _settle(tester);

    await tester.tap(find.text('Profil Resmi Efekti'));
    await _settle(tester);
    expect(service.catalogQueries.last.kind, 'avatar_effect');
    expect(find.text('Işıltı'), findsNothing);
    expect(find.text('Alev Çerçeve'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Katalogda ara'), 'alev');
    await tester.pump(const Duration(milliseconds: 500)); // gecikmeli arama
    await _settle(tester);
    expect(service.catalogQueries.last.search, 'alev');
  });

  testWidgets('geniş ekran: solda kullanıcı listesi, sağda seçili kullanıcı', (tester) async {
    final service = _FakeService();
    await _pump(tester, service, size: const Size(1200, 900));

    expect(find.text('Soldan bir kullanıcı seçin; sonra katalogdan özellik verin.'), findsOneWidget);
    await tester.tap(find.text('Mehmet Kaya'));
    await _settle(tester);

    expect(find.text('Katalogdan özellik ver'), findsOneWidget);
    expect(find.text('Profile ver'), findsNWidgets(3));
    expect(tester.takeException(), isNull);
  });
}
