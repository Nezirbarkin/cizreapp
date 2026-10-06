import 'package:flutter/material.dart';

/// Kartın türü: sıralama listesi, sayaç kartı ya da rekorlar (Görev 4.4).
enum LeaderboardKind { ranking, stats, records }

/// Sayaç kartları üç tanedir: genel sayılar, günlük ("Bugün Cizre'de") ve
/// kişisel ("Rakamlarla Sen", Görev 4.4 — yalnız kullanıcının kendi sayıları).
/// Her [LeaderboardStat] birine aittir; kart yalnız kendi grubunun açık
/// sayaçlarını gösterir. Tümünü tek kartta göstermek karuseli çok uzatırdı.
enum LeaderboardStatGroup { general, today, personal }

/// Liderler Tablosu'ndaki kartlar (25 adet: 21 pano + 3 sayaç kartı + rekorlar;
/// 8'i 101 Okey).
///
/// Enum SIRASI varsayılan kart sırasıdır ve sunucudaki
/// `leaderboard_card_keys()` ile AYNI olmalı. [key] sunucudaki
/// `get_leaderboard(p_board)` argümanı VE `app_settings` anahtarının son
/// parçasıdır (`leaderboard_board_<key>`). Bir pano eklemek için üç yeri
/// birlikte güncelle: bu enum, migration'daki `leaderboard_card_keys()` +
/// `get_leaderboard` dalı ve (gerekirse) `leaderboard_user_counts`.
enum LeaderboardBoard {
  stats(
    key: 'stats',
    title: 'Rakamlarla Cizre',
    chipLabel: 'Sayılar',
    description: 'Üye, sipariş ve içerik sayıları',
    icon: Icons.insights_rounded,
    color: Color(0xFF6366F1),
    periodAware: false,
    kind: LeaderboardKind.stats,
    statGroup: LeaderboardStatGroup.general,
  ),
  statsToday(
    key: 'stats_today',
    title: 'Bugün Cizre’de',
    chipLabel: 'Bugün',
    description: 'Ziyaretçi ve günlük hareket sayıları',
    icon: Icons.today_rounded,
    color: Color(0xFF0891B2),
    periodAware: false,
    kind: LeaderboardKind.stats,
    statGroup: LeaderboardStatGroup.today,
  ),
  // Görev 4.4
  myStats(
    key: 'my_stats',
    title: 'Rakamlarla Sen',
    chipLabel: 'Sen',
    description: 'Senin sayıların — yalnız sana görünür',
    icon: Icons.person_pin_rounded,
    color: Color(0xFF7C3AED),
    periodAware: false,
    kind: LeaderboardKind.stats,
    statGroup: LeaderboardStatGroup.personal,
  ),
  records(
    key: 'records',
    title: 'Rekor Skorlar',
    chipLabel: 'Rekorlar',
    description: 'Cizre’nin tüm zamanlar rekorları',
    icon: Icons.military_tech_rounded,
    color: Color(0xFFD97706),
    periodAware: false,
    kind: LeaderboardKind.records,
  ),
  newMembers(
    key: 'new_members',
    title: 'Yeni Üyeler',
    chipLabel: 'Yeni Üyeler',
    description: 'En son aramıza katılanlar',
    icon: Icons.waving_hand_rounded,
    color: Color(0xFF0EA5E9),
    periodAware: false,
  ),
  topFollowed(
    key: 'top_followed',
    title: 'En Çok Takipçisi Olanlar',
    chipLabel: 'Takipçi',
    description: 'Takipçi sayısı en yüksek kullanıcılar',
    icon: Icons.groups_rounded,
    color: Color(0xFF8B5CF6),
    periodAware: false,
  ),
  topLikedPosts(
    key: 'top_liked_posts',
    title: 'En Çok Beğenilen Gönderiler',
    chipLabel: 'Beğenilen',
    description: 'En çok beğeni alan gönderiler',
    icon: Icons.favorite_rounded,
    color: Color(0xFFEF4444),
    periodAware: true,
  ),
  topViewedPosts(
    key: 'top_viewed_posts',
    title: 'En Çok Görüntülenen Gönderiler',
    chipLabel: 'Görüntülenen',
    description: 'En çok görüntülenen gönderiler',
    icon: Icons.visibility_rounded,
    color: Color(0xFF06B6D4),
    periodAware: true,
  ),
  topViewedStories(
    key: 'top_viewed_stories',
    title: 'En Çok İzlenen Hikayeler',
    chipLabel: 'Hikayeler',
    description: 'Şu an yayındaki hikayeler',
    icon: Icons.auto_stories_rounded,
    color: Color(0xFFD946EF),
    // Yalnız yayındaki hikayeler sıralanır; dönem uygulanmaz (bkz. migration).
    periodAware: false,
  ),
  topSellers(
    key: 'top_sellers',
    title: 'En Çok Sipariş Alan Dükkanlar',
    chipLabel: 'Satıcılar',
    description: 'Tamamlanan sipariş sayısı en yüksek dükkanlar',
    icon: Icons.storefront_rounded,
    color: Color(0xFFF97316),
    periodAware: true,
  ),
  topProductSellers(
    key: 'top_product_sellers',
    title: 'En Çok Ürün Yükleyen Dükkanlar',
    chipLabel: 'Ürün',
    description: 'En çok ürün yükleyen dükkanlar',
    icon: Icons.inventory_2_rounded,
    color: Color(0xFF84CC16),
    periodAware: true,
  ),
  topCustomers(
    key: 'top_customers',
    title: 'En Çok Sipariş Verenler',
    chipLabel: 'Müşteriler',
    description: 'Tamamlanan sipariş sayısı en yüksek müşteriler',
    icon: Icons.shopping_bag_rounded,
    color: Color(0xFF10B981),
    periodAware: true,
  ),
  topRatedShops(
    key: 'top_rated_shops',
    title: 'En Yüksek Puanlı Dükkanlar',
    chipLabel: 'Puan',
    description: 'Ortalama yorum puanı en yüksek dükkanlar',
    icon: Icons.star_rounded,
    color: Color(0xFFEAB308),
    periodAware: false,
  ),
  topPosters(
    key: 'top_posters',
    title: 'En Çok Paylaşım Yapanlar',
    chipLabel: 'Paylaşım',
    description: 'En çok gönderi paylaşan kullanıcılar',
    icon: Icons.edit_note_rounded,
    color: Color(0xFFEC4899),
    periodAware: true,
  ),
  mostLiked(
    key: 'most_liked',
    title: 'En Çok Beğeni Alanlar',
    chipLabel: 'Beğeni',
    description: 'Gönderileri en çok beğenilen kullanıcılar',
    icon: Icons.thumb_up_alt_rounded,
    color: Color(0xFFF43F5E),
    periodAware: true,
  ),
  topLogins(
    key: 'top_logins',
    title: 'En Çok Giriş Yapanlar',
    chipLabel: 'Giriş',
    description: 'Uygulamaya en çok giriş yapan kullanıcılar',
    icon: Icons.login_rounded,
    color: Color(0xFF3B82F6),
    periodAware: true,
  ),
  topCouriers(
    key: 'top_couriers',
    title: 'En Çok Teslimat Yapan Kuryeler',
    chipLabel: 'Kuryeler',
    description: 'Teslim ettiği sipariş sayısı en yüksek kuryeler',
    icon: Icons.delivery_dining_rounded,
    color: Color(0xFF14B8A6),
    periodAware: true,
  ),

