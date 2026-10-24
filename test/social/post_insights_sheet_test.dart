import 'package:cizreapp/core/models/post_model.dart';
import 'package:cizreapp/features/social/services/post_insights_service.dart';
import 'package:cizreapp/features/social/widgets/post_insights_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeInsights extends PostInsightsService {
  _FakeInsights(this.data);

  final PostInsights data;

  @override
  Future<PostInsights> fetch(String postId) async => data;
}

PostInsights _sample() => PostInsights.fromJson({
      'views': 1250,
      'unique_viewers': 40,
      'detail_opens': 12,
      'likes': 8,
      'comments': 3,
      'shares': 2,
      'saves': 1,
      'follower_viewers': 10,
      'engagement_rate': 35,
      'non_follower_rate': 75,
      'daily': [
        for (var i = 6; i >= 0; i--)
          {'day': DateTime(2026, 10, 24).subtract(Duration(days: i)).toIso8601String().substring(0, 10), 'views': i * 3},
      ],
    });

void main() {
  testWidgets('kutucuklar, 7 günlük çubuklar ve erişim çizilir', (t) async {
    t.view.physicalSize = const Size(400, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final post = Post(
      id: 'p1',
      userId: 'me',
      content: 'Cizre akşamı',
      createdAt: DateTime.utc(2026, 10, 20),
      updatedAt: DateTime.utc(2026, 10, 20),
    );
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PostInsightsSheet(post: post, service: _FakeInsights(_sample())),
        ),
      ),
    );
    await t.pumpAndSettle();

    expect(find.text('Gönderi istatistikleri'), findsOneWidget);
    expect(find.text('1,2B'), findsOneWidget);
    expect(find.text('Benzersiz kişi'), findsOneWidget);
    expect(find.text('%35'), findsOneWidget);
    expect(find.text('Bugün'), findsOneWidget);
    expect(find.text('Takipçiler: 10'), findsOneWidget);
    expect(find.text('Takip etmeyenler: 30 (%75)'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  test('PostInsights.fromJson eksik alanlara dayanıklı', () {
    final p = PostInsights.fromJson(const {'views': '5', 'daily': 'x'});
    expect(p.views, 5);
    expect(p.daily, isEmpty);
    expect(p.engagementRate, isNull);
    expect(p.interactions, 0);
  });
}
