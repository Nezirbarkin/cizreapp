import 'package:cizreapp/features/admin/services/admin_live_service.dart';
import 'package:cizreapp/features/admin/services/admin_moderators_service.dart';
import 'package:cizreapp/features/admin/widgets/admin_live_content.dart';
import 'package:cizreapp/features/admin/widgets/admin_moderators_content.dart';
import 'package:cizreapp/features/moderation/models/moderation_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Görev 4.6 — Admin > Moderatörler ve canlı yayın ekranının moderatör kipi.

class _FakeModerators extends AdminModeratorsService {
  final calls = <String>[];

  List<AdminModerator> rows = [
    AdminModerator(
      userId: 'm1',
      scopes: {ModerationScope.reports, ModerationScope.content},
      createdAt: DateTime(2026, 9, 1),
      fullName: 'Zeynep Kaya',
      username: 'zeynep',
      role: 'seller',
      note: 'Topluluk',
      grantedByName: 'Yönetici',
      actions30d: 7,
    ),
  ];

  @override
  Future<List<AdminModerator>> list() async {
    calls.add('list');
    return List.of(rows);
  }

  @override
  Future<List<ModeratorCandidate>> searchUsers(String query) async {
    calls.add('search:${query.trim()}');
    return const [
      ModeratorCandidate(id: 'u5', fullName: 'Ali Veli', username: 'aliveli', role: 'customer'),
      ModeratorCandidate(id: 'adm', fullName: 'Baş Yönetici', username: 'admin', role: 'admin'),
      ModeratorCandidate(id: 'm1', fullName: 'Zeynep Kaya', username: 'zeynep', role: 'seller'),
    ];
  }

  ModerationCategoryOptions categories = const ModerationCategoryOptions(
    ilan: [
      ModCategory(id: 'c-emlak', name: 'Emlak'),
      ModCategory(id: 'c-vasita', name: 'Vasıta'),
      ModCategory(id: 'c-eski', name: 'Eski', isActive: false),
    ],
    shop: [
      ModCategory(id: 's-gida', name: 'Gıda'),
      ModCategory(id: 's-giyim', name: 'Giyim'),
    ],
  );
  Object? categoriesError;

  @override
  Future<ModerationCategoryOptions> fetchCategories() async {
    calls.add('categories');
    if (categoriesError != null) throw categoriesError!;
    return categories;
  }

  /// null = "değiştirme" (-), boş = tümü (*), dolu = kimlikler.
  static String _ids(List<String>? ids) => ids == null ? '-' : (ids.isEmpty ? '*' : ids.join('|'));

  /// Sunucu gibi: null eskisini korur, boş = tümü (null), kapsam yoksa sınır yok.
  List<ModCategory>? _apply(List<ModCategory>? old, List<String>? ids, List<ModCategory> options, bool hasScope) {
    if (!hasScope) return null;
    if (ids == null) return old;
    if (ids.isEmpty) return null;
    return [for (final c in options) if (ids.contains(c.id)) c];
  }

  @override
  Future<Set<ModerationScope>> setModerator(
    String userId,
    Set<ModerationScope> scopes, {
    String? note,
    List<String>? ilanCategoryIds,
    List<String>? shopCategoryIds,
  }) async {
    final keys = [for (final s in ModerationScope.values) if (scopes.contains(s)) s.key];
    calls.add('set:$userId:${keys.join(',')}:${note ?? ''}:${_ids(ilanCategoryIds)}:${_ids(shopCategoryIds)}');
    final old = rows.where((r) => r.userId == userId).firstOrNull;
    rows = [
      for (final r in rows)
        if (r.userId != userId) r,
      if (scopes.isNotEmpty)
        AdminModerator(
          userId: userId,
          scopes: scopes,
          createdAt: DateTime(2026, 9, 28),
          fullName: old?.fullName ?? 'Ali Veli',
          ilanCategories: _apply(
            old?.ilanCategories,
            ilanCategoryIds,
            categories.ilan,
            scopes.contains(ModerationScope.ilanlar),
          ),
          shopCategories: _apply(
            old?.shopCategories,
            shopCategoryIds,
            categories.shop,
            scopes.contains(ModerationScope.live),
          ),
        ),
    ];
    return scopes;
  }
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// İlanlar + Canlı yayınlar kapsamlı, ilanda kategori sınırlı moderatör.
AdminModerator _restricted({List<ModCategory>? ilan = const [ModCategory(id: 'c-emlak', name: 'Emlak')]}) =>
    AdminModerator(
      userId: 'm2',
      scopes: {ModerationScope.ilanlar, ModerationScope.live},
      createdAt: DateTime(2026, 9, 2),
      fullName: 'Mehmet Demir',
      ilanCategories: ilan,
    );

Future<_FakeModerators> _pump(WidgetTester tester, {void Function(_FakeModerators fake)? setup}) async {
  final fake = _FakeModerators();
  setup?.call(fake);
  tester.view.physicalSize = const Size(700, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: AdminModeratorsContent(service: fake))));
  await _settle(tester);
  return fake;
}

