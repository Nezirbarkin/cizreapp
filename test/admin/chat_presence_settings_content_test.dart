import 'dart:convert';

import 'package:cizreapp/features/admin/widgets/chat_presence_settings_content.dart';
import 'package:cizreapp/features/chat/models/chat_presence.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Sahte sunucu: `admin_set_chat_presence_setting` yazımlarını kaydeder ve
/// sonraki okumalara yansıtır (gerçek RPC gibi güncel ayarları döner).
class _FakeServer {
  final writes = <({String key, String value})>[];
  bool failWrites = false;
  bool failReads = false;

  static const _keys = {
    'chat_presence_last_seen_enabled': 'last_seen',
    'chat_presence_last_seen_in_chat': 'last_seen_in_chat',
    'chat_presence_last_seen_in_profile': 'last_seen_in_profile',
    'chat_presence_last_seen_max_days': 'last_seen_max_days',
    'chat_presence_online_enabled': 'online',
    'chat_presence_typing_enabled': 'typing',
    'chat_presence_typing_in_groups': 'typing_in_groups',
  };

  Map<String, dynamic> cfg = _defaults();

  static Map<String, dynamic> _defaults() => {
    'last_seen': true,
    'last_seen_in_chat': true,
    'last_seen_in_profile': true,
    'last_seen_max_days': 7,
    'online': true,
    'typing': true,
    'typing_in_groups': true,
  };

  void reset() {
    writes.clear();
    failWrites = false;
    failReads = false;
    cfg = _defaults();
  }

  MockClient client() => MockClient((req) async {
    final name = req.url.pathSegments.last;
    Object body = [];
    var status = 200;

    if (failReads && name == 'get_chat_presence_settings') {
      return http.Response(
        jsonEncode({'message': 'boom', 'code': 'XX000'}),
        500,
        request: req,
        headers: {'content-type': 'application/json'},
      );
    }

    switch (name) {
      case 'get_chat_presence_settings':
        body = cfg;
      case 'admin_chat_presence_stats':
        body = {
          'total': 173,
          'online_now': 4,
          'last_seen_hidden': 12,
          'last_seen_friends': 7,
          'typing_off': 3,
          'ghost': 2,
          'online_off': 5,
        };
      case 'admin_set_chat_presence_setting':
        if (failWrites) {
          return http.Response(
            jsonEncode({'message': 'admin required', 'code': '42501'}),
            403,
            request: req,
            headers: {'content-type': 'application/json'},
          );
        }
        final params = jsonDecode(req.body) as Map<String, dynamic>;
        final key = params['p_key'] as String;
        final value = params['p_value'] as String;
        writes.add((key: key, value: value));
        final field = _keys[key]!;
        cfg = {...cfg, field: key.endsWith('max_days') ? int.parse(value) : value == 'true'};
        body = cfg;
    }
    return http.Response(
      jsonEncode(body),
      status,
      request: req,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  });
}

late _FakeServer _server;

Future<void> _open(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    const MaterialApp(home: Scaffold(body: ChatPresenceSettingsContent())),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pumpAndSettle();
}

// Ekrandaki sıra: 0 son görülme, 1 sohbette, 2 profilde, 3 çevrimiçi, 4 yazıyor, 5 grup
Switch _switchAt(WidgetTester tester, int index) =>
    tester.widget<Switch>(find.byType(Switch).at(index));

String _chatLine(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const ValueKey('preview-chat-line'))).data!;

