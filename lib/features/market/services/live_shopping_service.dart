import 'dart:async';
import 'dart:io' show SocketException;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/models/live_shopping_model.dart';
import '../../../core/models/product_model.dart';
import 'product_service.dart';

/// Sohbet olayı: yeni mesaj ya da silinen (moderasyon) mesajın kimliği.
class LiveChatEvent {
  final LiveMessage? message;
  final String? deletedId;

  const LiveChatEvent.message(LiveMessage this.message) : deletedId = null;
  const LiveChatEvent.deleted(String this.deletedId) : message = null;
}

/// Canlı yayın servisi (Görev 3.4).
///
/// Tüm yazmalar DEFINER RPC'lerle (sunucu yayın durumunu, izleyici sayısını ve
/// sabit ürünü doğrular); Agora anahtarı `live-token` Edge Function'ından
/// (App Certificate yalnız sunucuda). Mesaj yazar adı sunucuda yazılır.
/// Anlık akış: `live_sessions` satırı (durum/izleyici/sabit ürün), sohbet
/// (INSERT + moderasyon DELETE) ve Realtime presence ile izleyici sayısı.
class LiveShoppingService {
  LiveShoppingService({SupabaseClient? client}) : _clientOverride = client;

  final SupabaseClient? _clientOverride;

  SupabaseClient get _client => _clientOverride ?? Supabase.instance.client;

  String? get currentUserId => _client.auth.currentUser?.id;

  // ------------------------------------------------------------------ okuma

  Future<LiveFeed> fetchFeed({int limit = 30}) => _guard(() async {
    final data = await _client.rpc('live_sessions_feed', params: {'p_limit': limit});
    return data is Map ? LiveFeed.fromJson(Map<String, dynamic>.from(data)) : const LiveFeed();
  });

  Future<LiveSession?> fetchSession(String sessionId) => _guard(() async {
    final data = await _client.rpc('live_session_detail', params: {'p_session_id': sessionId});
    return data is Map ? LiveSession.fromJson(Map<String, dynamic>.from(data)) : null;
  });

  /// Biten yayınlar (en yeni önce, yönetici ayarındaki gün kadar geriye).
  /// [shopId] verilirse yalnız o mağazanınkiler.
  Future<LiveHistoryPage> fetchHistory({int limit = 20, int offset = 0, String? shopId}) => _guard(() async {
    final data = await _client.rpc(
      'live_history',
      params: {'p_limit': limit, 'p_offset': offset, 'p_shop_id': shopId},
    );
    return data is Map ? LiveHistoryPage.fromJson(Map<String, dynamic>.from(data)) : const LiveHistoryPage();
  });

  /// Yayınlarım: oturumdaki kişinin biten yayınları (mağaza ya da kullanıcı
  /// yayını), en yeni önce, süre sınırı yok. Misafirde sunucu AUTH_REQUIRED.
  Future<LiveHistoryPage> fetchMyHistory({int limit = 20, int offset = 0}) => _guard(() async {
    final data = await _client.rpc('live_my_history', params: {'p_limit': limit, 'p_offset': offset});
    return data is Map ? LiveHistoryPage.fromJson(Map<String, dynamic>.from(data)) : const LiveHistoryPage();
  });

  /// Ana sayfa kartı: canlı yayın (en çok izlenen) ya da son 24 saatte biten yayın.
  Future<LiveHomeCard> fetchHomeCard() => _guard(() async {
    final data = await _client.rpc('live_home_card');
    return data is Map ? LiveHomeCard.fromJson(Map<String, dynamic>.from(data)) : const LiveHomeCard();
  });

  /// Mağazanın yayın bildirimi aboneliği (misafirde subscribed=false).
  Future<LiveSubscription> fetchSubscription(String shopId) => _guard(() async {
    final data = await _client.rpc('live_shop_subscription', params: {'p_shop_id': shopId});
    return LiveSubscription.fromJson(Map<String, dynamic>.from(data as Map), shopId: shopId);
  });

  /// "Yayınlarından haberdar ol" aç/kapat (giriş gerekir).
  Future<LiveSubscription> setSubscription(String shopId, bool subscribed) => _guard(() async {
    if (currentUserId == null) throw const LiveException(LiveFailure.authRequired);
    final data = await _client.rpc('live_set_subscription', params: {'p_shop_id': shopId, 'p_on': subscribed});
    return LiveSubscription.fromJson(Map<String, dynamic>.from(data as Map), shopId: shopId);
  });

  Future<List<LiveMessage>> fetchRecentMessages(String sessionId, {int limit = 50}) => _guard(() async {
    final rows = await _client
        .from('live_messages')
        .select('id, session_id, user_id, message, is_host, author_name, author_avatar, created_at')
        .eq('session_id', sessionId)
        .order('created_at', ascending: false)
        .limit(limit);
    return (rows as List)
        .map((row) => LiveMessage.fromJson(Map<String, dynamic>.from(row as Map)))
        .toList()
        .reversed
        .toList();
  });

  /// Satıcının yayında sabitleyebileceği ürünler (satıştakiler).
  Future<List<Product>> fetchShopProducts(String shopId) => ProductService().getShopProducts(shopId);

