import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// "Yazıyor…" bilgisinin taşındığı katman. Mantık ([TypingChannel]) ile ağ
/// ([SupabaseTypingTransport]) ayrıdır ki zamanlama kuralları sahte bir taşıma
/// ile test edilebilsin.
abstract class TypingTransport {
  /// Kanal adını sunucudan alır ve abone olur.
  ///
  /// Özellik kapalı, kullanıcılar arasında engel var ya da (grupta) üye
  /// değilsen `false` döner ve hiçbir kanal açılmaz. [onEvent] karşıdan gelen her
  /// yayın için, [onJoined] kanal katıldığında/koptuğunda çağrılır.
  Future<bool> open({
    required void Function(Map<String, dynamic> payload) onEvent,
    required void Function(bool joined) onJoined,
  });

  /// Sunucu bu kullanıcının kendi "yazıyor" bilgisini paylaşmasına izin veriyor mu
  /// (kullanıcı tercihi kapalıysa false; yine de karşıyı görebilir).
  bool get canSend;

  /// Kanal katıldı mı? Katılmadan gönderim REST'e düşer; yazıyor gibi geçici bir
  /// sinyal için buna değmez, bu yüzden gönderilmez.
  bool get isJoined;

  void send(Map<String, dynamic> payload);

  Future<void> close();
}

/// Bir sohbetteki "yazıyor…" durumu: hem kendi yazdığını karşıya bildirir hem de
/// karşıdakilerin yazdığını izler.
///
/// Kurallar:
///  * yazmaya başlayınca HEMEN bir "yazıyor" gider, yazmaya devam ettikçe en çok
///    [pingEvery] aralıkla tekrarlanır (kanalı boğmamak için);
///  * [idleAfter] boyunca metin değişmezse ya da metin boşalırsa/mesaj gidince
///    "yazmıyor" gönderilir (yarım kalmış metin sonsuza dek "yazıyor" bırakmaz);
///  * alıcı, son "yazıyor"dan [expireAfter] sonra kendiliğinden düşer (bağlantısı
///    kopan birinin göstergesi takılı kalmaz).
class TypingChannel {
  TypingChannel({
    required this.transport,
    required this.selfId,
    this.pingEvery = const Duration(seconds: 3),
    this.idleAfter = const Duration(seconds: 5),
    this.expireAfter = const Duration(seconds: 6),
  });

  final TypingTransport transport;
  final String selfId;
  final Duration pingEvery;
  final Duration idleAfter;
  final Duration expireAfter;

  final ValueNotifier<Set<String>> _typing = ValueNotifier(const <String>{});

  /// Şu an yazmakta olan kullanıcılar (kendin hariç).
  ValueListenable<Set<String>> get typing => _typing;

  final Map<String, Timer> _expiry = {};
  Timer? _pingCooldown;
  Timer? _idle;
  bool _sentTyping = false;
  bool _started = false;
  bool _closed = false;

  /// Kanal gerçekten açıldı mı (özellik açık ve izin var).
  bool get isActive => _started && !_closed;

  Future<void> start() async {
    if (_started || _closed) return;
    _started = true;
    final opened = await transport.open(
      onEvent: _onEvent,
      onJoined: _onJoined,
    );
    if (!opened) _started = false;
    if (_closed) await transport.close();
  }

  /// Metin kutusu her değiştiğinde çağrılır.
  void onTextChanged(String text) {
    if (_closed || !_started || !transport.canSend) return;

    if (text.trim().isEmpty) {
      stopTyping();
      return;
    }

    // Ping YALNIZ gerçekten gittiyse sayılır: kanal henüz katılmadıysa bir
    // sonraki tuşta yeniden denenir (aksi halde ilk sinyal 3 sn kaybolurdu).
    if (_pingCooldown == null && _send(true)) {
      _sentTyping = true;
      _pingCooldown = Timer(pingEvery, () => _pingCooldown = null);
    }
    _idle?.cancel();
    _idle = Timer(idleAfter, stopTyping);
  }

  /// Mesaj gönderilince, ekran arka plana gidince, kutu boşalınca çağrılır.
  void stopTyping() {
    _idle?.cancel();
    _idle = null;
    _pingCooldown?.cancel();
    _pingCooldown = null;
    if (_sentTyping) {
      _sentTyping = false;
      _send(false);
    }
  }

  bool _send(bool typing) {
    if (!transport.isJoined || !transport.canSend) return false;
    // Her seferinde YENİ bir harita: realtime istemcisi gönderilen haritaya
    // `type` ve `event` anahtarlarını ekleyerek onu değiştirir.
    transport.send({'u': selfId, 't': typing});
    return true;
  }

  // Kanal kapandıktan sonra yoldaki geç bir olay gelebilir; atılmış bildirimciye
  // dokunmamak için kapalıyken hiçbir olay işlenmez.
  void _onJoined(bool joined) {
    if (_closed) return;
    if (!joined) _clearTyping();
  }

