import 'package:cizreapp/features/social/models/follow_suggestion.dart';
import 'package:cizreapp/features/social/services/follow_service.dart';
import 'package:cizreapp/features/social/widgets/follow_suggestions_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_fonts.dart';

/// Görev 3.5 — ana sayfa "Önerilen Kişiler" kartları.

class _FakeFollowService extends FollowService {
  _FakeFollowService({this.userId = 'me'});

  String? userId;
  List<FollowSuggestion> items = [];
  int loads = 0;
  final List<String> calls = [];
  Object? followError;
  FollowStatus followResult = FollowStatus.following;

  @override
  String? get currentUserId => userId;

  @override
  Future<List<FollowSuggestion>> suggestions({int limit = 10}) async {
    loads++;
    return items;
  }

  @override
  Future<FollowResult> follow(String userId) async {
    calls.add('follow:$userId');
    if (followError != null) throw followError!;
    return FollowResult(followResult, 1);
  }

  @override
  Future<FollowResult> unfollow(String userId) async {
    calls.add('unfollow:$userId');
    return const FollowResult(FollowStatus.none, 0);
  }

  @override
  Future<void> dismissSuggestion(String userId) async => calls.add('dismiss:$userId');
}

FollowSuggestion _s(String id, {FollowSuggestionReason reason = FollowSuggestionReason.mutual, bool private = false, bool followsYou = false}) =>
    FollowSuggestion(
      id: id,
      username: 'kisi_$id',
      fullName: 'Kişi $id',
      isPrivate: private,
      followsYou: followsYou,
      mutualCount: 2,
      mutualNames: const ['ayse'],
      followersCount: 15,
      reason: reason,
    );

void main() {
  setUpAll(loadTestFonts);

  Future<List<String>> pump(WidgetTester tester, _FakeFollowService service, {int tick = 0}) async {
    tester.view.physicalSize = const Size(700, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final opened = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeFollowSuggestionsSection(
            service: service,
            refreshTick: tick,
            openProfile: (_, id) => opened.add(id),
          ),
        ),
      ),
    );
    await tester.pump();
    return opened;
  }

  testWidgets('kartlar: ad, kullanıcı adı, gerekçe, düğme etiketi', (tester) async {
    final service = _FakeFollowService()
      ..items = [
        _s('1', reason: FollowSuggestionReason.followsYou, followsYou: true),
        _s('2'),
        _s('3', private: true, reason: FollowSuggestionReason.popular),
      ];
    await pump(tester, service);
    expect(find.text('Önerilen Kişiler'), findsOneWidget);
    expect(find.text('Kişi 1'), findsOneWidget);
    expect(find.text('@kisi_1'), findsOneWidget);
    expect(find.text('Seni takip ediyor'), findsOneWidget);
    expect(find.text('Geri Takip Et'), findsOneWidget);
    expect(find.text('ayse ve 1 kişi daha takip ediyor'), findsOneWidget);
    expect(find.text('Takip Et'), findsOneWidget);
    expect(find.text('15 takipçi'), findsOneWidget);
    expect(find.text('İstek Gönder'), findsOneWidget);
  });

  testWidgets('takip et → Takip Ediliyor; tekrar dokununca geri alınır', (tester) async {
    final service = _FakeFollowService()..items = [_s('2')];
    await pump(tester, service);
    await tester.tap(find.text('Takip Et'));
    await tester.pump();
    await tester.pump();
    expect(service.calls, ['follow:2']);
    expect(find.text('Takip Ediliyor'), findsOneWidget);
    await tester.tap(find.text('Takip Ediliyor'));
    await tester.pump();
    await tester.pump();
    expect(service.calls, ['follow:2', 'unfollow:2']);
    expect(find.text('Takip Et'), findsOneWidget);
  });

  testWidgets('gizli hesap: İstek Gönderildi ve bilgi mesajı', (tester) async {
    final service = _FakeFollowService()
      ..items = [_s('3', private: true)]
      ..followResult = FollowStatus.requested;
    await pump(tester, service);
    await tester.tap(find.text('İstek Gönder'));
    await tester.pump();
    await tester.pump();
    expect(find.text('İstek Gönderildi'), findsOneWidget);
    expect(find.text('Kişi 3 gizli hesap; takip isteği gönderildi.'), findsOneWidget);
  });

  testWidgets('hata: mesaj gösterilir, düğme eski hâlinde kalır', (tester) async {
    final service = _FakeFollowService()
      ..items = [_s('2')]
      ..followError = const FollowException('Bu kullanıcıyı takip edemezsin.', 'FOLLOW_BLOCKED');
    await pump(tester, service);
    await tester.tap(find.text('Takip Et'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Bu kullanıcıyı takip edemezsin.'), findsOneWidget);
    expect(find.text('Takip Et'), findsOneWidget);
  });

  testWidgets('kaldır: kart hemen gider, sunucuya bildirilir; son kart gidince bölüm kapanır', (tester) async {
    final service = _FakeFollowService()..items = [_s('2')];
    await pump(tester, service);
    await tester.tap(find.byTooltip('Öneriyi kaldır'));
    await tester.pump();
    expect(service.calls, ['dismiss:2']);
    expect(find.text('Kişi 2'), findsNothing);
    expect(find.text('Önerilen Kişiler'), findsNothing);
  });

  testWidgets('profile dokunma; misafir ve boş listede bölüm yok', (tester) async {
    final service = _FakeFollowService()..items = [_s('2')];
    final opened = await pump(tester, service);
    await tester.tap(find.text('Kişi 2'));
    expect(opened, ['2']);

    final guest = _FakeFollowService(userId: null)..items = [_s('2')];
    await tester.pumpWidget(const SizedBox());
    await pump(tester, guest);
    expect(find.text('Önerilen Kişiler'), findsNothing);
    expect(guest.loads, 0, reason: 'misafirde sunucuya gidilmez');

    await tester.pumpWidget(const SizedBox());
    await pump(tester, _FakeFollowService());
    expect(find.text('Önerilen Kişiler'), findsNothing);
  });

  testWidgets('ana sayfa yenilenince (refreshTick) öneriler yeniden yüklenir', (tester) async {
    final service = _FakeFollowService()..items = [_s('2')];
    await pump(tester, service);
    expect(service.loads, 1);
    service.items = [_s('5')];
    await pump(tester, service, tick: 1);
    expect(service.loads, 2);
    expect(find.text('Kişi 5'), findsOneWidget);
  });
}
