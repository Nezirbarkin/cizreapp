import 'package:cizreapp/core/models/live_shopping_model.dart';
import 'package:cizreapp/features/admin/services/admin_live_service.dart';
import 'package:cizreapp/features/admin/widgets/admin_live_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Görev 4.3 — Admin > Canlı Yayınlar ekranı.

String _iso(DateTime value) => value.toUtc().toIso8601String();

Map<String, dynamic> _session(
  String id, {
  required String title,
  String status = 'live',
  String shop = 'Çay Evi',
  String shopId = 'shop-1',
  int viewers = 12,
  int peak = 30,
  String? endedReason,
  String? endedNote,
  String? endedBy,
  String access = 'ok',
}) {
  final now = DateTime.now();
  return {
    'id': id,
    'shop_id': shopId,
    'host_user_id': 'owner-$shopId',
    'title': title,
    'channel_name': 'cz_$id',
    'status': status,
    'is_live': status == 'live',
    'started_at': _iso(now.subtract(const Duration(minutes: 20))),
    'ended_at': status == 'ended' ? _iso(now.subtract(const Duration(minutes: 2))) : null,
    'ended_reason': endedReason,
    'viewer_count': status == 'live' ? viewers : 0,
    'peak_viewer_count': peak,
    'created_at': _iso(now.subtract(const Duration(minutes: 25))),
    'shop_name': shop,
    'pinned_product': status == 'live'
        ? {'id': 'p1', 'name': 'Demlik', 'price': 250, 'effective_price': 250, 'is_available': true}
        : null,
    'host_name': 'Ayşe Yılmaz',
    'host_username': 'ayse',
    'message_count': 41,
    'duration_seconds': 1200,
    'ended_note': endedNote,
    'ended_by_name': endedBy,
    'shop_access': access,
  };
}

Map<String, dynamic> _shop(
  String id, {
  required String name,
  String? permission,
  String effective = 'ok',
  String? note,
  int sessions = 0,
  String? liveId,
}) => {
  'shop_id': id,
  'shop_name': name,
  'is_active': true,
  'is_approved': true,
  'owner_name': 'Sahip $name',
  'permission': permission,
  'note': note,
  'effective': effective,
  'session_count': sessions,
  'last_live_at': sessions > 0 ? _iso(DateTime.now().subtract(const Duration(hours: 3))) : null,
  'live_session_id': liveId,
};

class _FakeLiveAdminService extends AdminLiveService {
  final calls = <String>[];
  bool enabled = true;
  String access = 'open';

  final live = <Map<String, dynamic>>[
    _session('s1', title: 'Yeni sezon çaydanlıklar'),
  ];
  final ended = <Map<String, dynamic>>[
    _session(
      'e1',
      title: 'Hafta sonu indirimi',
      status: 'ended',
      endedReason: 'admin',
      endedNote: 'Uygunsuz içerik',
      endedBy: 'Yönetici Ali',
    ),
  ];
  final shops = <Map<String, dynamic>>[
    _shop('shop-1', name: 'Çay Evi', sessions: 3, liveId: 's1'),
    _shop('shop-2', name: 'Dicle Kebap', permission: 'revoked', effective: 'LIVE_REVOKED', note: 'Kural ihlali'),
  ];

  String userMode = 'open';

  final users = <Map<String, dynamic>>[
    {'user_id': 'u1', 'username': 'zeynep', 'full_name': 'Zeynep K.', 'effective': 'ok', 'session_count': 2},
    {
      'user_id': 'u2',
      'username': 'mehmet',
      'permission': 'revoked',
      'note': 'Şikayet',
      'effective': 'LIVE_USER_REVOKED',
      'session_count': 1,
    },
  ];

  Map<String, dynamic> get _settings => {'enabled': enabled, 'access': access, 'user_mode': userMode};