  // --- 101 Okey (gerçek oyuncular; `okey_stats` birikimli, dönem uygulanmaz) ---
  okeyMostPlayed(
    key: 'okey_most_played',
    title: 'Okey: En Çok Maç Oynayanlar',
    chipLabel: 'Okey Maç',
    description: '101 Okey\'de en çok maç oynayanlar',
    icon: Icons.sports_esports_rounded,
    color: Color(0xFF92400E),
    periodAware: false,
  ),
  okeyMostWins(
    key: 'okey_most_wins',
    title: 'Okey: En Çok Maç Kazananlar',
    chipLabel: 'Okey Galibiyet',
    description: '101 Okey\'de en çok maç kazananlar',
    icon: Icons.military_tech_rounded,
    color: Color(0xFF15803D),
    periodAware: false,
  ),
  okeyMostLosses(
    key: 'okey_most_losses',
    title: 'Okey: En Çok Maç Kaybedenler',
    chipLabel: 'Okey Mağlubiyet',
    description: '101 Okey\'de en çok maç kaybedenler',
    icon: Icons.sentiment_dissatisfied_rounded,
    color: Color(0xFFB91C1C),
    periodAware: false,
  ),
  okeyWinRate(
    key: 'okey_win_rate',
    title: 'Okey: En Yüksek Kazanma Oranı',
    chipLabel: 'Okey Oran',
    description: 'Kazanma oranı en yüksek oyuncular (en az 5 maç)',
    icon: Icons.percent_rounded,
    color: Color(0xFF7C3AED),
    periodAware: false,
  ),
  okeyRichest(
    key: 'okey_richest',
    title: 'Okey: En Çok Puanı Olanlar',
    chipLabel: 'Okey Puan',
    description: 'Okey cüzdanında en çok puanı olanlar',
    icon: Icons.savings_rounded,
    color: Color(0xFFCA8A04),
    periodAware: false,
  ),
  okeyPointsWon(
    key: 'okey_points_won',
    title: 'Okey: En Çok Puan Kazananlar',
    chipLabel: 'Okey Kazanç',
    description: '101 Okey\'de toplam en çok puan kazananlar',
    icon: Icons.trending_up_rounded,
    color: Color(0xFF0D9488),
    periodAware: false,
  ),
  okeyHandsWon(
    key: 'okey_hands_won',
    title: 'Okey: En Çok El Kazananlar',
    chipLabel: 'Okey El',
    description: '101 Okey\'de en çok el kazananlar',
    icon: Icons.back_hand_rounded,
    color: Color(0xFF2563EB),
    periodAware: false,
  ),
  okeyBestScore(
    key: 'okey_best_score',
    title: 'Okey: En İyi Maç Skoru',
    chipLabel: 'Okey Skor',
    // 101 Okey'de düşük skor iyidir (ceza puanı); sunucu bu yüzden en DÜŞÜĞÜ
    // birinci sayar.
    description: 'En düşük (en iyi) maç skoru',
    icon: Icons.workspace_premium_rounded,
    color: Color(0xFFDB2777),
    periodAware: false,
  );

