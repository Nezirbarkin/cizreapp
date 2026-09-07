import '../engine/okey_tile.dart';

OkeyTile _tileFromMap(Map<String, dynamic> map) => OkeyTile.fromMap(map);

/// Bir elin (hand) tüm oyuncuların gördüğü ortak durumu.
class OkeyMatch {
  final String id;
  final String roomId;
  final String status; // in_progress | finished
  final int handNo;
  final int dealerSeat;
  final int turnSeat;
  final String turnPhase; // draw | discard
  final String turnToken;
  final DateTime? turnDeadline;
  final OkeyTile indicatorTile;
  final OkeyTile okeyTile;
  final int deckRemaining;
  final Map<int, List<OkeyTile>> discardPiles;
  final Map<int, int> scores;

  /// Koltuk → bu elde MASAYA AÇILAN toplam puan (anlık per puanı).
  ///
  /// [scores] ile karıştırılmamalı: o KÜMÜLATİF CEZADIR ve düşük olanı iyidir.
  /// Bu ise elin içinde büyüyen bir kazanım — per açtıkça ve taş işledikçe
  /// artar. İkisi masada da ayrı ayrı gösterilir (bkz. OkeyCornerPileWidget).
  final Map<int, int> openPoints;

  final int? winnerSeat;
  final String? winType;
  final int highestOpeningPoints;
  final int highestOpeningPairs;

  const OkeyMatch({
    required this.id,
    required this.roomId,
    required this.status,
    required this.handNo,
    required this.dealerSeat,
    required this.turnSeat,
    required this.turnPhase,
    required this.turnToken,
    required this.indicatorTile,
    required this.okeyTile,
    required this.deckRemaining,
    required this.discardPiles,
    required this.scores,
    this.openPoints = const {},
    this.turnDeadline,
    this.winnerSeat,
    this.winType,
    this.highestOpeningPoints = 0,
    this.highestOpeningPairs = 0,
  });

  factory OkeyMatch.fromMap(Map<String, dynamic> map) {
    final rawPiles = (map['discard_piles'] as Map<String, dynamic>? ?? {});
    final piles = <int, List<OkeyTile>>{};
    rawPiles.forEach((seat, tiles) {
      piles[int.parse(seat)] = (tiles as List)
          .map((t) => _tileFromMap(t as Map<String, dynamic>))
          .toList();
    });

    final rawScores = (map['scores'] as Map<String, dynamic>? ?? {});
    final scores = <int, int>{};
    rawScores.forEach((seat, pts) => scores[int.parse(seat)] = pts as int);

    // Anlık per puanı sunucudan gelmiyorsa (eski maç satırı) boş kalır;
    // arayüz onu "0" diye gösterir, çökmez.
    final rawOpen = (map['open_points'] as Map<String, dynamic>? ?? {});
    final openPoints = <int, int>{};
    rawOpen.forEach(
      (seat, pts) => openPoints[int.parse(seat)] = (pts as num).toInt(),
    );

    return OkeyMatch(
      id: map['id'] as String,
      roomId: map['room_id'] as String,
      status: map['status'] as String,
      handNo: map['hand_no'] as int,
      dealerSeat: map['dealer_seat'] as int,
      turnSeat: map['turn_seat'] as int,
      turnPhase: map['turn_phase'] as String,
      turnToken: map['turn_token'] as String,
      turnDeadline: map['turn_deadline'] == null
          ? null
          : DateTime.parse(map['turn_deadline'] as String),
      indicatorTile: _tileFromMap(
        map['indicator_tile'] as Map<String, dynamic>,
      ),
      okeyTile: _tileFromMap(map['okey_tile'] as Map<String, dynamic>),
      deckRemaining: map['deck_remaining'] as int,
      discardPiles: piles,
      scores: scores,
      openPoints: openPoints,
      winnerSeat: map['winner_seat'] as int?,
      winType: map['win_type'] as String?,
      highestOpeningPoints: map['highest_opening_points'] as int? ?? 0,
      highestOpeningPairs: map['highest_opening_pairs'] as int? ?? 0,
    );
  }
}

/// Masaya açık şekilde konmuş bir per (run) veya grup (set).
class OkeyTableMeld {
  final int id;
  final String matchId;
  final int laidBySeat;
  final String meldType; // run | set
  final List<OkeyTile> tiles;

  const OkeyTableMeld({
    required this.id,
    required this.matchId,
    required this.laidBySeat,
    required this.meldType,
    required this.tiles,
  });

  factory OkeyTableMeld.fromMap(Map<String, dynamic> map) => OkeyTableMeld(
    id: map['id'] as int,
    matchId: map['match_id'] as String,
    laidBySeat: map['laid_by_seat'] as int,
    meldType: map['meld_type'] as String,
    tiles: (map['tiles'] as List)
        .map((t) => _tileFromMap(t as Map<String, dynamic>))
        .toList(),
  );
}