  @override
  Future<AdminLiveUsersPage> fetchUsers({String? search, String filter = 'all', int limit = 30, int offset = 0}) async {
    calls.add('users:$filter:${(search ?? '').trim()}');
    final rows = users.where((u) => switch (filter) {
      'granted' => u['permission'] == 'granted',
      'revoked' => u['permission'] == 'revoked',
      _ => true,
    }).toList();
    return AdminLiveUsersPage.fromJson({
      'total': rows.length,
      'rows': rows,
      'summary': {
        'granted': users.where((u) => u['permission'] == 'granted').length,
        'revoked': users.where((u) => u['permission'] == 'revoked').length,
      },
      'settings': _settings,
    });
  }

  @override
  Future<AdminLiveChange> setUserPermission(String userId, String permission, {String? note}) async {
    calls.add('user-permission:$userId:$permission:${note ?? ''}');
    var closed = 0;
    if (permission == 'revoked') {
      closed = live.where((r) => r['host_user_id'] == userId && r['shop_id'] == null).length;
      live.removeWhere((r) => r['host_user_id'] == userId && r['shop_id'] == null);
    }
    final index = users.indexWhere((u) => u['user_id'] == userId);
    final effective = permission == 'revoked' ? 'LIVE_USER_REVOKED' : 'ok';
    if (index >= 0) {
      users[index] = {
        ...users[index],
        'permission': permission == 'default' ? null : permission,
        'note': note,
        'effective': effective,
      };
    }
    return AdminLiveChange(closed: closed, effective: LiveShopAccess.fromCode(effective));
  }

  @override
  Future<AdminLiveChange> setUserMode(String mode, {bool closeRunning = false}) async {
    calls.add('user-mode:$mode:$closeRunning');
    userMode = mode;
    return const AdminLiveChange();
  }

  Map<String, dynamic> options = {
    'notify_enabled': true,
    'notify_cooldown_hours': 3,
    'notify_followers': true,
    'notify_product_fans': true,
    'notify_customers': false,
    'notify_max_recipients': 2000,
    'home_card_enabled': true,
    'history_days': 30,
    'stats': {
      'subscriptions': 14,
      'subscribed_shops': 5,
      'notifications_30d': 7,
      'recipients_30d': 230,
      'cooldown_skips_30d': 2,
    },
  };

  @override
  Future<AdminLiveOptions> fetchOptions() async {
    calls.add('options');
    return AdminLiveOptions.fromJson(options);
  }

  @override
  Future<AdminLiveOptions> saveOptions(Map<String, Object> changes) async {
    calls.add('options:${changes.entries.map((e) => '${e.key}=${e.value}').join(',')}');
    options = {...options, ...changes};
    return AdminLiveOptions.fromJson(options);
  }

  @override
  Future<AdminLiveSessionsPage> fetchSessions(String status, {int limit = 30, int offset = 0}) async {
    calls.add('sessions:$status');
    final rows = status == 'live' ? live : ended;
    return AdminLiveSessionsPage.fromJson({
      'total': rows.length,
      'rows': rows,
      'summary': {
        'live_now': live.length,
        'preparing': 0,
        'today': 4,
        'minutes_7d': 340,
        'admin_closed_30d': 1,
        'granted_shops': shops.where((s) => s['permission'] == 'granted').length,
        'revoked_shops': shops.where((s) => s['permission'] == 'revoked').length,
      },
      'settings': _settings,
    });
  }

  @override
  Future<AdminLiveShopsPage> fetchShops({String? search, String filter = 'all', int limit = 30, int offset = 0}) async {
    final query = (search ?? '').trim().toLowerCase();
    calls.add('shops:$filter:$query');
    final rows = shops.where((s) {
      final nameOk = query.isEmpty || (s['shop_name'] as String).toLowerCase().contains(query);
      final filterOk = switch (filter) {
        'granted' => s['permission'] == 'granted',
        'revoked' => s['permission'] == 'revoked',
        'streamed' => (s['session_count'] as int) > 0,
        _ => true,
      };
      return nameOk && filterOk;
    }).toList();
    return AdminLiveShopsPage.fromJson({
      'total': rows.length,
      'rows': rows,
      'summary': {
        'granted': shops.where((s) => s['permission'] == 'granted').length,
        'revoked': shops.where((s) => s['permission'] == 'revoked').length,
      },
      'settings': _settings,
    });
  }