class _FakeLive extends AdminLiveService {
  @override
  Future<AdminLiveSessionsPage> fetchSessions(String status, {int limit = 30, int offset = 0}) async =>
      AdminLiveSessionsPage.fromJson({
        'total': status == 'live' ? 1 : 0,
        'rows': [
          if (status == 'live')
            {
              'id': 's1',
              'shop_id': 'shop-1',
              'host_user_id': 'o1',
              'title': 'Yeni sezon',
              'channel_name': 'cz_s1',
              'status': 'live',
              'is_live': true,
              'started_at': DateTime.now().toUtc().toIso8601String(),
              'created_at': DateTime.now().toUtc().toIso8601String(),
              'shop_name': 'Çay Evi',
              'viewer_count': 3,
              'peak_viewer_count': 5,
            },
        ],
        'summary': {'live_now': status == 'live' ? 1 : 0, 'revoked_shops': 2},
        'settings': {'enabled': true, 'access': 'open'},
      });
}

void main() {
  testWidgets('liste: kapsamlar, rol, not, işlem sayısı', (tester) async {
    await _pump(tester);
    expect(find.text('Zeynep Kaya'), findsOneWidget);
    expect(find.text('@zeynep'), findsOneWidget);
    expect(find.text('Şikayetler'), findsOneWidget);
    expect(find.text('İçerik'), findsOneWidget);
    expect(find.text('Rol: seller'), findsOneWidget);
    expect(find.text('Not: Topluluk'), findsOneWidget);
    expect(find.textContaining('30 günde 7 işlem'), findsOneWidget);
  });

  testWidgets('ekle: ara, yönetici ve mevcut moderatör seçilemez, kapsam seç ve kaydet', (tester) async {
    final fake = await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('add-moderator')));
    await _settle(tester);
    await tester.enterText(find.byKey(const ValueKey('moderator-search')), 'al');
    await _settle(tester);
    expect(fake.calls, contains('search:al'));
    expect(tester.widget<ListTile>(find.byKey(const ValueKey('candidate-adm'))).enabled, isFalse);
    expect(tester.widget<ListTile>(find.byKey(const ValueKey('candidate-m1'))).enabled, isFalse);
    expect(find.text('Yönetici — zaten tüm yetkilere sahip'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('candidate-u5')));
    await _settle(tester);
    expect(find.text('Ali Veli'), findsOneWidget);
    final save = find.widgetWithText(FilledButton, 'Kaydet');
    expect(tester.widget<FilledButton>(save).onPressed, isNull, reason: 'kapsam seçmeden kaydedilmez');
    await tester.tap(find.byKey(const ValueKey('scope-ilanlar')));
    await tester.tap(find.byKey(const ValueKey('scope-live')));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('moderator-note')), 'Hafta sonu');
    await tester.tap(save);
    await _settle(tester);
    expect(fake.calls, contains('set:u5:ilanlar,live:Hafta sonu:-:-'), reason: 'kategoriye dokunulmadı → tümü');
    expect(find.text('Ali Veli: İlanlar, Canlı yayınlar'), findsOneWidget);
  });

  Future<void> editM2(WidgetTester tester) async {
    await tester.tap(
      find.descendant(of: find.byKey(const ValueKey('moderator-m2')), matching: find.text('Yetkileri düzenle')),
    );
    await _settle(tester);
  }

  String lastSet(_FakeModerators fake) => fake.calls.lastWhere((c) => c.startsWith('set:'));

  bool chip(WidgetTester tester, String key) => tester.widget<FilterChip>(find.byKey(ValueKey(key))).selected;

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, 'Kaydet'));
    await _settle(tester);
  }

  testWidgets('kategori: kartta rozet; dokunulmazsa değişmez; tek tek, Tümü ve kapsamı kaldırma', (tester) async {
    final fake = await _pump(tester, setup: (f) => f.rows = [...f.rows, _restricted()]);
    expect(find.text('İlan: Emlak'), findsOneWidget);
    expect(find.textContaining('Mağaza:'), findsNothing, reason: 'mağaza kategorisi sınırsız');

    await editM2(tester);
    expect(chip(tester, 'mod-ilan-cat-c-emlak'), isTrue);
    expect(chip(tester, 'mod-ilan-cat-all'), isFalse);
    expect(chip(tester, 'mod-shop-cat-all'), isTrue);
    expect(find.text('Eski (pasif)'), findsOneWidget);
    await save(tester);
    expect(lastSet(fake), 'set:m2:ilanlar,live::-:-');

    await editM2(tester);
    await tester.tap(find.byKey(const ValueKey('mod-ilan-cat-c-vasita')));
    await tester.tap(find.byKey(const ValueKey('mod-shop-cat-s-gida')));
    await tester.pump();
    expect(chip(tester, 'mod-shop-cat-all'), isFalse);
    await save(tester);
    expect(lastSet(fake), 'set:m2:ilanlar,live::c-emlak|c-vasita:s-gida');
    expect(find.text('İlan: Emlak, Vasıta'), findsOneWidget);
    expect(find.text('Mağaza: Gıda'), findsOneWidget);
    expect(fake.calls.where((c) => c == 'categories'), hasLength(1), reason: 'seçenekler bir kez yüklenir');

    await editM2(tester);
    await tester.tap(find.byKey(const ValueKey('mod-ilan-cat-all')));
    await tester.pump();
    expect(chip(tester, 'mod-ilan-cat-c-emlak'), isFalse);
    await save(tester);
    expect(lastSet(fake), 'set:m2:ilanlar,live::*:-');
    expect(find.textContaining('İlan:'), findsNothing);

    await editM2(tester);
    await tester.tap(find.byKey(const ValueKey('scope-ilanlar')));
    await tester.pump();
    expect(find.byKey(const ValueKey('mod-ilan-cat-picker')), findsNothing);
    expect(find.byKey(const ValueKey('mod-shop-cat-picker')), findsOneWidget);
    await save(tester);
    expect(lastSet(fake), 'set:m2:live::-:-');
  });

  testWidgets('kategorileri silinmiş sınırlı moderatör: "Tümü" seçili görünmez, kaydetmek genişletmez', (tester) async {
    final fake = await _pump(tester, setup: (f) => f.rows = [...f.rows, _restricted(ilan: const [])]);
    expect(find.text('İlan: kategori kalmadı'), findsOneWidget);

    await editM2(tester);
    expect(find.byKey(const ValueKey('mod-ilan-cat-orphaned')), findsOneWidget);
    expect(chip(tester, 'mod-ilan-cat-all'), isFalse);
    await save(tester);
    expect(lastSet(fake), 'set:m2:ilanlar,live::-:-', reason: 'boş seçim "tümü" diye gönderilmez');
    expect(find.text('İlan: kategori kalmadı'), findsOneWidget);

    await editM2(tester);
    await tester.tap(find.byKey(const ValueKey('mod-ilan-cat-all')));
    await tester.pump();
    expect(find.byKey(const ValueKey('mod-ilan-cat-orphaned')), findsNothing);
    expect(chip(tester, 'mod-ilan-cat-all'), isTrue);
    await save(tester);
    expect(lastSet(fake), 'set:m2:ilanlar,live::*:-', reason: 'yönetici bilerek "Tümü" seçti');
  });

  testWidgets('kategoriler alınamazsa seçici yok; mevcut sınır korunur', (tester) async {
    final fake = await _pump(
      tester,
      setup: (f) => f
        ..rows = [...f.rows, _restricted()]
        ..categoriesError = Exception('ağ yok'),
    );
    await editM2(tester);
    expect(find.text('Kategoriler alınamadı; kategori sınırı değiştirilmeyecek.'), findsOneWidget);
    expect(find.text('Kategoriler alınamadı; mevcut kategori sınırı korunur.'), findsOneWidget);
    expect(find.byKey(const ValueKey('mod-ilan-cat-picker')), findsNothing);
    await save(tester);
    expect(lastSet(fake), 'set:m2:ilanlar,live::-:-');
    expect(find.text('İlan: Emlak'), findsOneWidget);
  });

  testWidgets('düzenle: tüm kapsamları kaldırmak "Kaldır" olur; kaldır onaylı', (tester) async {
    final fake = await _pump(tester);
    await tester.tap(find.text('Yetkileri düzenle'));
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('scope-reports')));
    await tester.tap(find.byKey(const ValueKey('scope-content')));
    await tester.pump();
    expect(find.text('Hiçbir alan seçili değil: kaydedince moderatörlükten çıkarılır.'), findsOneWidget);
    await tester.tap(find.text('Vazgeç'));
    await _settle(tester);
    expect(fake.calls.where((c) => c.startsWith('set:')), isEmpty);

    await tester.tap(find.widgetWithText(TextButton, 'Kaldır'));
    await _settle(tester);
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.widgetWithText(FilledButton, 'Kaldır')));
    await _settle(tester);
    expect(fake.calls, contains('set:m1::Topluluk:-:-'));
    expect(find.text('Zeynep Kaya moderatörlükten çıkarıldı'), findsOneWidget);
    expect(find.text('Henüz moderatör yok'), findsOneWidget);
  });

  testWidgets('canlı yayın moderatör kipi: yalnız Yayında/Geçmiş, izin kaldırma yok', (tester) async {
    tester.view.physicalSize = const Size(700, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AdminLiveContent(service: _FakeLive(), moderatorMode: true, openViewer: (_, __) {})),
      ),
    );
    await _settle(tester);

    expect(find.widgetWithText(Tab, 'Geçmiş'), findsOneWidget);
    expect(find.widgetWithText(Tab, 'Mağaza İzinleri'), findsNothing);
    expect(find.widgetWithText(Tab, 'Ayarlar'), findsNothing);
    expect(find.text('İzni yok'), findsNothing);

    await tester.tap(find.text('Yayını kapat'));
    await _settle(tester);
    expect(find.text('Yayın kapatılsın mı?'), findsOneWidget);
    expect(find.byKey(const ValueKey('live-close-revoke')), findsNothing);
  });
}