  const LeaderboardBoard({
    required this.key,
    required this.title,
    required this.chipLabel,
    required this.description,
    required this.icon,
    required this.color,
    required this.periodAware,
    this.kind = LeaderboardKind.ranking,
    this.statGroup,
  });

  final String key;
  final String title;
  final String chipLabel;

  /// Admin ekranında ve kartın başlığının altında görünen tek satır.
  final String description;
  final IconData icon;
  final Color color;

  /// `leaderboard_period` bu panoyu etkiliyor mu? Takipçi sayısı, yorum puanı
  /// ve katılma tarihi zamana yayılmaz; sipariş/paylaşım/beğeni yayılır.
  final bool periodAware;
  final LeaderboardKind kind;

  /// Yalnız sayaç kartlarında: hangi gruptaki sayıları gösterir.
  final LeaderboardStatGroup? statGroup;

  bool get isStats => kind == LeaderboardKind.stats;

  bool get isRecords => kind == LeaderboardKind.records;

  /// `app_settings` anahtarı.
  String get settingKey => 'leaderboard_board_$key';

  static LeaderboardBoard? fromKey(String key) {
    for (final board in values) {
      if (board.key == key) return board;
    }
    return null;
  }

  /// Kart başlığının altındaki tek satır. Dönemli panolarda yalnız dönem
  /// ("Son 30 gün"): ne sıralandığını başlık zaten söylüyor, ikisini birleştirmek
  /// dar ekranda taşıyordu.
  String caption(LeaderboardPeriod period) =>
      periodAware ? period.caption : description;

  /// Satırın sağındaki değer rozeti.
  String metricLabel(LeaderboardEntry entry) {
    final metric = entry.metric;
    if (this == LeaderboardBoard.newMembers) {
      final at = entry.at;
      return at == null ? '' : relativeJoinLabel(at);
    }
    if (metric == null) return '';
    switch (this) {
      case LeaderboardBoard.topRatedShops:
        // Yıldız karakteri değil ikon çizilir (bkz. widget): '★' her yazı
        // tipinde yok.
        return metric.toStringAsFixed(1);
      case LeaderboardBoard.topFollowed:
        return '${metric.round()} takipçi';
      case LeaderboardBoard.topSellers:
      case LeaderboardBoard.topCustomers:
        return '${metric.round()} sipariş';
      case LeaderboardBoard.topCouriers:
        return '${metric.round()} teslimat';
      case LeaderboardBoard.topPosters:
        return '${metric.round()} gönderi';
      case LeaderboardBoard.mostLiked:
      case LeaderboardBoard.topLikedPosts:
        return '${metric.round()} beğeni';
      case LeaderboardBoard.topViewedPosts:
        return '${metric.round()} görüntülenme';
      case LeaderboardBoard.topViewedStories:
        return '${metric.round()} izlenme';
      case LeaderboardBoard.topLogins:
        return '${metric.round()} giriş';
      case LeaderboardBoard.topProductSellers:
        return '${metric.round()} ürün';
      case LeaderboardBoard.okeyMostPlayed:
        return '${metric.round()} maç';
      case LeaderboardBoard.okeyMostWins:
        return '${metric.round()} galibiyet';
      case LeaderboardBoard.okeyMostLosses:
        return '${metric.round()} mağlubiyet';
      case LeaderboardBoard.okeyWinRate:
        return '%${metric.round()}';
      case LeaderboardBoard.okeyRichest:
      case LeaderboardBoard.okeyPointsWon:
        return '${formatCount(metric.round())} puan';
      case LeaderboardBoard.okeyHandsWon:
        return '${metric.round()} el';
      case LeaderboardBoard.okeyBestScore:
        // Negatif olabilir (iyi skor); ekleme yapılmaz, sayı olduğu gibi.
        return '${metric.round()}';
      case LeaderboardBoard.newMembers:
      case LeaderboardBoard.stats:
      case LeaderboardBoard.statsToday:
      case LeaderboardBoard.myStats:
      case LeaderboardBoard.records:
        return '';
    }
  }

  /// Değer rozetinin altındaki ikinci satır: puan panosunda yorum sayısı,
  /// kazanma oranında oynanan maç sayısı.
  String? metricSubLabel(LeaderboardEntry entry) {
    final count = entry.extra?.round();
    if (count == null || count <= 0) return null;
    switch (this) {
      case LeaderboardBoard.topRatedShops:
        return '$count yorum';
      case LeaderboardBoard.okeyWinRate:
        return '$count maç';
      default:
        return null;
    }
  }
}