/// Lobide/oda listesinde gösterilecek özet oda bilgisi.
class OkeyRoom {
  final String id;
  final String createdBy;
  final String status; // waiting | in_progress | finished | abandoned
  final bool isPrivate;
  final String? joinCode;
  final int maxScore;
  final int turnSeconds;
  final String gameMode; // katlamasiz | katlamali
  final String teamMode; // essiz | esli
  final String assistMode; // yardimli | yardimsiz
  /// EL BAŞINA giriş puanı — masaya girmenin bedeli DEĞİLDİR.
  ///
  /// Gerçek bedel [tableStake]'tir: bu sayı el sayısıyla çarpılır. İkisini
  /// karıştırmamak için ekranlarda hep [tableStake] gösterilir; [entryFee]
  /// yalnızca çarpımın "500 × 3 el" biçiminde okunabilmesi için durur.
  final int entryFee;

  /// Maçın kaç el süreceği (oda kurulurken seçilir).
  final int totalHands;

  final String? currentMatchId;
  final DateTime createdAt;

  /// Lobi listesinde dolan koltuk sayıları (okey_list_open_rooms'tan gelir).
  final int seatedCount;
  final int botCount;
  final String? creatorName;
  final String? creatorAvatar;

  /// Masayı ŞU AN izleyen kişi sayısı (okey_list_live_rooms'tan gelir).
  final int spectatorCount;

  const OkeyRoom({
    required this.id,
    required this.createdBy,
    required this.status,
    required this.isPrivate,
    required this.maxScore,
    required this.turnSeconds,
    required this.gameMode,
    required this.teamMode,
    required this.assistMode,
    this.entryFee = 0,
    this.totalHands = 3,
    required this.createdAt,
    this.joinCode,
    this.currentMatchId,
    this.seatedCount = 0,
    this.botCount = 0,
    this.creatorName,
    this.creatorAvatar,
    this.spectatorCount = 0,
  });

  /// MASA PUANI = [entryFee] × [totalHands] (kullanıcı isteği, 2026-09-05).
  ///
  /// Sunucudaki `okey_rooms.table_stake` ÜRETİLMİŞ sütunuyla birebir aynı
  /// hesap. Türetilmiş bir alan olarak duruyor (sunucudan gelen sayıyı
  /// okumak yerine) çünkü lobi listesi RPC'leri satırın tamamını değil
  /// seçili sütunları döndürüyor — formülü tek satırda tutmak, "bazı
  /// ekranda gelir bazısında gelmez" ayrımını baştan siliyor.
  int get tableStake => entryFee * totalHands;

  /// Masadaki toplam dolu koltuk (insan + bot).
  int get occupiedSeats => seatedCount + botCount;
  bool get isFull => occupiedSeats >= 4;

  factory OkeyRoom.fromMap(Map<String, dynamic> map) => OkeyRoom(
    id: map['id'] as String,
    createdBy: map['created_by'] as String,
    status: map['status'] as String,
    isPrivate: map['is_private'] as bool,
    joinCode: map['join_code'] as String?,
    maxScore: map['max_score'] as int,
    turnSeconds: map['turn_seconds'] as int,
    gameMode: map['game_mode'] as String? ?? 'katlamasiz',
    teamMode: map['team_mode'] as String? ?? 'essiz',
    assistMode: map['assist_mode'] as String? ?? 'yardimli',
    entryFee: map['entry_fee'] as int? ?? 0,
    totalHands: map['total_hands'] as int? ?? 3,
    currentMatchId: map['current_match_id'] as String?,
    createdAt: DateTime.parse(map['created_at'] as String),
    seatedCount: (map['seated_count'] as num?)?.toInt() ?? 0,
    botCount: (map['bot_count'] as num?)?.toInt() ?? 0,
    creatorName: map['creator_name'] as String?,
    creatorAvatar: map['creator_avatar'] as String?,
    spectatorCount: (map['spectator_count'] as num?)?.toInt() ?? 0,
  );
}

/// MAÇ SONU ÖDEME SATIRI — bir koltuğun bu maçtaki puan hareketi.
///
/// ## Neden ayrı bir kayıt, skorun yanında bir alan değil
///
/// Skor (ceza) ile ödeme birbirinden BAĞIMSIZDIR: en düşük cezayı yapan
/// kazanır, ama ne kazandığı masa puanına ve masadaki İNSAN sayısına bağlıdır
/// (botlardan pot toplanmaz). İkisini tek bir sayıya katlamak, "kazandım ama
/// neden bu kadar" sorusunu yanıtsız bırakırdı.
class OkeyMatchPayout {
  final int seatNo;

  /// Bot koltuğunda null.
  final String? userId;

  /// Bu koltuğun masaya ödediği puan (masa puanı; el sayısıyla çarpılmış).
  final int stake;

  /// Pottan aldığı pay (kaybeden için 0).
  final int won;

  /// KAZANANA GERİ VERİLEN masa puanı (2026-09-05 kullanıcı kuralı:
  /// "kazanan kişiden masa ücreti alınmasın").
  ///
  /// [stake] zaten iadeyi düşerek gelir — yani kazanan için 0'dır. Ama
  /// "0 ödedim" ile "zaten ücretsiz masaydı" aynı şey değil ve kart bu
  /// ikisini ancak iadenin KENDİSİNİ görerek ayırt edebilir.
  final int refund;