  void _onEvent(Map<String, dynamic> raw) {
    if (_closed) return;
    final data = unwrap(raw);
    final uid = data['u'];
    if (uid is! String || uid.isEmpty || uid == selfId) return;

    _expiry.remove(uid)?.cancel();
    if (data['t'] == true) {
      if (!_typing.value.contains(uid)) {
        _typing.value = {..._typing.value, uid};
      }
      _expiry[uid] = Timer(expireAfter, () => _drop(uid));
    } else {
      _drop(uid);
    }
  }

  void _drop(String uid) {
    _expiry.remove(uid)?.cancel();
    if (_typing.value.contains(uid)) {
      _typing.value = {..._typing.value}..remove(uid);
    }
  }

  void _clearTyping() {
    for (final timer in _expiry.values) {
      timer.cancel();
    }
    _expiry.clear();
    if (_typing.value.isNotEmpty) _typing.value = const <String>{};
  }

  /// Realtime istemcisi yayını düz ya da `payload` altında sarmalanmış
  /// verebilir; ikisini de kabul et.
  @visibleForTesting
  static Map<String, dynamic> unwrap(Map<String, dynamic> raw) {
    final inner = raw['payload'];
    if (inner is Map) return Map<String, dynamic>.from(inner);
    return raw;
  }

  Future<void> dispose() async {
    if (_closed) return;
    // "Yazmıyor"u kanal kapanmadan ÖNCE gönder.
    stopTyping();
    _closed = true;
    _clearTyping();
    _pingCooldown?.cancel();
    _idle?.cancel();
    try {
      await transport.close();
    } catch (e) {
      debugPrint('⚠️ Yazıyor kanalı kapatılamadı: $e');
    }
    _typing.dispose();
  }
}

/// Supabase Realtime üzerinden taşıma.
///
/// Kanal adı TAHMİN EDİLEMEZ: sunucudaki gizli anahtarla HMAC'lenmiş çift
/// kimliğidir ve yalnız o çiftin kendisine verilir (bkz.
/// `get_typing_channel`). Veritabanına hiçbir şey yazılmaz.
class SupabaseTypingTransport implements TypingTransport {
  SupabaseTypingTransport.direct(String peerId, {SupabaseClient? client})
    : _rpcName = 'get_typing_channel',
      _rpcParams = {'p_peer': peerId},
      _clientOverride = client;

  SupabaseTypingTransport.group(String groupId, {SupabaseClient? client})
    : _rpcName = 'get_group_typing_channel',
      _rpcParams = {'p_group_id': groupId},
      _clientOverride = client;

  final String _rpcName;
  final Map<String, dynamic> _rpcParams;
  final SupabaseClient? _clientOverride;

  /// AÇIK kanallar (istemci + konu adına göre). Aynı konuya hızlı çık-gir
  /// yapılınca eski kanal kapanmadan yenisi açılmasın diye (RealtimeChannel.topic
  /// dışarıdan kullanılamadığı için kayıt burada tutulur). Anahtar istemciyi de
  /// içerir: iki ayrı istemci (test) aynı konuyu birbirinin kanalını kapatmadan
  /// açabilmeli.
  static final Map<String, RealtimeChannel> _openChannels = {};

  String _channelKey(String topic) => '${identityHashCode(_client)}|$topic';

  RealtimeChannel? _channel;
  String? _topic;
  bool _canSend = false;
  bool _joined = false;

  SupabaseClient get _client => _clientOverride ?? Supabase.instance.client;

  @override
  bool get canSend => _canSend;

  @override
  bool get isJoined => _joined;

  @override
  Future<bool> open({
    required void Function(Map<String, dynamic> payload) onEvent,
    required void Function(bool joined) onJoined,
  }) async {
    try {
      final raw = await _client.rpc(_rpcName, params: _rpcParams);
      final info = raw is Map ? raw : const {};
      final topic = info['topic'];
      if (topic is! String || topic.isEmpty) return false;
      _canSend = info['send'] != false;

      // Aynı konuya kalmış eski bir kanal varsa (hızlı çık-gir) önce kaldır.
      final stale = _openChannels.remove(_channelKey(topic));
      if (stale != null) await _client.removeChannel(stale);

      final channel = _client.channel(topic);
      channel.onBroadcast(event: 'typing', callback: onEvent);
      channel.subscribe((status, error) {
        _joined = status == RealtimeSubscribeStatus.subscribed;
        onJoined(_joined);
        if (error != null) debugPrint('⚠️ Yazıyor kanalı: $status $error');
      });
      _channel = channel;
      _topic = topic;
      _openChannels[_channelKey(topic)] = channel;
      return true;
    } catch (e) {
      debugPrint('⚠️ Yazıyor kanalı açılamadı: $e');
      return false;
    }
  }

  @override
  void send(Map<String, dynamic> payload) {
    final channel = _channel;
    if (channel == null) return;
    unawaited(
      channel
          .sendBroadcastMessage(event: 'typing', payload: payload)
          .then<void>((_) {}, onError: (Object _) {}),
    );
  }

  @override
  Future<void> close() async {
    final channel = _channel;
    final topic = _topic;
    _channel = null;
    _topic = null;
    _joined = false;
    if (topic != null && identical(_openChannels[_channelKey(topic)], channel)) {
      _openChannels.remove(_channelKey(topic));
    }
    if (channel != null) await _client.removeChannel(channel);
  }
}
