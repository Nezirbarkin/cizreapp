import 'dart:async';

import 'package:cizreapp/core/models/live_shopping_model.dart';
import 'package:cizreapp/core/models/product_model.dart';
import 'package:cizreapp/features/market/services/agora_service.dart';
import 'package:cizreapp/features/market/services/live_shopping_service.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgresChangePayload;

/// Canlı yayın ekran testleri için sahte servis + sahte video motoru
/// (Görev 3.4). Ağ/Agora yok; akışlar StreamController'larla sürülür.

final kLiveNow = DateTime.utc(2026, 9, 28, 12);

Map<String, dynamic> liveSessionJson({
  String id = 'sess-1',
  String status = 'scheduled',
  String title = 'Çay Evi canlı yayında',
  bool isLive = false,
  DateTime? startedAt,
  DateTime? endedAt,
  String? endedReason,
  int viewers = 0,
  int peak = 0,
  Map<String, dynamic>? pinned,
  List<Map<String, dynamic>>? featured,
  int? durationSeconds,
  int? messageCount,
  String shopId = 'shop-1',
  String shopName = 'Çay Evi',
  // Kullanıcı (mağazasız) yayını: shop_id/shop_name boş, yayıncı alanları dolu.
  bool user = false,
  String hostName = 'zeynep',
}) => {
  'id': id,
  'kind': user ? 'user' : 'shop',
  'shop_id': user ? null : shopId,
  'host_user_id': user ? 'host-9' : 'owner-1',
  if (user) 'host_display_name': hostName,
  if (user) 'host_username': hostName,
  if (user) 'host_avatar_url': null,
  'title': title,
  'channel_name': 'cz_0123456789abcdef0123456789abcdef',
  'status': status,
  'is_live': isLive,
  'started_at': startedAt?.toIso8601String(),
  'ended_at': endedAt?.toIso8601String(),
  'ended_reason': endedReason,
  'viewer_count': viewers,
  'peak_viewer_count': peak,
  'created_at': kLiveNow.subtract(const Duration(minutes: 30)).toIso8601String(),
  'shop_name': user ? null : shopName,
  'shop_logo_url': null,
  'pinned_product': pinned,
  if (featured != null) 'featured_products': featured,
  if (durationSeconds != null) 'duration_seconds': durationSeconds,
  if (messageCount != null) 'message_count': messageCount,
};

Map<String, dynamic> pinnedJson({String id = 'p1', String name = 'Demlik', num price = 250, num? discount}) => {
  'id': id,
  'name': name,
  'image_url': null,
  'price': price,
  'discount_price': discount,
  'effective_price': discount ?? price,
  'is_available': true,
};

LiveMessage liveMessage(String id, String text, {bool host = false, String author = 'ayse'}) => LiveMessage(
  id: id,
  sessionId: 'sess-1',
  userId: host ? 'owner-1' : 'user-$id',
  message: text,
  isHost: host,
  createdAt: kLiveNow,
  authorName: host ? 'Çay Evi' : author,
);

Product liveProduct(String id, String name, {double price = 100}) => Product(
  id: id,
  shopId: 'shop-1',
  name: name,
  price: price,
  stockQuantity: 5,
  isAvailable: true,
  createdAt: kLiveNow,
  updatedAt: kLiveNow,
);

const kHostCredentials = LiveCredentials(
  appId: '970CA35de60c44645bbae8a215061b33',
  channel: 'cz_0123456789abcdef0123456789abcdef',
  uid: 1,
  hostUid: 1,
  token: '007host',
);

const kViewerCredentials = LiveCredentials(
  appId: '970CA35de60c44645bbae8a215061b33',
  channel: 'cz_0123456789abcdef0123456789abcdef',
  uid: 424242,
  hostUid: 1,
  token: '007viewer',
);

class FakeLiveService extends LiveShoppingService {
  FakeLiveService({this.userId = 'owner-1'});

  String? userId;
  final List<String> calls = [];

  // hazırlık / başlatma
  LiveSession created = LiveSession.fromJson(liveSessionJson());
  bool resumed = false;
  Object? createError;
  Object? credentialsError;
  LiveCredentials credentials = kHostCredentials;
  final List<String> titles = [];

  /// `start_live_session` dönüşündeki bildirim sayısı (null = gönderilmedi).
  int? startNotified;

