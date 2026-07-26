import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/live_shopping_model.dart';

/// Canlı Yayın Alışverişi servisi - Agora kanalı + Supabase Realtime senkronu.
/// Agora token üretimi sunucu tarafında (Edge Function) yapılması önerilir,
/// ancak basit başlangıç için client-side AppID ile çalışır (PrimaryCertificate
/// olmadan, sadece 7 gün test limiti).
class LiveShoppingService {
  SupabaseClient get _supabase => Supabase.instance.client;

  // ------------------ KEŞFET ------------------

  /// Şu an aktif olan (live) yayınları getir. Keşfet sayfası için.
  Future<List<LiveSession>> getLiveSessions({int limit = 30}) async {
    try {
      final response = await _supabase
          .from('live_sessions')
          .select('''
            *,
            shops!inner(id, name),
            users!host_user_id(id, full_name, username, avatar_url),
            live_pinned_products!left(
              is_current,
              products(id, name, image_url, price, discount_price)
            )
          ''')
          .eq('status', 'live')
          .order('started_at', ascending: false)
          .limit(limit);

      return (response as List)
          .map((j) => LiveSession.fromJson(j as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('LiveShoppingService.getLiveSessions error: $e');
      rethrow;
    }
  }

  /// Son biten yayınlar (sayfa altında göstermek için).
  Future<List<LiveSession>> getRecentEndedSessions({int limit = 20}) async {
    try {
      final response = await _supabase
          .from('live_sessions')
          .select('*, shops!inner(id, name), users!host_user_id(id, full_name)')
          .eq('status', 'ended')
          .order('ended_at', ascending: false)
          .limit(limit);
      return (response as List)
          .map((j) => LiveSession.fromJson(j as Map<String, dynamic>))
          .toList();
    } catch (e) {
      rethrow;
    }
  }

  /// ID'ye göre tek bir oturum getir.
  Future<LiveSession?> getSessionById(String sessionId) async {
    try {
      final response = await _supabase
          .from('live_sessions')
          .select('''
            *,
            shops!inner(id, name),
            users!host_user_id(id, full_name, username, avatar_url),
            live_pinned_products!left(
              is_current,
              products(id, name, image_url, price, discount_price)
            )
          ''')
          .eq('id', sessionId)
          .maybeSingle();
      if (response == null) return null;
      return LiveSession.fromJson(response);
    } catch (e) {
      debugPrint('getSessionById error: $e');
      return null;
    }
  }

  // ------------------ HOST (Satıcı) ------------------

  /// Yeni yayın oluştur. Status 'scheduled' olarak başlar; startLive ile 'live' olur.
  Future<LiveSession> createSession({
    required String shopId,
    required String title,
    String? description,
    String? coverImageUrl,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('Oturum açmanız gerekli');

    // channel_name: channel_<uuid_no_dash> - basit unique
    final channelName =
        'channel_${DateTime.now().millisecondsSinceEpoch}_${userId.substring(0, 8)}';

    final response = await _supabase
        .from('live_sessions')
        .insert({
          'host_user_id': userId,
          'shop_id': shopId,
          'title': title,
          'description': description,
          'cover_image_url': coverImageUrl,
          'channel_name': channelName,
          'status': 'scheduled',
        })
        .select('''
          *,
          shops!inner(id, name),
          users!host_user_id(id, full_name, username, avatar_url)
        ''')
        .single();
    return LiveSession.fromJson(response);
  }

  /// Yayını başlat (status -> live, started_at set).
  Future<void> startLive(String sessionId) async {
    await _supabase.rpc('start_live_session', params: {
      'p_session_id': sessionId,
    });
  }

  /// Yayını bitir.
  Future<void> endLive(String sessionId) async {
    await _supabase.rpc('end_live_session', params: {
      'p_session_id': sessionId,
    });
  }

  /// Satıcının kendi mağazasının yayınlarını listele.
  Future<List<LiveSession>> getMyShopSessions(String shopId) async {
    try {
      final response = await _supabase
          .from('live_sessions')
          .select('*, shops!inner(id, name)')
          .eq('shop_id', shopId)
          .order('created_at', ascending: false);
      return (response as List)
          .map((j) => LiveSession.fromJson(j as Map<String, dynamic>))
          .toList();
    } catch (e) {
      rethrow;
    }
  }

  // ------------------ PINNED PRODUCT (Satıcı) ------------------

  /// Yayında ürün pinle (eski pini is_current=false yapar, yeni pin ekler).
  Future<void> pinProduct({
    required String sessionId,
    required String productId,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('Oturum açmanız gerekli');

    // Önce mevcut pin'leri false yap
    await _supabase
        .from('live_pinned_products')
        .update({'is_current': false})
        .eq('session_id', sessionId)
        .eq('is_current', true);

    // Yeni pin ekle
    await _supabase.from('live_pinned_products').insert({
      'session_id': sessionId,
      'product_id': productId,
      'pinned_by': userId,
      'is_current': true,
    });
  }

  /// Pin'i kaldır.
  Future<void> unpinProduct(String sessionId) async {
    await _supabase
        .from('live_pinned_products')
        .update({'is_current': false})
        .eq('session_id', sessionId)
        .eq('is_current', true);
  }

  // ------------------ MESSAGES ------------------

  /// Yorum gönder. Realtime broadcast ile anlık olarak diğer kullanıcılara da yansır
  /// (live_messages tablosu postgres_changes ile sub). İstersen ek olarak
  /// channel.sendBroadcastMessage() ile çift kanaldan yayınlayabilirsin.
  Future<void> sendMessage({
    required String sessionId,
    required String message,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('Oturum açmanız gerekli');
    await _supabase.from('live_messages').insert({
      'session_id': sessionId,
      'user_id': userId,
      'message': message,
      'is_host': false,
    });
  }

  /// Son N mesajı getir.
  Future<List<LiveMessage>> getRecentMessages(
    String sessionId, {
    int limit = 50,
  }) async {
    try {
      final response = await _supabase
          .from('live_messages')
          .select('*, users(id, full_name, username, avatar_url)')
          .eq('session_id', sessionId)
          .order('created_at', ascending: false)
          .limit(limit);
      final list = (response as List)
          .map((j) => LiveMessage.fromJson(j as Map<String, dynamic>))
          .toList();
      return list.reversed.toList();
    } catch (e) {
      debugPrint('getRecentMessages error: $e');
      return [];
    }
  }

  /// Realtime: yeni mesaj geldiğinde stream emit eder.
  Stream<LiveMessage> watchMessages(String sessionId) {
    final controller = StreamController<LiveMessage>.broadcast();
    final channel = _supabase
        .channel('live_msg_$sessionId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'live_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'session_id',
            value: sessionId,
          ),
          callback: (payload) {
            try {
              final record = payload.newRecord;
              controller.add(LiveMessage.fromJson(record));
            } catch (e) {
              debugPrint('watchMessages parse: $e');
            }
          },
        )
        .subscribe();
    controller.onCancel = () => _supabase.removeChannel(channel);
    return controller.stream;
  }

  /// Realtime: pin değişimi (ürün ekle/kaldır). UI'da alt pinned product kartını günceller.
  Stream<void> watchPinChanges(String sessionId) {
    final controller = StreamController<void>.broadcast();
    final channel = _supabase
        .channel('live_pin_$sessionId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'live_pinned_products',
          callback: (_) => controller.add(null),
        )
        .subscribe();
    controller.onCancel = () => _supabase.removeChannel(channel);
    return controller.stream;
  }
}