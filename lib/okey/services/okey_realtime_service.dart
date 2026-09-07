import 'package:supabase_flutter/supabase_flutter.dart';

/// Bir maçın tüm realtime kanallarını tek bir yerden yönetir. chat_service.dart
/// deseni: her subscribe öncesi aynı isimli kanal varsa kaldırılır (çift
/// subscribe önleme). Kaçırılan event'lere hiç güvenilmez — her callback
/// sadece "bir şey değişti, tazele" sinyali olarak kullanılır; gerçek state
/// her zaman ayrıca bir SELECT ile DB'den okunur (OkeyGameProvider.refresh).
class OkeyRealtimeService {
  SupabaseClient get _client => Supabase.instance.client;
  RealtimeChannel? _channel;

  /// HEDİYE KANALI AYRI — çünkü ANAHTARI da ayrı.
  ///
  /// Maçın tüm tabloları `match_id` ile süzülür; hediye ise ODAYA aittir
  /// (masaya el değişse de aynı masadır, üstelik izleyici de gönderir).
  /// Aynı kanala eklenseydi oda kimliği bilinene kadar maç aboneliği de
  /// beklerdi — masa ilk açılışta gereksiz yere geç canlanırdı.
  RealtimeChannel? _giftChannel;

  void subscribe({
    required String matchId,
    required void Function() onMatchChanged,
    required void Function() onHandChanged,
    required void Function() onMeldsChanged,
    required void Function() onMovesChanged,
  }) {
    final channelName = 'okey_match:$matchId';
    final existing = _client.channel(channelName);
    _client.removeChannel(existing);

    final uid = _client.auth.currentUser?.id;

    final channel = _client.channel(channelName);
    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'okey_matches',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'id',
        value: matchId,
      ),
      callback: (_) => onMatchChanged(),
    );

    if (uid != null) {
      channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'okey_player_hands',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'match_id',
          value: matchId,
        ),
        callback: (_) => onHandChanged(),
      );
    }

    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'okey_table_melds',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'match_id',
        value: matchId,
      ),
      callback: (_) => onMeldsChanged(),
    );

    channel.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'okey_moves',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'match_id',
        value: matchId,
      ),
      callback: (_) => onMovesChanged(),
    );

    channel.subscribe();
    _channel = channel;
  }

  /// Masaya gönderilen hediyeler — oda kimliği bilinir bilinmez abone olunur.
  ///
  /// Yalnızca INSERT dinlenir: hediye kaydı hiç güncellenmez, silinmez.
  void subscribeGifts({
    required String roomId,
    required void Function(Map<String, dynamic> row) onGift,
  }) {
    final channelName = 'okey_gifts:$roomId';
    final existing = _client.channel(channelName);
    _client.removeChannel(existing);

    final channel = _client.channel(channelName);
    channel.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'okey_gifts_sent',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'room_id',
        value: roomId,
      ),
      callback: (payload) => onGift(payload.newRecord),
    );
    channel.subscribe();
    _giftChannel = channel;
  }

  /// YALNIZCA maç kanalını kapatır; hediye kanalı ODAYA aittir ve masada
  /// kalınmaya devam ediliyorsa yaşamalıdır.
  ///
  /// Yeni ele geçerken (bkz. OkeyGameProvider.switchToMatch) maç kimliği
  /// değişir ama oda aynıdır. [unsubscribe] çağrılsaydı hediye kanalı da
  /// kapanır, yeni elde masaya gönderilen hediyeler hiç görünmezdi.
  Future<void> unsubscribeMatch() async {
    final channel = _channel;
    _channel = null;
    if (channel != null) {
      await _client.removeChannel(channel);
    }
  }

  Future<void> unsubscribe() async {
    final channel = _channel;
    _channel = null;
    if (channel != null) {
      await _client.removeChannel(channel);
    }
    final gifts = _giftChannel;
    _giftChannel = null;
    if (gifts != null) {
      await _client.removeChannel(gifts);
    }
  }
}