  /// Net değişim: [won] − [stake]. Sunucudan gelir, burada TÜRETİLMEZ —
  /// defterin kendisi tek doğruluk kaynağıdır.
  final int net;

  const OkeyMatchPayout({
    required this.seatNo,
    required this.stake,
    required this.won,
    required this.net,
    this.refund = 0,
    this.userId,
  });

  factory OkeyMatchPayout.fromMap(Map<String, dynamic> map) => OkeyMatchPayout(
    seatNo: (map['seat_no'] as num).toInt(),
    userId: map['user_id'] as String?,
    stake: (map['stake'] as num?)?.toInt() ?? 0,
    won: (map['won'] as num?)?.toInt() ?? 0,
    net: (map['net'] as num?)?.toInt() ?? 0,
    refund: (map['refund'] as num?)?.toInt() ?? 0,
  );
}

/// Masayı izleyen bir kişi (okey_room_spectators_list).
class OkeySpectator {
  final String userId;
  final String displayName;
  final String? avatarUrl;

  /// Misafir (anonim) giriş yapmış izleyici.
  final bool isGuest;

  const OkeySpectator({
    required this.userId,
    required this.displayName,
    required this.isGuest,
    this.avatarUrl,
  });

  factory OkeySpectator.fromMap(Map<String, dynamic> map) => OkeySpectator(
    userId: map['user_id'] as String,
    displayName: (map['display_name'] as String?) ?? 'İzleyici',
    avatarUrl: map['avatar_url'] as String?,
    isGuest: map['is_guest'] as bool? ?? false,
  );
}

/// Bir odadaki tek koltuk: boşsa [userId] null olur.
class OkeyRoomSeat {
  final String roomId;
  final int seatNo;
  final String? userId;
  final bool isReady;
  final bool isBot;
  final String? displayName;
  final String? avatarUrl;

  /// Bu koltuğa atanmış bot kimliğinin id'si (bot değilse null).
  ///
  /// Profil kartını açmak için gerekli: bot koltuğunun `userId`'si yoktur,
  /// dolayısıyla kart ancak bu id ile sorgulanabilir.
  final String? botProfileId;

  const OkeyRoomSeat({
    required this.roomId,
    required this.seatNo,
    required this.isReady,
    this.isBot = false,
    this.userId,
    this.displayName,
    this.avatarUrl,
    this.botProfileId,
  });

  bool get isEmpty => userId == null && !isBot;

  /// Masada GÖRÜNEN ad.
  ///
  /// ## Neden tek bir yerde
  ///
  /// Bu hesap dört ekranda ayrı ayrı yazılıydı (masa, bekleme odası, el
  /// sonucu, maç sonucu) ve hepsi botu "Bot 1", "Bot 2" diye adlandırıyordu.
  /// Yani admin panelinde ne yazarsan yaz, bir yerde mutlaka "Bot" görünüyordu.
  ///
  /// ## Neden bot olduğunu söylemiyor (2026-09, kullanıcı isteği)
  ///
  /// Botlar masada gerçek oyuncular gibi görünür. Profili olan bot kendi
  /// adıyla; profili OLMAYAN bot ise koltuk numarasından türeyen yedek bir
  /// adla görünür. Yedek adın DETERMİNİSTİK olması şart: her istemcide
  /// rastgele üretilseydi aynı oyuncu dört ekranda dört farklı isim taşırdı.
  String get displayLabel {
    final name = displayName?.trim();
    if (name != null && name.isNotEmpty) return name;
    // Gerçek bir oyuncunun adı yoksa uydurma bir kimlik verilmez; yalnızca
    // profili tanımlanmamış BOT yedek ada düşer.
    return isBot
        ? _fallbackBotNames[seatNo % _fallbackBotNames.length]
        : 'Oyuncu';
  }

  /// Admin panelinde profil tanımlanmamışken kullanılan yedek adlar.
  static const List<String> _fallbackBotNames = [
    'Yusuf K.',
    'Elif A.',
    'Murat D.',
    'Zeynep S.',
  ];

  factory OkeyRoomSeat.fromMap(Map<String, dynamic> map) {
    final profile = map['profiles'] as Map<String, dynamic>?;
    // Bot koltukları için admin panelinde tanımlanmış kimlik (varsa).
    final botProfile = map['okey_bot_profiles'] as Map<String, dynamic>?;
    return OkeyRoomSeat(
      roomId: map['room_id'] as String,
      seatNo: map['seat_no'] as int,
      userId: map['user_id'] as String?,
      isReady: map['is_ready'] as bool,
      isBot: map['is_bot'] as bool? ?? false,
      botProfileId: map['bot_profile_id'] as String?,
      displayName: botProfile != null
          ? botProfile['display_name'] as String?
          : (profile == null
                ? null
                : ((profile['full_name'] as String?)?.trim().isNotEmpty == true
                      ? profile['full_name'] as String
                      : profile['username'] as String?)),
      avatarUrl: botProfile != null
          ? botProfile['avatar_url'] as String?
          : profile?['avatar_url'] as String?,
    );
  }
}
