import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/okey_models.dart';

/// Oda/lobi RPC'leri için ince istemci katmanı. Gerçek doğrulama/güvenlik
/// her zaman sunucudaki (SECURITY DEFINER) RPC'lerde — bu sınıf yalnızca
/// çağırır ve gelen veriyi modele çevirir.
class OkeyRoomService {
  SupabaseClient get _client => Supabase.instance.client;

  /// Bir masanın EN DÜŞÜK giriş puanı. Masa sadece puanla açılır; ücretsiz
  /// masa yoktur. Sunucudaki `okey_settings.min_entry_fee` ile aynı olmalı —
  /// son sözü sunucu söyler, buradaki değer yalnızca arayüz içindir.
  static const int minEntryFee = 100;

  /// Bekleyen (herkese açık, dolmamış) odalar. RLS zaten yalnızca
  /// 'waiting' + 'is_private=false' odaları veya kullanıcının kendi
  /// oturduğu odaları döndürür.
  /// Bekleyen, herkese açık ve DOLMAMIŞ masalar — doluluk bilgisiyle birlikte
  /// tek çağrıda gelir (oda başına ayrı sorgu atılmaz).
  Future<List<OkeyRoom>> listOpenRooms() async {
    final rows = await _client.rpc(
      'okey_list_open_rooms',
      params: {'p_limit': 50},
    );
    return (rows as List)
        .map((r) => OkeyRoom.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  /// İZLENEBİLİR masalar: oyunu SÜRMEKTE olan, herkese açık masalar.
  ///
  /// [listOpenRooms] bunun tam TERSİNİ döndürür (henüz başlamamış ve
  /// dolmamış masalar) — yani izlenecek masayı orada aramak boşuna. İki
  /// liste bilerek ayrıdır: biri "oturulacak", diğeri "izlenecek" masadır.
  Future<List<OkeyRoom>> listLiveRooms() async {
    final rows = await _client.rpc(
      'okey_list_live_rooms',
      params: {'p_limit': 50},
    );
    return ((rows as List?) ?? const [])
        .map((r) => OkeyRoom.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  /// Masayı izlemeye başla — ve izlemeye DEVAM ettiğini bildir.
  ///
  /// Aynı çağrı hem katılma hem KALP ATIŞIDIR: uygulamayı kapatan bir
  /// izleyici "çıktım" diyemez, dolayısıyla izleyici sayısının doğru
  /// kalmasının tek yolu periyodik tazelemedir (sunucu 90 saniyedir
  /// tazelenmemiş kayıtları siler).
  Future<void> watchRoom(String roomId) async {
    await _client.rpc('okey_watch_room', params: {'p_room_id': roomId});
  }

  Future<void> unwatchRoom(String roomId) async {
    await _client.rpc('okey_unwatch_room', params: {'p_room_id': roomId});
  }

  /// Masayı ŞU AN izleyenler — masadaki oyuncular da bunu görür.
  Future<List<OkeySpectator>> listSpectators(String roomId) async {
    final rows = await _client.rpc(
      'okey_room_spectators_list',
      params: {'p_room_id': roomId},
    );
    return ((rows as List?) ?? const [])
        .map((r) => OkeySpectator.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  /// Kullanıcının DEVAM EDEN oyunu varsa o odayı döner (yanlışlıkla çıkma,
  /// uygulama kapanması veya bağlantı kopması sonrası geri dönebilmek için).
  /// RLS gereği kullanıcı zaten yalnızca kendi oturduğu odaları görebilir.
  /// GERÇEKTEN devam eden odam.
  ///
  /// Odanın durumuna bakmak yetmez: maçı bitmiş bir oda hâlâ `in_progress`
  /// görünebiliyor ve lobide "Devam Et" olarak çıkıp oyuncuyu ÖLÜ bir masaya
  /// götürüyordu. Sunucudaki `okey_my_active_room` maç durumunu da kontrol
  /// eder.
  Future<OkeyRoom?> getMyActiveRoom() async {
    final rows = await _client.rpc('okey_my_active_room');
    final list = (rows as List?) ?? const [];
    if (list.isEmpty) return null;
    return OkeyRoom.fromMap(list.first as Map<String, dynamic>);
  }

  /// Maçı bitmiş ama açık kalmış / uzun süredir boş bekleyen odaları kapatır.
  Future<void> cleanupStaleRooms() async {
    await _client.rpc('okey_cleanup_stale_rooms');
  }

  Future<OkeyRoom> getRoom(String roomId) async {
    final row = await _client
        .from('okey_rooms')
        .select()
        .eq('id', roomId)
        .single();
    return OkeyRoom.fromMap(row);
  }

  Future<List<OkeyRoomSeat>> getSeats(String roomId) async {
    final rows = await _client
        .from('okey_room_players')
        .select(
          '*, profiles(username, full_name, avatar_url), okey_bot_profiles(display_name, avatar_url)',
        )
        .eq('room_id', roomId)
        .order('seat_no');
    return (rows as List)
        .map((r) => OkeyRoomSeat.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  /// [gameMode]: 'katlamasiz' | 'katlamali', [teamMode]: 'essiz' | 'esli'
  /// (RULES.md §5).
  /// MASA SADECE PUANLA AÇILIR: [entryFee] en az [minEntryFee] olmalıdır.
  /// Her oyuncudan bu kadar puan alınır ve pot kazanan(lar)a dağıtılır.
  /// Sunucu da aynı alt sınırı uygular — arayüz atlansa bile geçilemez.
  Future<OkeyRoom> createRoom({
    bool isPrivate = false,
    String gameMode = 'katlamasiz',
    String teamMode = 'essiz',
    String assistMode = 'yardimli',
    int totalHands = 3,
    int entryFee = OkeyRoomService.minEntryFee,
  }) async {
    final row = await _client.rpc(
      'create_okey_room',
      params: {
        'p_is_private': isPrivate,
        'p_game_mode': gameMode,
        'p_team_mode': teamMode,
        'p_assist_mode': assistMode,
        'p_total_hands': totalHands,
        'p_entry_fee': entryFee,
      },
    );
    return OkeyRoom.fromMap(row as Map<String, dynamic>);
  }

  /// [roomId] veya [joinCode] ile boş bir koltuğa oturur. Döner: koltuk no.
  Future<int> joinRoom({String? roomId, String? joinCode}) async {
    final rows = await _client.rpc(
      'join_okey_room',
      params: {'p_room_id': roomId, 'p_join_code': joinCode},
    );
    final row = (rows as List).first as Map<String, dynamic>;
    return row['r_seat_no'] as int;
  }

  Future<void> leaveRoom(String roomId) async {
    await _client.rpc('leave_okey_room', params: {'p_room_id': roomId});
  }

  Future<void> setReady(String roomId, bool ready) async {
    await _client.rpc(
      'set_okey_ready',
      params: {'p_room_id': roomId, 'p_ready': ready},
    );
  }

  /// Test kolaylığı: odadaki boş koltukları botlarla doldurur.
  Future<void> fillWithBots(String roomId) async {
    await _client.rpc('okey_fill_with_bots', params: {'p_room_id': roomId});
  }

  /// MAÇ SONU ÖDEME ÖZETİ — kim ne ödedi, kim ne kazandı.
  ///
  /// Puan hareketleri `okey_point_transactions` defterinde duruyor ama o
  /// defter başka kullanıcıların satırlarını da içerdiği için istemciye
  /// açılamaz; RPC yalnızca BU odanın hareketlerini koltuk koltuk özetler
  /// (bkz. okey_match_payouts).
  /// AYNI MASAYLA YENİDEN OYNA.
  ///
  /// Biten oda bir defterdir (skorlar, ödemeler, hediyeler ona bağlı), o
  /// yüzden sıfırlanmaz: aynı ayarlarla YENİ bir oda kurulur ve eskisine
  /// bağlanır. İlk basan kurar, sonrakiler aynı odaya katılır — buluşma
  /// noktasının tek olmasını veritabanı garanti eder
  /// (bkz. okey_rematch_room).
  Future<String> rematch(String roomId) async {
    final rows = await _client.rpc(
      'okey_rematch_room',
      params: {'p_room_id': roomId},
    );
    final list = (rows as List?) ?? const [];
    if (list.isEmpty) throw 'Yeni masa kurulamadı.';
    return (list.first as Map<String, dynamic>)['room_id'] as String;
  }

  /// Bu biten masa için ZATEN bir "yeniden oyna" odası kuruldu mu?
  ///
  /// Düğmenin "YENİDEN OYNA" mı "MASAYA KATIL" mı diyeceğini belirler:
  /// basmadan önce öğrenilmezse herkes oda kurduğunu sanır.
  Future<({String roomId, String status, int seated})?> rematchRoomOf(
    String roomId,
  ) async {
    final rows = await _client.rpc(
      'okey_rematch_room_of',
      params: {'p_room_id': roomId},
    );
    final list = (rows as List?) ?? const [];
    if (list.isEmpty) return null;
    final m = list.first as Map<String, dynamic>;
    return (
      roomId: m['room_id'] as String,
      status: m['status'] as String? ?? 'waiting',
      seated: (m['seated_count'] as num?)?.toInt() ?? 0,
    );
  }

  /// OTOMATİK EŞLEŞTİRME — uygun masaya otur, yoksa kur.
  ///
  /// Tek dokunuş: "hangi masa?" ve "kaç kişi bekleyeceğim?" sorularını
  /// oyuncuya sormaz. Eşleştirme ölçütünü ve bot son tarihini SUNUCU
  /// belirler (bkz. okey_quick_match).
  Future<({String roomId, int seatNo, bool created})> quickMatch({
    String gameMode = 'katlamasiz',
    String teamMode = 'essiz',
    String assistMode = 'yardimli',
    int totalHands = 3,
    int entryFee = 100,
  }) async {
    final rows = await _client.rpc(
      'okey_quick_match',
      params: {
        'p_game_mode': gameMode,
        'p_team_mode': teamMode,
        'p_assist_mode': assistMode,
        'p_total_hands': totalHands,
        'p_entry_fee': entryFee,
      },
    );
    final list = (rows as List?) ?? const [];
    if (list.isEmpty) throw 'Masa bulunamadı.';
    final m = list.first as Map<String, dynamic>;
    return (
      roomId: m['room_id'] as String,
      seatNo: (m['seat_no'] as num?)?.toInt() ?? 0,
      created: m['created'] as bool? ?? false,
    );
  }

  /// Otomatik eşleştirme masasında süre dolduysa boş koltukları botlarla
  /// doldurur. Süreyi SUNUCU doğrular; erken çağrı hiçbir şey yapmaz.
  Future<bool> maybeAutofillBots(String roomId) async {
    final r = await _client.rpc(
      'okey_maybe_autofill_bots',
      params: {'p_room_id': roomId},
    );
    return r == true;
  }

  Future<List<OkeyMatchPayout>> matchPayouts(String roomId) async {
    final rows = await _client.rpc(
      'okey_match_payouts',
      params: {'p_room_id': roomId},
    );
    return ((rows as List?) ?? const [])
        .map((r) => OkeyMatchPayout.fromMap(r as Map<String, dynamic>))
        .toList();
  }
}