  // okuma
  LiveFeed feed = const LiveFeed();
  Object? feedError;
  LiveSession? detail;
  List<LiveMessage> recent = [];
  List<Product> products = [liveProduct('p1', 'Demlik', price: 250), liveProduct('p2', 'Bardak seti')];

  // yazma
  LiveHeartbeat heartbeatResult = const LiveHeartbeat(status: 'live');
  final List<int> heartbeats = [];
  LiveEndSummary endSummary = const LiveEndSummary(
    status: 'ended',
    endedReason: 'host',
    duration: Duration(minutes: 12, seconds: 5),
    peakViewerCount: 9,
    messageCount: 14,
  );
  final List<String> pinned = [];
  final List<String> sent = [];
  Object? sendError;
  final List<String> deleted = [];

  // geçmiş / ana sayfa kartı / abonelik
  final List<LiveHistoryPage> historyPages = [];
  Object? historyError;
  final List<LiveHistoryPage> myHistoryPages = [];
  Object? myHistoryError;
  LiveHomeCard homeCard = const LiveHomeCard();
  final Map<String, LiveSubscription> subscriptions = {};
  Object? subscriptionError;

  // akışlar
  final rows = StreamController<Map<String, dynamic>>.broadcast();
  final chat = StreamController<LiveChatEvent>.broadcast();
  final audience = StreamController<int>.broadcast();
  final changes = StreamController<PostgresChangePayload>.broadcast();
  bool? audienceCountsMe;

  @override
  String? get currentUserId => userId;

  @override
  Future<({LiveSession session, bool resumed})> createSession({
    required String shopId,
    required String title,
    String? description,
  }) async {
    calls.add('create');
    titles.add(title);
    if (createError != null) throw createError!;
    final json = liveSessionJson(
      status: created.status,
      title: title,
      isLive: created.isLiveNow,
      startedAt: created.startedAt,
    );
    created = LiveSession.fromJson(json);
    return (session: created, resumed: resumed);
  }

  @override
  Future<({LiveSession session, bool resumed})> createUserSession({required String title, String? description}) async {
    calls.add('create:user');
    titles.add(title);
    if (createError != null) throw createError!;
    created = LiveSession.fromJson(liveSessionJson(status: created.status, title: title, user: true));
    return (session: created, resumed: resumed);
  }

  @override
  Future<LiveCredentials> fetchCredentials(String sessionId, {required bool asHost}) async {
    calls.add(asHost ? 'token:host' : 'token:viewer');
    if (credentialsError != null) throw credentialsError!;
    return credentials;
  }

  @override
  Future<LiveSession> startLive(String sessionId) async {
    calls.add('start');
    return LiveSession.fromJson({
      ...liveSessionJson(
        status: 'live',
        isLive: true,
        title: created.title,
        startedAt: kLiveNow,
        user: created.isUserStream,
      ),
      if (startNotified != null) 'notified': startNotified,
    });
  }

  @override
  Future<LiveEndSummary> endLive(String sessionId) async {
    calls.add('end');
    return endSummary;
  }

  @override
  Future<LiveHeartbeat> heartbeat(String sessionId, int viewerCount) async {
    heartbeats.add(viewerCount);
    return heartbeatResult;
  }

  @override
  Future<LiveSession> pinProduct(String sessionId, String productId) async {
    pinned.add(productId);
    final product = products.firstWhere((p) => p.id == productId);
    return LiveSession.fromJson(liveSessionJson(
      status: 'live',
      isLive: true,
      title: created.title,
      startedAt: kLiveNow,
      pinned: pinnedJson(id: product.id, name: product.name, price: product.price),
    ));
  }

  @override
  Future<LiveSession> unpinProduct(String sessionId) async {
    pinned.add('-');
    return LiveSession.fromJson(liveSessionJson(status: 'live', isLive: true, title: created.title, startedAt: kLiveNow));
  }

  @override
  Future<LiveFeed> fetchFeed({int limit = 30}) async {
    calls.add('feed');
    if (feedError != null) throw feedError!;
    return feed;
  }

  @override
  Future<LiveSession?> fetchSession(String sessionId) async {
    calls.add('detail');
    return detail;
  }