/// Sayaç kartındaki tek bir sayı (`leaderboard_stats()` anahtarları).
///
/// ÜYE / ÜYESİZ: misafir girişi anonim kullanıcıdır; "Toplam üye" onları
/// saymaz, [guests] yalnız onları sayar. ZİYARETÇİ ise misafirler DAHİL bugün iz
/// bırakan herkestir; hesapsız ve misafir oturumu bile açmadan gezenler izlenmez.
enum LeaderboardStat {
  // --- Genel ("Rakamlarla Cizre") ---
  members(
    key: 'members',
    label: 'Toplam üye',
    icon: Icons.groups_rounded,
    color: Color(0xFF8B5CF6),
    group: LeaderboardStatGroup.general,
  ),
  guests(
    key: 'guests',
    label: 'Üyesiz kullanıcı',
    icon: Icons.no_accounts_rounded,
    color: Color(0xFF64748B),
    group: LeaderboardStatGroup.general,
  ),
  ghosts(
    key: 'ghosts',
    label: 'Hayalet kullanıcı',
    icon: Icons.visibility_off_rounded,
    color: Color(0xFF6D28D9),
    group: LeaderboardStatGroup.general,
  ),
  orders(
    key: 'orders',
    label: 'Tamamlanan sipariş',
    icon: Icons.local_shipping_rounded,
    color: Color(0xFF10B981),
    group: LeaderboardStatGroup.general,
  ),
  shops(
    key: 'shops',
    label: 'Aktif dükkan',
    icon: Icons.storefront_rounded,
    color: Color(0xFFF97316),
    group: LeaderboardStatGroup.general,
  ),
  products(
    key: 'products',
    label: 'Toplam ürün',
    icon: Icons.inventory_2_rounded,
    color: Color(0xFF84CC16),
    group: LeaderboardStatGroup.general,
  ),
  posts(
    key: 'posts',
    label: 'Toplam gönderi',
    icon: Icons.article_rounded,
    color: Color(0xFFEC4899),
    group: LeaderboardStatGroup.general,
  ),
  okeyMatches(
    key: 'okey_matches',
    label: 'Oynanan Okey maçı',
    icon: Icons.sports_esports_rounded,
    color: Color(0xFF92400E),
    group: LeaderboardStatGroup.general,
  ),

  // --- Bugün ("Bugün Cizre'de") ---
  visitorsToday(
    key: 'visitors_today',
    label: 'Bugün ziyaretçi',
    icon: Icons.directions_walk_rounded,
    color: Color(0xFF0891B2),
    group: LeaderboardStatGroup.today,
  ),
  activeToday(
    key: 'active_today',
    label: 'Bugün aktif üye',
    icon: Icons.bolt_rounded,
    color: Color(0xFFF59E0B),
    group: LeaderboardStatGroup.today,
  ),
  guestsToday(
    key: 'guests_today',
    label: 'Bugün üyesiz ziyaretçi',
    icon: Icons.person_outline_rounded,
    color: Color(0xFF64748B),
    group: LeaderboardStatGroup.today,
  ),
  onlineNow(
    key: 'online_now',
    label: 'Şu an çevrimiçi',
    icon: Icons.sensors_rounded,
    color: Color(0xFF22C55E),
    group: LeaderboardStatGroup.today,
  ),
  newToday(
    key: 'new_today',
    label: 'Bugün yeni üye',
    icon: Icons.person_add_alt_1_rounded,
    color: Color(0xFF3B82F6),
    group: LeaderboardStatGroup.today,
  ),
  postsToday(
    key: 'posts_today',
    label: 'Bugün paylaşım',
    icon: Icons.edit_note_rounded,
    color: Color(0xFFEC4899),
    group: LeaderboardStatGroup.today,
  ),
  ordersToday(
    key: 'orders_today',
    label: 'Bugün verilen sipariş',
    icon: Icons.shopping_cart_checkout_rounded,
    color: Color(0xFF10B981),
    group: LeaderboardStatGroup.today,
  ),

  // --- Kişisel ("Rakamlarla Sen"; yalnız kullanıcının kendisine, Görev 4.4) ---
  myDays(
    key: 'my_days',
    label: 'Gündür üyesin',
    icon: Icons.cake_rounded,
    color: Color(0xFF7C3AED),
    group: LeaderboardStatGroup.personal,
  ),
  myPosts(
    key: 'my_posts',
    label: 'Gönderin',
    icon: Icons.article_rounded,
    color: Color(0xFFEC4899),
    group: LeaderboardStatGroup.personal,
  ),
  myLikes(
    key: 'my_likes',
    label: 'Aldığın beğeni',
    icon: Icons.favorite_rounded,
    color: Color(0xFFEF4444),
    group: LeaderboardStatGroup.personal,
  ),
  myPostViews(
    key: 'my_post_views',
    label: 'Gönderi görüntülenmen',
    icon: Icons.visibility_rounded,
    color: Color(0xFF0EA5E9),
    group: LeaderboardStatGroup.personal,
  ),
  myFollowers(
    key: 'my_followers',
    label: 'Takipçin',
    icon: Icons.groups_rounded,
    color: Color(0xFF8B5CF6),
    group: LeaderboardStatGroup.personal,
  ),
  myFollowing(
    key: 'my_following',
    label: 'Takip ettiğin',
    icon: Icons.person_add_alt_rounded,
    color: Color(0xFF6366F1),
    group: LeaderboardStatGroup.personal,
  ),
  myOrders(
    key: 'my_orders',
    label: 'Tamamlanan siparişin',
    icon: Icons.local_shipping_rounded,
    color: Color(0xFF10B981),
    group: LeaderboardStatGroup.personal,
  ),
  myLogins(
    key: 'my_logins',
    label: 'Girişin (son 90 gün)',
    icon: Icons.login_rounded,
    color: Color(0xFF0891B2),
    group: LeaderboardStatGroup.personal,
  ),
  myOkeyMatches(
    key: 'my_okey_matches',
    label: 'Okey maçın',
    icon: Icons.sports_esports_rounded,
    color: Color(0xFF92400E),
    group: LeaderboardStatGroup.personal,
  ),
  myOkeyWins(
    key: 'my_okey_wins',
    label: 'Okey galibiyetin',
    icon: Icons.emoji_events_rounded,
    color: Color(0xFFF59E0B),
    group: LeaderboardStatGroup.personal,
  );