  @override
  Future<String> endSession(String sessionId, {String? note}) async {
    calls.add('end:$sessionId:${note ?? ''}');
    final row = live.firstWhere((r) => r['id'] == sessionId);
    live.remove(row);
    ended.insert(0, {...row, 'status': 'ended', 'ended_reason': 'admin', 'ended_note': note});
    return 'ended';
  }

  @override
  Future<AdminLiveChange> setShopPermission(String shopId, String permission, {String? note}) async {
    calls.add('permission:$shopId:$permission:${note ?? ''}');
    final index = shops.indexWhere((s) => s['shop_id'] == shopId);
    var closed = 0;
    if (permission == 'revoked') {
      closed = live.where((r) => r['shop_id'] == shopId).length;
      live.removeWhere((r) => r['shop_id'] == shopId);
    }
    final effective = switch (permission) {
      'revoked' => 'LIVE_REVOKED',
      'granted' => 'ok',
      _ => access == 'invite' ? 'LIVE_NOT_PERMITTED' : 'ok',
    };
    shops[index] = {
      ...shops[index],
      'permission': permission == 'default' ? null : permission,
      'note': note,
      'effective': effective,
      if (permission == 'revoked') 'live_session_id': null,
    };
    return AdminLiveChange(closed: closed, effective: LiveShopAccess.fromCode(effective));
  }

  @override
  Future<AdminLiveChange> setSettings({bool? enabled, String? access, bool closeRunning = false}) async {
    calls.add('settings:${enabled ?? '-'}:${access ?? '-'}:$closeRunning');
    if (enabled != null) this.enabled = enabled;
    if (access != null) this.access = access;
    var closed = 0;
    if (closeRunning && !this.enabled) {
      closed = live.length;
      live.clear();
    }
    return AdminLiveChange(closed: closed, settings: AdminLiveSettings.fromJson(_settings));
  }
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<(_FakeLiveAdminService, List<String>)> _pump(
  WidgetTester tester, {
  Size size = const Size(900, 1600),
  double textScale = 1,
  void Function(_FakeLiveAdminService fake)? setup,
}) async {
  final fake = _FakeLiveAdminService();
  setup?.call(fake);
  final watched = <String>[];
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: AdminLiveContent(
          service: fake,
          openViewer: (_, LiveSession session) => watched.add(session.id),
        ),
      ),
    ),
  );
  await _settle(tester);
  return (fake, watched);
}

Future<void> _openTab(WidgetTester tester, String label) async {
  await tester.tap(find.widgetWithText(Tab, label));
  await _settle(tester);
}

