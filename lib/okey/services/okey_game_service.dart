import 'package:supabase_flutter/supabase_flutter.dart';

import '../engine/okey_tile.dart';
import '../models/okey_models.dart';

/// Oyuncunun kendi eli ve el açma durumu.
class OkeyMyHand {
  final List<OkeyTile> tiles;
  final bool isOpeningDone;
  final bool openedWithPairs;
  final bool wentForPairs;

  /// BU EL İÇİNDE biriken ek cezalar: işlek taş atma, okey atma, yandan
  /// çekilen taşı kullanmama (RULES.md §7/§8).
  ///
  /// El bitince skora eklenir — ama oyuncunun bunu el BİTMEDEN görmesi
  /// gerekir, yoksa +101'lik bir hatayı yaptığını ancak el sonunda,
  /// düzeltemeyeceği bir anda öğrenir.
  ///
  /// Yalnızca KENDİ satırım okunabilir (RLS): rakibin biriken cezası
  /// istemciye hiç gelmez.
  final int penaltyPoints;

  /// RULES.md §3 — SERİ ile açan oyuncunun BU TURDA indirdiği çift sayısı ve
  /// sayacın hangi tura ait olduğu (`okey_matches.turn_token`).
  ///
  /// İkisi birlikte gelir çünkü sayaç tur sonunda SİLİNMEZ: token eskidiyse
  /// sayı sıfır sayılır. Sıfırlamayı ayrı bir yazma adımına bırakmak, o adımı
  /// atlayan her yolda (el bitişi, kopmuş oyuncu) hakkın kaybolması demekti.
  final String? seriesPairsTurnToken;
  final int seriesPairsTurnCount;

  /// YANDAN ALDIĞIM TAŞI GERİ KOYDUĞUM TURUN kimliği
  /// (`okey_matches.turn_token`), yoksa null.
  ///
  /// RULES.md §4: geri konan taş O TURDA bir daha alınamaz. Sunucu kuralı
  /// `okey_internal_draw_for_seat` içinde uyguluyor; bu alan yalnızca
  /// arayüzün ıskartayı sönük göstermesi için gelir — düğme basılıp
  /// reddedilmesin diye. Tur devredince maçın token'ı değişir, karşılaştırma
  /// kendiliğinden bozulur: ayrıca sıfırlanması gerekmez.
  final String? sideDrawUndoneToken;

  const OkeyMyHand({
    required this.tiles,
    required this.isOpeningDone,
    required this.openedWithPairs,
    required this.wentForPairs,
    this.penaltyPoints = 0,
    this.seriesPairsTurnToken,
    this.seriesPairsTurnCount = 0,
    this.sideDrawUndoneToken,
  });

  const OkeyMyHand.empty()
    : tiles = const [],
      isOpeningDone = false,
      openedWithPairs = false,
      wentForPairs = false,
      penaltyPoints = 0,
      seriesPairsTurnToken = null,
      seriesPairsTurnCount = 0,
      sideDrawUndoneToken = null;

  /// [matchTurnToken] turunda yandan çekme kapalı mı? (bkz.
  /// [sideDrawUndoneToken])
  bool sideDrawBlockedInTurn(String? matchTurnToken) =>
      sideDrawUndoneToken != null && sideDrawUndoneToken == matchTurnToken;

  /// [matchTurnToken] için geçerli sayaç: token eskiyse hak yeniden tamdır.
  int pairsLaidInTurn(String matchTurnToken) =>
      seriesPairsTurnToken == matchTurnToken ? seriesPairsTurnCount : 0;
}

/// `okey_moves` tablosundan okunan tek bir hamle satırı.
///
/// Ses ve UÇAN TAŞ için kullanılır; masanın durumu bundan türetilmez
/// (tek doğruluk kaynağı her zaman maç/el satırlarıdır).
typedef OkeyMoveRow = ({int id, int seatNo, String action, OkeyTile? tile});