  @override
  Future<LiveHistoryPage> fetchHistory({int limit = 20, int offset = 0, String? shopId}) async {
    calls.add('history:$offset${shopId == null ? '' : ':$shopId'}');
    if (historyError != null) throw historyError!;
    final index = offset ~/ (limit <= 0 ? 1 : limit);
    return index < historyPages.length ? historyPages[index] : const LiveHistoryPage();
  }

  @override
  Future<LiveHistoryPage> fetchMyHistory({int limit = 20, int offset = 0}) async {
    calls.add('mine:$offset');
    if (myHistoryError != null) throw myHistoryError!;
    final index = offset ~/ (limit <= 0 ? 1 : limit);
    return index < myHistoryPages.length ? myHistoryPages[index] : const LiveHistoryPage();
  }

  @override
  Future<LiveHomeCard> fetchHomeCard() async {
    calls.add('home');
    return homeCard;
  }

  @override
  Future<LiveSubscription> fetchSubscription(String shopId) async {
    calls.add('sub:get:$shopId');
    return subscriptions[shopId] ?? LiveSubscription(shopId: shopId);
  }

  @override
  Future<LiveSubscription> setSubscription(String shopId, bool subscribed) async {
    calls.add('sub:set:$shopId:$subscribed');
    if (subscriptionError != null) throw subscriptionError!;
    final before = subscriptions[shopId] ?? LiveSubscription(shopId: shopId);
    final count = before.subscribers + (subscribed == before.subscribed ? 0 : (subscribed ? 1 : -1));
    return subscriptions[shopId] = LiveSubscription(shopId: shopId, subscribed: subscribed, subscribers: count);
  }

  @override
  Future<List<LiveMessage>> fetchRecentMessages(String sessionId, {int limit = 50}) async => recent;

  @override
  Future<List<Product>> fetchShopProducts(String shopId) async => products;

  @override
  Future<LiveMessage> sendMessage(String sessionId, String text) async {
    if (sendError != null) throw sendError!;
    sent.add(text);
    return liveMessage('sent-${sent.length}', text, host: userId == 'owner-1', author: 'ben');
  }

  @override
  Future<void> deleteMessage(String messageId) async => deleted.add(messageId);

  @override
  Stream<Map<String, dynamic>> watchSessionRow(String sessionId) => rows.stream;

  @override
  Stream<LiveChatEvent> watchChat(String sessionId) => chat.stream;

  @override
  Stream<int> watchAudience(String sessionId, {required bool countMe}) {
    audienceCountsMe = countMe;
    return audience.stream;
  }

  @override
  Stream<PostgresChangePayload> watchAllSessions() => changes.stream;
}

class FakeLiveEngine implements LiveVideoEngine {
  FakeLiveEngine({this.supported = true});

  final bool supported;
  final List<String> calls = [];
  LiveEngineEvents? events;
  Object? previewError;
  bool micMuted = false;
  bool cameraEnabled = true;
  bool remoteMuted = false;
  String? renewedToken;

  @override
  bool get isSupported => supported;

  @override
  Future<void> startPreview(LiveCredentials credentials) async {
    calls.add('preview');
    if (previewError != null) throw previewError!;
  }

  @override
  Future<void> joinAsHost(LiveCredentials credentials, LiveEngineEvents events) async {
    calls.add('joinHost:${credentials.uid}');
    this.events = events;
  }

  @override
  Future<void> joinAsViewer(LiveCredentials credentials, LiveEngineEvents events) async {
    calls.add('joinViewer:${credentials.uid}');
    this.events = events;
  }

  @override
  Future<void> renewToken(String token) async => renewedToken = token;

  @override
  Future<void> setMicMuted(bool muted) async => micMuted = muted;

  @override
  Future<void> setCameraEnabled(bool enabled) async => cameraEnabled = enabled;

  @override
  Future<void> switchCamera() async => calls.add('switch');

  @override
  Future<void> setRemoteAudioMuted(bool muted) async => remoteMuted = muted;

  @override
  Widget buildLocalView() => const ColoredBox(key: ValueKey('fake-local-view'), color: Colors.blueGrey);

  @override
  Widget buildRemoteView(int uid) => ColoredBox(key: ValueKey('fake-remote-view-$uid'), color: Colors.teal);

  @override
  Future<void> leave() async => calls.add('leave');

  @override
  Future<void> dispose() async => calls.add('dispose');
}