  // ------------------------------------------------------------ satıcı akışı

  /// Yayın hazırla ya da mağazanın açık yayınını sürdür. `resumed` = taze canlı
  /// yayın vardı (uygulama kapanıp açıldı) → hazırlık adımı atlanır.
  Future<({LiveSession session, bool resumed})> createSession({
    required String shopId,
    required String title,
    String? description,
  }) => _guard(() async {
    final data = await _client.rpc(
      'live_create_session',
      params: {'p_shop_id': shopId, 'p_title': title, 'p_description': description},
    );
    final json = Map<String, dynamic>.from(data as Map);
    return (session: LiveSession.fromJson(json), resumed: json['resumed'] == true);
  });

  /// Kişinin kullanıcı yayını açma erişimi: 'ok' ya da sunucu kodu
  /// (AUTH_REQUIRED, LIVE_USERS_OFF, LIVE_USER_NOT_PERMITTED, …).
  Future<String> fetchMyStreamAccess() => _guard(() async {
    if (currentUserId == null) return 'AUTH_REQUIRED';
    final data = await _client.rpc('live_my_stream_access');
    return (data is Map ? data['access']?.toString() : null) ?? 'unknown';
  });

  /// "Yayın aç" / hikaye ekranındaki "Canlı" düğmesi gösterilsin mi.
  /// Ağ hatasında false (düğme gizli kalır, kural yine sunucuda).
  Future<bool> canStartUserStream() async {
    try {
      return await fetchMyStreamAccess() == 'ok';
    } catch (_) {
      return false;
    }
  }

  /// Kullanıcı (mağazasız) yayını hazırla ya da açık yayınını sürdür.
  Future<({LiveSession session, bool resumed})> createUserSession({
    required String title,
    String? description,
  }) => _guard(() async {
    final data = await _client.rpc(
      'live_create_user_session',
      params: {'p_title': title, 'p_description': description},
    );
    final json = Map<String, dynamic>.from(data as Map);
    return (session: LiveSession.fromJson(json), resumed: json['resumed'] == true);
  });

  Future<LiveSession> startLive(String sessionId) => _sessionRpc('start_live_session', {'p_session_id': sessionId});

  /// Yayını bitirir; hiç başlamamışsa kayıt silinir (status 'discarded').
  Future<LiveEndSummary> endLive(String sessionId) => _guard(() async {
    final data = await _client.rpc('end_live_session', params: {'p_session_id': sessionId});
    return LiveEndSummary.fromJson(Map<String, dynamic>.from(data as Map));
  });

  /// 20 sn'de bir: "yayındayım" + anlık izleyici sayısı.
  Future<LiveHeartbeat> heartbeat(String sessionId, int viewerCount) => _guard(() async {
    final data = await _client.rpc(
      'live_session_heartbeat',
      params: {'p_session_id': sessionId, 'p_viewer_count': viewerCount},
    );
    return LiveHeartbeat.fromJson(Map<String, dynamic>.from(data as Map));
  });

  Future<LiveSession> pinProduct(String sessionId, String productId) =>
      _sessionRpc('live_pin_product', {'p_session_id': sessionId, 'p_product_id': productId});

  Future<LiveSession> unpinProduct(String sessionId) =>
      _sessionRpc('live_unpin_product', {'p_session_id': sessionId});

  /// Agora'ya katılma bilgileri (App ID + kısa ömürlü anahtar + uid).
  Future<LiveCredentials> fetchCredentials(String sessionId, {required bool asHost}) => _guard(() async {
    final response = await _client.functions.invoke(
      'live-token',
      body: {'session_id': sessionId, 'role': asHost ? 'host' : 'viewer'},
    );
    final data = response.data;
    if (data is! Map) throw const LiveException(LiveFailure.unknown, 'boş yanıt');
    if (data['ok'] != true) {
      throw LiveException(LiveFailure.fromCode(data['error']?.toString()), data['error']?.toString());
    }
    return LiveCredentials.fromJson(Map<String, dynamic>.from(data));
  });

  // ------------------------------------------------------------------ sohbet

  /// Mesaj gönderir; eklenen satır döner (Realtime yankısı kimlikle ayıklanır).
  Future<LiveMessage> sendMessage(String sessionId, String text) => _guard(() async {
    final userId = currentUserId;
    if (userId == null) throw const LiveException(LiveFailure.authRequired);
    final row = await _client
        .from('live_messages')
        .insert({'session_id': sessionId, 'user_id': userId, 'message': text})
        .select('id, session_id, user_id, message, is_host, author_name, author_avatar, created_at')
        .single();
    return LiveMessage.fromJson(row);
  });

  /// Satıcı moderasyonu (RLS: yalnız yayının sahibi).
  Future<void> deleteMessage(String messageId) => _guard(() async {
    await _client.from('live_messages').delete().eq('id', messageId);
  });

  // ---------------------------------------------------------- anlık akışlar

