import 'package:supabase_flutter/supabase_flutter.dart';

/// Masada gönderilebilen bir hediye (kahve, çay, dondurma...).
///
/// Liste KODDA GÖMÜLÜ DEĞİLDİR: hepsi `okey_gift_catalog` tablosundan gelir
/// ve admin panelinden düzenlenir (kullanıcı isteği, 2026-09-05). İkon bir
/// emojidir — yeni bir hediye eklemek bir görsel yüklemeyi değil, bir satır
/// yazmayı gerektirsin diye.
class OkeyGift {
  final String id;
  final String code;
  final String name;

  /// Emoji — doğrudan metin olarak çizilir.
  final String icon;

  /// Okey puanı cinsinden bedel.
  final int price;

  /// İkonun masada NASIL OYNAYACAĞI: bounce | shake | beat | spin | float.
  ///
  /// Hareket ikonun kendisinde (GIF/Lottie) değil, onu çizen widget'ta:
  /// emoji her platformda hazır ve ölçeklenir, animasyon ise tek bir
  /// AnimationController. Tanınmayan bir değer 'bounce'a düşer — admin
  /// yarın yeni bir hareket adı yazsa uygulama çökmez.
  final String anim;

  const OkeyGift({
    required this.id,
    required this.code,
    required this.name,
    required this.icon,
    required this.price,
    this.anim = 'bounce',
  });

  factory OkeyGift.fromMap(Map<String, dynamic> m) => OkeyGift(
    id: (m['id'] ?? '').toString(),
    code: m['code'] as String? ?? '',
    name: m['name'] as String? ?? 'Hediye',
    icon: m['icon'] as String? ?? '🎁',
    price: (m['price'] as num?)?.toInt() ?? 0,
    anim: m['anim'] as String? ?? 'bounce',
  );
}

/// Masada GÖNDERİLMİŞ bir hediye — animasyonun ve günlüğün girdisi.
///
/// Ad ve ikon kaydın İÇİNDE saklanır (kataloğa bakılmaz): admin hediyeyi
/// sonradan yeniden adlandırsa veya silse bile masada yaşanmış an geriye
/// dönük değişmemeli.
class OkeyGiftEvent {
  final int id;
  final String senderName;
  final int recipientSeat;
  final String recipientName;
  final String giftName;
  final String giftIcon;

  /// Gönderildiği ANDAKİ hareket (bkz. [OkeyGift.anim]).
  final String giftAnim;
  final int price;

  const OkeyGiftEvent({
    required this.id,
    required this.senderName,
    required this.recipientSeat,
    required this.recipientName,
    required this.giftName,
    required this.giftIcon,
    required this.price,
    this.giftAnim = 'bounce',
  });

  factory OkeyGiftEvent.fromMap(Map<String, dynamic> m) => OkeyGiftEvent(
    id: (m['id'] as num?)?.toInt() ?? 0,
    senderName: m['sender_name'] as String? ?? 'Oyuncu',
    recipientSeat: (m['recipient_seat'] as num?)?.toInt() ?? 0,
    recipientName: m['recipient_name'] as String? ?? 'Oyuncu',
    giftName: m['gift_name'] as String? ?? 'Hediye',
    giftIcon: m['gift_icon'] as String? ?? '🎁',
    giftAnim: m['gift_anim'] as String? ?? 'bounce',
    price: (m['price'] as num?)?.toInt() ?? 0,
  );
}

/// Hediye gönderme/okuma için ince veri katmanı.
///
/// Gönderme her zaman `okey_send_gift` RPC'sinden geçer: bakiye kontrolü,
/// alıcı payı ve kasa kaydı tek bir işlemde, sunucuda yapılır. İstemcinin
/// doğrudan `okey_gifts_sent`'e yazma yetkisi YOKTUR.
class OkeyGiftService {
  SupabaseClient get _client => Supabase.instance.client;

  /// Masadaki hediye menüsü (yalnızca aktif olanlar, adminin verdiği sırada).
  Future<List<OkeyGift>> catalog() async {
    final rows = await _client.rpc('okey_list_gifts');
    return [
      for (final r in (rows as List? ?? const []))
        OkeyGift.fromMap(r as Map<String, dynamic>),
    ];
  }

  /// Bir koltuğa hediye gönderir. Bakiye yetmezse sunucu hata döndürür.
  Future<void> send({
    required String roomId,
    required int seatNo,
    required String giftCode,
  }) async {
    await _client.rpc(
      'okey_send_gift',
      params: {'p_room_id': roomId, 'p_seat': seatNo, 'p_gift_code': giftCode},
    );
  }

  /// Masaya SONRADAN katılan (ya da yeni ele geçen) birinin son hediyeleri
  /// görebilmesi için.
  Future<List<OkeyGiftEvent>> recent(String roomId, {int limit = 20}) async {
    final rows = await _client.rpc(
      'okey_recent_gifts',
      params: {'p_room_id': roomId, 'p_limit': limit},
    );
    return [
      for (final r in (rows as List? ?? const []))
        OkeyGiftEvent.fromMap(r as Map<String, dynamic>),
    ];
  }
}