  const LeaderboardStat({
    required this.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.group,
  });

  final String key;
  final String label;
  final IconData icon;
  final Color color;
  final LeaderboardStatGroup group;

  /// `app_settings` anahtarı.
  String get settingKey => 'leaderboard_stat_$key';

  /// 101 Okey sayacı mı (modül kapalıyken gizlenir, Görev 4.1).
  bool get isOkey => key.contains('okey');
}

/// "Rekor Skorlar" kartındaki rekorlar (Görev 4.4). Sıra = sunucudaki
/// `leaderboard_record_keys()`; ayar anahtarı `leaderboard_record_<key>`.
enum LeaderboardRecord {
  busiestDay(
    key: 'busiest_day',
    label: 'En kalabalık gün',
    icon: Icons.local_fire_department_rounded,
    color: Color(0xFFF97316),
    unit: 'kişi',
  ),
  signupDay(
    key: 'signup_day',
    label: 'Tek günde en çok yeni üye',
    icon: Icons.person_add_alt_1_rounded,
    color: Color(0xFF3B82F6),
    unit: 'üye',
  ),
  ordersDay(
    key: 'orders_day',
    label: 'Tek günde en çok sipariş',
    icon: Icons.shopping_bag_rounded,
    color: Color(0xFF10B981),
    unit: 'sipariş',
  ),
  postsDay(
    key: 'posts_day',
    label: 'Tek günde en çok gönderi',
    icon: Icons.edit_note_rounded,
    color: Color(0xFFEC4899),
    unit: 'gönderi',
  ),
  oldestMember(
    key: 'oldest_member',
    label: 'En eski üye',
    icon: Icons.workspace_premium_rounded,
    color: Color(0xFF8B5CF6),
    unit: 'gün',
  ),
  topPostLikes(
    key: 'top_post_likes',
    label: 'En çok beğenilen gönderi',
    icon: Icons.favorite_rounded,
    color: Color(0xFFEF4444),
    unit: 'beğeni',
  ),
  livePeak(
    key: 'live_peak',
    label: 'En kalabalık canlı yayın',
    icon: Icons.live_tv_rounded,
    color: Color(0xFFDC2626),
    unit: 'izleyici',
  ),
  firstPost(
    key: 'first_post',
    label: 'İlk gönderi',
    icon: Icons.flag_rounded,
    color: Color(0xFF0EA5E9),
    unit: '',
  );

  const LeaderboardRecord({
    required this.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.unit,
  });

  final String key;
  final String label;
  final IconData icon;
  final Color color;

  /// Değerin birimi ("87 kişi"); boşsa değer yerine tarih gösterilir.
  final String unit;

  /// `app_settings` anahtarı.
  String get settingKey => 'leaderboard_record_$key';

  static LeaderboardRecord? fromKey(String key) {
    for (final record in values) {
      if (record.key == key) return record;
    }
    return null;
  }
}

const _trMonths = [
  'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran',
  'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık',
];

/// "21 Eylül 2026" (yerel takvim günü).
String formatTrDate(DateTime at) {
  final local = at.isUtc ? at.toLocal() : at;
  return '${local.day} ${_trMonths[local.month - 1]} ${local.year}';
}

/// Üyelik süresi: "12 gündür üye", "10 aydır üye", "1 yıl 2 aydır üye", "2 yıldır üye".
String memberForLabel(int days) {
  if (days < 30) return '$days gündür üye';
  final months = days ~/ 30;
  if (months < 12) return '$months aydır üye';
  final years = months ~/ 12;
  final rest = months % 12;
  return rest == 0 ? '$years yıldır üye' : '$years yıl $rest aydır üye';
}

/// Bir rekorun değeri ve öznesi (gün, kişi, gönderi ya da dükkân).
class LeaderboardRecordValue {
  const LeaderboardRecordValue({
    required this.record,
    this.value,
    this.at,
    this.type,
    this.id,
    this.name,
    this.handle,
    this.avatarUrl,
    this.ownerId,
    this.detail,
  });

  final LeaderboardRecord record;
  final int? value;
  final DateTime? at;

  /// Öznenin türü; gün rekorunda null.
  final LeaderboardEntityType? type;
  final String? id;
  final String? name;
  final String? handle;
  final String? avatarUrl;
  final String? ownerId;

  /// Ek bilgi (canlı yayının başlığı).
  final String? detail;

  static LeaderboardRecordValue? tryFromJson(LeaderboardRecord record, Object? raw) {
    if (raw is! Map) return null;
    String? text(Object? value) {
      final t = value?.toString().trim();
      return t == null || t.isEmpty ? null : t;
    }

    final rawType = text(raw['type']);
    final value = raw['value'];
    return LeaderboardRecordValue(
      record: record,
      value: value is num ? value.toInt() : int.tryParse('${value ?? ''}'),
      at: DateTime.tryParse('${raw['at'] ?? ''}'),
      type: rawType == null || rawType == 'day' ? null : LeaderboardEntityType.parse(rawType),
      id: text(raw['id']),
      name: text(raw['name']),
      handle: text(raw['handle']),
      avatarUrl: text(raw['avatar']),
      ownerId: text(raw['owner']),
      detail: text(raw['detail']),
    );
  }