String _profileLine(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const ValueKey('preview-profile-line'))).data!;

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    _server = _FakeServer();
    await Supabase.initialize(
      url: 'https://test.invalid',
      publishableKey: 'test-publishable-key',
      httpClient: _server.client(),
    );
  });

  setUp(() => _server.reset());

  testWidgets('bölümler, özet kutuları ve varsayılan önizleme görünür', (tester) async {
    await _open(tester);
    expect(find.text('Kullanıcılar böyle görür'), findsOneWidget);
    expect(find.text('Son görülme'), findsWidgets);
    expect(find.text('Çevrimiçi durumu'), findsWidgets);
    expect(find.text('Yazıyor… göstergesi'), findsWidgets);
    expect(find.text('7 gün'), findsWidgets, reason: 'süre sınırı adımlayıcısı + hazır seçim');

    // Özet
    expect(find.text('173 kullanıcı üzerinden (botlar hariç)'), findsOneWidget);
    expect(find.text('Şu an çevrimiçi'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);

    // Varsayılan senaryo: çevrimiçi → her iki ekranda da görünür
    expect(_chatLine(tester), 'çevrimiçi');
    expect(_profileLine(tester), 'çevrimiçi');
    expect(
      List.generate(6, (i) => _switchAt(tester, i).value),
      everyElement(isTrue),
    );
  });

  testWidgets('ana anahtar kapanınca: doğru anahtar/değer yazılır, alt anahtarlar kilitlenir, önizleme boşalır', (tester) async {
    await _open(tester);
    await tester.tap(find.byType(Switch).at(0));
    await tester.pumpAndSettle();

    expect(_server.writes, [
      (key: 'chat_presence_last_seen_enabled', value: 'false'),
    ]);
    expect(_switchAt(tester, 0).value, isFalse);
    expect(_switchAt(tester, 1).onChanged, isNull, reason: 'ana anahtar kapalıyken alt anahtar kilitli');
    expect(_switchAt(tester, 2).onChanged, isNull);
    // Alt anahtarların kendi değeri KORUNUR (yalnız etkisiz)
    expect(_switchAt(tester, 1).value, isTrue);

    await tester.tap(find.text('Dün çıktı'));
    await tester.pumpAndSettle();
    expect(_chatLine(tester), 'hiçbir durum gösterilmez');
    expect(_profileLine(tester), 'hiçbir durum gösterilmez');

    // Çevrimiçi senaryosu son görülmeden bağımsız: hâlâ görünür
    await tester.tap(find.text('Çevrimiçi'));
    await tester.pumpAndSettle();
    expect(_chatLine(tester), 'çevrimiçi');
  });

  testWidgets('sohbette kapalı, profilde açık: önizleme ekranlara göre ayrışır', (tester) async {
    await _open(tester);
    await tester.tap(find.byType(Switch).at(1)); // sohbet ekranında göster → kapat
    await tester.pumpAndSettle();
    expect(_server.writes.single, (key: 'chat_presence_last_seen_in_chat', value: 'false'));

    await tester.tap(find.text('Dün çıktı'));
    await tester.pumpAndSettle();
    expect(_chatLine(tester), 'hiçbir durum gösterilmez');
    expect(_profileLine(tester), startsWith('son görülme dün'));
  });

  testWidgets('9 gün önce: varsayılan 7 günlük sınırda GİZLİ; süre 14 yapılınca görünür', (tester) async {
    await _open(tester);
    await tester.tap(find.text('9 gün önce'));
    await tester.pumpAndSettle();
    expect(_chatLine(tester), 'hiçbir durum gösterilmez');
    expect(_profileLine(tester), 'hiçbir durum gösterilmez');

    await tester.tap(find.widgetWithText(ChoiceChip, '14 gün'));
    await tester.pumpAndSettle();
    expect(_server.writes.single, (key: 'chat_presence_last_seen_max_days', value: '14'));
    expect(_chatLine(tester), matches(RegExp(r'^son görülme \d{2}\.\d{2}\.\d{4}$')));
    expect(_profileLine(tester), matches(RegExp(r'^son görülme \d{2}\.\d{2}\.\d{4}$')));
  });

  testWidgets('süre adımlayıcısı bir gün artırır/azaltır ve sunucunun döndürdüğü değeri gösterir', (tester) async {
    await _open(tester);
    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();
    expect(_server.writes.last, (key: 'chat_presence_last_seen_max_days', value: '8'));

    await tester.tap(find.byIcon(Icons.remove_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.remove_rounded));
    await tester.pumpAndSettle();
    expect(_server.writes.last, (key: 'chat_presence_last_seen_max_days', value: '6'));
    expect(find.text('6 gün'), findsWidgets);
  });

  testWidgets('süre 1 günde azaltma düğmesi pasif', (tester) async {
    _server.cfg = {..._server.cfg, 'last_seen_max_days': 1};
    await _open(tester);
    final minus = tester.widget<IconButton>(
      find.ancestor(of: find.byIcon(Icons.remove_rounded), matching: find.byType(IconButton)),
    );
    expect(minus.onPressed, isNull);
  });

  testWidgets('süre 365 günde artırma düğmesi pasif', (tester) async {
    _server.cfg = {..._server.cfg, 'last_seen_max_days': 365};
    await _open(tester);
    final plus = tester.widget<IconButton>(
      find.ancestor(of: find.byIcon(Icons.add_rounded), matching: find.byType(IconButton)),
    );
    expect(plus.onPressed, isNull);
  });

  testWidgets('çevrimiçi kapanınca çevrimiçi önizlemesi boşalır; yazıyor ayrı çalışır', (tester) async {
    await _open(tester);
    await tester.tap(find.byType(Switch).at(3));
    await tester.pumpAndSettle();
    expect(_server.writes.single, (key: 'chat_presence_online_enabled', value: 'false'));
    expect(_chatLine(tester), 'hiçbir durum gösterilmez');

    await tester.tap(find.text('Yazıyor'));
    await tester.pumpAndSettle();
    expect(_chatLine(tester), 'yazıyor…');
    expect(_profileLine(tester), 'hiçbir durum gösterilmez', reason: 'yazıyor yalnız sohbet ekranında');
  });

  testWidgets('yazıyor kapanınca grup anahtarı kilitlenir', (tester) async {
    await _open(tester);
    await tester.tap(find.byType(Switch).at(4));
    await tester.pumpAndSettle();
    expect(_server.writes.single, (key: 'chat_presence_typing_enabled', value: 'false'));
    expect(_switchAt(tester, 5).onChanged, isNull);
    expect(_switchAt(tester, 5).value, isTrue, reason: 'alt anahtarın değeri korunur');

    await tester.tap(find.text('Yazıyor'));
    await tester.pumpAndSettle();
    expect(_chatLine(tester), 'hiçbir durum gösterilmez');
  });

  testWidgets('grup anahtarı doğru anahtarı yazar', (tester) async {
    await _open(tester);
    await tester.tap(find.byType(Switch).at(5));
    await tester.pumpAndSettle();
    expect(_server.writes.single, (key: 'chat_presence_typing_in_groups', value: 'false'));
  });

  testWidgets('yazım başarısız olursa hata gösterilir ve anahtar eski konumunda kalır', (tester) async {
    await _open(tester);
    _server.failWrites = true;
    await tester.tap(find.byType(Switch).at(0));
    await tester.pumpAndSettle();

    expect(find.textContaining('Kaydedilemedi'), findsOneWidget);
    expect(_switchAt(tester, 0).value, isTrue, reason: 'sunucu reddetti; ekran aynı kaldı');
    expect(_switchAt(tester, 0).onChanged, isNotNull, reason: 'meşguliyet bitti, yeniden denenebilir');
  });

  testWidgets('ayarlar okunamazsa "Yeniden dene" gösterilir ve sunucu düzelince yüklenir', (tester) async {
    _server.failReads = true;
    await _open(tester);
    expect(find.text('Ayarlar okunamadı'), findsOneWidget);
    expect(find.byType(Switch), findsNothing, reason: '"okunamadı" ile "kapalı" karışmamalı: anahtar çizilmez');

    _server.failReads = false;
    await tester.tap(find.text('Yeniden dene'));
    await tester.pumpAndSettle();
    expect(find.text('Ayarlar okunamadı'), findsNothing);
    expect(_switchAt(tester, 0).value, isTrue);
  });

  group('previewLine (saf mantık)', () {
    final now = DateTime.utc(2026, 9, 21, 12, 0);
    const on = ChatPresenceSettings();

    String? line(ChatPresenceSettings s, PresenceContext c, PresencePreviewScenario sc) =>
        presencePreviewLine(s, c, sc, now: now);

    test('çevrimiçi yalnız çevrimiçi anahtarına bağlı', () {
      expect(line(on, PresenceContext.chat, PresencePreviewScenario.online), 'çevrimiçi');
      expect(line(on.copyWith(online: false), PresenceContext.chat, PresencePreviewScenario.online), isNull);
      // son görülme kapalıyken de çevrimiçi görünür
      expect(line(on.copyWith(lastSeen: false), PresenceContext.chat, PresencePreviewScenario.online), 'çevrimiçi');
    });

    test('dün: 1 gün sınırın içinde', () {
      expect(
        line(on, PresenceContext.chat, PresencePreviewScenario.recent),
        startsWith('son görülme dün'),
      );
      expect(line(on.copyWith(lastSeenMaxDays: 1), PresenceContext.chat, PresencePreviewScenario.recent), isNotNull);
    });

    test('9 gün önce: sınır 7 iken yok, 9 ve üstünde var (sınır DAHİL)', () {
      expect(line(on, PresenceContext.chat, PresencePreviewScenario.old), isNull);
      expect(line(on.copyWith(lastSeenMaxDays: 8), PresenceContext.chat, PresencePreviewScenario.old), isNull);
      expect(line(on.copyWith(lastSeenMaxDays: 9), PresenceContext.chat, PresencePreviewScenario.old), '''son görülme 12.09.2026''');
      expect(line(on.copyWith(lastSeenMaxDays: 30), PresenceContext.chat, PresencePreviewScenario.old), '''son görülme 12.09.2026''');
    });

    test('bağlam anahtarları ekranları ayırır', () {
      final noChat = on.copyWith(lastSeenInChat: false);
      expect(line(noChat, PresenceContext.chat, PresencePreviewScenario.recent), isNull);
      expect(line(noChat, PresenceContext.profile, PresencePreviewScenario.recent), isNotNull);
      final noProfile = on.copyWith(lastSeenInProfile: false);
      expect(line(noProfile, PresenceContext.profile, PresencePreviewScenario.recent), isNull);
      expect(line(noProfile, PresenceContext.chat, PresencePreviewScenario.recent), isNotNull);
    });

    test('yazıyor yalnız sohbette ve yalnız açıkken', () {
      expect(line(on, PresenceContext.chat, PresencePreviewScenario.typing), 'yazıyor…');
      expect(line(on, PresenceContext.profile, PresencePreviewScenario.typing), isNull);
      expect(line(on.copyWith(typing: false), PresenceContext.chat, PresencePreviewScenario.typing), isNull);
    });
  });
}