void main() {
  testWidgets('Yayında: kart, özet ve izle', (tester) async {
    final (fake, watched) = await _pump(tester);

    expect(fake.calls.first, 'sessions:live');
    expect(find.widgetWithText(Tab, 'Yayında (1)'), findsOneWidget);
    expect(find.text('Yeni sezon çaydanlıklar'), findsOneWidget);
    expect(find.text('Çay Evi · Ayşe Yılmaz'), findsOneWidget);
    expect(find.text('CANLI'), findsOneWidget);
    expect(find.text('12 izleyici'), findsOneWidget);
    expect(find.text('41 mesaj'), findsOneWidget);
    expect(find.text('Sabit ürün: Demlik'), findsOneWidget);
    expect(find.text('340'), findsOneWidget, reason: '7 günlük dakika');
    expect(find.byKey(const ValueKey('live-disabled-banner')), findsNothing);

    await tester.tap(find.text('İzle'));
    await _settle(tester);
    expect(watched, ['s1']);
  });

  testWidgets('Yayını kapat: not satıcıya gider, liste yenilenir', (tester) async {
    final (fake, _) = await _pump(tester);

    await tester.tap(find.text('Yayını kapat'));
    await _settle(tester);
    expect(find.text('Yayın kapatılsın mı?'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('live-close-note')), '  Uygunsuz içerik ');
    await tester.tap(find.widgetWithText(FilledButton, 'Kapat'));
    await _settle(tester);

    expect(fake.calls, contains('end:s1:Uygunsuz içerik'));
    expect(find.text('Yayın kapatıldı'), findsOneWidget);
    expect(find.text('Şu an canlı yayın yok'), findsOneWidget);
    expect(find.widgetWithText(Tab, 'Yayında'), findsOneWidget);
  });

  testWidgets('Yayını kapat + izni kaldır: tek işlemde mağaza izni kalkar', (tester) async {
    final (fake, _) = await _pump(tester);

    await tester.tap(find.text('Yayını kapat'));
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('live-close-revoke')));
    await _settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Kapat'));
    await _settle(tester);

    expect(fake.calls, contains('permission:shop-1:revoked:'));
    expect(fake.calls.where((c) => c.startsWith('end:')), isEmpty, reason: 'izin kaldırma yayını da kapatır');
    expect(find.text('Yayın kapatıldı ve mağazanın izni kaldırıldı'), findsOneWidget);
  });

  testWidgets('Geçmiş: bitiş nedeni, not ve kapatan', (tester) async {
    await _pump(tester);
    await _openTab(tester, 'Geçmiş');

    expect(find.text('Hafta sonu indirimi'), findsOneWidget);
    expect(find.text('Yönetici kapattı'), findsOneWidget);
    expect(find.text('Not: Uygunsuz içerik'), findsOneWidget);
    expect(find.text('Kapatan: Yönetici Ali'), findsOneWidget);
    expect(find.text('En çok 30 izleyici'), findsOneWidget);
    expect(find.text('Yayını kapat'), findsNothing);
  });

  testWidgets('Mağaza İzinleri: arama, süzgeç, izni kaldır (notlu) ve varsayılana dön', (tester) async {
    final (fake, _) = await _pump(tester);
    await _openTab(tester, 'Mağaza İzinleri');

    expect(fake.calls, contains('shops:all:'));
    expect(find.text('Çay Evi'), findsOneWidget);
    expect(find.text('Dicle Kebap'), findsOneWidget);
    expect(find.text('İzni kaldırıldı'), findsOneWidget);
    expect(find.text('Not: Kural ihlali'), findsOneWidget);
    expect(find.text('3 yayın · son: '), findsNothing);
    expect(find.textContaining('3 yayın · son:'), findsOneWidget);

    // Arama 350 ms gecikmeli
    await tester.enterText(find.byKey(const ValueKey('live-shops-search')), 'dicle');
    await tester.pump(const Duration(milliseconds: 200));
    expect(fake.calls.where((c) => c == 'shops:all:dicle'), isEmpty);
    await _settle(tester);
    expect(fake.calls, contains('shops:all:dicle'));
    expect(find.text('Çay Evi'), findsNothing);
    await tester.tap(find.byTooltip('Temizle'));
    await _settle(tester);

    // Süzgeç
    await tester.tap(find.byKey(const ValueKey('live-shops-filter-revoked')));
    await _settle(tester);
    expect(fake.calls, contains('shops:revoked:'));
    expect(find.text('Çay Evi'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('live-shops-filter-all')));
    await _settle(tester);

    // Çay Evi: izni kaldır (canlı → uyarı), not
    await tester.tap(find.byKey(const ValueKey('live-shop-menu-shop-1')));
    await _settle(tester);
    await tester.tap(find.text('İzni kaldır'));
    await _settle(tester);
    expect(find.textContaining('şu anki yayını da hemen kapatılır'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('live-revoke-note')), 'Spam yayın');
    await tester.tap(find.widgetWithText(FilledButton, 'İzni kaldır'));
    await _settle(tester);
    expect(fake.calls, contains('permission:shop-1:revoked:Spam yayın'));
    expect(find.text('Çay Evi: yayın izni kaldırıldı · 1 yayın kapatıldı'), findsOneWidget);

    // Dicle Kebap: varsayılana dön
    await tester.tap(find.byKey(const ValueKey('live-shop-menu-shop-2')));
    await _settle(tester);
    await tester.tap(find.text('Varsayılana döndür'));
    await _settle(tester);
    expect(fake.calls, contains('permission:shop-2:default:'));
    expect(find.text('Dicle Kebap: varsayılana döndü (Yayın açabilir)'), findsOneWidget);
  });

  testWidgets('Mağaza menüsü: mevcut durum seçilemez', (tester) async {
    await _pump(tester);
    await _openTab(tester, 'Mağaza İzinleri');
    await tester.tap(find.byKey(const ValueKey('live-shop-menu-shop-2')));
    await _settle(tester);

    PopupMenuItem<String> item(String text) =>
        tester.widget<PopupMenuItem<String>>(find.ancestor(of: find.text(text), matching: find.byType(PopupMenuItem<String>)));
    expect(item('İzin ver').enabled, isTrue);
    expect(item('İzni kaldır').enabled, isFalse, reason: 'zaten kaldırılmış');
    expect(item('Varsayılana döndür').enabled, isTrue);
  });

  testWidgets('Ayarlar: kapatma onayı (süren yayınlar), bant; yalnız izinliler modu', (tester) async {
    final (fake, _) = await _pump(tester);
    await _openTab(tester, 'Ayarlar');

    await tester.tap(find.byKey(const ValueKey('live-enabled')));
    await _settle(tester);
    expect(find.text('Canlı yayın kapatılsın mı?'), findsOneWidget);
    expect(
      tester.widget<CheckboxListTile>(find.byKey(const ValueKey('live-confirm-checkbox'))).value,
      isTrue,
      reason: 'süren yayınları kapatmak varsayılan',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Kapat'));
    await _settle(tester);
    expect(fake.calls, contains('settings:false:-:true'));
    expect(find.text('Canlı yayın kapatıldı · 1 yayın kapatıldı'), findsOneWidget);
    expect(find.byKey(const ValueKey('live-disabled-banner')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('live-access-invite')));
    await _settle(tester);
    expect(find.text('Yalnız izinliler moduna geçilsin mi?'), findsOneWidget);
    expect(tester.widget<CheckboxListTile>(find.byKey(const ValueKey('live-confirm-checkbox'))).value, isFalse);
    await tester.tap(find.widgetWithText(FilledButton, 'Geç'));
    await _settle(tester);
    expect(fake.calls, contains('settings:-:invite:false'));

    await tester.tap(find.byKey(const ValueKey('live-enabled')));
    await _settle(tester);
    expect(fake.calls, contains('settings:true:-:false'), reason: 'açmak onay istemez');
    expect(find.byKey(const ValueKey('live-disabled-banner')), findsNothing);
  });

  testWidgets('Ayarlar: yayın bildirimi, ana sayfa kartı ve geçmiş seçenekleri', (tester) async {
    final (fake, _) = await _pump(tester);
    await _openTab(tester, 'Ayarlar');
    expect(fake.calls, contains('options'));

    await tester.ensureVisible(find.byKey(const ValueKey('live-opt-stats')));
    await _settle(tester);
    expect(
      find.text('7 yayın bildirimi · 230 kişiye ulaştı · 2 bekleme süresine takıldı\n'
          '"Haberdar ol" aboneliği: 14 (5 mağaza)'),
      findsOneWidget,
    );

    // Bildirimi kapatmak hedef kitle ve sayı ayarlarını pasifleştirir.
    await tester.ensureVisible(find.byKey(const ValueKey('live-opt-notify')));
    await tester.tap(find.byKey(const ValueKey('live-opt-notify')));
    await _settle(tester);
    expect(fake.calls, contains('options:notify_enabled=false'));
    expect(find.text('Yayın bildirimleri kapatıldı'), findsOneWidget);
    expect(tester.widget<SwitchListTile>(find.byKey(const ValueKey('live-opt-followers'))).onChanged, isNull);
    expect(tester.widget<ListTile>(find.byKey(const ValueKey('live-opt-cooldown'))).enabled, isFalse);
    expect(tester.widget<SwitchListTile>(find.byKey(const ValueKey('live-opt-home'))).onChanged, isNotNull);

    // Ana sayfa kartı anında kaydedilir.
    await tester.ensureVisible(find.byKey(const ValueKey('live-opt-home')));
    await tester.tap(find.byKey(const ValueKey('live-opt-home')));
    await _settle(tester);
    expect(fake.calls, contains('options:home_card_enabled=false'));
    expect(find.text('Ana sayfa kartı kapatıldı'), findsOneWidget);

    // Geçmiş süresi: aralık dışı reddedilir, geçerli değer kaydedilir.
    await tester.ensureVisible(find.byKey(const ValueKey('live-opt-history')));
    await tester.tap(find.byKey(const ValueKey('live-opt-history')));
    await _settle(tester);
    await tester.enterText(find.byKey(const ValueKey('live-opt-number')), '400');
    await tester.tap(find.widgetWithText(FilledButton, 'Kaydet'));
    await _settle(tester);
    expect(find.text('1–180 arası bir sayı girin'), findsOneWidget);
    expect(fake.calls.where((c) => c.startsWith('options:history_days')), isEmpty);
    await tester.enterText(find.byKey(const ValueKey('live-opt-number')), '60');
    await tester.tap(find.widgetWithText(FilledButton, 'Kaydet'));
    await _settle(tester);
    expect(fake.calls, contains('options:history_days=60'));
    expect(find.text('Biten yayınlar 60 gün listelenir'), findsOneWidget);
    expect(find.text('Yayın geçmişi: 60 gün'), findsOneWidget);
  });

  testWidgets('Dar ekran + büyük yazı: sekmeler ve pencereler taşmaz', (tester) async {
    await _pump(tester, size: const Size(320, 568), textScale: 1.6);
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text('Yayını kapat'));
    await _settle(tester);
    await tester.tap(find.text('Yayını kapat'));
    await _settle(tester);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Vazgeç'));
    await _settle(tester);

    for (final tab in ['Geçmiş', 'Mağaza İzinleri', 'Kullanıcı İzinleri', 'Ayarlar']) {
      await tester.drag(find.byType(TabBar), const Offset(-200, 0));
      await tester.pump();
      await _openTab(tester, tab);
      expect(tester.takeException(), isNull, reason: tab);
    }
  });

  testWidgets('Kullanıcı yayını kartı: yayıncı ve rozet; kapat + izni kaldır kullanıcı iznine gider', (tester) async {
    final (fake, _) = await _pump(
      tester,
      setup: (fake) => fake.live
        ..clear()
        ..add({
          ..._session('su', title: 'Akşam sohbeti'),
          'shop_id': null,
          'shop_name': null,
          'kind': 'user',
          'host_user_id': 'u1',
          'host_display_name': 'zeynep',
          'host_username': 'zeynep',
          'pinned_product': null,
        }),
    );
    expect(find.text('Kullanıcı yayını · @zeynep'), findsOneWidget);
    expect(find.text('KULLANICI'), findsOneWidget);

    await tester.tap(find.text('Yayını kapat'));
    await _settle(tester);
    expect(find.text('Kullanıcının yayın iznini de kaldır'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('live-close-revoke')));
    await _settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Kapat'));
    await _settle(tester);

    expect(fake.calls, contains('user-permission:u1:revoked:'));
    expect(fake.calls.where((c) => c.startsWith('permission:')), isEmpty, reason: 'mağaza izni değişmez');
    expect(find.text('Yayın kapatıldı ve kullanıcının izni kaldırıldı'), findsOneWidget);
  });

  testWidgets('Kullanıcı İzinleri: liste, süzgeç, izni kaldır (notlu) ve varsayılana dön', (tester) async {
    final (fake, _) = await _pump(tester);
    await _openTab(tester, 'Kullanıcı İzinleri');

    expect(fake.calls, contains('users:all:'));
    expect(find.text('@zeynep'), findsOneWidget);
    expect(find.text('Not: Şikayet'), findsOneWidget);
    expect(find.text('İzin kaldırıldı'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('live-users-filter-revoked')));
    await _settle(tester);
    expect(fake.calls, contains('users:revoked:'));
    expect(find.text('@zeynep'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('live-users-filter-all')));
    await _settle(tester);

    await tester.tap(find.byKey(const ValueKey('live-user-menu-u1')));
    await _settle(tester);
    await tester.tap(find.text('İzni kaldır').last);
    await _settle(tester);
    expect(find.text('Yayın izni kaldırılsın mı?'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('live-revoke-note')), 'Kural dışı yayın');
    await tester.tap(find.widgetWithText(FilledButton, 'İzni kaldır'));
    await _settle(tester);
    expect(fake.calls, contains('user-permission:u1:revoked:Kural dışı yayın'));
    expect(find.text('@zeynep: yayın izni kaldırıldı'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('live-user-menu-u2')));
    await _settle(tester);
    await tester.tap(find.text('Varsayılana döndür').last);
    await _settle(tester);
    expect(fake.calls, contains('user-permission:u2:default:'));
  });

  testWidgets('Kullanıcı İzinleri: "Tüm kullanıcılar canlı yayın açabilir" anahtarı', (tester) async {
    final (fake, _) = await _pump(tester, setup: (fake) => fake.userMode = 'invite');
    await _openTab(tester, 'Kullanıcı İzinleri');

    final toggle = find.byKey(const ValueKey('live-users-all'));
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    expect(find.text('Şu an yalnız aşağıda izin verdiğiniz kullanıcılar yayın açabilir.'), findsOneWidget);

    await tester.tap(toggle);
    await _settle(tester);
    expect(fake.calls, contains('user-mode:open:false'), reason: 'herkese açmak onay istemez');
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
    expect(find.text('Tüm aktif kullanıcılar yayın açabilir'), findsOneWidget);

    await tester.tap(toggle);
    await _settle(tester);
    expect(find.text('Yalnız izinli kullanıcılar moduna geçilsin mi?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Geç'));
    await _settle(tester);
    expect(fake.calls, contains('user-mode:invite:false'));
  });

  testWidgets('Ayarlar: kullanıcı yayını modu; kapatma onaylı', (tester) async {
    final (fake, _) = await _pump(tester);
    await _openTab(tester, 'Ayarlar');

    await tester.ensureVisible(find.byKey(const ValueKey('live-user-mode-off')));
    await tester.tap(find.byKey(const ValueKey('live-user-mode-off')));
    await _settle(tester);
    expect(find.text('Kullanıcı yayınları kapatılsın mı?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Kapat'));
    await _settle(tester);
    expect(fake.calls, contains('user-mode:off:true'));
    expect(find.text('Kullanıcı yayınları kapatıldı'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const ValueKey('live-user-mode-open')));
    await tester.tap(find.byKey(const ValueKey('live-user-mode-open')));
    await _settle(tester);
    expect(fake.calls, contains('user-mode:open:false'), reason: 'açmak onay istemez');
  });
}