  /// Yayın satırındaki değişiklikler (durum, izleyici, sabit ürün, bitiş).
  Stream<Map<String, dynamic>> watchSessionRow(String sessionId) {
    late final RealtimeChannel channel;
    final controller = StreamController<Map<String, dynamic>>.broadcast(
      onCancel: () => _client.removeChannel(channel),
    );
    channel = _client
        .channel('live_session:$sessionId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'live_sessions',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'id', value: sessionId),
          callback: (payload) {
            if (!controller.isClosed) controller.add(Map<String, dynamic>.from(payload.newRecord));
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'live_sessions',
          callback: (payload) {
            // Hiç başlamamış kayıt silindi: bitmiş say.
            if (payload.oldRecord['id']?.toString() == sessionId && !controller.isClosed) {
              controller.add({'id': sessionId, 'status': 'ended'});
            }
          },
        )
        .subscribe();
    return controller.stream;
  }

  /// Sohbet: yeni mesajlar (yayına süzülmüş) ve silinenler (DELETE olayları
  /// süzülemez; kimliğe göre ayıklanır).
  Stream<LiveChatEvent> watchChat(String sessionId) {
    late final RealtimeChannel channel;
    final controller = StreamController<LiveChatEvent>.broadcast(
      onCancel: () => _client.removeChannel(channel),
    );
    channel = _client
        .channel('live_chat:$sessionId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'live_messages',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'session_id', value: sessionId),
          callback: (payload) {
            try {
              final message = LiveMessage.fromJson(Map<String, dynamic>.from(payload.newRecord));
              if (!controller.isClosed) controller.add(LiveChatEvent.message(message));
            } catch (e) {
              debugPrint('live chat parse: $e');
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'live_messages',
          callback: (payload) {
            final id = payload.oldRecord['id']?.toString();
            if (id != null && !controller.isClosed) controller.add(LiveChatEvent.deleted(id));
          },
        )
        .subscribe();
    return controller.stream;
  }

  /// İzleyici sayısı (Realtime presence). İzleyici `countMe: true` ile kendini
  /// sayar; satıcı yalnız sayar. Kalıcı yazma yok; bağlantı kopunca düşer.
  Stream<int> watchAudience(String sessionId, {required bool countMe}) {
    late final RealtimeChannel channel;
    final controller = StreamController<int>.broadcast(onCancel: () => _client.removeChannel(channel));
    void publish() {
      if (controller.isClosed) return;
      try {
        controller.add(channel.presenceState().length);
      } catch (e) {
        debugPrint('live audience: $e');
      }
    }

    channel = _client.channel('live_audience:$sessionId')
      ..onPresenceSync((_) => publish())
      ..onPresenceJoin((_) => publish())
      ..onPresenceLeave((_) => publish());
    channel.subscribe((status, error) async {
      if (status == RealtimeSubscribeStatus.subscribed && countMe) {
        try {
          await channel.track({'at': DateTime.now().toUtc().toIso8601String()});
        } catch (e) {
          debugPrint('live audience track: $e');
        }
      }
    });
    return controller.stream;
  }

  /// Keşfet listesi için tüm yayın değişiklikleri (INSERT/UPDATE/DELETE).
  Stream<PostgresChangePayload> watchAllSessions() {
    late final RealtimeChannel channel;
    final controller = StreamController<PostgresChangePayload>.broadcast(
      onCancel: () => _client.removeChannel(channel),
    );
    channel = _client
        .channel('live_sessions_feed')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'live_sessions',
          callback: (payload) {
            if (!controller.isClosed) controller.add(payload);
          },
        )
        .subscribe();
    return controller.stream;
  }

  // -------------------------------------------------------------- yardımcı

  Future<LiveSession> _sessionRpc(String fn, Map<String, dynamic> params) => _guard(() async {
    final data = await _client.rpc(fn, params: params);
    return LiveSession.fromJson(Map<String, dynamic>.from(data as Map));
  });

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } catch (e) {
      throw toLiveException(e);
    }
  }

  /// Sunucu ipucu (HINT) / Edge Function hata kodu → [LiveException].
  static LiveException toLiveException(Object error) {
    if (error is LiveException) return error;
    if (error is PostgrestException) {
      final byHint = LiveFailure.fromCode(error.hint);
      if (byHint != LiveFailure.unknown) {
        // Görev 4.3: izin kaldırıldıysa yönetimin notu DETAIL'de gelir.
        final note = byHint == LiveFailure.revoked || byHint == LiveFailure.userRevoked
            ? error.details?.toString()
            : null;
        return LiveException(byHint, error.message, note);
      }
      if (error.code == '42501') return LiveException(LiveFailure.authRequired, error.message);
      return LiveException(LiveFailure.unknown, error.message);
    }
    if (error is FunctionException) {
      final details = error.details;
      final code = details is Map ? details['error']?.toString() : null;
      final failure = LiveFailure.fromCode(code);
      if (failure != LiveFailure.unknown) return LiveException(failure, code);
      return LiveException(LiveFailure.connection, 'HTTP ${error.status}');
    }
    if (error is SocketException || error is http.ClientException || error is TimeoutException) {
      return LiveException(LiveFailure.connection, error.toString());
    }
    return LiveException(LiveFailure.unknown, error.toString());
  }
}
