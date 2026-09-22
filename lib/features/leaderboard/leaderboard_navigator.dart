import 'package:flutter/material.dart';

import '../market/screens/shop_detail_screen.dart';
import '../profile/screens/user_profile_screen.dart';
import '../social/screens/post_detail_screen.dart';
import '../social/screens/story_viewer_screen.dart';
import '../social/services/post_service.dart';
import 'models/leaderboard_models.dart';
import 'services/leaderboard_service.dart';

/// Liderler Tablosu'ndaki bir satıra dokununca doğru ekranı açar.
///
/// Bu dosya `leaderboard.dart` barrel'ından BİLEREK dışarıda: ağır ekranları
/// (profil, dükkan, gönderi, hikaye) içe aktarır. Bölüm widget'ı ([HomeLeaderboardSection])
/// bunu kendisi çağırmaz, çağıran verir — böylece bölüm ve testleri uygulamanın
/// geri kalanını derlemeden çalışır.
///
/// * kullanıcı -> profil, dükkan -> dükkan sayfası
/// * gönderi -> gönderi detayı
/// * hikaye -> hikaye görüntüleyici (yalnız hâlâ yayındaysa; süresi dolmuş
///   hikaye yeniden açılmaz)
Future<void> openLeaderboardEntry(
  BuildContext context,
  LeaderboardEntry entry,
) async {
  final navigator = Navigator.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);

  void push(Widget screen) =>
      navigator.push(MaterialPageRoute(builder: (_) => screen));

  switch (entry.type) {
    case LeaderboardEntityType.user:
      push(UserProfileScreen(userId: entry.id));
    case LeaderboardEntityType.shop:
      push(ShopDetailScreen(shopId: entry.id));
    case LeaderboardEntityType.post:
      final post = await PostService().getPostById(entry.id);
      if (!context.mounted) return;
      if (post == null) {
        messenger?.showSnackBar(
          const SnackBar(content: Text('Bu gönderi artık görüntülenemiyor.')),
        );
        return;
      }
      push(PostDetailScreen(post: post));
    case LeaderboardEntityType.story:
      final story = await LeaderboardService.fetchLiveStory(entry.id);
      if (!context.mounted) return;
      if (story == null) {
        messenger?.showSnackBar(
          const SnackBar(content: Text('Bu hikaye artık yayında değil.')),
        );
        return;
      }
      push(StoryViewerScreen(stories: [story]));
  }
}
