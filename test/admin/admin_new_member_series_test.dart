import 'package:cizreapp/core/services/admin_new_member_series_service.dart';
import 'package:cizreapp/features/admin/screens/admin_new_member_series_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Supabase'e dokunmayan sahte servis: seri sabit, yazmalar kaydedilir.
class _FakeService extends AdminNewMemberSeriesService {
  _FakeService(this.series);

  NewMemberSeries series;
  final List<String> calls = [];
  final List<Map<String, Object?>> saved = [];

  @override
  Future<NewMemberSeries> load() async => series;

  @override
  Future<void> setEnabled(bool enabled) async {
    calls.add('enabled:$enabled');
    series = NewMemberSeries(enabled: enabled, steps: series.steps);
  }

  @override
  Future<void> setStepActive(String id, bool active) async => calls.add('active:$id:$active');

  @override
  Future<void> sendTest(String id) async => calls.add('test:$id');

  @override
  Future<void> deleteStep(String id) async => calls.add('delete:$id');

  @override
  Future<NewMemberStep> saveStep({
    String? id,
    required String title,
    required String body,
    String? voiceText,
    String? voiceGender,
    required String icon,
    required int delayMinutes,
    required String condition,
    String? actionRoute,
    required bool respectQuietHours,
    required bool isActive,
  }) async {
    saved.add({
      'id': id,
      'title': title,
      'body': body,
      'voice': voiceText,
      'icon': icon,
      'delay': delayMinutes,
      'condition': condition,
      'route': actionRoute,
    });
    return NewMemberStep(
      id: id ?? 'new',
      stepKey: 'custom',
      sortOrder: 9,
      delayMinutes: delayMinutes,
      title: title,
      body: body,
      icon: icon,
      condition: condition,
      isActive: isActive,
      respectQuietHours: respectQuietHours,
    );
  }
}

NewMemberSeries _sample() => const NewMemberSeries(
      enabled: true,
      steps: [
        NewMemberStep(
          id: 's1',
          stepKey: 'welcome',
          sortOrder: 1,
          delayMinutes: 1,
          title: 'CizreApp\'e hoş geldin {ad} 👋',
          body: 'Aramıza katıldığın için çok mutluyuz!',
          voiceText: 'Merhaba {ad}, hoş geldin!',
          icon: 'gift',
          condition: 'always',
          isActive: true,
          respectQuietHours: false,
          sent: 4,
          read: 3,
        ),
        NewMemberStep(
          id: 's2',
          stepKey: 'complete_profile',
          sortOrder: 2,
          delayMinutes: 60,
          title: 'Profilini tamamla {ad} 📸',
          body: 'Bir profil fotoğrafı ekle.',
          icon: 'update',
          condition: 'no_avatar',
          actionRoute: 'edit_profile',
          isActive: false,
          respectQuietHours: true,
          sent: 2,
          skipped: 1,
          failed: 1,
        ),
      ],
    );

Future<void> _open(WidgetTester t, _FakeService svc) async {
  t.view.physicalSize = const Size(430, 1600);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(home: AdminNewMemberSeriesScreen(service: svc)));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('seri, adımlar ve sayaçlar çizilir', (t) async {
    await _open(t, _FakeService(_sample()));

    expect(find.text('Karşılama serisi'), findsOneWidget);
    expect(find.text('Kayıttan 1 dk sonra'), findsOneWidget);
    expect(find.text('Kayıttan 1 sa sonra'), findsOneWidget);
    expect(find.text('Profil fotoğrafı yoksa'), findsOneWidget);
    expect(find.text('Profil düzenleme'), findsOneWidget);
    expect(find.text('Sesli metin'), findsOneWidget);
    expect(find.text('Gece de gider'), findsOneWidget);
    expect(find.text('%75 okundu'), findsOneWidget);
    expect(find.text('1 hata'), findsOneWidget);
    // Toplam: 6 gönderim, 3 okunma → %50
    expect(find.text('6'), findsOneWidget);
    expect(find.text('%50'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('adım aç/kapa, test gönderimi ve ana anahtar servise gider', (t) async {
    final svc = _FakeService(_sample());
    await _open(t, svc);

    // Switch'ler: [ana anahtar, s1, s2]
    await t.tap(find.byType(Switch).at(2));
    await t.pumpAndSettle();
    expect(svc.calls, contains('active:s2:true'));

    await t.tap(find.text('Bana gönder').first);
    await t.pumpAndSettle();
    expect(svc.calls, contains('test:s1'));
    expect(find.text('Test bildirimi size gönderildi'), findsOneWidget);

    await t.tap(find.byType(Switch).first);
    await t.pumpAndSettle();
    expect(svc.calls, contains('enabled:false'));
  });

  testWidgets('düzenleyici: boş başlık reddedilir, gün birimi dakikaya çevrilir', (t) async {
    final svc = _FakeService(_sample());
    await _open(t, svc);

    await t.tap(find.text('Adım ekle'));
    await t.pumpAndSettle();
    expect(find.text('Yeni adım'), findsOneWidget);

    await t.tap(find.text('Kaydet'));
    await t.pumpAndSettle();
    expect(find.text('Başlık yazın'), findsOneWidget);
    expect(svc.saved, isEmpty);

    final fields = find.byType(TextField);
    // Sıra: gecikme, başlık, metin, sesli metin
    await t.enterText(fields.at(0), '2');
    await t.enterText(fields.at(1), 'İkinci gün {ad}');
    await t.enterText(fields.at(2), 'Kampanyalara göz at.');
    await t.pump();

    // Varsayılan birim saat (60 dk) → gün seç
    await t.tap(find.text('saat'));
    await t.pumpAndSettle();
    await t.tap(find.text('gün').last);
    await t.pumpAndSettle();

    await t.tap(find.text('Kaydet'));
    await t.pumpAndSettle();

    expect(svc.saved, hasLength(1));
    expect(svc.saved.single['id'], isNull);
    expect(svc.saved.single['delay'], 2880);
    expect(svc.saved.single['title'], 'İkinci gün {ad}');
    expect(svc.saved.single['voice'], isNull);
    expect(find.text('Adım eklendi'), findsOneWidget);
  });
}
