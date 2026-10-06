// Canlı yayın (satıcı canlı alışverişi) modelleri — Görev 3.4.
//
// Sunucu biçimi `private.live_session_json` (RPC'ler: live_sessions_feed,
// live_session_detail, live_create_session, start_live_session, …). Realtime
// `live_sessions` satır güncellemeleri [LiveSession.applyRow] ile işlenir.

DateTime? _time(Object? value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString())?.toUtc();
}

double? _num(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

int _int(Object? value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

String? _text(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

/// Yayında o an sabitlenen ürün.
class LivePinnedProduct {
  final String id;
  final String name;
  final String? imageUrl;
  final double price;
  final double? discountPrice;
  final double effectivePrice;
  final bool isAvailable;

  const LivePinnedProduct({
    required this.id,
    required this.name,
    this.imageUrl,
    required this.price,
    this.discountPrice,
    required this.effectivePrice,
    this.isAvailable = true,
  });

  bool get hasDiscount => effectivePrice < price;

  static LivePinnedProduct? tryFromJson(Object? json) {
    if (json is! Map) return null;
    final id = _text(json['id']);
    if (id == null) return null;
    final price = _num(json['price']) ?? 0;
    return LivePinnedProduct(
      id: id,
      name: _text(json['name']) ?? 'Ürün',
      imageUrl: _text(json['image_url']),
      price: price,
      discountPrice: _num(json['discount_price']),
      effectivePrice: _num(json['effective_price']) ?? price,
      isAvailable: json['is_available'] != false,
    );
  }
}

/// Canlı yayın oturumu. status: 'scheduled' (hazırlık) | 'live' | 'ended'.
///
/// İki tür: mağaza yayını ([shopId] dolu) ve kullanıcı yayını ([shopId] boş;
/// yayıncı [hostUserId], adı/görseli [hostDisplayName]/[hostAvatarUrl]).
class LiveSession {
  final String id;
  final String hostUserId;

  /// Kullanıcı yayınında boş.
  final String shopId;
  final String title;
  final String? description;
  final String? coverImageUrl;
  final String channelName;
  final String status;

  /// Sunucuya göre şu an canlı mı (durum 'live' VE son 2 dk'da sinyal var).
  final bool isLiveNow;
  final DateTime? startedAt;
  final DateTime? endedAt;

  /// 'host' | 'timeout' | 'admin' (yalnız bitmiş yayında).
  final String? endedReason;
  final int viewerCount;
  final int peakViewerCount;
  final DateTime? lastHeartbeatAt;
  final DateTime createdAt;
  final String? shopName;
  final String? shopLogoUrl;

  /// Yalnız kullanıcı yayınında: yayıncının görünen adı (önce kullanıcı adı),
  /// kullanıcı adı ve profil görseli.
  final String? hostDisplayName;
  final String? hostUsername;
  final String? hostAvatarUrl;
  final LivePinnedProduct? pinnedProduct;

  /// Realtime satırında gelen sabit ürün kimliği ([pinnedProduct] ayrıntısı
  /// henüz yüklenmemiş olabilir).
  final String? pinnedProductId;

  /// Yayında sabitlenmiş (öne çıkan) ürünler, ilk sabitlenme sırasıyla.
  /// Yalnız geçmiş/ayrıntı/ana sayfa kartı yanıtlarında gelir.
  final List<LivePinnedProduct> featuredProducts;

  /// Sunucunun hesapladığı süre (saniye) ve mesaj sayısı (geçmiş/ayrıntı).
  final int? durationSeconds;
  final int? messageCount;

  /// `start_live_session` dönüşü: yayın başlarken kaç kişiye bildirim gitti
  /// (null = bu çağrıda bildirim gönderilmedi, ör. zaten canlıydı).
  final int? notified;

  const LiveSession({
    required this.id,
    required this.hostUserId,
    required this.shopId,
    required this.title,
    this.description,
    this.coverImageUrl,
    required this.channelName,
    required this.status,
    this.isLiveNow = false,
    this.startedAt,
    this.endedAt,
    this.endedReason,
    this.viewerCount = 0,
    this.peakViewerCount = 0,
    this.lastHeartbeatAt,
    required this.createdAt,
    this.shopName,
    this.shopLogoUrl,
    this.hostDisplayName,
    this.hostUsername,
    this.hostAvatarUrl,
    this.pinnedProduct,
    this.pinnedProductId,
    this.featuredProducts = const [],
    this.durationSeconds,
    this.messageCount,
    this.notified,
  });

  factory LiveSession.fromJson(Map<String, dynamic> json) {
    final pinned = LivePinnedProduct.tryFromJson(json['pinned_product']);
    final status = _text(json['status']) ?? 'scheduled';
    final featured = json['featured_products'];
    return LiveSession(
      id: json['id'].toString(),
      hostUserId: json['host_user_id']?.toString() ?? '',
      shopId: json['shop_id']?.toString() ?? '',
      title: _text(json['title']) ?? 'Canlı yayın',
      description: _text(json['description']),
      coverImageUrl: _text(json['cover_image_url']),
      channelName: json['channel_name']?.toString() ?? '',
      status: status,
      isLiveNow: json['is_live'] == true,
      startedAt: _time(json['started_at']),
      endedAt: _time(json['ended_at']),
      endedReason: _text(json['ended_reason']),
      viewerCount: _int(json['viewer_count']),
      peakViewerCount: _int(json['peak_viewer_count']),
      lastHeartbeatAt: _time(json['last_heartbeat_at']),
      createdAt: _time(json['created_at']) ?? DateTime.now().toUtc(),
      shopName: _text(json['shop_name']),
      shopLogoUrl: _text(json['shop_logo_url']),
      hostDisplayName: _text(json['host_display_name']),
      hostUsername: _text(json['host_username']),
      hostAvatarUrl: _text(json['host_avatar_url']),
      pinnedProduct: pinned,
      pinnedProductId: pinned?.id,
      featuredProducts: featured is List
          ? featured.map(LivePinnedProduct.tryFromJson).whereType<LivePinnedProduct>().toList()
          : const [],
      durationSeconds: json['duration_seconds'] == null ? null : _int(json['duration_seconds']),
      messageCount: json['message_count'] == null ? null : _int(json['message_count']),
      notified: json['notified'] == null ? null : _int(json['notified']),
    );
  }

  bool get isLive => status == 'live';
  bool get isEnded => status == 'ended';
  bool get isScheduled => status == 'scheduled';

  /// Mağazası olmayan kullanıcının yayını.
  bool get isUserStream => shopId.isEmpty;

  /// Listelerde/başlıkta gösterilen ad: mağaza adı ya da yayıncı.
  String get displayName => isUserStream ? (hostDisplayName ?? 'Kullanıcı') : (shopName ?? 'Mağaza');

  /// Mağaza logosu ya da yayıncının profil görseli.
  String? get displayAvatarUrl => isUserStream ? hostAvatarUrl : shopLogoUrl;

  /// Yayın süresi (bitmişse başlangıç→bitiş, sürüyorsa başlangıç→[now]).
  Duration? durationAt(DateTime now) {
    final start = startedAt;
    if (start == null) return null;
    final end = endedAt ?? now;
    final value = end.difference(start);
    return value.isNegative ? Duration.zero : value;
  }

  /// Realtime `live_sessions` UPDATE satırını uygular. Sabit ürün kimliği
  /// değişirse ayrıntı düşer (çağıran yeniden yükler).
  LiveSession applyRow(Map<String, dynamic> row) {
    final hasPin = row.containsKey('pinned_product_id');
    final newPinId = hasPin ? _text(row['pinned_product_id']) : pinnedProductId;
    final status = _text(row['status']) ?? this.status;
    final heartbeat = row.containsKey('last_heartbeat_at') ? _time(row['last_heartbeat_at']) : lastHeartbeatAt;
    return LiveSession(
      id: id,
      hostUserId: hostUserId,
      shopId: shopId,
      title: _text(row['title']) ?? title,
      description: row.containsKey('description') ? _text(row['description']) : description,
      coverImageUrl: coverImageUrl,
      channelName: channelName,
      status: status,
      isLiveNow: status == 'live' && (row.containsKey('last_heartbeat_at') ? heartbeat != null : isLiveNow),
      startedAt: row.containsKey('started_at') ? _time(row['started_at']) : startedAt,
      endedAt: row.containsKey('ended_at') ? _time(row['ended_at']) : endedAt,
      endedReason: row.containsKey('ended_reason') ? _text(row['ended_reason']) : endedReason,
      viewerCount: row.containsKey('viewer_count') ? _int(row['viewer_count']) : viewerCount,
      peakViewerCount: row.containsKey('peak_viewer_count') ? _int(row['peak_viewer_count']) : peakViewerCount,
      lastHeartbeatAt: heartbeat,
      createdAt: createdAt,
      shopName: shopName,
      shopLogoUrl: shopLogoUrl,
      hostDisplayName: hostDisplayName,
      hostUsername: hostUsername,
      hostAvatarUrl: hostAvatarUrl,
      pinnedProduct: newPinId != null && newPinId == pinnedProduct?.id ? pinnedProduct : null,
      pinnedProductId: newPinId,
      featuredProducts: featuredProducts,
      durationSeconds: durationSeconds,
      messageCount: messageCount,
    );
  }

  /// Sabit ürün ayrıntısı yüklenmesi gerekiyor mu (kimlik var, ayrıntı yok).
  bool get needsPinnedDetail => pinnedProductId != null && pinnedProduct?.id != pinnedProductId;
}

/// Keşfet sayfası: şu an canlı olanlar + son 7 günün biten yayınları.
class LiveFeed {
  final List<LiveSession> live;
  final List<LiveSession> recent;

  /// Yönetim canlı yayını açık tutuyor mu (Görev 4.3). Kapalıyken süren
  /// yayınlar bitene kadar listelenir, yeni yayın açılamaz.
  final bool enabled;

  /// Kişinin kullanıcı yayını açma erişimi: 'ok' ya da sunucu kodu
  /// (AUTH_REQUIRED, LIVE_USERS_OFF, LIVE_USER_NOT_PERMITTED, …).
  final String? myAccess;

  const LiveFeed({this.live = const [], this.recent = const [], this.enabled = true, this.myAccess});

  factory LiveFeed.fromJson(Map<String, dynamic> json) {
    List<LiveSession> list(Object? raw) => raw is List
        ? raw.whereType<Map>().map((e) => LiveSession.fromJson(Map<String, dynamic>.from(e))).toList()
        : const [];
    return LiveFeed(
      live: list(json['live']),
      recent: list(json['recent']),
      enabled: json['enabled'] != false,
      myAccess: _text(json['my_access']),
    );
  }

  bool get isEmpty => live.isEmpty && recent.isEmpty;

  /// "Yayın aç" düğmesi gösterilsin mi.
  bool get canStartUserStream => enabled && myAccess == 'ok';

  LiveFeed copyWith({List<LiveSession>? live}) =>
      LiveFeed(live: live ?? this.live, recent: recent, enabled: enabled, myAccess: myAccess);
}

List<LiveSession> _sessions(Object? raw) => raw is List
    ? raw.whereType<Map>().map((e) => LiveSession.fromJson(Map<String, dynamic>.from(e))).toList()
    : const [];

LiveSession? _session(Object? raw) => raw is Map ? LiveSession.fromJson(Map<String, dynamic>.from(raw)) : null;

/// Yayın geçmişi sayfası (`live_history`): biten yayınlar, en yeni önce;
/// her satırda öne çıkan ürünler, süre ve mesaj sayısı.
class LiveHistoryPage {
  final List<LiveSession> rows;
  final int total;

  /// Geçmişin kaç gün geriye gittiği (yönetici ayarı).
  final int days;

  const LiveHistoryPage({this.rows = const [], this.total = 0, this.days = 30});

  factory LiveHistoryPage.fromJson(Map<String, dynamic> json) => LiveHistoryPage(
    rows: _sessions(json['rows']),
    total: _int(json['total']),
    days: json['days'] == null ? 30 : _int(json['days']),
  );
}

/// Ana sayfadaki (Şehiriçi kartının yanındaki) canlı yayın kartı
/// (`live_home_card`): canlı yayın varsa en çok izleneni, yoksa son biten.
class LiveHomeCard {
  /// Yönetici kartı ya da canlı yayın modülünü kapattıysa false.
  final bool enabled;
  final int liveCount;
  final LiveSession? live;
  final LiveSession? last;

  const LiveHomeCard({this.enabled = false, this.liveCount = 0, this.live, this.last});

  factory LiveHomeCard.fromJson(Map<String, dynamic> json) => LiveHomeCard(
    enabled: json['enabled'] == true,
    liveCount: _int(json['live_count']),
    live: _session(json['live']),
    last: _session(json['last']),
  );

  /// Gösterilecek yayın: canlı olan, yoksa son biten.
  LiveSession? get session => live ?? last;

  bool get isLive => live != null;
  bool get isVisible => enabled && session != null;
}

/// "Yayınlarından haberdar ol" aboneliği.
class LiveSubscription {
  final String shopId;
  final bool subscribed;
  final int subscribers;

  const LiveSubscription({required this.shopId, this.subscribed = false, this.subscribers = 0});

  factory LiveSubscription.fromJson(Map<String, dynamic> json, {String? shopId}) => LiveSubscription(
    shopId: _text(json['shop_id']) ?? shopId ?? '',
    subscribed: json['subscribed'] == true,
    subscribers: _int(json['subscribers']),
  );
}

/// Paylaşım metni (uygulamanın diğer paylaşımları gibi düz metin + davet).
String liveShareText(LiveSession session) {
  final shop = session.isUserStream ? session.displayName : (session.shopName ?? 'Bir mağaza');
  return [
    session.isLive ? '🔴 $shop şu an CizreApp\'te canlı yayında!' : '🎥 $shop CizreApp\'te canlı yayın yaptı.',
    '"${session.title}"',
    '',
    'CizreApp › Canlı Yayınlar\'dan izleyebilirsin.',
    'https://www.cizreapp.com',
  ].join('\n');
}

/// Yayın sohbet mesajı. Yazar adı/avatarı ve satıcı bayrağı sunucuda yazılır
/// (Realtime yükü tek başına gösterilebilir).
class LiveMessage {
  final String id;
  final String sessionId;
  final String userId;
  final String message;
  final bool isHost;
  final DateTime createdAt;
  final String authorName;
  final String? authorAvatar;

  const LiveMessage({
    required this.id,
    required this.sessionId,
    required this.userId,
    required this.message,
    required this.isHost,
    required this.createdAt,
    required this.authorName,
    this.authorAvatar,
  });

  factory LiveMessage.fromJson(Map<String, dynamic> json) {
    return LiveMessage(
      id: json['id'].toString(),
      sessionId: json['session_id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      message: json['message']?.toString() ?? '',
      isHost: json['is_host'] == true,
      createdAt: _time(json['created_at']) ?? DateTime.now().toUtc(),
      authorName: _text(json['author_name']) ?? 'Kullanıcı',
      authorAvatar: _text(json['author_avatar']),
    );
  }
}

/// Satıcı "yayındayım" sinyalinin cevabı.
class LiveHeartbeat {
  final String status;
  final String? endedReason;
  final int viewerCount;
  final int peakViewerCount;

  const LiveHeartbeat({
    required this.status,
    this.endedReason,
    this.viewerCount = 0,
    this.peakViewerCount = 0,
  });

  factory LiveHeartbeat.fromJson(Map<String, dynamic> json) => LiveHeartbeat(
    status: _text(json['status']) ?? 'live',
    endedReason: _text(json['ended_reason']),
    viewerCount: _int(json['viewer_count']),
    peakViewerCount: _int(json['peak_viewer_count']),
  );

  bool get isEnded => status == 'ended';
}

/// Yayın bitince özet. status 'discarded' = hiç başlamamış kayıt silindi.
class LiveEndSummary {
  final String status;
  final String? endedReason;
  final Duration duration;
  final int peakViewerCount;
  final int messageCount;

  const LiveEndSummary({
    required this.status,
    this.endedReason,
    this.duration = Duration.zero,
    this.peakViewerCount = 0,
    this.messageCount = 0,
  });

  factory LiveEndSummary.fromJson(Map<String, dynamic> json) => LiveEndSummary(
    status: _text(json['status']) ?? 'ended',
    endedReason: _text(json['ended_reason']),
    duration: Duration(seconds: _int(json['duration_seconds'])),
    peakViewerCount: _int(json['peak_viewer_count']),
    messageCount: _int(json['message_count']),
  );
}

/// `live-token` Edge Function cevabı: Agora'ya katılma bilgileri.
class LiveCredentials {
  final String appId;
  final String channel;
  final int uid;
  final int hostUid;
  final String token;
  final Duration expiresIn;

  const LiveCredentials({
    required this.appId,
    required this.channel,
    required this.uid,
    required this.hostUid,
    required this.token,
    this.expiresIn = const Duration(hours: 1),
  });

  factory LiveCredentials.fromJson(Map<String, dynamic> json) => LiveCredentials(
    appId: json['app_id'].toString(),
    channel: json['channel'].toString(),
    uid: _int(json['uid']),
    hostUid: json['host_uid'] == null ? 1 : _int(json['host_uid']),
    token: json['token'].toString(),
    expiresIn: Duration(seconds: json['expires_in'] == null ? 3600 : _int(json['expires_in'])),
  );
}

/// Canlı yayın hataları — sunucu ipucu (HINT) / anahtar hata kodu eşlemesi.
enum LiveFailure {
  notConfigured('Canlı yayın henüz etkin değil. Yönetici Agora ayarlarını tamamlayınca açılacak.'),
  authRequired('Bu işlem için giriş yapmalısın.'),
  notShopOwner('Bu mağaza adına yayın açamazsın.'),
  shopInactive('Yayın için mağazan aktif ve onaylı olmalı.'),
  titleInvalid('Yayın başlığı 3–80 karakter olmalı.'),
  notFound('Yayın bulunamadı.'),
  notHost('Bu yayın sana ait değil.'),
  ended('Bu yayın sona erdi.'),
  notLive('Yayın şu an canlı değil.'),
  productInvalid('Bu ürün yayında gösterilemez.'),
  messageEmpty('Mesaj boş olamaz.'),
  messageTooLong('Mesaj en fazla 300 karakter olabilir.'),
  messageRate('Çok hızlı mesaj gönderiyorsun; biraz bekle.'),
  rateLimited('Çok fazla deneme yapıldı; biraz sonra tekrar dene.'),
  permissionDenied('Yayın için kamera ve mikrofon izni gerekli.'),
  unsupported('Canlı yayın yalnız mobil uygulamada çalışır.'),
  connection('Bağlantı kurulamadı; internetini kontrol edip tekrar dene.'),
  // Görev 4.3: yönetim kontrolü
  disabled('Canlı yayın şu anda kapalı.'),
  revoked('Mağazanın canlı yayın izni yönetim tarafından kaldırıldı.'),
  notPermitted('Canlı yayın şu an yalnız izin verilen mağazalara açık. İzin için yönetimle iletişime geç.'),
  shopNotFound('Mağaza bulunamadı.'),
  // Kullanıcı (mağazasız) yayını
  accountInactive('Hesabın canlı yayın açmaya uygun değil.'),
  usersOff('Kullanıcı canlı yayınları şu anda kapalı.'),
  userRevoked('Canlı yayın iznin yönetim tarafından kaldırıldı.'),
  userNotPermitted('Canlı yayın şu an yalnız izin verilen kullanıcılara açık. İzin için yönetimle iletişime geç.'),
  userNotFound('Kullanıcı bulunamadı.'),
  unknown('Bir şeyler ters gitti; tekrar dene.');

  const LiveFailure(this.message);

  final String message;

  static LiveFailure fromCode(String? code) {
    switch (code) {
      case 'LIVE_NOT_CONFIGURED':
        return LiveFailure.notConfigured;
      case 'AUTH_REQUIRED':
        return LiveFailure.authRequired;
      case 'LIVE_NOT_SHOP_OWNER':
        return LiveFailure.notShopOwner;
      case 'LIVE_SHOP_INACTIVE':
      case 'SHOP_INACTIVE':
        return LiveFailure.shopInactive;
      case 'LIVE_TITLE_INVALID':
        return LiveFailure.titleInvalid;
      case 'LIVE_NOT_FOUND':
      case 'NOT_FOUND':
        return LiveFailure.notFound;
      case 'LIVE_NOT_HOST':
      case 'FORBIDDEN':
        return LiveFailure.notHost;
      case 'LIVE_ENDED':
      case 'ENDED':
        return LiveFailure.ended;
      case 'LIVE_NOT_LIVE':
      case 'NOT_LIVE':
        return LiveFailure.notLive;
      case 'LIVE_PRODUCT_INVALID':
        return LiveFailure.productInvalid;
      case 'LIVE_MESSAGE_EMPTY':
        return LiveFailure.messageEmpty;
      case 'LIVE_MESSAGE_TOO_LONG':
        return LiveFailure.messageTooLong;
      case 'LIVE_MESSAGE_RATE':
        return LiveFailure.messageRate;
      case 'RATE_LIMITED':
        return LiveFailure.rateLimited;
      case 'LIVE_DISABLED':
        return LiveFailure.disabled;
      case 'LIVE_REVOKED':
        return LiveFailure.revoked;
      case 'LIVE_NOT_PERMITTED':
        return LiveFailure.notPermitted;
      case 'LIVE_SHOP_NOT_FOUND':
        return LiveFailure.shopNotFound;
      case 'LIVE_ACCOUNT_INACTIVE':
        return LiveFailure.accountInactive;
      case 'LIVE_USERS_OFF':
        return LiveFailure.usersOff;
      case 'LIVE_USER_REVOKED':
        return LiveFailure.userRevoked;
      case 'LIVE_USER_NOT_PERMITTED':
        return LiveFailure.userNotPermitted;
      case 'LIVE_USER_NOT_FOUND':
        return LiveFailure.userNotFound;
      default:
        return LiveFailure.unknown;
    }
  }
}

class LiveException implements Exception {
  final LiveFailure failure;
  final String? detail;

  /// Kullanıcıya gösterilecek ek açıklama (ör. yönetimin izin kaldırma notu).
  final String? note;

  const LiveException(this.failure, [this.detail, this.note]);

  String get message {
    final extra = note?.trim();
    return extra == null || extra.isEmpty ? failure.message : '${failure.message}\n\nYönetim notu: $extra';
  }

  @override
  String toString() => 'LiveException(${failure.name}${detail == null ? '' : ': $detail'})';
}