  /// Sağdaki değer: "87 kişi", "1.234 beğeni", "1 yıl 2 aydır üye"; birimsiz
  /// rekorda (ilk gönderi) tarih.
  String get valueLabel {
    final v = value;
    if (record == LeaderboardRecord.oldestMember) return v == null ? '' : memberForLabel(v);
    if (record.unit.isEmpty) return at == null ? '' : formatTrDate(at!);
    return v == null ? '' : '${formatCount(v)} ${record.unit}';
  }

  /// Etiketin altındaki satır: gün rekorunda tarih, kişide ad, gönderide
  /// yazar ve metin, canlı yayında dükkân ve başlık.
  String get subtitle {
    final h = handle, n = name, d = detail, date = at;
    final parts = switch (type) {
      null => [if (date != null) formatTrDate(date)],
      LeaderboardEntityType.post => [if (h != null) h, if (n != null) n],
      LeaderboardEntityType.shop => [if (n != null) n, if (d != null) d],
      _ => [if (n != null) n, if (h != null) h],
    };
    return parts.join(' · ');
  }

  /// Dokununca açılacak satır (kişi, gönderi, dükkân); gün rekorunda null.
  LeaderboardEntry? toEntry() {
    final entityType = type;
    final entityId = id;
    if (entityType == null || entityId == null) return null;
    return LeaderboardEntry(
      rank: 1,
      type: entityType,
      id: entityId,
      name: name ?? '',
      handle: handle,
      avatarUrl: avatarUrl,
      metric: value?.toDouble(),
      at: at,
      ownerId: ownerId,
    );
  }
}