/// `okey_match_snapshot` cevabı — masanın bir andaki tam hali.
///
/// Tek bir RPC turunda gelen bu paket, eskiden yedi ayrı sorgunun
/// (maç, el, perler, taş sayıları, hamleler, barajlar, geri koyma hakkı)
/// karşılığıdır (bkz. [OkeyGameService.getSnapshot]).
typedef OkeyTableSnapshot = ({
  OkeyMatch match,
  OkeyMyHand hand,
  List<OkeyTableMeld> melds,
  Map<int, int> counts,
  List<OkeyMoveRow> moves,
  Map<int, String> barajs,
  ({int minPoints, int minPairs})? requiredOpening,
  bool canUndoSideDraw,
});

/// Maç içi RPC/veri çağrıları için ince istemci katmanı. Gerçek doğrulama
/// her zaman sunucudaki SECURITY DEFINER RPC'lerde.
class OkeyGameService {
  SupabaseClient get _client => Supabase.instance.client;

  Future<OkeyMatch> getMatch(String matchId) async {
    final row = await _client
        .from('okey_matches')
        .select()
        .eq('id', matchId)
        .single();
    return OkeyMatch.fromMap(row);
  }

  /// Kendi elim + el açma durumum. RLS gereği yalnızca kendi satırım görünür.
  Future<OkeyMyHand> getMyHand(String matchId) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return const OkeyMyHand.empty();
    final row = await _client
        .from('okey_player_hands')
        .select(
          'tiles, is_opening_done, opened_with_pairs, went_for_pairs, '
          'penalty_points, series_pairs_turn_token, series_pairs_turn_count, '
          'side_draw_undone_token',
        )
        .eq('match_id', matchId)
        .eq('user_id', uid)
        .maybeSingle();
    if (row == null) return const OkeyMyHand.empty();
    return _handFromMap(row);
  }

  static OkeyMyHand _handFromMap(Map<String, dynamic> row) => OkeyMyHand(
    tiles: (row['tiles'] as List)
        .map((t) => OkeyTile.fromMap(t as Map<String, dynamic>))
        .toList(),
    isOpeningDone: row['is_opening_done'] as bool? ?? false,
    openedWithPairs: row['opened_with_pairs'] as bool? ?? false,
    wentForPairs: row['went_for_pairs'] as bool? ?? false,
    penaltyPoints: (row['penalty_points'] as num?)?.toInt() ?? 0,
    seriesPairsTurnToken: row['series_pairs_turn_token'] as String?,
    seriesPairsTurnCount:
        (row['series_pairs_turn_count'] as num?)?.toInt() ?? 0,
    sideDrawUndoneToken: row['side_draw_undone_token'] as String?,
  );

  /// Bu maçtaki son hamle — masaya İLK girişte "nereden devam ediyorum"
  /// işaretini koymak için (o hamle oynatılmaz, yalnızca kimliği not edilir).
  Future<OkeyMoveRow?> getLastMove(String matchId) async {
    final rows = await _client
        .from('okey_moves')
        .select('id, seat_no, action, tile')
        .eq('match_id', matchId)
        .order('id', ascending: false)
        .limit(1);
    final list = rows as List;
    if (list.isEmpty) return null;
    return _moveRow(list.first as Map<String, dynamic>);
  }

  /// [afterId]'den SONRAKİ hamleler — ESKİDEN YENİYE sıralı.
  ///
  /// ## Neden "son hamle" yetmiyordu (kullanıcı: "desteden taş çektiğinde
  /// uçan taş kullanıcılar görsün çektiğini")
  ///
  /// Bot bir turun TAMAMINI (çek → işle → at) tek bir RPC'de bitiriyor; sıra
  /// bir insana geçtiğinde `okey_moves`'a iki-üç satır BİRDEN girmiş oluyor.
  /// İstemci yalnızca SONUNCU satırı okuduğu için masada hep ıskartaya düşen
  /// taş uçuyor, DESTEDEN ÇEKME hiç görünmüyordu — oysa rakibin taş çektiğini
  /// gösteren tek işaret oydu.
  ///
  /// Sıralama SONDAN alınır (`descending` + `limit`, sonra ters çevrilir):
  /// baştan alınsaydı, uzun bir kopmanın ardından en ESKİ hamleler okunur ve
  /// masanın şu anki hali hiç görünmezdi.
  Future<List<OkeyMoveRow>> getMovesSince(
    String matchId,
    int afterId, {
    int limit = 6,
  }) async {
    final rows = await _client
        .from('okey_moves')
        .select('id, seat_no, action, tile')
        .eq('match_id', matchId)
        .gt('id', afterId)
        .order('id', ascending: false)
        .limit(limit);
    return [
      for (final r in (rows as List).reversed)
        _moveRow(r as Map<String, dynamic>),
    ];
  }

  OkeyMoveRow _moveRow(Map<String, dynamic> r) {
    final rawTile = r['tile'] as Map<String, dynamic>?;
    return (
      id: r['id'] as int,
      seatNo: r['seat_no'] as int,
      action: r['action'] as String,
      tile: rawTile == null ? null : OkeyTile.fromMap(rawTile),
    );
  }

  /// MASADAKİ BARAJLAR — koltuk → 'pairs' | 'series'.
  ///
  /// Sunucudan sorulmak ZORUNDA: baraj, açılış anındaki puan/çift sayısından
  /// türüyor ve o sayılar okey_player_hands'te — RLS gereği bir oyuncu
  /// yalnızca kendi satırını okuyabilir, rakibininkini hesaplayamaz.
  /// (Dönen bilgi gizli değil: masada açık duran perlerden zaten sayılabilir.)
  Future<Map<int, String>> getBarajs(String matchId) async {
    final rows = await _client.rpc(
      'okey_match_barajs',
      params: {'p_match_id': matchId},
    );
    final result = <int, String>{};
    for (final r in (rows as List? ?? const [])) {
      final m = r as Map<String, dynamic>;
      final seat = (m['seat_no'] as num?)?.toInt();
      final kind = m['kind'] as String?;
      if (seat != null && kind != null) result[seat] = kind;
    }
    return result;
  }

  Future<List<OkeyTableMeld>> getTableMelds(String matchId) async {
    final rows = await _client
        .from('okey_table_melds')
        .select()
        .eq('match_id', matchId)
        .order('id');
    return (rows as List)
        .map((r) => OkeyTableMeld.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  /// seat_no -> tile_count (rakiplerin elinde kaç taş kaldığı; gerçek taşlar dönmez).
  Future<Map<int, int>> getSeatTileCounts(String matchId) async {
    final rows = await _client.rpc(
      'get_match_seat_tile_counts',
      params: {'p_match_id': matchId},
    );
    final result = <int, int>{};
    for (final r in (rows as List)) {
      result[r['seat_no'] as int] = r['tile_count'] as int;
    }
    return result;
  }

  /// MASANIN TAMAMI TEK OKUMADA (performans, 2026-09-13).
  ///
  /// [getSnapshot] yoksa (eski sunucu) null döner ve çağıran eski yola —
  /// yedi ayrı sorguya — düşer. Bayrak KÜTÜPHANE düzeyindedir: her masada
  /// yeniden denemenin anlamı yok.
  static bool _snapshotSupported = true;

  /// Masa durumunun tamamı: maç, kendi elim, masadaki perler, rakiplerin taş
  /// sayıları, son hamleler, baraj rozetleri ve "geri koy" hakkı.
  ///
  /// Eskiden bunların her biri ayrı bir ağ turuydu; paralel gitseler bile
  /// toplam gecikme en yavaş turdan aşağı inemiyor, üstelik her biri kendi
  /// PostgREST maliyetini ödüyordu. Tek RPC hepsini tek planda toplar.
  ///
  /// [afterMoveId] null ise yalnızca SON hamle döner (masaya ilk girişte
  /// "nereden devam ediyorum" işareti); doluysa ondan sonraki en çok 6 hamle
  /// eskiden yeniye sıralı gelir — [getMovesSince] ile aynı sözleşme.
  Future<OkeyTableSnapshot?> getSnapshot(
    String matchId, {
    int? afterMoveId,
  }) async {
    if (!_snapshotSupported) return null;
    try {
      final row =
          await _client.rpc(
                'okey_match_snapshot',
                params: {
                  'p_match_id': matchId,
                  'p_after_move_id': afterMoveId,
                },
              )
              as Map<String, dynamic>;

      final handRow = row['hand'] as Map<String, dynamic>?;
      final counts = <int, int>{};
      for (final c in (row['counts'] as List? ?? const [])) {
        final m = c as Map<String, dynamic>;
        counts[(m['seat_no'] as num).toInt()] =
            (m['tile_count'] as num).toInt();
      }
      final barajs = <int, String>{};
      for (final b in (row['barajs'] as List? ?? const [])) {
        final m = b as Map<String, dynamic>;
        final seat = (m['seat_no'] as num?)?.toInt();
        final kind = m['kind'] as String?;
        if (seat != null && kind != null) barajs[seat] = kind;
      }
      return (
        match: OkeyMatch.fromMap(row['match'] as Map<String, dynamic>),
        hand: handRow == null
            ? const OkeyMyHand.empty()
            : _handFromMap(handRow),
        melds: [
          for (final m in (row['melds'] as List? ?? const []))
            OkeyTableMeld.fromMap(m as Map<String, dynamic>),
        ],
        counts: counts,
        moves: [
          for (final m in (row['moves'] as List? ?? const []))
            _moveRow(m as Map<String, dynamic>),
        ],
        barajs: barajs,
        requiredOpening: switch (row['required_opening']) {
          final Map<String, dynamic> r => (
            minPoints: (r['min_points'] as num?)?.toInt() ?? 101,
            minPairs: (r['min_pairs'] as num?)?.toInt() ?? 5,
          ),
          _ => null,
        },
        canUndoSideDraw: row['can_undo_side_draw'] == true,
      );
    } catch (e) {
      if (!_isMissingFunction(e)) rethrow;
      _snapshotSupported = false;
      return null;
    }
  }

  /// SUNUCU ÇEKİLEN TAŞI DA DÖNDÜREBİLİYOR MU? (performans, 2026-09-08)
  ///
  /// `okey_take_turn_action_v2` yalnızca maç satırını değil, ÇEKİLEN TAŞI da
  /// döndürür — böylece istemci çektiği taşı görmek için ikinci bir ağ turu
  /// atmak zorunda kalmaz. Fonksiyon henüz yayınlanmamış bir sunucuda yoksa
  /// (PostgREST `PGRST202`) bayrak indirilir ve oturum boyunca eski çağrı
  /// kullanılır; oyun HİÇBİR ŞEKİLDE kesintiye uğramaz.
  ///
  /// Sınıf değil KÜTÜPHANE düzeyinde: her provider yeni bir servis kuruyor,
  /// örnek alanı olsaydı her masada yeniden denenirdi.
  static bool _drawV2Supported = true;

  static bool _isMissingFunction(Object e) {
    if (e is PostgrestException) {
      if (e.code == 'PGRST202' || e.code == '42883') return true;
      final msg = e.message.toLowerCase();
      return msg.contains('could not find the function') ||
          msg.contains('does not exist');
    }
    return false;
  }

  /// Çekme/atma — [drawn] YALNIZCA çekme hamlelerinde ve yalnızca sunucu v2
  /// destekliyorsa dolu gelir.
  Future<({OkeyMatch match, OkeyTile? drawn})> _turnAction(
    String matchId,
    String action, {
    OkeyTile? tile,
  }) async {
    final params = <String, dynamic>{
      'p_match_id': matchId,
      'p_action': action,
      if (tile != null) 'p_tile': tile.toMap(),
    };
    if (_drawV2Supported) {
      try {
        final row = await _client.rpc('okey_take_turn_action_v2',
            params: params) as Map<String, dynamic>;
        final drawn = row['drawn'] as Map<String, dynamic>?;
        return (
          match: OkeyMatch.fromMap(row['match'] as Map<String, dynamic>),
          drawn: drawn == null ? null : OkeyTile.fromMap(drawn),
        );
      } catch (e) {
        if (!_isMissingFunction(e)) rethrow;
        _drawV2Supported = false;
      }
    }
    final row = await _client.rpc('okey_take_turn_action', params: params);
    return (match: OkeyMatch.fromMap(row as Map<String, dynamic>), drawn: null);
  }

  Future<({OkeyMatch match, OkeyTile? drawn})> drawFromDeck(String matchId) =>
      _turnAction(matchId, 'draw_deck');

  Future<({OkeyMatch match, OkeyTile? drawn})> drawFromDiscard(
    String matchId,
  ) => _turnAction(matchId, 'draw_discard');

  /// RULES.md §4 — YANDAN ALINAN TAŞI GERİ KOY.
  ///
  /// Taş, alındığı ıskartanın en üstüne döner ve sıra yeniden 'çekme'
  /// aşamasına geçer; oyuncu bu kez desteden çekebilir. Koşulları (taş hâlâ
  /// elde mi, o turda başka hamle yapıldı mı, tur başına bir kez) SUNUCU
  /// doğrular — istemci yalnızca düğmeyi gösterip gizler.
  Future<OkeyMatch> undoSideDraw(String matchId) async {
    final row = await _client.rpc(
      'okey_undo_side_draw',
      params: {'p_match_id': matchId},
    );
    return OkeyMatch.fromMap(row as Map<String, dynamic>);
  }

  /// "Geri koy" düğmesi şu an gösterilmeli mi?
  ///
  /// Kararı SUNUCU verir: koşullar istemcide ayrıca hesaplansaydı kural iki
  /// yerde yaşar ve kaçınılmaz olarak ayrışırdı (düğme görünür ama işlem
  /// reddedilir, ya da tersi).
  Future<bool> canUndoSideDraw(String matchId) async {
    final r = await _client.rpc(
      'okey_can_undo_side_draw',
      params: {'p_match_id': matchId},
    );
    return r == true;
  }

  Future<OkeyMatch> discard(String matchId, OkeyTile tile) async {
    final result = await _turnAction(matchId, 'discard', tile: tile);
    return result.match;
  }

  /// RULES.md §3 — seri/grup ile ([isPairs] false) veya çift ile ([isPairs]
  /// true) el açma; el zaten açıksa ek per/çift koyma.
  Future<void> layMeld(
    String matchId,
    List<List<OkeyTile>> groups, {
    bool isPairs = false,
  }) async {
    await _client.rpc(
      'okey_lay_meld',
      params: {
        'p_match_id': matchId,
        'p_groups': groups
            .map((g) => g.map((t) => t.toMap()).toList())
            .toList(),
        'p_is_pairs': isPairs,
      },
    );
  }

  /// RULES.md §3/§5 — bu oyuncunun açması için gereken baraj
  /// (katlamalı ve eşli istisnaları sunucuda hesaplanır).
  Future<({int minPoints, int minPairs})> getRequiredOpening(
    String matchId,
    int seatNo,
  ) async {
    final rows = await _client.rpc(
      'okey_required_opening',
      params: {'p_match_id': matchId, 'p_seat': seatNo},
    );
    final row = (rows as List).first as Map<String, dynamic>;
    return (
      minPoints: row['min_points'] as int,
      minPairs: row['min_pairs'] as int,
    );
  }

  /// RULES.md §7 — "çifte gidiyorum" beyanı (açamazsa 404 ceza).
  Future<void> setWentForPairs(String matchId, bool value) async {
    await _client.rpc(
      'okey_set_went_for_pairs',
      params: {'p_match_id': matchId, 'p_value': value},
    );
  }

  Future<void> addToMeld(String matchId, int meldId, OkeyTile tile) async {
    await _client.rpc(
      'okey_add_to_meld',
      params: {
        'p_match_id': matchId,
        'p_meld_id': meldId,
        'p_tile': tile.toMap(),
      },
    );
  }

  /// RULES.md §4 — OKEY ÇALMA: masadaki [meldId] perinde joker olarak duran
  /// okey taşını, onun yerine geçen [tile] taşını koyarak ele alır.
  /// Eli açık olmayan oyuncu kullanamaz (sunucu doğrular).
  Future<void> stealJoker(String matchId, int meldId, OkeyTile tile) async {
    await _client.rpc(
      'okey_steal_joker',
      params: {
        'p_match_id': matchId,
        'p_meld_id': meldId,
        'p_tile': tile.toMap(),
      },
    );
  }

  /// "Buradayım" damgası — bağlantısı kopan oyuncuların tespiti için.
  Future<void> touchPresence(String roomId) async {
    await _client.rpc('okey_touch_presence', params: {'p_room_id': roomId});
  }

  /// Sırası gelen oyuncu yoksa/kopmuşsa onun adına oynatır (çektiği taşı
  /// doğrudan atar). Sunucu, oyuncunun gerçekten yok olduğunu bağımsız
  /// doğrular; öyle değilse hiçbir şey yapmaz.
  Future<bool> autoPlayAbsent(String matchId) async {
    final r = await _client.rpc(
      'okey_auto_play_absent',
      params: {'p_match_id': matchId},
    );
    return r == true;
  }

  /// Sıra süresi dolduysa, sırası gelen koltuk adına desteden taş çekip
  /// ÇEKİLEN TAŞI DOĞRUDAN attırır (oyuncunun eli değişmez).
  ///
  /// Süreyi SUNUCU doğrular (`now() > turn_deadline`); erken çağrılırsa
  /// hiçbir şey yapmaz ve false döner. Masadaki herhangi bir oyuncu
  /// tetikleyebilir — dördü aynı anda çağırsa bile sıra tek adım ilerler.
  Future<bool> autoAdvance(String matchId) async {
    final r = await _client.rpc(
      'okey_auto_advance',
      params: {'p_match_id': matchId},
    );
    return r == true;
  }

  /// Oyuncu maç sırasında "Masadan ayrıl" dediğinde çağrılır: koltuğu
  /// kalıcı olarak AI'ya devreder (bkz. migration 20260915000001) ve sırası
  /// oysa turu hemen oynatır — diğer oyuncular 90 sn'lik "kayıp mı?"
  /// belirsizliğini beklemez.
  Future<void> leaveMatchSeat(String matchId) async {
    await _client.rpc('okey_leave_match_seat', params: {'p_match_id': matchId});
  }

  /// Sırası gelen koltuk botsa onun hamlesini oynatır.
  ///
  /// [turnToken] verilmelidir: istemcinin GÖRDÜĞÜ sıranın kimliğidir. Masadaki
  /// dört istemci de bu RPC'yi tetikleyebildiği için, kaçırılan bir realtime
  /// olayından sonra BAYAT bir zamanlayıcı ateşlenip artık sırası gelmiş
  /// BAŞKA bir botu gecikmesiz oynatabiliyordu (RPC hangi koltuk için
  /// çağrıldığını sormuyordu). Token eskiyse sunucu sessizce hiçbir şey yapmaz.
  Future<void> botTakeTurn(String matchId, {String? turnToken}) async {
    await _client.rpc(
      'okey_bot_take_turn',
      params: {'p_match_id': matchId, 'p_expected_turn_token': turnToken},
    );
  }
}