/// Sayıyı Türkçe binlik ayraçla yazar: 1234 -> "1.234".
String formatCount(int value) {
  final digits = value.abs().toString();
  final buffer = StringBuffer(value < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write('.');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

/// "Katıldı" etiketi. Saat farkı yerine takvim günü esas alınır: gece
/// yarısından sonra katılan biri "Dün" olarak görünmeli, "3 saat önce" değil.
String relativeJoinLabel(DateTime at, {DateTime? now}) {
  final current = (now ?? DateTime.now());
  final local = at.toLocal();
  final diff = current.difference(local);
  if (diff.isNegative || diff.inMinutes < 60) return 'Az önce';
  final today = DateTime(current.year, current.month, current.day);
  final joined = DateTime(local.year, local.month, local.day);
  final days = today.difference(joined).inDays;
  if (days <= 0) return '${diff.inHours} saat önce';
  if (days == 1) return 'Dün';
  if (days < 30) return '$days gün önce';
  final months = days ~/ 30;
  if (months < 12) return '$months ay önce';
  return '${months ~/ 12} yıl önce';
}

/// Sipariş/paylaşım/beğeni panolarının dönemi (`leaderboard_period`).
enum LeaderboardPeriod {
  all(key: 'all', label: 'Tümü', caption: 'Tüm zamanlar'),
  month(key: 'month', label: 'Son 30 gün', caption: 'Son 30 gün'),
  week(key: 'week', label: 'Son 7 gün', caption: 'Son 7 gün');

  const LeaderboardPeriod({
    required this.key,
    required this.label,
    required this.caption,
  });

  final String key;
  final String label;
  final String caption;

  static LeaderboardPeriod fromKey(String? key) {
    for (final period in values) {
      if (period.key == key) return period;
    }
    return LeaderboardPeriod.all;
  }
}

enum LeaderboardEntityType {
  user,
  shop,
  post,
  story;

  static LeaderboardEntityType parse(Object? raw) {
    switch (raw) {
      case 'shop':
        return LeaderboardEntityType.shop;
      case 'post':
        return LeaderboardEntityType.post;
      case 'story':
        return LeaderboardEntityType.story;
    }
    return LeaderboardEntityType.user;
  }
}

/// Bir panodaki tek satır (`get_leaderboard` çıktısı).
class LeaderboardEntry {
  const LeaderboardEntry({
    required this.rank,
    required this.type,
    required this.id,
    required this.name,
    this.handle,
    this.avatarUrl,
    this.metric,
    this.extra,
    this.at,
    this.ownerId,
    this.isMe = false,
  });

  final int rank;
  final LeaderboardEntityType type;
  final String id;

  /// Kullanıcı/dükkan adı; gönderi/hikayede metnin kısa özeti.
  final String name;

  /// `@kullaniciadi`; dükkanlarda boş, gönderi/hikayede yazarın adı.
  final String? handle;

  /// Avatar, logo ya da gönderi/hikaye görseli.
  final String? avatarUrl;

  /// Sıralanan sayı; "Yeni üyeler" panosunda boş.
  final double? metric;

  /// Puan panosunda yorum sayısı.
  final double? extra;

  /// "Yeni üyeler" panosunda katılma zamanı.
  final DateTime? at;

  /// Gönderi/hikayede yazarın kullanıcı kimliği.
  final String? ownerId;

  /// Bu satır giriş yapmış kullanıcının kendisi mi.
  final bool isMe;

  factory LeaderboardEntry.fromJson(Map<String, dynamic> json) {
    return LeaderboardEntry(
      rank: (json['r_rank'] as num?)?.toInt() ?? 0,
      type: LeaderboardEntityType.parse(json['r_type']),
      id: json['r_id'] as String,
      name: ((json['r_name'] as String?) ?? '').trim(),
      handle: _nonEmpty(json['r_handle']),
      avatarUrl: _nonEmpty(json['r_avatar']),
      metric: _toDouble(json['r_metric']),
      extra: _toDouble(json['r_extra']),
      at: DateTime.tryParse('${json['r_at'] ?? ''}'),
      ownerId: _nonEmpty(json['r_owner']),
      isMe: json['r_me'] == true,
    );
  }

  static String? _nonEmpty(Object? value) {
    final text = value?.toString().trim();
    return (text == null || text.isEmpty) ? null : text;
  }

  // `numeric` sütunları PostgREST'ten sayı ya da metin olarak gelebilir.
  static double? _toDouble(Object? value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }
}

/// Admin anahtarları (`leaderboard_settings()` RPC'si).
class LeaderboardSettings {
  const LeaderboardSettings({
    required this.enabled,
    required this.period,
    required this.limit,
    required this.boards,
    this.order = const [],
    this.stats = const {},
    this.records = const {},
  });

  final bool enabled;
  final LeaderboardPeriod period;
  final int limit;

  /// Kart anahtarı -> açık mı (sayaç kartı `stats` dahil).
  final Map<String, bool> boards;

  /// Admin'in belirlediği kart sırası (kart anahtarları). Eksik/bilinmeyen
  /// anahtarlar [orderedBoards]'da düzeltilir.
  final List<String> order;

  /// Sayaç anahtarı -> açık mı.
  final Map<String, bool> stats;

  /// Rekor anahtarı -> açık mı (Görev 4.4).
  final Map<String, bool> records;

  /// Ayar okunamadığında bölüm HİÇ görünmesin: yanlışlıkla kapatılmış bir
  /// özelliği açık göstermektense ana sayfayı boş bırakmak daha güvenli.
  static const LeaderboardSettings fallback = LeaderboardSettings(
    enabled: false,
    period: LeaderboardPeriod.all,
    limit: 5,
    boards: {},
  );

  bool isBoardEnabled(LeaderboardBoard board) => boards[board.key] ?? false;

  bool isStatEnabled(LeaderboardStat stat) => stats[stat.key] ?? false;

  bool isRecordEnabled(LeaderboardRecord record) => records[record.key] ?? false;

  /// Yalnız kart sırası değişmiş kopya (admin ekranındaki anlık sıralama için).
  LeaderboardSettings withOrder(List<LeaderboardBoard> newOrder) =>
      LeaderboardSettings(
        enabled: enabled,
        period: period,
        limit: limit,
        boards: boards,
        order: [for (final b in newOrder) b.key],
        stats: stats,
        records: records,
      );

  /// TÜM kartlar, admin sırasıyla: kayıtlı sıradaki bilinen anahtarlar önce
  /// (tekrarsız), sonra eksik kalanlar varsayılan (enum) sırasıyla. Sunucudaki
  /// `leaderboard_order()` ile aynı kural — yeni bir pano eklenince eski
  /// kayıtlı sıra bozulmaz.
  List<LeaderboardBoard> get orderedBoards {
    final result = <LeaderboardBoard>[];
    for (final key in order) {
      final board = LeaderboardBoard.fromKey(key);
      if (board != null && !result.contains(board)) result.add(board);
    }
    for (final board in LeaderboardBoard.values) {
      if (!result.contains(board)) result.add(board);
    }
    return result;
  }

  /// Ana anahtar açıkken görünmesi gereken kartlar, admin sırasıyla.
  List<LeaderboardBoard> get visibleBoards => enabled
      ? [
          for (final board in orderedBoards)
            if (isBoardEnabled(board)) board,
        ]
      : const [];

  factory LeaderboardSettings.fromJson(Map<String, dynamic> json) {
    Map<String, bool> flags(Object? raw) => raw is Map
        ? {
            for (final entry in raw.entries)
              entry.key.toString(): entry.value == true,
          }
        : const {};

    final rawOrder = json['order'];
    return LeaderboardSettings(
      enabled: json['enabled'] == true,
      period: LeaderboardPeriod.fromKey(json['period'] as String?),
      limit: ((json['limit'] as num?)?.toInt() ?? 5).clamp(3, 10),
      boards: flags(json['boards']),
      order: rawOrder is List
          ? [for (final key in rawOrder) key.toString()]
          : const [],
      stats: flags(json['stats']),
      records: flags(json['records']),
    );
  }
}

/// Ana sayfanın TEK çağrıyla aldığı her şey (`get_leaderboards()`).
class LeaderboardSnapshot {
  const LeaderboardSnapshot({
    required this.settings,
    this.boards = const {},
    this.stats = const {},
    this.records = const {},
  });

  final LeaderboardSettings settings;

  /// Pano anahtarı -> satırlar (yalnız açık panolar gelir). İlk N satıra ek
  /// olarak, çağıranın sırası N'den büyükse kendi satırı da bulunur.
  final Map<String, List<LeaderboardEntry>> boards;

  /// Sayaç anahtarı -> değer (yalnız açık sayaçlar gelir; kişisel sayaçlar
  /// `my_` önekiyle ve yalnız çağıranın kendisi için).
  final Map<String, int> stats;

  /// Rekor anahtarı -> değer (yalnız açık ve verisi olan rekorlar).
  final Map<String, LeaderboardRecordValue> records;

  static const LeaderboardSnapshot empty = LeaderboardSnapshot(
    settings: LeaderboardSettings.fallback,
  );

  factory LeaderboardSnapshot.fromJson(Map<String, dynamic> json) {
    final settings = LeaderboardSettings.fromJson(
      Map<String, dynamic>.from((json['settings'] as Map?) ?? const {}),
    );

    final boards = <String, List<LeaderboardEntry>>{};
    final rawBoards = json['boards'];
    if (rawBoards is Map) {
      for (final entry in rawBoards.entries) {
        final rows = entry.value;
        if (rows is! List) continue;
        boards[entry.key.toString()] = [
          for (final row in rows)
            if (row is Map)
              LeaderboardEntry.fromJson(Map<String, dynamic>.from(row)),
        ];
      }
    }

    final stats = <String, int>{};
    final rawStats = json['stats'];
    if (rawStats is Map) {
      for (final entry in rawStats.entries) {
        final value = entry.value;
        if (value is num) stats[entry.key.toString()] = value.toInt();
      }
    }

    final records = <String, LeaderboardRecordValue>{};
    final rawRecords = json['records'];
    if (rawRecords is Map) {
      for (final entry in rawRecords.entries) {
        final record = LeaderboardRecord.fromKey(entry.key.toString());
        if (record == null) continue;
        final value = LeaderboardRecordValue.tryFromJson(record, entry.value);
        if (value != null) records[record.key] = value;
      }
    }

    return LeaderboardSnapshot(
      settings: settings,
      boards: boards,
      stats: stats,
      records: records,
    );
  }

  /// 101 Okey modülü kapalıyken (Görev 4.1): Okey panoları ve sayaçları olmadan.
  LeaderboardSnapshot withoutOkey() => LeaderboardSnapshot(
    settings: settings,
    boards: {
      for (final entry in boards.entries)
        if (!entry.key.startsWith('okey_')) entry.key: entry.value,
    },
    stats: {
      for (final entry in stats.entries)
        if (!entry.key.contains('okey')) entry.key: entry.value,
    },
    records: records,
  );

  /// "Rekor Skorlar" kartındaki rekorlar, enum sırasıyla.
  List<LeaderboardRecordValue> recordsFor() => [
    for (final record in LeaderboardRecord.values)
      if (records[record.key] case final value?) value,
  ];

  /// Bir sayaç kartında gösterilecek sayaçlar: kartın grubundaki, sunucunun
  /// döndürdüğü (açık) olanlar, enum sırasıyla. Sıralama kartında boştur.
  List<LeaderboardStat> statsFor(LeaderboardBoard board) => [
    for (final stat in LeaderboardStat.values)
      if (stat.group == board.statGroup && stats.containsKey(stat.key)) stat,
  ];

  /// Ekranda kart olarak çizilecekler: açık kartlar, admin sırasıyla; hiç
  /// sayaç/rekor yoksa o kart da yok.
  List<LeaderboardBoard> get cards => [
    for (final board in settings.visibleBoards)
      if (board.isRecords
          ? recordsFor().isNotEmpty
          : (!board.isStats || statsFor(board).isNotEmpty))
        board,
  ];

  /// Listenin görünen kısmı (ilk N).
  List<LeaderboardEntry> topEntries(LeaderboardBoard board) => [
    for (final e in boards[board.key] ?? const <LeaderboardEntry>[])
      if (e.rank <= settings.limit) e,
  ];

  /// Çağıranın ilk N'in DIŞINDAKİ satırı ("Senin sıran"); yoksa null.
  LeaderboardEntry? myEntryBeyondTop(LeaderboardBoard board) {
    for (final e in boards[board.key] ?? const <LeaderboardEntry>[]) {
      if (e.isMe && e.rank > settings.limit) return e;
    }
    return null;
  }
}

/// Bir kullanıcının liderlik listelerinden gizlenme durumu.
class LeaderboardVisibility {
  const LeaderboardVisibility({
    this.selfHidden = false,
    this.adminHidden = false,
  });

  /// Kullanıcı kendi isteğiyle gizlendi.
  final bool selfHidden;

  /// Admin gizledi; kullanıcı bunu geri alamaz.
  final bool adminHidden;

  bool get hidden => selfHidden || adminHidden;

  factory LeaderboardVisibility.fromJson(Map<String, dynamic> json) {
    return LeaderboardVisibility(
      selfHidden: json['self_hidden'] == true,
      adminHidden: json['admin_hidden'] == true,
    );
  }

  /// Rozet/etiket metni: kim gizledi.
  String get label {
    if (adminHidden && selfHidden) return 'Liderlikte gizli (admin + kendisi)';
    if (adminHidden) return 'Liderlikten gizlendi (admin)';
    if (selfHidden) return 'Liderlikte gizli (kendisi)';
    return '';
  }
}
