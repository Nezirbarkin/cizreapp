import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../engine/okey_action_queue.dart';
import '../engine/okey_hand_hints.dart';
import '../engine/okey_hand_partition.dart';
import '../engine/okey_meld_validator.dart';
import '../engine/okey_rack_layout.dart';
import '../engine/okey_tile.dart';
import '../models/okey_models.dart';
import '../services/okey_game_service.dart';
import '../services/okey_gift_service.dart';
import '../services/okey_realtime_service.dart';
import '../widgets/okey_announcement_banner.dart';
import '../widgets/okey_move_flight.dart';
import '../services/okey_room_service.dart';
import '../services/okey_sound_service.dart';
import '../theme/okey_rack_style.dart';
import '../theme/okey_table_theme.dart';

enum OkeyRackSortMode { none, pairs, series }

/// Oyun masası ekranının tüm state'i ve aksiyonları. Tek doğruluk kaynağı
/// her zaman DB'dir — realtime event'leri yalnızca "bir şey değişti, DB'den
/// tazele" sinyali olarak kullanılır (bkz. OkeyRealtimeService).
class OkeyGameProvider with ChangeNotifier {
  /// ŞU AN oynanan elin maç kimliği.
  ///
  /// SABİT DEĞİL: bir el bitince sunucu aynı odada YENİ bir maç satırı açar
  /// (bkz. start_okey_hand) ve masa oraya geçer. Eskiden bu geçiş, ekranın
  /// tamamını yeni bir OkeyGameScreen ile değiştirerek yapılıyordu; oyuncu
  /// için sonuç "masadan atılıp yeni bir masaya oturtulmak"tı
  /// (bkz. [switchToMatch]).
  String _matchId;
  String get matchId => _matchId;

  /// Bu masaya İZLEYİCİ olarak girildi mi?
  ///
  /// İzleyici masayı okur ama oyuna DOKUNMAZ: bot sırasını tetiklemez,
  /// süresi dolan oyuncuyu otomatik oynatmaz, "buradayım" damgası atmaz.
  /// Bunlar bilerek kapatılır — masada oturmayan bir istemcinin oyunu
  /// ilerletmesi, izleyici sayısı arttıkça aynı hamlenin defalarca
  /// tetiklenmesi demek olurdu.
  final bool spectator;
  final OkeyGameService _service = OkeyGameService();
  final OkeyRoomService _roomService = OkeyRoomService();
  final OkeyRealtimeService _realtime = OkeyRealtimeService();
  final OkeyGiftService _giftService = OkeyGiftService();

  Timer? _tickTimer;
  Timer? _botTimer;
  Timer? _presenceTimer;
  Timer? _absentTimer;
  Timer? _watchTimer;
  Timer? _refreshDebounce;

  /// PERFORMANS — TAZELEME BİRLEŞTİRME.
  ///
  /// Tek bir hamle (ör. bir botun taş çekip atması) DÖRT ayrı realtime
  /// olayına yol açar: okey_matches güncellenir, okey_player_hands
  /// güncellenir, okey_moves'a satır girer, per konduysa okey_table_melds de
  /// değişir. Her olay ayrı ayrı [refresh]'i çağırdığında, her biri BEŞ ağ
  /// turu yapan tam bir tazeleme başlatıyordu — yani tek bir hamle için
  /// 20+ sorgu. Masada üç bot varken telefon bunu bir tur boyunca yapmaya
  /// çalışıyor, oyun donuk hissettiriyordu.
  ///
  /// Çözüm iki katmanlı:
  ///   * kısa bir GECİKME, aynı hamlenin olaylarını tek tazelemede toplar,
  ///   * uçuşta bir tazeleme varken gelen istekler KUYRUĞA yazılır ve
  ///     bitince BİR KEZ tekrarlanır (sonuncusu her zaman çalışır, yani
  ///     hiçbir güncelleme kaybolmaz).
  bool _refreshInFlight = false;
  bool _refreshQueued = false;

  /// İzleyici listesi oyunun akışı için gerekli değil: her tazelemede değil,
  /// en fazla bu aralıkla okunur.
  DateTime? _lastSpectatorFetch;
  static const Duration _spectatorInterval = Duration(seconds: 20);

  /// Koltuk listesi en son ne zaman ve hangi el için okundu
  /// (bkz. [_shouldRefetchSeats]).
  DateTime? _seatsFetchedAt;
  int? _seatsHandNo;
  static const Duration _seatsInterval = Duration(seconds: 30);

  bool _shouldRefetchSeats(OkeyMatch match) {
    if (_seats.isEmpty) return true;
    if (_seatsHandNo != match.handNo) return true;
    if (match.status != 'in_progress') return true;
    final at = _seatsFetchedAt;
    return at == null || DateTime.now().difference(at) >= _seatsInterval;
  }

  /// Süre dolumu otomatik oynatması: her sıra için tek deneme yapılır.
  /// Anahtar = maç + el + koltuk + son tarih.
  String? _autoAdvanceKey;
  bool _autoAdvancing = false;

  final OkeySoundService _sound = OkeySoundService.instance;

  /// Bot düşünme sürelerini değiştirmek için (sabit gecikme makine gibi durur).
  final math.Random _random = math.Random();

  /// Ses olaylarını tetiklemek için önceki durumun izleri.
  int? _lastSoundMoveId;
  int? _lastTurnSeatForSound;
  bool _timeWarningPlayed = false;

  OkeyMatch? _match;
  OkeyRoom? _room;
  List<OkeyTile> _myHand = [];

  /// EL SÜRÜMÜ — el sunucudan her okunduğunda (ya da sıfırlandığında) artar.
  ///
  /// Çekilen taşı yerel olarak eklemenin ([_applyDraw]) güvenli olup
  /// olmadığını anlamanın tek yolu budur: çağrı sürerken el yeniden
  /// okunduysa yerel ekleme yapılmaz, sunucunun okuduğu el geçerlidir.
  int _handRevision = 0;

  /// ELİME YEREL OLARAK KAÇ KEZ DOKUNULDU (iyimser güncelleme sayacı).
  ///
  /// Taş çekme/atma masaya sunucu cevabı BEKLENMEDEN yansıyor. O sırada
  /// uçuşta olan bir okuma varsa, o okuma hamleden ÖNCEKİ eli taşır: sonucu
  /// yazmak atılan taşı ıstakaya geri koyar, çekilen taşı da siler — yani
  /// masa bir an geri sarardı. Bu sayaç "okuma başladıktan sonra elime
  /// dokundum mu?" sorusunun cevabıdır; dokunduysam BAYAT okuma yazılmaz ve
  /// sıradaki tazeleme (hamleden sonra başlayan) doğru eli getirir.
  int _localHandOps = 0;
  List<OkeyTableMeld> _tableMelds = [];

  /// MASA PERLERİNİN PARMAK İZİ — perler her tazelemede yeniden kurulduğu
  /// için liste KİMLİĞİ hiçbir şey söylemez; içerik söyler.
  ///
  /// Tazeleme başına BİR KEZ hesaplanır ([_setTableMelds]) ve ipucu
  /// önbelleğinin geçerliliğinde kullanılır. Eskiden burada yalnızca per
  /// KİMLİKLERİ (m.id) karmalanıyordu; bir pere taş işlendiğinde ya da
  /// okey çalındığında kimlik AYNI kaldığı için ipuçları eski halinde
  /// donup kalıyordu — "bu taşı işleyebilirsin" vurgusu, taş işlendikten
  /// sonra da duruyordu.
  int _tableMeldsFingerprint = 0;

  void _setTableMelds(List<OkeyTableMeld> melds) {
    _tableMelds = melds;
    _tableMeldsFingerprint = Object.hashAll([
      for (final m in melds) Object.hash(m.id, Object.hashAll(m.tiles)),
    ]);
  }

  List<OkeyRoomSeat> _seats = [];
  List<OkeySpectator> _spectators = const [];
  Map<int, int> _opponentTileCounts = {};

  bool _isLoading = false;
  String? _error;

  bool _isOpeningDone = false;
  bool _openedWithPairs = false;
  bool _wentForPairs = false;

  /// YANDAN ALINAN TAŞ ŞU AN GERİ KONABİLİR Mİ (sunucunun cevabı).
  ///
  /// Koşulları istemci hesaplamaz (bkz. OkeyGameService.canUndoSideDraw):
  /// taşın elde olması, o turda başka hamle yapılmamış olması ve tur başına
  /// tek kullanım kuralı sunucudadır. Burada yalnızca son cevap tutulur.
  bool _canUndoSideDraw = false;

  /// YANDAN ALDIĞIM TAŞI GERİ KOYDUĞUM TURUN kimliği (bkz.
  /// [OkeyMyHand.sideDrawUndoneToken]). Aynı turda yan kapalıdır.
  String? _sideDrawUndoneToken;

  /// Masa tek okumayla mı tazeleniyor (`okey_match_snapshot` var mı)?
  ///
  /// Varsa baraj rozetleri ve "geri koy" hakkı her tazelemede zaten geliyor
  /// demektir; onlar için AYRICA ağ turu atılmaz.
  bool _snapshotMode = false;

  /// KOLTUK → BARAJ TÜRÜ ('pairs' | 'series'). Rozetin veri kaynağı.
  ///
  /// Baraj bir elde EN FAZLA BİR KEZ oluşur (açılış anında) ve sonra
  /// değişmez; bu yüzden her tazelemede değil, yalnızca EL DEĞİŞTİĞİNDE ve
  /// biri MASAYA PER KOYDUĞUNDA okunur. Her tazelemeye eklemek, hiç
  /// değişmeyen bir veri için tur başına bir ağ turu daha demekti.
  Map<int, String> _barajs = const {};

  /// Barajlar en son hangi el için okundu.
  int? _barajHandNo;

  /// Bu koltuk baraj yaptıysa türü, yapmadıysa null.
  String? barajKindOf(int seatNo) => _barajs[seatNo];

  /// Bu el içinde biriken ek cezalarım (bkz. [OkeyMyHand.penaltyPoints]).
  int _myPenaltyPoints = 0;

  /// RULES.md §3 — seri açan olarak BU TURDA indirdiğim çift sayısı ve
  /// sayacın ait olduğu tur (bkz. [OkeyMyHand.pairsLaidInTurn]).
  String? _seriesPairsTurnToken;
  int _seriesPairsTurnCount = 0;
  int _requiredMinPoints = 101;
  int _requiredMinPairs = 5;

  /// Istaka yerleşimi: her eleman bir slot (null = boşluk). Oyuncunun elle
  /// yaptığı dizilim burada saklanır ve sunucudan gelen her güncellemede
  /// korunarak birleştirilir (bkz. OkeyRackLayout.mergeWithHand).
  List<OkeyTile?> _rackSlots = List<OkeyTile?>.filled(
    OkeyRackLayout.totalSlots,
    null,
  );

  /// ISTAKANIN SÜRÜMÜ — rafa dokunan her yazma bunu bir artırır.
  ///
  /// ## Neden bir sayaç, "parmak izi" değil (performans, 2026-09-08)
  ///
  /// Rafa bağlı TÜM türetilmiş değerler (öbekler, per adayları, ipuçları,
  /// puan sayacı) önbelleklidir ve önbelleğin geçerliliği rafın değişip
  /// değişmediğine bakar. O soru eskiden `Object.hashAll(_rackSlots…)` ile,
  /// yani 32 elemanlık bir karma HESAPLAYARAK soruluyordu — üstelik ayrı ayrı
  /// dört yerde ve bu getter'lar her build'de defalarca okunuyor. Yani
  /// "değişti mi?" sorusunun kendisi, cevabından pahalı hale gelmişti.
  ///
  /// Raf hiçbir yerde YERİNDE değiştirilmez (her zaman yeni bir liste atanır),
  /// bu yüzden tek giriş noktası [_setRackSlots] ve monoton bir sayaç kesin
  /// sonuç verir.
  int _rackRevision = 0;

  /// [rackSlots] için değişmez görünüm — sürüm başına BİR KEZ kurulur.
  /// Her build'de `List.unmodifiable` çağırmak 32 elemanlık bir kopya
  /// demekti (ve her seferinde YENİ bir kimlik, yani gereksiz yeniden kurma).
  List<OkeyTile?>? _rackSlotsView;

  void _setRackSlots(List<OkeyTile?> next) {
    _rackSlots = next;
    _rackRevision++;
    _rackSlotsView = null;
  }

  /// Sürükleme sürerken UI'ın yeniden kurulmasını engeller. Realtime bir
  /// güncelleme tam sürükleme sırasında gelirse widget ağacı yeniden kurulup
  /// sürükleme katmanıyla çakışabiliyordu; bu bayrak bildirimi erteler.
  bool _isDragging = false;
  bool _pendingNotify = false;

  /// Çekilen taşın yerleşeceği slot — oyuncunun bıraktığı yer.
  /// Tek kullanımlıktır: yerleştikten sonra sıfırlanır.
  int? _pendingDrawSlot;

  /// Çift basılarak AÇILAN okey taşlarının slot indeksleri.
  final Set<int> _revealedOkeySlots = {};

  // PERFORMANS: processableTileIndices/meldableTileIndices, rafta ~1540
  // kombinasyon deneyen bir tarama yapıyor. Eskiden HER notifyListeners()'da
  // (ör. sadece bir rakip ıskarta attığında, ya da ses açıp kapatınca) baştan
  // hesaplanıyordu — asıl jank kaynağı buydu. Artık rafın/masa perlerinin
  // "parmak izi" değişmediği sürece önceki sonuç aynen döner.
  int? _hintsFingerprint;
  Set<int> _cachedProcessableIndices = const {};
  Set<int> _cachedMeldableIndices = const {};
  Set<int> _cachedStealableIndices = const {};
  Set<int> _cachedRiskyIndices = const {};

  int _computeHintsFingerprint() => Object.hash(
    _rackRevision,
    _tableMeldsFingerprint,
    canActOnHand,
    _isOpeningDone,
    isAssistOn,
  );

  void _recomputeHintsIfNeeded() {
    final fp = _computeHintsFingerprint();
    if (_hintsFingerprint == fp) return;
    _hintsFingerprint = fp;
    _cachedProcessableIndices = _computeProcessableTileIndices();
    _cachedMeldableIndices = _computeMeldableTileIndices();
    _cachedStealableIndices = _computeStealableTileIndices();
    _cachedRiskyIndices = _computeRiskyDiscardIndices();
  }

  final Set<int> _selectedIndices = {};
  final List<List<OkeyTile>> _stagedGroups = [];
  OkeyRackSortMode _sortMode = OkeyRackSortMode.none;
  bool _isCompactRack = false; // "katlamalı" (kompakt) / "katlamasız" (geniş)

  /// Sıra süre sayacı, BİLEREK notifyListeners()'dan ayrı tutulur: aksi
  /// halde saniyede bir TÜM ekran (raf, sürüklenebilir taşlar, DragTarget'lar)
  /// yeniden kurulurdu. Bu, aktif bir sürükleme (drag) sırasında Flutter'ın
  /// Element ağacını bozan bir çökmeye yol açtı (owner!._debugCurrentBuildTarget
  /// assertion hatası). Sadece sayaç rozetini gösteren küçük widget bunu dinler.
  final ValueNotifier<int> secondsLeftNotifier = ValueNotifier<int>(0);

  /// Oyuncu, masadaki bir pere İŞLENEBİLECEK bir taşı yanlışlıkla ıskartaya
  /// attığında bu SAYAÇ artar — arayüz bunu dinleyip kısa bir kırmızı
  /// yanıp-sönme (uyarı) gösterir. secondsLeftNotifier ile AYNI sebepten
  /// notifyListeners()'dan ayrı: tüm ekranı yeniden kurmadan tek bir
  /// overlay katmanını tetikler.
  final ValueNotifier<int> discardMistakeTick = ValueNotifier<int>(0);

  /// MASADAKİ SON ANONS (kullanıcı isteği, 2026-09-07: "seri açıldı, çift
  /// açıldı, son üç taş diye sesli söylesin").
  ///
  /// discardMistakeTick ile aynı sebepten notifyListeners()'dan ayrı tutulur:
  /// yalnızca üstteki bant katmanını yeniler, masanın tamamını değil.
  final ValueNotifier<OkeyAnnouncement?> announcement =
      ValueNotifier<OkeyAnnouncement?>(null);

  int _announcementSeq = 0;

  /// Anons durumu HANGİ el için tutuluyor — el değişince sıfırlanır.
  int? _announceHandNo;

  /// Şimdiye kadar görülmüş masa peri kimlikleri. Yeni bir kimlik belirmesi
  /// "biri yere per/çift indirdi" demektir; `add_to_meld` mevcut perin
  /// taşlarını büyüttüğü için burada iz bırakmaz — yani "seri açıldı" anonsu
  /// yalnızca GERÇEK bir açılışta çalar.
  Set<int> _knownMeldIds = <int>{};

  /// "Son üç taş" anonsu bu elde hangi koltuklar için yapıldı.
  final Set<int> _lowTileAnnouncedSeats = <int>{};

  /// BU ELDE AÇILIŞ ZATEN DUYURULDU MU? (kullanıcı isteği, 2026-09-07:
  /// "sadece ilk açılışta anons olsun".)
  ///
  /// Dört oyuncunun dördü de açılıyor, üstelik seri açan oyuncu aynı elde
  /// ayrıca çift de indirebiliyordu: bir el "Seri açıldı / Çift açıldı /
  /// Seri açıldı …" diye akıyordu. Bilgi değeri yalnızca BİRİNCİSİNDEDİR —
  /// "masa açıldı, artık taşlar işleniyor" haberi. Sonrakiler aynı haberi
  /// tekrar eder.
  ///
  /// "Son üç taş" anonsu bu kısıtın DIŞINDADIR: o, her seferinde YENİ bir
  /// oyuncu için yeni bir bilgidir (kimin bitmeye yaklaştığı).
  bool _openingAnnounced = false;

  /// SIRAYA GİREN ANONSLAR.
  ///
  /// Tek bir tazeleme birden çok olay taşıyabilir — oyuncu perlerini serip
  /// aynı turda 3 taşa düşebilir, yani "Seri açıldı" ile "… son üç taş" arka
  /// arkaya doğar. İkisini aynı anda duyurmak ikisini de yutardı: konuşma
  /// motoru yeni cümle gelince öncekini KESER, bant da yalnızca sonuncuyu
  /// gösterir. Kuyruk, anonsları aralıklı olarak tek tek çıkarır.
  final List<String> _announceQueue = [];
  Timer? _announceTimer;

  /// KOLTUK → O KOLTUĞA GELEN SON HEDİYELER (en yenisi başta).
  ///
  /// ## Neden SABİT kalıyor (kullanıcı isteği, 2026-09-05:
  /// "atılan hediyeler sabitlensin")
  ///
  /// Hediye üç saniye görünüp kaybolduğunda, masaya o an bakmayan herkes
  /// için hiç olmamış sayılıyordu — gönderen puanını harcıyor, alıcı çoğu
  /// zaman görmüyordu. Artık hediye oyuncunun levhasının yanında ASILI
  /// KALIR; masaya sonradan oturan ya da yeni ele geçen de görür.
  ///
  /// Liste [_maxPinnedGifts] ile sınırlı: dar kenar sütunlarındaki levhanın
  /// yanına sığması gereken bir rozet bu; sınırsız bir sıra masayı yerdi.
  ///
  /// secondsLeftNotifier ile AYNI gerekçeyle notifyListeners()'dan ayrı:
  /// hediye masanın OYUN durumunu hiç değiştirmez. notifyListeners() olsaydı
  /// bir bardak çay için 22 sürüklenebilir taş ve dört DragTarget yeniden
  /// kurulurdu — üstelik tam bir sürükleme sürerken gelebilir.
  final ValueNotifier<Map<int, List<OkeyGiftEvent>>> seatGifts =
      ValueNotifier<Map<int, List<OkeyGiftEvent>>>(const {});

  /// Bir koltuğun yanında en fazla kaç hediye asılı durur.
  static const int _maxPinnedGifts = 3;

  /// Masaya girerken geçmiş hediyeler bir kez okundu mu.
  bool _pinnedGiftsLoaded = false;

  /// AZ ÖNCE OYNANAN HAMLE — uçan taşı tetikler.
  ///
  /// Masada bir hamle olduğunda ekranda değişen tek şey SON DURUMDU: ıskartada
  /// bir taş beliriveriyor, deste sayacı bir azalıyordu. Hangi taşın nereden
  /// nereye gittiği hiç görünmüyordu (kullanıcı isteği, 2026-09-06: "taş
  /// atma, çekme, işletme... taşın kaydığı belli olsun").
  ///
  /// secondsLeftNotifier / seatGifts ile AYNI gerekçeyle notifyListeners()'dan
  /// ayrı: animasyon masanın OYUN durumunu değiştirmez ve tam bir sürükleme
  /// sürerken gelebilir.
  final ValueNotifier<OkeyMoveFlash?> lastMove = ValueNotifier<OkeyMoveFlash?>(
    null,
  );

  /// SIRAYA GİREN UÇUŞLAR.
  ///
  /// Tek bir tazeleme birden çok hamle getirebilir — bot çekip atmasını tek
  /// RPC'de bitiriyor (bkz. OkeyGameService.getMovesSince). Hepsini aynı
  /// anda [lastMove]'a yazmak yalnızca SONUNCUSUNU göstermek demekti:
  /// desteden çekme hiç uçmuyordu. Kuyruk, uçuşları arka arkaya çıkarır.
  final List<OkeyMoveFlash> _flightQueue = [];
  Timer? _flightTimer;

  /// İki uçuş arasındaki KAYMA (kullanıcı isteği, 2026-09-07: "taş atma,
  /// işlek yapma, taş çekme ile taş uçuşu uyuşsun").
  ///
  /// Önce 560 ms'ydi: bir uçuş BİTMEDEN diğeri başlamasın diye. Bunun bedeli,
  /// animasyonun masanın durumundan kopmasıydı — bot turunun üç hamlesi
  /// (çek → işle → at) masaya bir anda yansıyor, oysa son uçuş bir buçuk
  /// saniye sonra başlıyordu; oyuncu taşı çoktan ıskartada görürken ona doğru
  /// uçan bir taş izliyordu.
  ///
  /// Uçuş katmanı artık aynı anda birden çok taş taşıyor
  /// (bkz. OkeyMoveFlightOverlay), yani bu değer "bekleme" değil yalnızca
  /// OKUNABİLİRLİK KAYMASI: üç hamle üst üste binmesin, sırayla okunsun.
  /// Turun tamamı yarım saniyede biter.
  static const Duration _flightGap = Duration(milliseconds: 110);

  /// Hediye menüsü — masa açıkken bir kez okunur, sonra bellekten verilir.
  List<OkeyGift>? _giftCatalog;

  /// Hediye kanalına hangi oda için abone olundu (oda kimliği ilk
  /// tazelemeden sonra bilinir).
  String? _giftRoomId;

  bool _notifyScheduled = false;
  bool _disposed = false;

  /// TÜM state bildirimleri buradan geçer ve ASLA SENKRON çalışmaz.
  ///
  /// Neden: sürükleme bırakıldığında Flutter iki ayrı geri çağrıyı art arda
  /// senkron çalıştırır — Draggable.onDragEnd ve DragTarget.onAcceptWithDetails.
  /// Bunların içinden doğrudan notifyListeners() çağrılırsa, o sırada hâlâ
  /// kendi callback'ini yürüten DragTarget dahil TÜM ağaç yeniden kurulmaya
  /// çalışılıyor ve Flutter'ın "aynı anda tek build hedefi" değişmezi bozuluyor
  /// ('owner!._debugCurrentBuildTarget == this' assertion hatası).
  /// Mikro göreve ertelemek, bildirimin her zaman mevcut çağrı yığını
  /// (build / gesture teardown) tamamen boşaldıktan SONRA çalışmasını garanti eder.
  void _notify() {
    if (_isDragging) {
      _pendingNotify = true;
      return;
    }
    if (_notifyScheduled) return; // aynı turdaki bildirimleri birleştir
    _notifyScheduled = true;
    scheduleMicrotask(() {
      _notifyScheduled = false;
      if (!_disposed) notifyListeners();
    });
  }

  void beginDrag() {
    _isDragging = true;
  }

  void endDrag() {
    if (!_isDragging && !_pendingNotify) return;
    _isDragging = false;
    if (_pendingNotify) {
      _pendingNotify = false;
      _notify();
    }
  }

  OkeyGameProvider(String matchId, {this.spectator = false})
    : _matchId = matchId {
    // KRİTİK: _init() (dolayısıyla içindeki refresh()) SENKRON olarak
    // çağrılırsa, refresh()'in ilk await'ten ÖNCEKİ kısmı (notifyListeners()
    // dahil) bu constructor'ın çağrıldığı build/mount işlemiyle AYNI
    // senkron çağrı yığınında çalışır. ChangeNotifierProvider(create: ...)
    // tam olarak bir widget mount edilirken çalıştığından, bu, Flutter'ın
    // "aynı anda tek bir build hedefi" kuralını ihlal edip
    // owner!._debugCurrentBuildTarget assertion hatasıyla çöküyordu.
    // Future.microtask, çağrıyı mevcut senkron build/mount zincirinin
    // TAMAMEN dışına, bir sonraki mikro-görev turuna erteler.
    Future.microtask(_init);
  }

  Future<void> _init() async {
    await _sound.load();
    // ISTAKA + MASA TEMASI TERCİHİ — masaya girmeden okunur ki ilk kare
    // doğru takoz VE doğru zeminle çizilsin. İkinci çağrılarda kendini kısa
    // devre yapar.
    unawaited(OkeyRackStylePrefs.instance.load());
    unawaited(OkeyTableThemePrefs.instance.load());
    // Admin şarkı yüklediyse ve kullanıcı kapatmadıysa çalma listesini başlat
    unawaited(_sound.refreshPlaylist().then((_) => _sound.startMusic()));
    await refresh();
    _realtime.subscribe(
      matchId: matchId,
      onMatchChanged: _scheduleRefresh,
      onHandChanged: _scheduleRefresh,
      onMeldsChanged: _scheduleRefresh,
      onMovesChanged: _scheduleRefresh,
      onQuickPhrase: _handleIncomingQuickPhrase,
    );
    _subscribeGifts();
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());

    if (spectator) {
      // İZLEYİCİ KALP ATIŞI. Uygulamayı kapatan bir izleyici "çıktım"
      // diyemez; masadaki oyuncuların gördüğü izleyici sayısının doğru
      // kalmasının tek yolu bu periyodik tazelemedir (sunucu 90 saniyedir
      // tazelenmemiş kayıtları siler).
      _watchTimer = Timer.periodic(
        const Duration(seconds: 40),
        (_) => _touchWatch(),
      );
      unawaited(_touchWatch());
    } else {
      // "Buradayım" damgası — diğer istemciler benim bağlantımın canlı
      // olduğunu bu sayede anlar (bkz. okey_touch_presence).
      _presenceTimer = Timer.periodic(const Duration(seconds: 10), (_) {
        final roomId = _match?.roomId;
        if (roomId != null) _service.touchPresence(roomId).catchError((_) {});
      });
    }
  }

  /// Hediye kanalına abone olur (oda kimliği biliniyorsa ve daha önce
  /// abone olunmadıysa).
  void _subscribeGifts() {
    final roomId = _match?.roomId;
    if (roomId == null || _disposed) return;
    if (_giftRoomId == roomId) return;
    _giftRoomId = roomId;
    _realtime.subscribeGifts(
      roomId: roomId,
      onGift: (row) {
        if (_disposed) return;
        _pinGift(OkeyGiftEvent.fromMap(row));
      },
    );
    unawaited(_loadPinnedGifts(roomId));
  }

  /// Masadaki hediyeleri SUNUCUDAN okur — bir kez, masaya girerken.
  ///
  /// Realtime yalnızca ben masadayken gelen hediyeleri duyurur; oysa rozet
  /// SABİT (bkz. [seatGifts]). Bu okuma olmadan masaya sonradan oturan
  /// oyuncu, kendinden önce gönderilmiş hediyelerin hiçbirini görmezdi.
  Future<void> _loadPinnedGifts(String roomId) async {
    if (_pinnedGiftsLoaded) return;
    _pinnedGiftsLoaded = true;
    try {
      final recent = await _giftService.recent(roomId, limit: 40);
      if (_disposed || recent.isEmpty) return;
      // TEK BİR BİLDİRİM: harita yerel olarak kurulur, sonunda bir kez
      // atanır. Her satır için ayrı atama, kırk hediyelik bir masada kırk
      // yeniden çizim demekti.
      var next = seatGifts.value;
      // Sunucu en YENİDEN eskiye döndürür; [_withGift] en yeniyi başa
      // koyduğu için liste TERSTEN beslenir.
      for (final g in recent.reversed) {
        next = _withGift(next, g);
      }
      seatGifts.value = Map<int, List<OkeyGiftEvent>>.unmodifiable(next);
    } catch (_) {
      // Hediyeler oyunun işleyişi için gerekli değil — sessizce geç.
      // Bir sonraki masaya girişte yeniden denenir.
    }
  }

  /// Bir hediyeyi alıcısının koltuğuna asar (en yeni başta, en fazla üç).
  void _pinGift(OkeyGiftEvent gift) {
    final next = _withGift(seatGifts.value, gift);
    if (identical(next, seatGifts.value)) return;
    seatGifts.value = Map<int, List<OkeyGiftEvent>>.unmodifiable(next);
  }

  /// SAF hesap: haritanın hediyeli yeni hâli. Hediye zaten asılıysa harita
  /// AYNEN döner — çağıran taraf bunu `identical` ile anlar ve gereksiz bir
  /// bildirimden kaçınır.
  ///
  /// Aynı hediyenin iki kez asılması gerçek bir durumdur: realtime olayı ile
  /// geçmiş okuması aynı satırda buluşabilir.
  Map<int, List<OkeyGiftEvent>> _withGift(
    Map<int, List<OkeyGiftEvent>> current,
    OkeyGiftEvent gift,
  ) {
    final seat = gift.recipientSeat;
    final forSeat = current[seat] ?? const <OkeyGiftEvent>[];
    if (forSeat.any((g) => g.id == gift.id)) return current;

    return Map<int, List<OkeyGiftEvent>>.from(current)
      ..[seat] = [gift, ...forSeat.take(_maxPinnedGifts - 1)];
  }

  /// Masadaki hediye menüsü — ilk açılışta sunucudan, sonra bellekten.
  Future<List<OkeyGift>> giftCatalog() async {
    final cached = _giftCatalog;
    if (cached != null) return cached;
    final list = await _giftService.catalog();
    _giftCatalog = list;
    return list;
  }

  /// Bir koltuğa hediye gönderir.
  ///
  /// Sonuç EKRANDA ayrıca gösterilmez: hediye kaydı realtime ile geri gelir
  /// ve animasyonu herkeste olduğu gibi bende de o tetikler. Böylece
  /// gönderenin gördüğü ile masadakilerin gördüğü BİREBİR aynı olur.
  Future<void> sendGift(int seatNo, String giftCode) async {
    final roomId = _match?.roomId;
    if (roomId == null) return;
    await _giftService.send(roomId: roomId, seatNo: seatNo, giftCode: giftCode);
  }

  Future<void> _touchWatch() async {
    final roomId = _match?.roomId;
    if (roomId == null) return;
    try {
      await _roomService.watchRoom(roomId);
    } catch (_) {
      // Ağ hatası izlemeyi bozmaz: bir sonraki atışta tekrar denenir.
    }
  }

  /// Realtime olaylarının ortak girişi: tazelemeyi ERTELER ve BİRLEŞTİRİR
  /// (bkz. [_refreshInFlight] üzerindeki açıklama).
  void _scheduleRefresh() {
    if (_disposed) return;
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(const Duration(milliseconds: 120), () {
      if (_disposed) return;
      unawaited(refresh(silent: true));
    });
  }

  /// Masayı ŞU AN izleyenler — hem izleyicide hem OYUNCULARDA gösterilir.
  Future<void> refreshSpectators({bool force = false}) async {
    final roomId = _match?.roomId;
    if (roomId == null) return;
    final now = DateTime.now();
    if (!force &&
        _lastSpectatorFetch != null &&
        now.difference(_lastSpectatorFetch!) < _spectatorInterval) {
      return;
    }
    _lastSpectatorFetch = now;
    try {
      final list = await _roomService.listSpectators(roomId);
      if (_disposed) return;
      // DEĞİŞMEDİYSE BİLDİRME: izleyici sayısı masanın en durağan verisidir,
      // ama _notify() TÜM masayı (22 sürüklenebilir taş dahil) yeniden kurar.
      // Aynı listeyi tekrar yazmak için o bedeli ödemenin anlamı yok.
      final same =
          _spectators.length == list.length &&
          List.generate(
            list.length,
            (i) => _spectators[i].userId == list[i].userId,
          ).every((x) => x);
      _spectators = list;
      if (!same) _notify();
    } catch (_) {
      // İzleyici listesi oyunun işleyişi için gerekli değil — sessizce geç.
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _tickTimer?.cancel();
    _botTimer?.cancel();
    _presenceTimer?.cancel();
    _absentTimer?.cancel();
    _watchTimer?.cancel();
    _hintTimer?.cancel();
    _refreshDebounce?.cancel();
    _announceTimer?.cancel();
    _flightTimer?.cancel();
    if (spectator) {
      final roomId = _match?.roomId;
      // Masadan ayrılırken izleyici listesinden ÇIK. Başarısız olursa da
      // sorun değil: 90 saniyelik kalp atışı zaman aşımı yine temizler.
      if (roomId != null) {
        unawaited(_roomService.unwatchRoom(roomId).catchError((_) {}));
      }
    }
    _realtime.unsubscribe();
    secondsLeftNotifier.dispose();
    discardMistakeTick.dispose();
    announcement.dispose();
    seatGifts.dispose();
    lastMove.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // Getters
  // ---------------------------------------------------------------------

  OkeyMatch? get match => _match;
  OkeyRoom? get room => _room;
  List<OkeyRoomSeat> get seats => _seats;

  /// Masayı ŞU AN izleyenler (bkz. [refreshSpectators]).
  List<OkeySpectator> get spectators => _spectators;

  /// Masada oturmuyorum — yalnızca izliyorum.
  ///
  /// [spectator] bayrağı niyeti söyler, [mySeatNo] gerçeği: koltuğu olmayan
  /// bir istemci ne kadar "oyuncuyum" derse desin oynayamaz.
  bool get isSpectating => spectator || mySeatNo == null;

  /// Bir koltuğun bu eldeki ANLIK PER PUANI — masaya açtığı ve işlediği
  /// taşların toplam değeri (bkz. `okey_matches.open_points`).
  ///
  /// Ceza puanıyla ([OkeyMatch.scores]) karıştırılmamalı: bu büyüdükçe iyidir.
  int openPointsOf(int seatNo) => _match?.openPoints[seatNo] ?? 0;

  /// MASA PUANI: masaya girmenin bedeli = el başına puan × el sayısı.
  int get tableStake => _room?.tableStake ?? 0;

  /// RULES.md §5 — mod rozetleri için etiketler.
  String get gameModeLabel =>
      _room?.gameMode == 'katlamali' ? 'Katlamalı' : 'Katlamasız';
  String get teamModeLabel => _room?.teamMode == 'esli' ? 'Eşli' : 'Eşsiz';

  /// Ham takım modu ('essiz' | 'esli') — skor tablosu takım hesabı için.
  String get teamModeRaw => _room?.teamMode ?? 'essiz';
  String get assistModeLabel =>
      _room?.assistMode == 'yardimsiz' ? 'Yardımsız' : 'Yardımlı';

  /// Yardımlı mod açık mı? (varsayılan: açık)
  bool get isAssistOn => _room?.assistMode != 'yardimsiz';

  /// YARDIMLI MOD — rafımdaki hangi taşlar masadaki bir pere İŞLENEBİLİR?
  /// Dönen değer, [availableRackTiles] üzerindeki indekslerdir.
  ///
  /// Bu yalnızca bir arayüz ipucudur ve hiçbir gizli bilgi kullanmaz: sadece
  /// kendi taşlarım ile herkesin gördüğü masa perlerini karşılaştırır.
  /// Elim açık değilse işleme yapılamayacağı için boş küme döner.
  Set<int> get processableTileIndices {
    _recomputeHintsIfNeeded();
    return _cachedProcessableIndices;
  }

  /// ATILIRSA +101 CEZA yazacak taşların slotları (RULES.md §7 "işlek taş").
  ///
  /// ## Neden yardımlı moda BAĞLI DEĞİL
  ///
  /// [processableTileIndices] bir FIRSAT ipucudur ("bunu işleyebilirsin") ve
  /// yardımlı mod kapalıyken gösterilmez — oyuncu yardım istemiyorsa
  /// istemesin. Bu küme ise bir BEDEL uyarısıdır: ceza 2026-09-07'den beri
  /// eli kapalı oyuncuya da işliyor ve o oyuncunun elinde hiçbir işaret
  /// yoktu; hatasını ancak +101'i ödedikten sonra öğreniyordu. Kuralı
  /// görünmez kılmak, kuralı adaletsiz kılardı.
  ///
  /// Eli AÇIK ve yardımlı moddaki oyuncuda bu taşlar zaten yeşil çerçeveyle
  /// işaretli; taş widget'ı çift işareti kendi eler (bkz. OkeyTileWidget).
  Set<int> get riskyDiscardIndices {
    _recomputeHintsIfNeeded();
    return _cachedRiskyIndices;
  }

  Set<int> _computeRiskyDiscardIndices() {
    // Yalnızca ATMA aşamasında anlamlı: sıra bende değilken kırmızı çizgiler
    // masada sürekli duran bir gürültüye dönüşürdü.
    if (_match == null || !canActOnHand) return const {};
    final result = <int>{};
    for (var i = 0; i < _rackSlots.length; i++) {
      final tile = _rackSlots[i];
      if (tile == null) continue;
      if (_isTileProcessableOntoTable(tile)) result.add(i);
    }
    return result;
  }

  Set<int> _computeProcessableTileIndices() {
    final match = _match;
    if (!isAssistOn || match == null || !_isOpeningDone || !canActOnHand) {
      return const {};
    }
    final result = <int>{};
    for (var i = 0; i < _rackSlots.length; i++) {
      final tile = _rackSlots[i];
      if (tile == null) continue;
      for (final meld in _tableMelds) {
        // Çiftlere ve GÖSTERGE çiftine işleme yapılamaz
        if (meld.meldType == 'pair' || meld.meldType == 'gosterge') {
          continue;
        }
        if (OkeyMeldValidator.extendMeld(meld.tiles, tile, match.okeyTile) !=
            null) {
          result.add(i);
          break;
        }
      }
    }
    return result;
  }

  /// YARDIMLI MOD — OKEY ÇALINABİLİR taşların slot indeksleri (RULES.md §4).
  ///
  /// Masadaki bir perde JOKER olarak duran okeyin yerine geçebilen taşlarım.
  /// [processableTileIndices] gibi hiçbir gizli bilgi kullanmaz: yalnızca
  /// kendi taşlarım ile herkesin gördüğü masa perleri karşılaştırılır.
  Set<int> get stealableTileIndices {
    _recomputeHintsIfNeeded();
    return _cachedStealableIndices;
  }

  Set<int> _computeStealableTileIndices() {
    final match = _match;
    if (!isAssistOn || match == null || !_isOpeningDone || !canActOnHand) {
      return const {};
    }
    final result = <int>{};
    for (var i = 0; i < _rackSlots.length; i++) {
      final tile = _rackSlots[i];
      if (tile == null) continue;
      if (stealTargetMeldId(tile) != null) result.add(i);
    }
    return result;
  }

  /// [tile] ile okey çalınabilecek masa perinin id'si (yoksa null).
  ///
  /// Çiftlere/göstergeye dokunulmaz. Taş peri normal yoldan UZATABİLİYORSA
  /// çalma önerilmez: uzatmak hem eli bir taş azaltır hem de okeyi masada
  /// bırakır — çalma yalnızca uzatmanın mümkün olmadığı yerde anlamlıdır.
  int? stealTargetMeldId(OkeyTile tile) {
    final match = _match;
    if (match == null || !_isOpeningDone) return null;
    for (final meld in _tableMelds) {
      if (meld.meldType == 'pair' || meld.meldType == 'gosterge') continue;
      if (OkeyMeldValidator.extendMeld(meld.tiles, tile, match.okeyTile) !=
          null) {
        continue;
      }
      if (OkeyMeldValidator.stealableJokerIndex(
            meld.tiles,
            tile,
            match.okeyTile,
          ) !=
          null) {
        return meld.id;
      }
    }
    return null;
  }

  /// Bu TEK taş, masadaki açık bir pere işlenebilir mi? Yardımlı mod
  /// AÇIK OLMASA BİLE çalışır — [processableTileIndices]'in aksine bu
  /// yardımlı mod ipucu değil, "hata uyarısı" (ıskartaya atmadan önce
  /// kaçırdığın bir işleme var mı) için kullanılır (bkz. discardMistakeTick).
  ///
  /// ELİM AÇIK OLMASA DA DOĞRU SONUÇ VERİR (2026-09-07). Eskiden burada
  /// `!_isOpeningDone` erken çıkışı vardı ve uyarı, cezanın yazıldığı
  /// durumların yalnızca küçük bir kısmında görünüyordu. Sunucu artık işlek
  /// taş cezasını elin açık olup olmamasından bağımsız yazıyor
  /// (bkz. 20260907000003 göçü); iki taraf ayrışırsa oyuncu "sebepsiz" ceza
  /// almış olur — uyarı ile ceza AYNI koşula bakmak zorunda.
  bool _isTileProcessableOntoTable(OkeyTile tile) {
    final match = _match;
    if (match == null) return false;
    // OKEY ATMAK AYRI BİR HATADIR. Sunucu da okey atıldığında işlek taş
    // cezası YAZMAZ, yalnızca okey atma cezasını uygular (RULES.md §7
    // "cezaların üst üste binmemesi"). Uyarı metni "işlek taş attın" diyor;
    // okeyi kapsasaydı yanlış hatayı adlandırırdı.
    if (tile.isJokerFor(match.okeyTile)) return false;
    return _isProcessableTile(tile);
  }

  /// YARDIMLI MOD — rafımda birlikte geçerli bir per/grup/çift oluşturan
  /// taşların indeksleri (henüz açmadıysam neyi bir araya getirebileceğimi
  /// gösterir).
  ///
  /// Hesabın kendisi SAF MOTORDA (bkz. [OkeyHandHints.meldableSlots]): burada
  /// eskiden rafın tüm ikili/üçlü kombinasyonları taranıyordu ve bu, taş
  /// çekme/atma karesinde çalışan en pahalı ikinci işti. Motor aynı sonucu
  /// dağılımdan doğrudan okur; eşdeğerlik testle sabitlenmiştir.
  Set<int> get meldableTileIndices {
    _recomputeHintsIfNeeded();
    return _cachedMeldableIndices;
  }

  Set<int> _computeMeldableTileIndices() {
    final match = _match;
    if (!isAssistOn || match == null || !canActOnHand) return const {};
    return OkeyHandHints.meldableSlots(_rackSlots, match.okeyTile);
  }

  /// Koltuk → elinde kalan taş sayısı.
  ///
  /// KENDİ KOLTUĞUM YEREL ELDEN OKUNUR (performans, 2026-09-08): sayaç
  /// sunucudan ayrı bir RPC ile geliyor ve ancak tazelemeyle güncelleniyor.
  /// Taş çekip attığımda masa hamleyi anında gösterirken levhamdaki sayı bir
  /// tazeleme boyunca eski değerde kalıyordu — "taş gitti mi gitmedi mi"
  /// sorusunu yeniden doğuran tam da o sayıydı. Elim zaten elimde; sormaya
  /// gerek yok.
  Map<int, int> get opponentTileCounts {
    final seat = mySeatNo;
    if (seat == null || _myHand.isEmpty) return _opponentTileCounts;
    if (_opponentTileCounts[seat] == _myHand.length) return _opponentTileCounts;
    return {..._opponentTileCounts, seat: _myHand.length};
  }

  List<OkeyTableMeld> get tableMelds => _tableMelds;

  /// Masadaki SERİ ve GRUPLAR — geniş tablaya serilir, taş İŞLENEBİLİR.
  List<OkeyTableMeld> get seriesMelds => [
    for (final m in _tableMelds)
      if (m.meldType == 'run' || m.meldType == 'set') m,
  ];

  /// Masadaki ÇİFTLER (gösterge çifti dahil) — dar tablaya serilir.
  ///
  /// Ayrı tutulmalarının sebebi görsel değil kuraldır: çiftlere taş
  /// işlenemez (bkz. okey_process_tile) ve çiftle açan oyuncu seri açamaz.
  List<OkeyTableMeld> get pairMelds => [
    for (final m in _tableMelds)
      if (m.meldType == 'pair' || m.meldType == 'gosterge') m,
  ];

  /// RULES.md §3 — SERİ ile açan oyuncunun **bir TURDA** indirebileceği en çok
  /// çift sayısı. Sunucudaki eşi: `okey_series_pairs_limit()`.
  static const int seriesPairsLimit = 3;

  /// Masada BAŞKASININ indirdiği çift var mı?
  ///
  /// Seri ile açmış oyuncunun çift indirebilmesinin ön şartı budur. Ölçüt
  /// bilerek "masadaki çift" — rakibin `opened_with_pairs` değeri RLS gereği
  /// istemciye kapalıdır (okey_player_hands'i yalnızca sahibi okur), yani
  /// sunucuyla aynı cevabı verebilecek TEK gözlenebilir ölçüt bu.
  bool get pairsOpenerOnTable {
    final seat = mySeatNo;
    return pairMelds.any((m) => m.laidBySeat != seat);
  }

  /// Seri açan olarak BU TURDA masaya indirdiğim çift sayısı.
  ///
  /// Sayaç tur sonunda silinmez; hangi tura ait olduğu (`turn_token`) ile
  /// birlikte tutulur ve token eskiyse sıfır sayılır — sunucudaki
  /// `okey_internal_series_pairs_this_turn` ile birebir aynı hesap.
  int get seriesPairsThisTurn {
    final token = _match?.turnToken;
    if (token == null || _seriesPairsTurnToken != token) return 0;
    return _seriesPairsTurnCount;
  }

  /// SERİ ile açmış oyuncunun BU TURDA kalan çift hakkı. Çiftle açana sınır
  /// yoktur (onun eli zaten çifttir) — orada [seriesPairsLimit] hiç işlemez.
  int get seriesPairsAllowance {
    if (!_isOpeningDone || _openedWithPairs) return 0;
    if (!pairsOpenerOnTable) return 0;
    final left = seriesPairsLimit - seriesPairsThisTurn;
    return left < 0 ? 0 : left;
  }

  bool get isLoading => _isLoading;
  String? get error => _error;

  /// KAPALI BİR DÜĞMENİN SEBEBİNİ söyler.
  ///
  /// Mevcut hata şeridini kullanır — masada ikinci bir bildirim biçimi
  /// açmak yerine. Hata şeridi zaten "bu hamle neden olmadı" sorusunun
  /// yeri; kapalı düğme de aynı sorunun bir başka hâli.
  ///
  /// KENDİLİĞİNDEN SÖNER: gerçek bir hata bir sonraki hamleye kadar durur
  /// (kullanıcı onu okumalı), ama bir ipucu masanın üstünde asılı kalmamalı.
  void explain(String reason) {
    _error = reason;
    _hintTimer?.cancel();
    _hintTimer = Timer(const Duration(seconds: 5), () {
      if (_disposed) return;
      if (_error != reason) return; // araya gerçek bir hata girdi
      _error = null;
      _notify();
    });
    _notify();
  }

  Timer? _hintTimer;
  OkeyRackSortMode get sortMode => _sortMode;
  bool get isCompactRack => _isCompactRack;
  List<List<OkeyTile>> get stagedGroups => List.unmodifiable(_stagedGroups);
  Set<int> get selectedIndices => Set.unmodifiable(_selectedIndices);

  /// Seçili slotlardaki taşlar (slot sırasına göre).
  List<OkeyTile> get selectedTiles {
    final sorted = _selectedIndices.toList()..sort();
    return sorted
        .map((i) => i < _rackSlots.length ? _rackSlots[i] : null)
        .whereType<OkeyTile>()
        .toList();
  }

  /// Bu el bittikten sonra odanın durumunu tazeler: yeni bir el başladıysa
  /// yeni match id'sini, tüm maç bittiyse null döner.
  /// SIRADAKİ ELİN maç kimliği; maç bittiyse (ya da hiç açılmadıysa) null.
  ///
  /// ## Neden BEKLİYOR
  ///
  /// El biterken sunucu aynı işlemde bir sonraki eli açar
  /// (okey_internal_finalize_hand → start_okey_hand). Ama istemci, el sonu
  /// kartını maçın 'finished' olduğunu GÖRÜR GÖRMEZ kapatıp buraya gelir;
  /// odanın yeni `current_match_id`'si o mikro saniyede henüz okunamamış
  /// olabilir — ağ gecikmesi, okuma kopyası, yeniden bağlanma. Tek bir
  /// okumayla yetinildiğinde sonuç, oyuncunun MAÇ SÜRERKEN maç sonucu
  /// ekranına düşmesiydi: "el bitti, oyun devam etmiyor".
  ///
  /// Oda 'in_progress' olduğu sürece kısa aralıklarla yeniden bakılır. Oda
  /// 'finished' ise beklenecek bir şey yok, hemen null döner.
  Future<String?> checkForNextMatchId({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final roomId = _match?.roomId;
    if (roomId == null) return null;
    final deadline = DateTime.now().add(timeout);
    while (true) {
      final room = await _roomService.getRoom(roomId);
      if (_disposed) return null;
      // Oda bilgisi tazelendi: el sonu ödeme özeti ve mod rozetleri bunu
      // okur, bayat kalmasın.
      _room = room;
      if (room.status != 'in_progress') return null; // maç bitti
      final next = room.currentMatchId;
      if (next != null && next != _matchId) return next;
      if (DateTime.now().isAfter(deadline)) return null;
      await Future<void>.delayed(const Duration(milliseconds: 600));
      if (_disposed) return null;
    }
  }

  /// AYNI MASADA sıradaki ele geçer (kullanıcı isteği, 2026-09-07: "2. el,
  /// 3. el bittiğinde devam edilmiyor, tekrar yeni masa açmış gibi oluyor").
  ///
  /// ## Neden ekran değiştirmek yerine provider'ı taşıyoruz
  ///
  /// Her el sunucuda AYRI bir maç satırıdır, ama oyuncu için aynı masadır:
  /// aynı oyuncular, aynı skor tablosu, aynı sohbet, aynı hediyeler. Eskiden
  /// yeni ele `pushReplacement(OkeyGameScreen(matchId: yeni))` ile geçiliyor
  /// ve bunun bedeli ekranın TAMAMEN yeniden kurulmasıydı: ekran yönü
  /// sıfırlanıp yeniden yatay yapılıyor (gözle görülür bir dönme), masa boş
  /// bir yükleniyor çarkına düşüyor, oda/koltuk/hediye okumaları baştan
  /// yapılıyordu. Oyuncunun gördüğü, oyunun devam etmesi değil YENİ BİR
  /// MASAYA OTURTULMASIYDI.
  ///
  /// Artık yalnızca maç kimliği değişir: masa ekranda kalır, skorlar ve
  /// oyuncular yerinde durur, yeni el aynı çerçevenin içinde başlar.
  ///
  /// ODAYA BAĞLI olan hiçbir şey sıfırlanmaz (oda kaydı, koltuklar, asılı
  /// hediyeler, hediye kanalı); yalnızca ELE ait durum sıfırlanır.
  Future<void> switchToMatch(String nextMatchId) async {
    if (_disposed || nextMatchId == _matchId) return;

    // Önceki elin zamanlayıcıları yeni ele SARKMAMALI: bayat bir bot
    // zamanlayıcısı yeni elin ilk turunu anında oynatabilirdi.
    _botTimer?.cancel();
    _absentTimer?.cancel();
    _refreshDebounce?.cancel();
    _announceTimer?.cancel();
    _announceTimer = null;
    _flightTimer?.cancel();
    _flightTimer = null;

    await _realtime.unsubscribeMatch();
    if (_disposed) return;

    _matchId = nextMatchId;

    // ---- ELE AİT DURUM SIFIRLANIR ---------------------------------------
    //
    // [_match] BİLEREK SIFIRLANMAZ: ekran, maç null iken "Maç bulunamadı"
    // yazar (bkz. OkeyGameScreen.build). Biten elin maçı bir kaç yüz
    // milisaniye daha ekranda durur ve yerini yeni ele bırakır — tam da
    // düzeltmeye çalıştığımız "masa kayboldu" hissini yaratmasın diye.
    _myHand = const [];
    _handRevision++;
    _setTableMelds(const []);
    _opponentTileCounts = {};
    _isOpeningDone = false;
    _openedWithPairs = false;
    _wentForPairs = false;
    _myPenaltyPoints = 0;
    _seriesPairsTurnToken = null;
    _seriesPairsTurnCount = 0;
    _requiredMinPoints = 101;
    _requiredMinPairs = 5;
    _canUndoSideDraw = false;
    _sideDrawUndoneToken = null;
    _setRackSlots(List<OkeyTile?>.filled(OkeyRackLayout.totalSlots, null));
    _selectedIndices.clear();
    _stagedGroups.clear();
    _revealedOkeySlots.clear();
    _pendingDrawSlot = null;
    _hintsFingerprint = null;
    _barajs = const {};
    _barajHandNo = null;
    _autoAdvanceKey = null;
    _timeWarningPlayed = false;
    _error = null;

    // Koltuklar yeniden okunsun: yeni elde dağıtıcı ve sıra değişir.
    _seatsFetchedAt = null;
    _seatsHandNo = null;

    // Ses ve uçuş hafızası: hamle kimlikleri maça göre verildiği için yeni
    // maçın ilk hamleleri geçmiş sayılmalı, yoksa el başlar başlamaz
    // dağıtımın hamleleri arka arkaya uçardı.
    _lastSoundMoveId = null;
    _lastTurnSeatForSound = null;
    _flightQueue.clear();
    lastMove.value = null;

    // Anons hafızası: yeni elin ilk açılışı yeniden duyurulabilsin.
    _announceHandNo = null;
    _knownMeldIds = <int>{};
    _lowTileAnnouncedSeats.clear();
    _openingAnnounced = false;
    _announceQueue.clear();

    _notify();

    // ABONELİK TAZELEMEDEN ÖNCE: tersi olsaydı, okuma sürerken yeni elde
    // olan bitenler (dağıtım biter bitmez ilk hamle) hiç duyulmazdı.
    // Aboneliğin erken kurulması zararsız — her olay yalnızca "tazele"
    // sinyalidir ve tazeleme zaten birleştiriliyor.
    _realtime.subscribe(
      matchId: _matchId,
      onMatchChanged: _scheduleRefresh,
      onHandChanged: _scheduleRefresh,
      onMeldsChanged: _scheduleRefresh,
      onMovesChanged: _scheduleRefresh,
      onQuickPhrase: _handleIncomingQuickPhrase,
    );

    await refresh(silent: true);
  }

  /// Oturumdaki kullanıcı — OKUMASI ASLA ÇÖKMEZ.
  ///
  /// `Supabase.instance` başlatılmamışsa ASSERTION FIRLATIR ve bu getter
  /// build() içinden çağrıldığı için tüm ekranı kırmızı hata ekranına
  /// çeviriyordu. Kimliği okuyamamak "oturum yok" demektir; ekranın çökmesi
  /// için bir sebep değil. (Widget testlerinde de Supabase başlatılmadığı
  /// için ekranlar bu yüzden hiç kurulamıyordu.)
  String? get _myUserId {
    try {
      return Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  int? get mySeatNo {
    final uid = _myUserId;
    if (uid == null) return null;
    for (final s in _seats) {
      if (s.userId == uid) return s.seatNo;
    }
    return null;
  }

  bool get isMyTurn =>
      _match != null && mySeatNo != null && _match!.turnSeat == mySeatNo;
  bool get canDraw => isMyTurn && _match?.turnPhase == 'draw';
  bool get canActOnHand => isMyTurn && _match?.turnPhase == 'discard';

  /// BU TURDA yandan aldığım taşı geri koydum mu? (RULES.md §4)
  ///
  /// Geri koymak sırayı 'çekme' aşamasına döndürür; ama o taş artık
  /// alınamaz — yoksa "al → geri koy → yine al" ile oyuncu kendini tuzağa
  /// düşürürdü: geri alma hakkı tur başına bir kez olduğu için ikinci
  /// alıştan sonra vazgeçmenin yolu kalmaz.
  ///
  /// Kuralı SUNUCU uygular (`okey_internal_draw_for_seat`); buradaki hesap
  /// yalnızca ıskartayı sönük göstermek ve reddedilecek bir dokunuşu baştan
  /// engellemek içindir. Tur devredince maçın `turn_token`'ı değişir ve
  /// karşılaştırma kendiliğinden bozulur.
  bool get sideDrawUndoneThisTurn =>
      _sideDrawUndoneToken != null && _sideDrawUndoneToken == _match?.turnToken;

  /// Soldaki oyuncunun ıskartasından taş alabilir miyim?
  bool get canDrawFromSide => canDraw && !sideDrawUndoneThisTurn;

  int get secondsLeft {
    final deadline = _match?.turnDeadline;
    if (deadline == null) return 0;
    final diff = deadline.difference(DateTime.now()).inSeconds;
    return diff < 0 ? 0 : diff;
  }

  /// Istaka slotları: her eleman bir taş ya da boşluk (null).
  List<OkeyTile?> get rackSlots =>
      _rackSlotsView ??= List.unmodifiable(_rackSlots);

  /// Rafta duran taşlar (boşluklar hariç). Seçim/işlem indeksleri SLOT
  /// indeksidir, bu liste yalnızca sayım/kontrol amaçlıdır.
  List<OkeyTile> get availableRackTiles => OkeyRackLayout.tilesOf(_rackSlots);

  /// Rafta olması gereken taşlar: elimdekiler eksi hazırlanmış (staged) gruplar.
  List<OkeyTile> get _expectedRackTiles {
    final remaining = List<OkeyTile>.from(_myHand);
    for (final group in _stagedGroups) {
      for (final tile in group) {
        remaining.remove(tile);
      }
    }
    return remaining;
  }

  /// Sunucudan gelen el ile mevcut yerleşimi birleştirir (elle dizilim korunur).
  void _syncRackSlots() {
    // Çekilen taş, oyuncunun BIRAKTIĞI slota yerleşir (varsa). Tek
    // kullanımlıktır: yerleştikten sonra sıfırlanır ki sonraki tazelemeler
    // taşları oraya toplamasın.
    _setRackSlots(
      OkeyRackLayout.mergeWithHand(
        _rackSlots,
        _expectedRackTiles,
        preferredSlot: _pendingDrawSlot,
      ),
    );
    _pendingDrawSlot = null;
  }

  // ---------------------------------------------------------------------
  // OTOMATİK PER SAYIMI
  // Istakada boşlukla ayrılmış bitişik taş öbekleri otomatik olarak
  // per/grup/çift adayı sayılır — oyuncunun ayrıca "grup yap" demesine
  // gerek yoktur (ör. 1-2-3-4-5 aynı renk, ya da 2-2-2 farklı renk).
  // ---------------------------------------------------------------------

  /// Istakadaki bitişik öbekler (boşluklarla ayrılmış).
  ///
  /// detectedSeriesGroups/detectedPairGroups/groupEndSlots/completeMeldSlots
  /// hepsi bunu okur — rafın parmak izi değişmediyse tekrar taramaya gerek
  /// yok.
  int? _groupsRackFingerprint;
  List<({List<int> slots, List<OkeyTile> tiles})>? _cachedGroups;

  /// Rafın parmak izi — hem öbekler hem de onlardan türeyen görsel kümeler
  /// (grup sonu boşlukları, tamamlanmış per vurgusu) bunu kullanır.
  ///
  /// PERFORMANS: bu getter'lar her build'de birkaç kez çağrılıyor; parmak izi
  /// 32 elemanlık ucuz bir karma, arkasındaki tarama ise değil.
  int _groupsFingerprint() => _rackRevision;

  List<({List<int> slots, List<OkeyTile> tiles})> get _groups {
    final fp = _groupsFingerprint();
    if (_cachedGroups != null && _groupsRackFingerprint == fp) {
      return _cachedGroups!;
    }
    _groupsRackFingerprint = fp;
    _cachedGroups = OkeyRackLayout.contiguousGroups(_rackSlots);
    return _cachedGroups!;
  }

  int? _groupEndFingerprint;
  Set<int>? _cachedGroupEndSlots;

  int? _completeMeldFingerprint;
  Set<int>? _cachedCompleteMeldSlots;

  int? _okeySlotsFingerprint;
  Set<int>? _cachedOkeySlots;

  // ---------------------------------------------------------------------
  // PER SAYIMI — ıstaka dizilimi ve elin EN İYİ ayrışımı
  //
  // İki ayrı soru vardır ve ikisinin de cevabı gerekir:
  //
  //   1. "Şu an ıstakada hangi perler duruyor?"  → detectedSeriesGroups
  //      (oyuncunun kendi dizilimine saygı duyar; SERİ AÇ bunu masaya koyar)
  //   2. "Elimde toplam kaç puan var?"           → handPotentialPoints
  //      (dizilimden BAĞIMSIZ; ıstakayı hiç düzenlememiş oyuncu da görür)
  //
  // 2026-09-05 — kullanıcı: "mevcut puan gösterilmiyor, 1·2·3 + 2·2·2 varsa
  // 12 yazmalı". Eskiden sayaç YALNIZCA (1)'i okuyordu ve (1) de bir öbeğin
  // TAMAMININ tek başına geçerli bir per olmasını şart koşuyordu: taşlar
  // aralarına boşluk konmadan yan yana dizildiyse "1·2·3·2·2·2" tek bir
  // 6'lık öbek sayılıyor, geçerli olmadığı için puan 0 çıkıyordu. Oyuncu
  // elinde 12 puan olduğu halde ekranda 0 görüyordu.
  // ---------------------------------------------------------------------

  int? _partitionFingerprint;
  List<List<OkeyTile>> _cachedSeriesGroups = const [];
  List<List<OkeyTile>> _cachedPotentialGroups = const [];
  int _cachedPotentialPoints = 0;

  /// Rafın + okey taşının parmak izi. Değişmediyse ayrışım aramaları
  /// (pahalı olan kısım) tekrar çalıştırılmaz.
  int _computePartitionFingerprint(OkeyTile okeyTile) =>
      Object.hash(_rackRevision, okeyTile.hashCode);

  void _recomputePartitionIfNeeded() {
    final match = _match;
    if (match == null) {
      _cachedSeriesGroups = const [];
      _cachedPotentialGroups = const [];
      _cachedPotentialPoints = 0;
      _partitionFingerprint = null;
      return;
    }
    final fp = _computePartitionFingerprint(match.okeyTile);
    if (_partitionFingerprint == fp) return;
    _partitionFingerprint = fp;

    final okey = match.okeyTile;

    // (1) ISTAKA DİZİLİMİ (saf hesap, bkz. OkeyHandPartitioner.fromRackGroups):
    // öbek tek başına geçerli bir perse aynen alınır, değilse içindeki
    // geçerli perler çıkarılır. Böylece "1·2·3·2·2·2" gibi araya boşluk
    // konmamış bir dizilim de iki per olarak sayılır.
    final arranged = OkeyHandPartitioner.fromRackGroups(
      _groups.map((g) => g.tiles),
      okey,
    );
    _cachedSeriesGroups = arranged;

    // (2) ELİN TAMAMI. Dizilime hiç bakmaz: "elimde kaç puan var" sorusunun
    // tek doğru cevabı budur.
    final all = <OkeyTile>[
      for (final t in _rackSlots)
        if (t != null) t,
    ];
    final best = OkeyHandPartitioner.best(all, okey, nodeBudget: 12000);
    final arrangedPoints = OkeyHandPartitioner.pointsOf(arranged, okey);

    // Arama bütçesi dolduysa (approximate) dizilimin kendisi daha iyi
    // olabilir — ikisinin BÜYÜĞÜ alınır, sayaç asla geriye düşmez.
    if (best.points >= arrangedPoints) {
      _cachedPotentialGroups = best.melds;
      _cachedPotentialPoints = best.points;
    } else {
      _cachedPotentialGroups = arranged;
      _cachedPotentialPoints = arrangedPoints;
    }
  }

  /// Geçerli SERİ/GRUP olan öbekler (masaya açılabilecekler).
  List<List<OkeyTile>> get detectedSeriesGroups {
    _recomputePartitionIfNeeded();
    return _cachedSeriesGroups;
  }

  /// ELİMDEKİ TOPLAM PER PUANI — ıstaka dizilimden bağımsız.
  ///
  /// Konsoldaki "açık puan" rozetinin ve SERİ AÇ rozetinin gösterdiği sayı
  /// budur: barajın (101 / katlamalıda daha fazlası) neresindeyim?
  int get handPotentialPoints {
    _recomputePartitionIfNeeded();
    return _cachedPotentialPoints;
  }

  /// AÇILIŞTA masaya konacak gruplar.
  ///
  /// Elim henüz açık değilken sayaç ile düğme AYNI şeyi söylemek zorundadır:
  /// ekranda "105/101" yazıp SERİ AÇ'ın kapalı kalması, oyuncunun anlamadığı
  /// bir kilittir. Bu yüzden ıstaka dizilimi barajı geçmiyor ama elin en iyi
  /// ayrışımı geçiyorsa, açılış o ayrışımla yapılır.
  ///
  /// Elim AÇIKSA dizilime birebir uyulur: o noktadan sonra hangi perin
  /// masaya gideceği oyuncunun tercihidir, tahmin edilmez.
  List<List<OkeyTile>> get openingCandidateGroups {
    // PERFORMANS: bu getter (ve onu okuyan openingCandidatePoints) her
    // build'de birkaç kez çağrılıyor; altındaki hesap ıstaka dizilimini ve
    // elin en iyi ayrışımını puanlıyor. Girdiler değişmediyse cevap da
    // değişmez.
    final fp = Object.hash(
      _rackRevision,
      _isOpeningDone,
      _requiredMinPoints,
      _match?.okeyTile,
    );
    if (_openingCandidateFingerprint == fp) return _cachedOpeningCandidate;
    final result = _computeOpeningCandidateGroups();
    _openingCandidateFingerprint = fp;
    _cachedOpeningCandidate = result;
    _cachedOpeningCandidatePoints = _match == null
        ? 0
        : OkeyHandPartitioner.pointsOf(result, _match!.okeyTile);
    return result;
  }

  int? _openingCandidateFingerprint;
  List<List<OkeyTile>> _cachedOpeningCandidate = const [];
  int _cachedOpeningCandidatePoints = 0;

  List<List<OkeyTile>> _computeOpeningCandidateGroups() {
    _recomputePartitionIfNeeded();
    if (_isOpeningDone) return _cachedSeriesGroups;

    final arranged = _cachedSeriesGroups;
    var arrangedPoints = 0;
    final match = _match;
    if (match != null) {
      for (final g in arranged) {
        arrangedPoints += OkeyMeldValidator.meldPoints(g, match.okeyTile);
      }
    }
    if (arrangedPoints >= _requiredMinPoints) return arranged;
    if (_cachedPotentialPoints > arrangedPoints &&
        _leavesDiscardTile(_cachedPotentialGroups)) {
      return _cachedPotentialGroups;
    }
    return arranged;
  }

  /// GÖSTERGE ÇİFTİ bana açık mı?
  ///
  /// Yalnızca ÇİFTLE AÇANIN hakkı (kullanıcı isteği, 2026-09-07). Henüz
  /// açmadıysam bu yol çiftle açılıştır, yani açıktır; SERİ ile açtıysam
  /// kapalıdır. Kural sunucuda da aynı yerde duruyor
  /// (okey_internal_lay_pairs_for_seat) — burada sadece düğmenin doğru
  /// görünmesi için tekrarlanıyor, çünkü sunucu reddettiğinde oyuncu
  /// "neden olmadı" sorusuyla baş başa kalırdı.
  bool get canUseGostergePair => !_isOpeningDone || _openedWithPairs;

  /// Geçerli ÇİFT olan öbekler.
  ///
  /// Göstergeyle aynı tek taş başlı başına bir çift sayılır — ama yalnızca
  /// çiftle açan için (bkz. [canUseGostergePair]). Bu sayede 4 gerçek çifti
  /// olan oyuncu göstergeyle 5 çift açabilir.
  List<List<OkeyTile>> get detectedPairGroups {
    final match = _match;
    if (match == null) return const [];
    final gostergeOk = canUseGostergePair;
    return _groups
        .where(
          (g) => gostergeOk
              ? OkeyMeldValidator.isValidPairEx(
                  g.tiles,
                  match.okeyTile,
                  match.indicatorTile,
                )
              : OkeyMeldValidator.isValidPair(g.tiles, match.okeyTile),
        )
        .map((g) => g.tiles)
        .toList();
  }

  /// Otomatik sayılan serilerin toplam açılış puanı (101 barajı göstergesi).
  int get detectedSeriesPoints {
    final match = _match;
    if (match == null) return 0;
    var total = 0;
    for (final g in detectedSeriesGroups) {
      total += OkeyMeldValidator.meldPoints(g, match.okeyTile);
    }
    return total;
  }

  /// [openingCandidateGroups] toplam puanı — SERİ AÇ'ın barajla karşılaştırdığı
  /// sayı ve konsolda gösterilen sayı BUDUR (ikisi ayrışamaz).
  int get openingCandidatePoints {
    if (_match == null) return 0;
    // Önbelleği tazeler; puan da aynı geçişte yazılır.
    final _ = openingCandidateGroups;
    return _cachedOpeningCandidatePoints;
  }

  int get detectedPairCount => detectedPairGroups.length;

  /// Bir perin/grubun SON slotu olan indeksler — bunlardan sonra küçük bir
  /// boşluk bırakılır ki perler gözle ayırt edilsin.
  ///
  /// Kuralın tamamı ve gerekçesi: [OkeyRackLayout.groupEndSlots].
  Set<int> get groupEndSlots {
    final fp = _groupsFingerprint();
    if (_cachedGroupEndSlots != null && _groupEndFingerprint == fp) {
      return _cachedGroupEndSlots!;
    }
    // Kural SAF MOTORDA (bkz. OkeyRackLayout.groupEndSlots): provider
    // Supabase'e bağlı olduğu için burada doğrudan test edilemez, orada ise
    // tek başına ölçülebilir.
    final result = OkeyRackLayout.groupEndSlots(_rackSlots);
    _groupEndFingerprint = fp;
    _cachedGroupEndSlots = result;
    return result;
  }

  /// Masadaki açık perlere İŞLENEBİLEN elimdeki taşlar.
  ///
  /// "TAŞLARI İŞLE" hiçbir taş seçili değilken bunları işler; oyuncunun
  /// işlek taşları tek tek seçmesi gerekmez.
  List<OkeyTile> get processableTiles {
    final match = _match;
    if (match == null || !_isOpeningDone) return const [];
    final result = <OkeyTile>[];
    for (final slot in processableTileIndices) {
      if (slot < 0 || slot >= _rackSlots.length) continue;
      final t = _rackSlots[slot];
      if (t != null) result.add(t);
    }
    return result;
  }

  /// Geçerli bir per/grup/çiftin PARÇASI olan slot indeksleri —
  /// ıstakada yeşil vurgu için.
  Set<int> get completeMeldSlots {
    final match = _match;
    if (match == null) return const {};
    // PERFORMANS: her öbek için iki ayrı doğrulama koşuyor ve bu getter her
    // build'de okunuyor. Raf ve okey/gösterge taşı değişmediyse sonuç da
    // değişmez.
    final fp = Object.hash(
      _groupsFingerprint(),
      match.okeyTile.hashCode,
      match.indicatorTile.hashCode,
      // Gösterge hakkı açılışla DEĞİŞİR: seriyle açan biri için tek başına
      // duran gösterge taşı artık "tamamlanmış çift" değildir, dolayısıyla
      // altın vurgu da kalkmalı. Parmak izine girmezse vurgu eski hâlinde
      // donup kalırdı.
      canUseGostergePair,
    );
    if (_cachedCompleteMeldSlots != null && _completeMeldFingerprint == fp) {
      return _cachedCompleteMeldSlots!;
    }
    final gostergeOk = canUseGostergePair;
    final result = <int>{};
    for (final g in _groups) {
      if (OkeyMeldValidator.isValidMeld(g.tiles, match.okeyTile) ||
          (gostergeOk
              ? OkeyMeldValidator.isValidPairEx(
                  g.tiles,
                  match.okeyTile,
                  match.indicatorTile,
                )
              : OkeyMeldValidator.isValidPair(g.tiles, match.okeyTile))) {
        result.addAll(g.slots);
      }
    }
    _completeMeldFingerprint = fp;
    _cachedCompleteMeldSlots = result;
    return result;
  }

  // ---------------------------------------------------------------------
  // OKEY TAŞLARININ GİZLENMESİ
  // Istakadaki okey (joker) taşlarım varsayılan olarak KAPALI durur;
  // üzerine ÇİFT BASINCA açılır. Yardımsız modda ise hep açıktır.
  // (Gösterge 1 ise okey 2'dir — türetme sunucuda yapılır.)
  // ---------------------------------------------------------------------

  // ---------------------------------------------------------------------
  // SES
  // ---------------------------------------------------------------------

  bool get isSoundOn => _sound.isEnabled;

  Future<void> toggleSound() async {
    await _sound.toggle();
    _notify();
  }

  /// Arka plan müziği efektlerden BAĞIMSIZ açılıp kapanır.
  bool get isMusicOn => _sound.isMusicEnabled;

  Future<void> toggleMusic() async {
    await _sound.toggleMusic();
    _notify();
  }

  /// SESLİ ANONS ("Seri açıldı" / "Çift açıldı" / "… son üç taş") açık mı?
  ///
  /// Efekt ve müzikten ayrı bir tercih (bkz. OkeySoundService.isVoiceEnabled).
  /// Kapalıyken anonsun YAZILI bandı görünmeye devam eder — bilgi kaybolmaz,
  /// yalnızca susar.
  bool get isVoiceOn => _sound.isVoiceEnabled;

  Future<void> toggleVoice() async {
    await _sound.toggleVoice();
    _notify();
  }

  /// Yardımlı modda okey taşları kapalı gösterilir.
  bool get hideOkeyTiles => isAssistOn;

  /// Istakada okey (joker) olan slotlar.
  Set<int> get okeySlots {
    final match = _match;
    if (match == null) return const {};
    final fp = Object.hash(_groupsFingerprint(), match.okeyTile.hashCode);
    if (_cachedOkeySlots != null && _okeySlotsFingerprint == fp) {
      return _cachedOkeySlots!;
    }
    final result = <int>{};
    for (var i = 0; i < _rackSlots.length; i++) {
      final tile = _rackSlots[i];
      if (tile != null && tile.isJokerFor(match.okeyTile)) result.add(i);
    }
    _okeySlotsFingerprint = fp;
    _cachedOkeySlots = result;
    return result;
  }

  /// Şu an KAPALI gösterilmesi gereken slotlar.
  Set<int> get hiddenOkeySlots {
    if (!hideOkeyTiles) return const {};
    return okeySlots.difference(_revealedOkeySlots);
  }

  /// Okey taşına çift basıldığında aç/kapat.
  void toggleOkeyReveal(int slotIndex) {
    if (!hideOkeyTiles) return;
    if (!okeySlots.contains(slotIndex)) return;
    if (_revealedOkeySlots.contains(slotIndex)) {
      _revealedOkeySlots.remove(slotIndex);
    } else {
      _revealedOkeySlots.add(slotIndex);
    }
    _notify();
  }

  /// Elim açık mı (101 barajını geçip masaya taş koydum mu)?
  bool get isOpeningDone => _isOpeningDone;

  /// BU ELDE topladığım ek ceza (işlek taş atma, okey atma, kullanılmayan
  /// yandan çekme). El sonunda skoruma eklenecek — konsolda skor balonunun
  /// yanında ANINDA gösterilir ki hata yapıldığı an fark edilsin.
  int get myPenaltyPoints => _myPenaltyPoints;

  /// Çift ile mi açtım? (bitiremezsem ceza 2 katı — RULES.md §7)
  bool get openedWithPairs => _openedWithPairs;

  /// "Çifte gidiyorum" beyanım (açamazsam 404 — RULES.md §7)
  bool get wentForPairs => _wentForPairs;

  /// Açmam için gereken baraj (katlamalı/eşli sunucuda hesaplanır).
  int get requiredMinPoints => _requiredMinPoints;
  int get requiredMinPairs => _requiredMinPairs;

  /// Seçili taşların oluşturduğu grupların toplam açılış puanı (UI ipucu).
  int get stagedPoints {
    final match = _match;
    if (match == null || _stagedGroups.isEmpty) return 0;
    var total = 0;
    for (final g in _stagedGroups) {
      if (OkeyMeldValidator.isValidMeld(g, match.okeyTile)) {
        total += OkeyMeldValidator.meldPoints(g, match.okeyTile);
      }
    }
    return total;
  }

  /// Hazırlanan grupların hepsi geçerli çift mi?
  bool get stagedAreAllPairs {
    final match = _match;
    if (match == null || _stagedGroups.isEmpty) return false;
    return _stagedGroups.every(
      (g) => OkeyMeldValidator.isValidPair(g, match.okeyTile),
    );
  }

  /// RULES.md §6 — BİTİŞ YALNIZCA ATMA İLE OLUR: hiçbir açma hamlesi eli
  /// tamamen boşaltamaz, elde atılacak en az bir taş kalmalıdır.
  ///
  /// Sunucu bunu `APP:must_keep_discard_tile` ile reddeder (bkz.
  /// 20260903000002_okey_finish_requires_discard.sql). Burada da bakılır ki
  /// buton daha basılmadan kapansın: aksi halde oyuncu tam kazanacakken
  /// anlamsız bir hata görürdü.
  bool _leavesDiscardTile(List<List<OkeyTile>> groups) {
    final laid = groups.fold<int>(0, (sum, g) => sum + g.length);
    return _myHand.length - laid >= 1;
  }

  /// Istakadaki geçerli perlerin TAMAMI açılırsa el boşalır mı? (uyarı metni)
  bool get wouldEmptyHandBySeries =>
      openingCandidateGroups.isNotEmpty &&
      !_leavesDiscardTile(openingCandidateGroups);

  bool get wouldEmptyHandByPairs =>
      pairGroupsToLay.isNotEmpty && !_leavesDiscardTile(pairGroupsToLay);

  /// RULES.md §3 — seri/grup ile açma/koyma yapılabilir mi?
  /// Gruplar ıstakadan OTOMATİK sayılır.
  bool get canLaySeries {
    if (!canActOnHand) return false;
    if (_openedWithPairs) return false; // çift açan çiftle devam eder
    final groups = openingCandidateGroups;
    if (groups.isEmpty) return false;
    if (!_leavesDiscardTile(groups)) return false;
    if (_isOpeningDone) return true; // açıksa baraj aranmaz
    return openingCandidatePoints >= _requiredMinPoints;
  }

  /// SERİ AÇ neden kapalı? Açıksa null.
  ///
  /// ## Neden var
  ///
  /// Kapalı bir düğme, sebebini söylemediği sürece bir HATADAN ayırt
  /// edilemez. [layPairs]/[laySeries] içinde zaten iyi yazılmış açıklamalar
  /// var ama düğme kapalıyken oraya hiç girilmiyor — yani metinler
  /// ulaşılamaz durumda duruyordu. Bu iki getter aynı gerekçeleri düğmenin
  /// kendisine taşır.
  ///
  /// Sıra [canLaySeries]/[canLayPairs] ile BİREBİR aynıdır: farklı olsaydı
  /// düğme bir sebeple kapanıp başka bir sebep söylerdi.
  String? get seriesBlockedReason {
    if (canLaySeries) return null;
    final turn = _turnBlockedReason;
    if (turn != null) return turn;
    if (_openedWithPairs) {
      return 'Elini ÇİFT ile açtın — bu elde seri/grup açamazsın, '
          'çiftle devam etmelisin.';
    }
    final groups = openingCandidateGroups;
    if (groups.isEmpty) {
      return 'Istakada geçerli bir per yok. Istakanın sağ ucundaki '
          'SERİ DİZ düğmesine bas.';
    }
    if (!_leavesDiscardTile(groups)) return _keepOneTileHint;
    if (!_isOpeningDone && openingCandidatePoints < _requiredMinPoints) {
      return 'Açmak için $_requiredMinPoints puan gerekli; '
          'ıstakadaki perler $openingCandidatePoints puan ediyor.';
    }
    return null;
  }

  /// ÇİFT AÇ neden kapalı? Açıksa null. (bkz. [seriesBlockedReason])
  String? get pairsBlockedReason {
    if (canLayPairs) return null;
    final turn = _turnBlockedReason;
    if (turn != null) return turn;
    // SERİ ile açmış oyuncu (RULES.md §3): masada çift açan varsa en çok
    // [seriesPairsLimit] çift indirebilir. İki şart da tek tek söylenir —
    // "çift açamazsın" demek artık yanlış olurdu.
    if (_isOpeningDone && !_openedWithPairs) {
      if (!pairsOpenerOnTable) {
        return 'Elini SERİ ile açtın: çift indirebilmen için masada çift '
            'açmış bir oyuncu olmalı. Henüz yok.';
      }
      if (seriesPairsAllowance <= 0) {
        return 'Seri ile açtın — bir turda en çok $seriesPairsLimit çift '
            'indirebilirsin. Bu turluk hakkın doldu; sıra sana dönünce '
            'yeniden $seriesPairsLimit hakkın olacak.';
      }
    }
    // BEYAN önce söylenir: çiftleri dizmiş bir oyuncunun eksiği çoğu zaman
    // budur ve rozette "5/5" yazarken düğmenin kapalı kalması, oyuncunun
    // kendi başına çözemeyeceği tek durumdur.
    if (!_isOpeningDone && !_wentForPairs) {
      return 'Çiftle açmak için önce "Çifte gidiyorum" demelisin — '
          'kutucuk plakanın yanında.';
    }
    final groups = pairGroupsToLay;
    if (groups.isEmpty) {
      return 'Istakada çift yok. Istakanın sol ucundaki ÇİFT DİZ düğmesine '
          'bas ya da aynı renk+rakam taşları İKİŞERLİ, aralarında boşluk '
          'bırakarak diz.';
    }
    if (!_leavesDiscardTile(groups)) return _keepOneTileHint;
    if (!_isOpeningDone && groups.length < _requiredMinPairs) {
      return 'Açmak için $_requiredMinPairs çift gerekli; ıstakada '
          '${groups.length} çift ayrılmış.';
    }
    return null;
  }

  /// İŞLE neden kapalı? Açıksa null. (bkz. [seriesBlockedReason])
  String? get processBlockedReason {
    final turn = _turnBlockedReason;
    if (turn != null) return turn;
    if (!_isOpeningDone) {
      return 'İşlemek için önce elini açmalısın.';
    }
    if (_selectedIndices.isEmpty && processableTiles.isEmpty) {
      return 'Masadaki perlere işlenebilecek taşın yok.';
    }
    return null;
  }

  /// TAŞI AT neden kapalı? Açıksa null. (bkz. [seriesBlockedReason])
  String? get discardBlockedReason {
    final turn = _turnBlockedReason;
    if (turn != null) return turn;
    if (_selectedIndices.isEmpty) {
      return 'Atmak için bir taş seç — ya da taşı doğrudan ıskartana sürükle.';
    }
    if (_selectedIndices.length > 1) {
      return 'Tek seferde tek taş atılır; ${_selectedIndices.length} taş '
          'seçili.';
    }
    return null;
  }

  /// Hamle sırası/aşaması engelliyorsa sebebi; engellemiyorsa null.
  String? get _turnBlockedReason {
    if (isSpectating) return 'Masayı izliyorsun — hamle yapamazsın.';
    if (!isMyTurn) return 'Sıra sende değil.';
    if (_match?.turnPhase == 'draw') {
      return 'Önce taş çek: soldaki ıskartadan ya da desteden.';
    }
    return null;
  }

  /// RULES.md §3 — çift ile açma/koyma yapılabilir mi?
  ///
  /// İLK açılışta "çifte gidiyorum" beyanı ŞARTTIR (RULES.md §7): beyan geri
  /// alınamaz ve 404 cezasının karşılığıdır. Sunucu beyansız çift açılışını
  /// `APP:pairs_declaration_required` ile reddeder.
  ///
  /// SERİ ile açmış oyuncu da çift indirebilir: masada başkasının indirdiği
  /// bir çift varsa ve [seriesPairsLimit] hakkı dolmadıysa
  /// (bkz. [pairGroupsToLay], [seriesPairsAllowance]).
  bool get canLayPairs {
    if (!canActOnHand) return false;
    final groups = pairGroupsToLay;
    if (groups.isEmpty) return false;
    if (!_leavesDiscardTile(groups)) return false;
    // Açılış türü/hak kontrolü pairGroupsToLay içinde yapıldı: seri ile açmış
    // ve hakkı olmayan oyuncu buraya boş listeyle gelir.
    if (_isOpeningDone) return true;
    if (!_wentForPairs) return false;
    return groups.length >= _requiredMinPairs;
  }

  /// ÇİFT AÇ'a basıldığında GERÇEKTEN gönderilecek gruplar.
  ///
  /// Seri ile açmış oyuncu için [seriesPairsLimit] sınırına göre budanır
  /// (RULES.md §3): ıstakada 5 çift ayrılmış olsa bile 3'ü gider. Budamak
  /// yerine hepsini göndermek, sunucudan `APP:series_pairs_limit` almak
  /// demekti — yani oyuncu hakkı olduğu 3 çifti de indiremezdi.
  List<List<OkeyTile>> get pairGroupsToLay {
    final groups = detectedPairGroups;
    if (!_isOpeningDone || _openedWithPairs) return groups;
    final allowance = seriesPairsAllowance;
    if (allowance <= 0) return const [];
    return groups.length <= allowance ? groups : groups.sublist(0, allowance);
  }

  /// RULES.md §6 — bitiş: eli boşaltıp son taşı atmak. Elde tek taş kaldıysa
  /// ve el açıksa, o taşı atmak oyunu bitirir.
  bool get isOneTileFromWinning =>
      canActOnHand && _isOpeningDone && _myHand.length == 1;

  // ---------------------------------------------------------------------
  // Veri yükleme
  // ---------------------------------------------------------------------

  /// Arka plandan dönüş / bağlantı kopması sonrası: realtime kanalları
  /// yeniden kurup durumu DB'den tam olarak yeniden okur.
  Future<void> reconnect() async {
    _isDragging = false;
    _pendingNotify = false;
    await _realtime.unsubscribe();
    _realtime.subscribe(
      matchId: matchId,
      onMatchChanged: _scheduleRefresh,
      onHandChanged: _scheduleRefresh,
      onMeldsChanged: _scheduleRefresh,
      onMovesChanged: _scheduleRefresh,
      onQuickPhrase: _handleIncomingQuickPhrase,
    );
    await refresh(silent: true);
    // Hediye kanalı da unsubscribe ile kapandı — oda kimliği elimizdeyken
    // yeniden kurulur, yoksa masaya dönen oyuncu hediyeleri hiç görmezdi.
    // Asılı hediyeler de baştan okunur: bağlantı kopukken gelenler
    // kaçırılmış olabilir.
    _giftRoomId = null;
    _pinnedGiftsLoaded = false;
    _subscribeGifts();
  }

  Future<void> refresh({bool silent = false}) async {
    if (_disposed) return;
    // Uçuşta bir tazeleme varken ikincisini BAŞLATMA: aynı beş sorgu iki kez
    // gider ve ikisi yarışa girip birbirinin sonucunu ezerdi. İstek kaybolmaz,
    // kuyruğa yazılır ve mevcut tazeleme biter bitmez BİR KEZ tekrarlanır.
    if (_refreshInFlight) {
      _refreshQueued = true;
      return;
    }
    _refreshInFlight = true;
    // HANGİ EL İÇİN okuduğumuzu yakala. El bitip sıradakine geçildiğinde
    // (bkz. [switchToMatch]) uçuşta kalmış bu okuma, biten elin durumunu yeni
    // elin üstüne yazardı — masa bir an için bitmiş eli gösterirdi.
    final requestedMatchId = _matchId;
    final requestedHandOps = _localHandOps;
    if (!silent) {
      _isLoading = true;
      _notify();
    }
    try {
      // Hamleler SES ve UÇAN TAŞ için okunur.
      //
      // İLK tazelemede yalnızca "en son hamle" okunur ve OYNATILMAZ: masaya
      // girerken geçmiş hamleler arka arkaya uçmasın diye sadece işaret konur.
      final seenMoveId = _lastSoundMoveId;

      // TEK OKUMA (performans, 2026-09-13). Masanın tamamı — maç, elim,
      // perler, taş sayıları, hamleler, baraj rozetleri, "geri koy" hakkı —
      // tek bir RPC turunda gelir. Eskiden bunlar YEDİ ayrı istekti;
      // paralel uçsalar bile toplam süre en yavaş istekten aşağı inmiyordu
      // ve her biri kendi PostgREST maliyetini ödüyordu.
      //
      // Sunucu bu fonksiyonu tanımıyorsa (yayınlanmamış sürüm) snapshot null
      // döner ve aşağıdaki ESKİ yol aynen çalışır — oyun kesintiye uğramaz.
      final snapshot = await _service.getSnapshot(
        matchId,
        afterMoveId: seenMoveId,
      );

      // ESKİ YOL — bu 4 çağrı birbirinden bağımsızdır (matchId zaten
      // biliniyor, hiçbiri diğerinin sonucuna muhtaç değil) ve Dart'ta bir
      // Future oluşturulduğu anda çalışmaya başlar, await edildiği anda
      // değil: hepsi aynı anda uçuşur.
      final matchFuture = snapshot != null ? null : _service.getMatch(matchId);
      final handFuture = snapshot != null ? null : _service.getMyHand(matchId);
      final meldsFuture = snapshot != null
          ? null
          : _service.getTableMelds(matchId);
      final countsFuture = snapshot != null
          ? null
          : _service.getSeatTileCounts(matchId);
      final movesFuture = snapshot != null
          ? Future<List<OkeyMoveRow>>.value(snapshot.moves)
          : (seenMoveId == null
                ? _service
                      .getLastMove(matchId)
                      .then(
                        (m) => m == null ? <OkeyMoveRow>[] : <OkeyMoveRow>[m],
                      )
                : _service.getMovesSince(matchId, seenMoveId));

      final match = snapshot?.match ?? await matchFuture!;
      // Bunlar match.roomId'ye muhtaç, o yüzden ancak match gelince
      // başlatılabilirler — ama ikisi birbirinden bağımsız, yine paralel.
      //
      // KOLTUKLAR HER TAZELEMEDE OKUNMAZ. Sorgu iki ilişkiyi (profiles,
      // okey_bot_profiles) birlikte çeker ve bu masanın en pahalı okumasıdır;
      // oysa OkeyRoomSeat yalnızca kimlik taşır (ad, avatar, bot mu, hazır
      // mı) ve el sürerken bunların hiçbiri değişmez. Yeni el başladığında,
      // koltuklar henüz yüklenmemişken ve arada bir emniyet için yenilenir.
      final seatsFuture = _shouldRefetchSeats(match)
          ? _roomService.getSeats(match.roomId)
          : null;
      final roomFuture = _room == null
          ? _roomService.getRoom(match.roomId)
          : null;

      final hand = snapshot?.hand ?? await handFuture!;
      final melds = snapshot?.melds ?? await meldsFuture!;
      final counts = snapshot?.counts ?? await countsFuture!;
      if (seatsFuture != null) {
        _seats = await seatsFuture;
        _seatsFetchedAt = DateTime.now();
        _seatsHandNo = match.handNo;
      }
      if (roomFuture != null) _room = await roomFuture;

      // BAYAT SONUÇ: bu okuma sürerken sıradaki ele geçildiyse hiçbir şey
      // yazılmaz; yeni el için kuyruktaki tazeleme zaten çalışacak.
      if (_disposed || requestedMatchId != _matchId) return;

      _match = match;
      // BAYAT EL YAZILMAZ (bkz. [_localHandOps]).
      if (_localHandOps == requestedHandOps) {
        _myHand = hand.tiles;
        _handRevision++;
      }
      _isOpeningDone = hand.isOpeningDone;
      _myPenaltyPoints = hand.penaltyPoints;
      _openedWithPairs = hand.openedWithPairs;
      _wentForPairs = hand.wentForPairs;
      _seriesPairsTurnToken = hand.seriesPairsTurnToken;
      _seriesPairsTurnCount = hand.seriesPairsTurnCount;
      _sideDrawUndoneToken = hand.sideDrawUndoneToken;
      _setTableMelds(melds);
      _opponentTileCounts = counts;
      // ANONSLAR — masa durumu tazelendikten SONRA, çünkü karar bu iki
      // listenin bir önceki haliyle karşılaştırılmasından çıkıyor
      // (bkz. _updateAnnouncements: kendi hafızasını kendi tutar).
      _updateAnnouncements(match, melds, counts);
      _syncRackSlots();
      // Artık elimde olmayan slotların "açık" işareti kalmasın
      _revealedOkeySlots.removeWhere(
        (i) => i >= _rackSlots.length || _rackSlots[i] == null,
      );

      // RULES.md §3/§5 — BARAJ.
      //
      // Katlamalı modda baraj "masadaki en yüksek açılış + 1"dir ve iki
      // girdisi de (highest_opening_points / _pairs) maç satırında, yani
      // ELİMDE. Eskiden bunun için HER tazelemede ayrı bir RPC turu daha
      // atılıyordu: hem gereksiz gecikme, hem de ağ hatasında sessizce 101'e
      // düşen (yani katlamalıyı yok sayan) bir yedek yol.
      //
      // İSTİSNA — EŞLİ MOD: eşim açtıysa baraj TABANA iner (101 / 5 çift,
      // katlama işlemez), ama eşimin is_opening_done değerini RLS gereği
      // okuyamam. Baraj artık aynı okumada geliyor (required_opening); yalnızca
      // eski sunucuda ayrı bir tur atılır.
      final required = snapshot?.requiredOpening;
      if (required != null) {
        _requiredMinPoints = required.minPoints;
        _requiredMinPairs = required.minPairs;
      } else {
        final seat = mySeatNo;
        if (seat != null && !hand.isOpeningDone) {
          // EŞLİ MODDA bu bir RPC turudur ve eskiden tazelemeyi BEKLETİYORDU
          // (performans, 2026-09-07). Yerel hesap zaten senkron yapılıyor;
          // sunucuya yalnızca "eşim açtı mı" sorusu için gidiliyor ve o cevap
          // bir rozet eşiğini değiştirir, masanın akışını değil.
          final local = _updateRequiredOpening(seat);
          if (_room?.teamMode == 'esli') {
            unawaited(local);
          } else {
            await local;
          }
        }
      }
      _error = null;
      _snapshotMode = snapshot != null;
      if (snapshot != null) {
        // BARAJ ROZETLERİ ve GERİ KOY HAKKI aynı okumada geldi — ikisi de
        // ayrıca sorulmaz. Rozetler artık el başına bir kez değil HER
        // tazelemede günceldir (maliyeti sıfır), yani bir per konduğunda
        // gecikmeden değişir.
        _barajHandNo = match.handNo;
        _barajs = snapshot.barajs;
        _canUndoSideDraw = snapshot.canUndoSideDraw;
      } else {
        // BARAJ ROZETLERİ — yalnızca el değiştiğinde. Açılışlar el içinde
        // olduğu için ayrıca "per kondu" haberiyle de tazelenir
        // (bkz. _playSoundsForNewState).
        if (_barajHandNo != match.handNo) {
          _barajHandNo = match.handNo;
          _barajs = const {};
          unawaited(_refreshBarajs());
        }
        // GERİ KOYMA DÜĞMESİ — TAZELEMEYİ BEKLETMEZ (performans, 2026-09-07).
        //
        // Bu soru bir RPC turu, ve eskiden diğer beş sorgunun SONUNDA await
        // ediliyordu: beşi paralel gittiği için tazelemenin toplam süresi
        // pratikte "en yavaş sorgu + BU sorgu" oluyordu. Yani sıra bendeyken
        // her tazeleme, masanın hiçbir yerinde görünmeyen bir düğme uğruna
        // bir tur daha uzuyordu.
        //
        // Artık arkada sorulur ve cevap DEĞİŞTİYSE ayrıca bildirilir.
        _refreshUndoSideDraw(match);
      }
      // Oda kimliği ancak maç okunduktan sonra bilinir; hediye kanalı ilk
      // tazelemede kurulur (idempotenttir, sonrakilerde hiçbir şey yapmaz).
      _subscribeGifts();
      secondsLeftNotifier.value = secondsLeft;
      unawaited(refreshSpectators());
      // SES, EKRANI BEKLETMEZ. Eskiden burada await vardı: _notify()
      // finally'de olduğu için masa, ses dosyası açılıp çalmaya başlayana
      // kadar (kayıttan okuma + oynatıcıyı durdurup kaynak atama) eski
      // durumu göstermeye devam ediyordu. Ses opsiyoneldir, hamle değil.
      unawaited(_playSoundsForNewState(movesFuture).catchError((_) {}));
      _maybeScheduleBotTurn();
    } catch (e) {
      _error = 'Maç bilgisi alınamadı: $e';
    } finally {
      _isLoading = false;
      _refreshInFlight = false;
      _notify();
      if (_refreshQueued && !_disposed) {
        _refreshQueued = false;
        // KUYRUKTAKİ TEKRAR DA BİRLEŞTİRİLİR (performans, 2026-09-07).
        //
        // Eskiden hemen yeni bir tam tazeleme başlıyordu. Tek bir hamle DÖRT
        // realtime olayı doğurduğu ve bunların bir kısmı hep sürmekte olan
        // tazelemenin ÜSTÜNE düştüğü için, pratikte her hamle iki tam
        // tazeleme (2 × 5 sorgu) demekti. Debounce'tan geçirmek hem araya
        // düşen yeni olayları aynı tura toplar hem de sunucudan okunanı
        // yarıya indirir; gecikme farkı 120 ms ve o tazeleme zaten "bir şey
        // kaçırmayalım" turudur.
        _scheduleRefresh();
      }
    }
  }

  /// "Yandan aldığım taşı geri koyabilir miyim?" — ARKA PLANDA sorulur.
  ///
  /// Cevap yalnızca DEĞİŞTİĞİNDE bildirilir: aynı cevabı tekrar yazmak için
  /// masanın tamamını (22 sürüklenebilir taş dahil) yeniden kurmanın anlamı
  /// yok.
  void _refreshUndoSideDraw(OkeyMatch match) {
    final shouldAsk =
        match.turnSeat == mySeatNo && match.turnPhase == 'discard';
    if (!shouldAsk) {
      if (_canUndoSideDraw) {
        _canUndoSideDraw = false;
        _notify();
      }
      return;
    }
    // TUR DAMGASI: cevap geldiğinde hâlâ aynı turda mıyız? Bayat bir "evet",
    // hakkı çoktan bitmiş bir turda düğmeyi yakardı.
    final token = match.turnToken;
    unawaited(() async {
      bool value;
      try {
        value = await _service.canUndoSideDraw(matchId);
      } catch (_) {
        // Düğmenin görünmemesi, yanlışlıkla görünmesinden iyidir.
        value = false;
      }
      if (_disposed || _match?.turnToken != token) return;
      if (_canUndoSideDraw == value) return;
      _canUndoSideDraw = value;
      _notify();
    }());
  }

  /// Açılış barajını günceller (bkz. [refresh] içindeki açıklama).
  Future<void> _updateRequiredOpening(int seat) async {
    final match = _match;
    final katlamali = _room?.gameMode == 'katlamali';

    // Yerel hesap — sunucudaki okey_required_opening ile AYNI formül
    // (bkz. 20260830000011_okey101_dealing_opening_finish.sql).
    if (match != null) {
      _requiredMinPoints = katlamali
          ? math.max(101, match.highestOpeningPoints + 1)
          : 101;
      _requiredMinPairs = katlamali
          ? math.max(5, match.highestOpeningPairs + 1)
          : 5;
    }

    // Eşli modda eşimin durumu gizli: barajın sıfırlanıp sıfırlanmadığını
    // ancak sunucu bilir.
    if (_room?.teamMode != 'esli') return;
    try {
      final req = await _service.getRequiredOpening(matchId, seat);
      if (_disposed) return;
      // DEĞİŞTİYSE BİLDİR: bu çağrı artık tazelemeyi beklemiyor, yani
      // cevabı finally'deki _notify()'dan SONRA gelebilir. Bildirmezsek
      // rozet bir sonraki hamleye kadar eski eşiği gösterirdi.
      final changed =
          _requiredMinPoints != req.minPoints ||
          _requiredMinPairs != req.minPairs;
      _requiredMinPoints = req.minPoints;
      _requiredMinPairs = req.minPairs;
      if (changed) _notify();
    } catch (_) {
      // Yerel hesap yerinde duruyor — ağ hatası barajı düşürmez.
    }
  }

  /// Yeni duruma göre ses efektlerini çalar ve UÇAN TAŞLARI kuyruğa yazar:
  ///  - sıra bana geldiyse "sıra sende"
  ///  - son hamle bir başkasınınsa çekme/atma/açma sesi
  ///  - rakip İŞLENEBİLİR ("işlek") bir taş attıysa gülme efekti
  ///
  /// [movesFuture] son tazelemeden bu yana oynanmış hamlelerin TAMAMINI
  /// eskiden yeniye taşır, tek bir hamleyi değil
  /// (bkz. [OkeyGameService.getMovesSince]).
  Future<void> _playSoundsForNewState(
    Future<List<OkeyMoveRow>> movesFuture,
  ) async {
    final match = _match;
    if (match == null || match.status != 'in_progress') {
      // Future yine de tüketilmeli: yakalanmayan bir hata "unhandled exception"
      // olarak yüzeye çıkardı.
      unawaited(movesFuture.catchError((_) => const <OkeyMoveRow>[]));
      return;
    }

    // Sıra bana yeni geldiyse
    if (_lastTurnSeatForSound != match.turnSeat) {
      final wasSet = _lastTurnSeatForSound != null;
      _lastTurnSeatForSound = match.turnSeat;
      if (wasSet && isMyTurn) {
        await _sound.play(OkeySound.yourTurn);
      }
    }

    try {
      final moves = await movesFuture;
      if (moves.isEmpty) return;
      if (_lastSoundMoveId == null) {
        // İlk yüklemede geçmiş hamleler oynatılmaz — masaya girerken en son
        // hamle zaten olmuş bitmiştir. Yalnızca "buradan devam" işareti.
        _lastSoundMoveId = moves.last.id;
        return;
      }
      final fresh = moves.where((m) => m.id > _lastSoundMoveId!).toList();
      if (fresh.isEmpty) return;
      _lastSoundMoveId = fresh.last.id;

      // UÇAN TAŞ: HER yeni hamle için bir uçuş. Hamleler zaten burada okundu,
      // ikinci bir ağ turu gerekmiyor. Kendi DESTEDEN çekmemde taş bilinir;
      // başkasınınkinde gizli kalsın diye kapalı uçar
      // (bkz. OkeyMoveFlightOverlay._faceUp).
      for (final m in fresh) {
        _queueFlight(m);
        // Baraj tam bu anda doğar: biri masaya açılış perlerini koydu. Her
        // hamleye bakılır — açılış, yığının ORTASINDA da olabilir.
        if (m.action == 'lay_meld') unawaited(_refreshBarajs());
      }

      // SES yalnızca SON hamle için. Üç ses aynı anda çalınca ses motoru
      // öncekini keser: hiçbiri duyulmaz, üstelik en önemlisi (son hamle)
      // kaybolur.
      await _playMoveSound(fresh.last);
    } catch (_) {
      // ses tamamen opsiyonel — hata oyunu etkilemez
    }
  }

  Future<void> _playMoveSound(OkeyMoveRow move) async {
    final isMine = move.seatNo == mySeatNo;
    // KENDİ ÇEKME/ATMAM BURADA ÇALMAZ (performans, 2026-09-08).
    //
    // Bu yol `okey_moves` okunduktan SONRA, yani hamleden bir-iki ağ turu
    // sonra işler. Masa artık hamleyi anında gösterdiği için (iyimser
    // güncelleme) ses de anında çalınıyor — burada bir kez daha çalmak aynı
    // sesin geç bir yankısı olurdu. Rakiplerin hamlelerinde tek kaynak
    // yine burasıdır. `timeout_auto_discard` KAPSAM DIŞI: onu ben
    // yapmadım, sunucu benim adıma yaptı; duyulması gerekir.
    if (isMine &&
        (move.action == 'draw_deck' ||
            move.action == 'draw_discard' ||
            move.action == 'discard')) {
      return;
    }
    switch (move.action) {
      case 'draw_deck':
      case 'draw_discard':
        await _sound.play(OkeySound.drawTile);
        break;
      case 'discard':
      case 'timeout_auto_discard':
        await _sound.play(OkeySound.discardTile);
        // RAKİP "İŞLEK" TAŞ ATTIYSA GÜLME EFEKTİ:
        // attığı taş benim masadaki bir perime işlenebiliyorsa.
        if (!isMine && move.tile != null && _isProcessableTile(move.tile!)) {
          await _sound.play(OkeySound.laugh);
        }
        break;
      case 'lay_meld':
        await _sound.play(OkeySound.layMeld);
        break;
      case 'add_to_meld':
      case 'steal_okey':
        await _sound.play(OkeySound.processTile);
        break;
      case 'declare_win':
        await _sound.play(isMine ? OkeySound.win : OkeySound.lose);
        break;
    }
  }

  /// Bir hamleyi uçuş kuyruğuna yazar.
  ///
  /// KENDİ hamlem kuyruğa hiç girmez: uçuş katmanı onu zaten oynatmıyor
  /// (bkz. OkeyMoveFlightOverlay — "kendi hamlem uçmaz"), oysa kuyrukta yer
  /// tutsaydı arkasındaki RAKİP uçuşunu yarım saniye geciktirirdi. İzleyicide
  /// koltuk yoktur, dolayısıyla dördü de uçar.
  void _queueFlight(OkeyMoveRow m) {
    final mySeat = mySeatNo;
    if (mySeat != null && m.seatNo == mySeat) return;
    // Kuyruk taşmasın: yeniden bağlanınca onlarca hamle birden gelebilir;
    // dakikalarca sürecek bir uçuş treni bilgi değil gürültü olurdu. En YENİ
    // hamleler tutulur, eskiler düşer.
    // Bir TURUN tamamı sığmalı: çek → işle → işle → at.
    if (_flightQueue.length >= 4) _flightQueue.removeAt(0);
    _flightQueue.add(
      OkeyMoveFlash(id: m.id, seatNo: m.seatNo, action: m.action, tile: m.tile),
    );
    if (_flightTimer == null) _emitNextFlight();
  }

  void _emitNextFlight() {
    _flightTimer = null;
    if (_disposed || _flightQueue.isEmpty) return;
    lastMove.value = _flightQueue.removeAt(0);
    // Pencere HER ZAMAN açılır: hemen ardından kuyruğa giren bir uçuş,
    // havadaki taşın üstüne binmesin diye bekler.
    _flightTimer = Timer(_flightGap, _emitNextFlight);
  }

  /// Baraj rozetlerini sunucudan tazeler.
  ///
  /// SESSİZCE BAŞARISIZ OLUR: rozet masanın süsü, oyunun kuralı değil. Ağ
  /// hatası yüzünden hamleyi kesmek ya da hata bandı göstermek, kazanılan
  /// bilgiyle orantısız olurdu — bir sonraki perde yeniden denenir.
  Future<void> _refreshBarajs() async {
    // TEK OKUMA VARSA GEREKSİZ: rozetler her tazelemede maçla birlikte
    // geliyor (bkz. [_snapshotMode]).
    if (_snapshotMode) return;
    try {
      final map = await _service.getBarajs(matchId);
      if (_disposed) return;
      // DEĞİŞMEDİYSE BİLDİRME: _notify() tüm masayı yeniden kurar ve baraj
      // bir elde en fazla dört kez değişir.
      if (map.length == _barajs.length &&
          map.entries.every((e) => _barajs[e.key] == e.value)) {
        return;
      }
      _barajs = map;
      _notify();
    } catch (_) {
      // bkz. yukarıdaki gerekçe
    }
  }

  // ---------------------------------------------------------------------
  // SESLİ ANONSLAR
  //
  // İki olay duyurulur (kullanıcı isteği, 2026-09-07):
  //   * "Seri açıldı" / "Çift açıldı" — masada İLK açılış oldu. ELDE BİR
  //     KEZ; sonraki açılışlar ve indirilen ek perler susar
  //     (bkz. [_openingAnnounced]).
  //   * "… son üç taş" — HERHANGİ bir oyuncunun ıstakasında 3 taş kaldı;
  //     masadaki herkes duyar ve kimin bitmeye yaklaştığını bilir
  //
  // ## Neden hamle akışından (okey_moves) değil, DURUM farkından
  //
  // `lay_meld` hamlesi perin TÜRÜNÜ taşımıyor (bkz. okey_moves.action) —
  // seri mi çift mi olduğu ancak masadaki perin `meld_type`'ından anlaşılır.
  // Tile sayıları da zaten her tazelemede okunuyor. Durum farkı ayrıca
  // KAÇIRMAYA dayanıklıdır: iki hamle tek tazelemede birleşse bile (ki
  // tazelemeler bilerek birleştiriliyor) yeni per yine görülür.
  //
  // ## Elin ORTASINDA masaya oturana geçmiş anons yapılmaz
  //
  // Bir elin durumu ilk kez görüldüğünde yalnızca "bilinen" kümeler
  // doldurulur, hiçbir şey duyurulmaz. Aksi halde masaya sonradan giren
  // oyuncu, o ana kadarki bütün açılışları arka arkaya dinlerdi.
  // ---------------------------------------------------------------------

  void _updateAnnouncements(
    OkeyMatch match,
    List<OkeyTableMeld> melds,
    Map<int, int> counts,
  ) {
    if (match.status != 'in_progress') return;

    final meldIds = {for (final m in melds) m.id};

    // YENİ EL (ya da bu eli ilk görüşüm) → yalnızca hafızayı kur.
    if (_announceHandNo != match.handNo) {
      _announceHandNo = match.handNo;
      _knownMeldIds = meldIds;
      // Masada ZATEN per varsa açılış olup bitmiştir: elin ortasında masaya
      // oturan oyuncu geçmiş açılışı duymaz, ama bir sonrakini de duymamalı.
      _openingAnnounced = melds.isNotEmpty;
      _lowTileAnnouncedSeats
        ..clear()
        ..addAll(counts.entries.where((e) => e.value <= 3).map((e) => e.key));
      return;
    }

    var laidSeries = false;
    var laidPairs = false;
    for (final m in melds) {
      if (_knownMeldIds.contains(m.id)) continue;
      if (m.meldType == 'pair' || m.meldType == 'gosterge') {
        laidPairs = true;
      } else {
        laidSeries = true;
      }
    }
    _knownMeldIds = meldIds;

    // ELDE TEK AÇILIŞ ANONSU (bkz. [_openingAnnounced]). Seri ve çift aynı
    // tazelemede birlikte gelirse SERİ duyurulur: seri açan oyuncu aynı
    // hamlede çift de indirebiliyor, oysa haber "masa açıldı"dır ve o haberi
    // açılışın kendi türü taşır.
    if (!_openingAnnounced && (laidSeries || laidPairs)) {
      _openingAnnounced = true;
      _announce(laidSeries ? 'Seri açıldı' : 'Çift açıldı');
    }

    // SON ÜÇ TAŞ — koltuk 3'e (veya altına) düştüğü anda BİR KEZ.
    // Sayı yeniden yükselirse (yandan çekme) işaret kalkar ki aynı oyuncu
    // için ikinci kez tetiklenebilsin.
    counts.forEach((seatNo, count) {
      if (count <= 0) return;
      if (count > 3) {
        _lowTileAnnouncedSeats.remove(seatNo);
        return;
      }
      if (!_lowTileAnnouncedSeats.add(seatNo)) return;
      _announce(
        seatNo == mySeatNo
            ? 'Sende son üç taş kaldı'
            : '${_spokenSeatName(seatNo)}, son üç taş',
      );
    });
  }

  /// Anonsta okunacak oyuncu adı.
  ///
  /// Ad KISALTILIR ve konuşma motorunun takılacağı işaretlerden arındırılır:
  /// masadaki adlar emoji ve süs karakteri içerebiliyor, TTS bunları ya
  /// harf harf okur ya da cümleyi ortasında keser.
  String _spokenSeatName(int seatNo) {
    String? label;
    for (final s in _seats) {
      if (s.seatNo == seatNo) {
        label = s.displayLabel;
        break;
      }
    }
    final cleaned = (label ?? 'Oyuncu')
        .replaceAll(RegExp(r"[^\p{L}\p{N} .'-]", unicode: true), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.isEmpty) return 'Oyuncu';
    return cleaned.length <= 24 ? cleaned : cleaned.substring(0, 24).trim();
  }

  /// HIZLI MESAJ GÖNDER — kullanıcı isteği, 2026-09-14: "Seri Lütfen",
  /// "Tebrikler", "Bol Şanslar" vb. butonlar, sesli olsun.
  ///
  /// ## Neden yankıyı BEKLEMEZ
  ///
  /// Realtime broadcast varsayılan olarak göndereni yankılamaz (`self`
  /// kapalı) — beklenseydi kendi mesajımı duymak için bir ağ turu (ve olası
  /// bir gecikme/kayıp) gerekirdi. Bunun yerine ekranımda ANINDA
  /// duyurulur/gösterilir ([_announce] aynı anda hem anons bandını hem
  /// TTS'i tetikler), sonra masadaki DİĞERLERİNE yayınlanır.
  void sendQuickPhrase(String phrase) {
    final trimmed = phrase.trim();
    if (trimmed.isEmpty || _disposed) return;
    _announce(trimmed);
    final seat = mySeatNo;
    if (seat != null) {
      unawaited(_realtime.sendQuickPhrase(seatNo: seat, text: trimmed));
    }
  }

  /// Masadaki BAŞKA bir oyuncunun gönderdiği hızlı mesajı işler.
  ///
  /// Kendi koltuğumdan gelen bir yankı asla beklenmez (bkz.
  /// [sendQuickPhrase] dokümanı) ama gelirse de burada elenir — çift anons
  /// olmasın diye.
  void _handleIncomingQuickPhrase(Map<String, dynamic> payload) {
    final seat = (payload['seat'] as num?)?.toInt();
    final text = payload['text'] as String?;
    if (seat == null || text == null || text.trim().isEmpty) return;
    if (seat == mySeatNo) return;
    _announce('${_spokenSeatName(seat)}: ${text.trim()}');
  }

  void _announce(String text) {
    // Kuyruk taşmasın: masada bir anda yığılan olaylar (ör. yeniden bağlanma)
    // dakikalarca sürecek bir anons treni yaratmamalı.
    if (_announceQueue.length >= 3) return;
    _announceQueue.add(text);
    if (_announceTimer == null) _emitNextAnnouncement();
  }

  void _emitNextAnnouncement() {
    _announceTimer = null;
    if (_disposed || _announceQueue.isEmpty) return;
    final text = _announceQueue.removeAt(0);
    _announcementSeq++;
    announcement.value = OkeyAnnouncement(id: _announcementSeq, text: text);
    unawaited(_sound.speak(text));
    // Bir sonraki anons için pencere HER ZAMAN açılır: hemen ardından gelen
    // bir anons öncekini kesmesin, sıraya girsin.
    _announceTimer = Timer(
      const Duration(milliseconds: 1800),
      _emitNextAnnouncement,
    );
  }

  /// Bu taş masadaki açık perlerden birine işlenebilir mi?
  bool _isProcessableTile(OkeyTile tile) {
    final match = _match;
    if (match == null) return false;
    for (final meld in _tableMelds) {
      if (meld.meldType == 'pair' || meld.meldType == 'gosterge') continue;
      if (OkeyMeldValidator.extendMeld(meld.tiles, tile, match.okeyTile) !=
          null) {
        return true;
      }
    }
    return false;
  }

  void _onTick() {
    if (_match?.status != 'in_progress') return;
    // Süre uyarısı: sıra bendeyken son 5 saniyede bir kez
    if (isMyTurn && secondsLeft <= 5 && secondsLeft > 0) {
      if (!_timeWarningPlayed) {
        _timeWarningPlayed = true;
        _sound.play(OkeySound.timeWarning);
      }
    } else {
      _timeWarningPlayed = false;
    }
    // Yalnızca sayaç rozetini besler — notifyListeners() ÇAĞIRMAZ (bkz.
    // secondsLeftNotifier üzerindeki açıklama).
    secondsLeftNotifier.value = secondsLeft;

    // Süre dolduysa sunucudan otomatik oynatma iste
    _maybeAutoAdvance();
  }

  /// Sıra süresi dolduğunda sunucuya "otomatik oyna" der: o koltuk adına
  /// desteden taş çekilir ve ÇEKİLEN TAŞ doğrudan atılır.
  ///
  /// Neden istemci tetikliyor: veritabanında zamanlanmış iş (pg_cron) yok.
  /// Bu güvenli, çünkü SÜREYİ SUNUCU DOĞRULUYOR — istemci "süre doldu" diye
  /// yalan söylerse sunucu hiçbir şey yapmaz.
  ///
  /// Masadaki DÖRT istemci de aynı anda tetikler; sunucu maç satırını
  /// kilitlediği için sıra yine tek adım ilerler.
  void _maybeAutoAdvance() {
    final match = _match;
    if (match == null || match.status != 'in_progress') return;
    final deadline = match.turnDeadline;
    if (deadline == null) return;
    if (DateTime.now().isBefore(deadline)) return;

    // Her sıra için tek deneme: aksi halde saniyede bir istek gönderilirdi.
    final key =
        '${match.id}#${match.handNo}#${match.turnSeat}'
        '#${deadline.toIso8601String()}';
    if (_autoAdvancing || _autoAdvanceKey == key) return;
    _autoAdvanceKey = key;
    _autoAdvancing = true;

    unawaited(() async {
      try {
        final played = await _service.autoAdvance(matchId);
        if (played && !_disposed) await refresh(silent: true);
      } catch (_) {
        // Ağ hatası vb.: anahtarı sıfırla ki bir sonraki saniyede tekrar
        // denensin — yoksa bu sıra sonsuza kadar kilitli kalırdı.
        _autoAdvanceKey = null;
      } finally {
        _autoAdvancing = false;
      }
    }());
  }

  void _maybeScheduleBotTurn() {
    _botTimer?.cancel();
    _absentTimer?.cancel();
    // İZLEYİCİ OYUNU İLERLETMEZ. Masada oturmayan bir istemcinin bot
    // sırasını ya da "süresi doldu, otomatik oyna" çağrısını tetiklemesi,
    // izleyici sayısı kadar aynı hamlenin gönderilmesi demek olurdu.
    if (isSpectating) return;
    final match = _match;
    if (match == null || match.status != 'in_progress') return;
    final turnSeat = match.turnSeat;
    OkeyRoomSeat? seat;
    for (final s in _seats) {
      if (s.seatNo == turnSeat) {
        seat = s;
        break;
      }
    }

    // Sıra BENDE değilse ve o koltuk (henüz) bot/AI-devir değilse, oyuncunun
    // bağlantısı kopmuş olabilir. Bir süre bekleyip sunucudan otomatik
    // oynatma iste — sunucu gerçekten yok olup olmadığını kendisi doğrular
    // ve yeterince uzun süre (90 sn) kayıpsa koltuğu KALICI olarak AI'ya
    // devreder (bkz. okey_auto_play_absent, migration 20260913120001) —
    // ondan sonraki turlar aşağıdaki bot dalından akar.
    if (seat != null && !seat.isBotDriven && turnSeat != mySeatNo) {
      _absentTimer = Timer(const Duration(seconds: 12), () async {
        try {
          final played = await _service.autoPlayAbsent(matchId);
          if (played) await refresh(silent: true);
        } catch (_) {
          // sessizce yut — başka bir istemci zaten tetiklemiş olabilir
        }
      });
    }

    if (seat == null || !seat.isBotDriven) return;

    // BOT DÜŞÜNME SÜRESİ.
    //
    // Bot 900 ms'de oynayınca üç rakip birden anında hamle yapıyor ve masa
    // "kendi kendine akıyor" gibi görünüyordu. Gerçek bir oyuncu gibi
    // düşünsün diye gecikme uzatıldı ve HER TURDA DEĞİŞİYOR — sabit gecikme
    // makine gibi hissettiriyor. 1.2–2.8 sn de HÂLÂ "hiç düşünmüyor" gibi
    // hissettirdiği için (bot AÇ->İŞLE->AT'ı tek RPC'de anında bitiriyor,
    // yani gecikmeden SONRA her şey bir anda oluyor) aralık uzatıldı.
    final thinkMs = 2000 + _random.nextInt(2200); // 2.0 – 4.2 sn

    // YARIŞ DURUMU KORUMASI: bu zamanlayıcı kurulurken hangi maç/el/koltuk
    // için kurulduğu YAKALANIR. Süre dolduğunda RPC'yi çağırmadan önce hâlâ
    // aynı sıra mı diye kontrol edilir. Bunsuz: bir realtime olayı kaçırılırsa
    // (ör. ağ titremesi), BAŞKA bir istemcinin bu ESKİ zamanlayıcısı iptal
    // edilmeden ateşlenip artık sırası gelmiş FARKLI bir bot için "anlık"
    // (gecikmesiz görünen) bir hamle tetikleyebiliyordu — RPC hangi koltuğun
    // sırası olduğunu kendi bulup oynatıyor, hangi koltuk için çağrıldığını
    // sormuyor.
    final expectedMatchId = match.id;
    final expectedHandNo = match.handNo;
    final expectedSeat = turnSeat;
    // SUNUCU TARAFI KORUMA: yukarıdaki stillSameTurn kontrolü TEK BAŞINA
    // yetmez — iki istemcinin bayat zamanlayıcısı aynı anda kontrolü geçip
    // RPC'ye varabilir. Token, sunucunun da "bu sıra artık geçti" diyebilmesini
    // sağlar (bkz. okey_bot_take_turn.p_expected_turn_token).
    final expectedToken = match.turnToken;
    _botTimer = Timer(Duration(milliseconds: thinkMs), () async {
      final stillSameTurn =
          _match?.id == expectedMatchId &&
          _match?.handNo == expectedHandNo &&
          _match?.turnSeat == expectedSeat;
      if (!stillSameTurn) return; // bayat zamanlayıcı: sessizce iptal
      try {
        await _service.botTakeTurn(matchId, turnToken: expectedToken);
        await refresh(silent: true);
      } catch (_) {
        // sessizce yut — başka bir client zaten tetiklemiş olabilir
      }
    });
  }

  /// "Masadan ayrıl" — sunucuya bilinçli çıkışı haber verir: koltuk kalıcı
  /// AI'ya devredilir ve sırası oysa turu hemen oynatılır (bkz.
  /// okey_leave_match_seat, migration 20260915000001). Ekranın kendisi zaten
  /// gezinip kapanacağı için burada UI beklemez — en iyi çaba, sessiz yutar:
  /// bu çağrı hiç ulaşmasa bile sunucu 90 sn'lik bağlantı-kopması yoluyla
  /// aynı sonuca varır, bu yalnızca o beklemeyi diğer oyuncular için ortadan
  /// kaldırır.
  void leaveTable() {
    unawaited(_service.leaveMatchSeat(matchId).catchError((_) {}));
  }

  // ---------------------------------------------------------------------
  // Raf: seçim, sıralama, görünüm modu
  // ---------------------------------------------------------------------

  /// [slotIndex] ıstakadaki slot indeksidir. Boş slot seçilemez.
  void toggleTileSelection(int slotIndex) {
    if (slotIndex < 0 || slotIndex >= _rackSlots.length) return;
    if (_rackSlots[slotIndex] == null) return;
    // ISTAKADA TAŞ SESİ — taşa dokunmak fiziksel bir eylemdir; sessiz
    // kalması ıstakayı "ekrandaki resim" gibi hissettiriyordu.
    unawaited(_sound.play(OkeySound.rackTile));
    if (_selectedIndices.contains(slotIndex)) {
      _selectedIndices.remove(slotIndex);
    } else {
      _selectedIndices.add(slotIndex);
    }
    _notify();
  }

  void clearSelection() {
    _selectedIndices.clear();
    _notify();
  }

  /// SERİ DİZ / ÇİFT DİZ — taşları gruplayıp ARALARINA BOŞLUK bırakarak
  /// yeniden dizer (ör. `1 2 3 4 _ 11 11 11`).
  void setSortMode(OkeyRackSortMode mode) {
    final match = _match;
    if (match == null || mode == OkeyRackSortMode.none) return;
    // Bütün ıstaka yeniden diziliyor: tek bir taş sesi yeter — her taş
    // için çalmak onlarca sesin üst üste binmesi demek olurdu.
    unawaited(_sound.play(OkeySound.rackTile));
    _sortMode = mode;
    _setRackSlots(
      OkeyRackLayout.buildSorted(
        _expectedRackTiles,
        match.okeyTile,
        byPairs: mode == OkeyRackSortMode.pairs,
        // GÖSTERGE ÇİFTİ (RULES.md §8) ancak gösterge taşı bilinirse KENDİ
        // öbeğine ayrılabilir; ayrılmazsa eşsizler yığınında kalır ve çift
        // olarak hiç sayılmaz.
        indicatorTile: match.indicatorTile,
      ),
    );
    _selectedIndices.clear();
    _error = null;
    _notify();
  }

  /// Bir taşı başka bir slota taşır (sürükle-bırak). Hedef doluysa taşlar
  /// yer değiştirir; boşsa taş oraya kayar. Tamamen yerel bir işlemdir,
  /// sunucuya gitmez.
  void moveTileToSlot(int fromSlot, int toSlot) {
    if (fromSlot == toSlot) return;
    unawaited(_sound.play(OkeySound.rackTile));
    _setRackSlots(OkeyRackLayout.moveTile(_rackSlots, fromSlot, toSlot));
    // Seçim slot indeksine bağlı olduğundan taşınan taşın seçimini taşı
    if (_selectedIndices.contains(fromSlot)) {
      _selectedIndices.remove(fromSlot);
      _selectedIndices.add(toSlot);
    } else if (_selectedIndices.contains(toSlot)) {
      _selectedIndices.remove(toSlot);
      _selectedIndices.add(fromSlot);
    }
    _sortMode = OkeyRackSortMode.none; // elle dizildi
    _notify();
  }

  void toggleCompactRack() {
    _isCompactRack = !_isCompactRack;
    _notify();
  }

  // ---------------------------------------------------------------------
  // Grup oluşturma (masaya açmadan önce hazırlama)
  // ---------------------------------------------------------------------

  /// Seçili taşları bir grup olarak hazırlar. 2 taş seçilirse ÇİFT,
  /// 3+ taş seçilirse seri/grup olarak doğrulanır (RULES.md §2).
  void stageSelectedAsGroup() {
    final match = _match;
    if (match == null) return;
    final tiles = selectedTiles;
    final isPair = tiles.length == 2;
    final valid = isPair
        ? OkeyMeldValidator.isValidPair(tiles, match.okeyTile)
        : OkeyMeldValidator.isValidMeld(tiles, match.okeyTile);
    if (!valid) {
      _error = isPair
          ? 'Seçilen 2 taş geçerli bir çift değil (aynı renk + aynı rakam).'
          : 'Seçilen taşlar geçerli bir per/grup oluşturmuyor.';
      _notify();
      return;
    }
    _stagedGroups.add(tiles);
    _selectedIndices.clear();
    _error = null;
    _notify();
  }

  void unstageGroup(int groupIndex) {
    _stagedGroups.removeAt(groupIndex);
    _notify();
  }

  /// GERİ TOPLA — hazırlanan (henüz masaya konmamış) tüm grupları rafa geri al.
  void takeBackStaged() {
    if (_stagedGroups.isEmpty && _selectedIndices.isEmpty) return;
    _stagedGroups.clear();
    _selectedIndices.clear();
    _error = null;
    _notify();
  }

  /// TAŞLARI İŞLE — seçili taşları masadaki uygun açık perlere otomatik ekler
  /// (RULES.md §4 işleme). Hiçbiri işlenemezse bilgi verir.
  Future<void> processSelectedTiles() => _runAction(() async {
    final match = _match;
    if (match == null) throw 'Maç bulunamadı.';
    if (!_isOpeningDone) throw 'Taş işlemek için önce elini açmalısın.';

    // SEÇİM ZORUNLU DEĞİL.
    //
    // Önce taşları tek tek seçmek gerekiyordu. Hiçbir taş seçili değilse
    // artık İŞLENEBİLEN TÜM TAŞLAR otomatik işlenir — oyuncunun "işlek"
    // taşları tek tek bulup dokunması gerekmiyor.
    final tiles = _selectedIndices.isEmpty ? processableTiles : selectedTiles;

    if (tiles.isEmpty) {
      throw 'İşlenebilecek taş yok.';
    }

    // ---- 1) PLANLA — ağa hiç çıkmadan, hangi taş hangi pere? -------------
    final plan = <int, List<OkeyTile>>{};
    var planned = 0;

    for (final tile in tiles) {
      // RULES.md §6 — SON TAŞ İŞLENMEZ: bitiş yalnızca atma ile olur, elde
      // atılacak bir taş kalmalıdır. Sunucu da reddeder
      // (APP:must_keep_discard_tile); burada durmak, toplu işlemenin son taşa
      // gelince gereksiz bir hatayla kesilmesini önler.
      if (_myHand.length - planned <= 1) break;

      for (final meld in _tableMelds) {
        // Taş bu pere işlenebilir mi? İKİ UÇ da denenir.
        //
        // Eskiden burada yalnızca `[...meld.tiles, tile]` (sona ekleme)
        // deneniyordu; oysa bir seri alt ucundan da uzatılır (masada 5-6-7
        // varken 4). Sonuç, tam da kullanıcının bildirdiği tutarsızlıktı:
        // taş "işlek" sayılıp ATILINCA +101 ceza yazılıyor, ama İŞLE düğmesi
        // aynı taşı "hiçbir pere işlenemiyor" diye geri çeviriyordu. Sunucu
        // ve masa ipuçları 2026-09-02'den beri iki ucu da kabul ediyor
        // (bkz. okey_internal_extend_meld / OkeyMeldValidator.extendMeld);
        // toplu işleme bu düzeltmenin dışında kalmıştı.
        final ok = (meld.meldType == 'pair' || meld.meldType == 'gosterge')
            ? false // çiftlere işleme yapılmaz
            : OkeyMeldValidator.extendMeld(meld.tiles, tile, match.okeyTile) !=
                  null;
        if (!ok) continue;
        (plan[meld.id] ??= <OkeyTile>[]).add(tile);
        planned++;
        break;
      }
    }

    _selectedIndices.clear();
    if (plan.isEmpty) {
      throw 'Seçilen taşlar masadaki hiçbir pere işlenemiyor.';
    }

    // ---- 2) GÖNDER — FARKLI perler PARALEL (performans, 2026-09-07) ------
    //
    // Eskiden her taş için ayrı ayrı BEKLENİYORDU: dört işlek taş, dört tam
    // ağ turu demekti ve o süre boyunca hamle kuyruğu kapalı olduğu için
    // masa donuk duruyordu.
    //
    // ## Paralel göndermek neden GÜVENLİ
    //
    // `okey_add_to_meld` işe MAÇ SATIRINI `FOR UPDATE` ile kilitleyerek
    // başlıyor (bkz. 20260905000001 göçü). Yani aynı maça gelen çağrıları
    // sunucu ZATEN teker teker işliyor; ikincisi birincinin commit'ini
    // bekleyip GÜNCEL durumu okuyor. Kazanılan şey ağ turlarının üst üste
    // binmesi, sunucudaki sıra değil.
    //
    // ## Aynı per İÇİNDE neden hâlâ sıralı
    //
    // Bir seriyi iki taşla uzatmak SIRA İSTER: masadaki 5-6-7'ye önce 4,
    // sonra 3 gider. Paralel gönderilseydi 3 önce varabilir ve sunucu haklı
    // olarak `invalid_meld_after_add` derdi.
    final done = <OkeyTile>[];
    Object? firstError;

    await Future.wait([
      for (final entry in plan.entries)
        () async {
          for (final tile in entry.value) {
            try {
              await _service.addToMeld(matchId, entry.key, tile);
              done.add(tile);
            } catch (e) {
              // Aynı perdeki SONRAKİ taşlar anlamsız: o per beklenen hâline
              // gelmedi. Öteki perler kendi zincirlerini sürdürür.
              firstError ??= e;
              break;
            }
          }
        }(),
    ]);

    if (done.isEmpty) {
      throw firstError ?? 'Seçilen taşlar masadaki hiçbir pere işlenemiyor.';
    }
    if (firstError != null) {
      // KISMİ BAŞARI hata değildir: taşların bir kısmı masaya indi, gerisi
      // inmedi (çoğunlukla aynı peri iki taşla uzatma sırası yüzünden).
      // Eskiden bu bir istisna olarak yüzeye çıkıyor ve BAŞARILI kısım da
      // olmamış gibi görünüyordu.
      explain('Taşların bir kısmı işlendi; kalanı için tekrar dene.');
    }
    await _finishTurnAfterProcessing(done);
  });

  /// İŞLEME BİTTİ, ELDE TEK TAŞ KALDIYSA TURU KAPAT (kullanıcı isteği,
  /// 2026-09-07: "işlekler yapınca taş atılsın").
  ///
  /// ## Neden gerekiyordu
  ///
  /// İşleme, elde ATILACAK bir taş bırakmak zorunda (RULES.md §6): toplu
  /// işleme son taşa gelince duruyor. O noktada oyuncunun yapabileceği TEK
  /// hamle o taşı atmaktır ve attığı anda eli biter, yani kazanır. Ama
  /// [processSelectedTiles] seçimi temizlediği için "AT — BİTİR" düğmesi
  /// sönük kalıyordu: oyuncu İŞLE'ye basıyor, her şey masaya iniyor ve oyun
  /// duruyordu. Eli bitirmek için taşa ayrıca dokunup düğmeye basması
  /// gerektiğini anlaması gerekiyordu.
  ///
  /// ## Neden HER durumda atmıyoruz
  ///
  /// Sunucu, atılan taş masadaki bir pere İŞLENEBİLİYORSA ya da OKEY'se ceza
  /// yazar (RULES.md §7/§8) ve bu ceza kazananın skoruna da eklenir
  /// (okey_internal_finalize_hand: `-101 + penalty`). Yani "senin adına
  /// attım" demek, oyuncuya sormadan 101 puana mal olabilirdi. O tek durumda
  /// karar oyuncunun kalır; ne olduğu ve bedeli açıkça yazılır.
  Future<void> _finishTurnAfterProcessing(List<OkeyTile> processed) async {
    if (processed.isEmpty || !_isOpeningDone || !canActOnHand) return;

    // Elde ne kaldı? İşlenen taşlar elden BİRER KOPYA düşülür — aynı taştan
    // iki tane olabilir, hepsini birden silmek eli olduğundan boş gösterirdi.
    final remaining = List<OkeyTile>.from(_myHand);
    for (final t in processed) {
      remaining.remove(t);
    }
    if (remaining.length != 1) return;

    final last = remaining.first;
    final okey = _match?.okeyTile;
    if (_isTileProcessableOntoTable(last) ||
        (okey != null && last.isJokerFor(okey))) {
      explain(
        'Elinde tek taş kaldı ama o taş ceza yazdırır (işlek taş / okey). '
        'Yine de bitirmek için taşa dokunup AT\'a bas.',
      );
      return;
    }

    _match = await _service.discard(matchId, last);
    _stagedGroups.clear();
    _selectedIndices.clear();
  }

  /// İŞLEME ya da OKEY ÇALMA — hangisi mümkünse.
  ///
  /// Masadaki bir pere taş bırakmak/dokunmak TEK bir jesttir; oyuncunun
  /// "işliyor muyum yoksa okey mi çalıyorum" diye ayrı bir mod seçmesi
  /// gerekmez. Uzatma mümkünse o tercih edilir (eli bir taş azaltır);
  /// değilse ve taş perdeki okeyin yerine geçiyorsa okey çalınır
  /// (RULES.md §4).
  Future<void> _addOrStealOnMeld(int meldId, OkeyTile tile) async {
    if (stealTargetMeldId(tile) == meldId) {
      await _service.stealJoker(matchId, meldId, tile);
      return;
    }
    await _service.addToMeld(matchId, meldId, tile);
  }

  // ---------------------------------------------------------------------
  // Sunucu aksiyonları
  // ---------------------------------------------------------------------

  /// Aynı anda YALNIZCA BİR hamle gider.
  ///
  /// NEDEN: Bu koruma yokken iki hamle üst üste binebiliyordu — örneğin
  /// desteden sürükleyip bırakma ile dokunmanın ikisi birden tetiklenmesi,
  /// ya da kullanıcının cevabı beklemeden tekrar denemesi. İkinci istek
  /// sunucuya vardığında sıra aşaması çoktan değişmiş oluyor ve sunucu
  /// haklı olarak `APP:wrong_phase` ile reddediyordu. Kullanıcı bunu ham bir
  /// `PostgrestException(...)` metni olarak görüyordu.
  final OkeyActionQueue _actions = OkeyActionQueue();

  Future<void> _runAction(Future<void> Function() action) {
    return _actions
        .add(() async {
          _error = null;
          try {
            await action();
            // HEMEN bildir: sunucu çağrısı güncel maçı zaten döndürdü, arayüz
            // tazelemeyi BEKLEMEDEN yeni aşamaya geçmeli. Aksi halde taş
            // çekildikten sonra kısa bir süre ıskarta kutusu bırakma hedefi
            // olmuyor ve atma yapılamıyordu.
            _notify();
          } catch (e) {
            await _handleActionError(e);
          }
        })
        .whenComplete(() {
          // TAZELEME KİLİDİN DIŞINDA.
          //
          // Önce refresh de kilidin içindeydi ve birkaç ağ turu sürdüğü için,
          // taş çektikten sonra uzunca bir süre atma yapılamıyordu. Sunucu
          // çağrıları zaten güncel maçı geri döndürüyor (bkz. drawFromDeck /
          // discard), yani sıradaki hamlenin aşama kontrolü için tazelemeyi
          // beklemesi GEREKMİYOR.
          //
          // DEBOUNCE'A GİRER, DOĞRUDAN ÇAĞRILMAZ (performans, 2026-09-08).
          // Kendi hamlem sunucuda dört realtime olayı doğuruyor (maç, el,
          // perler, hamleler) ve onların hepsi zaten _scheduleRefresh'e
          // düşüyor. Burada ayrıca DOĞRUDAN tazelemek, tek bir taş atmayı
          // iki tam tazelemeye (2 × 5 sorgu) çıkarıyordu: birincisi buradan,
          // ikincisi olaylardan. İkisi aynı 120 ms penceresinde birleşince
          // hamle başına okunan yarıya iner — ve masa zaten hamleyi İYİMSER
          // olarak göstermiş durumda, yani beklenen bir şey yok.
          _scheduleRefresh();
        });
  }

  /// Sunucu hatalarını kullanıcının anlayacağı hale çevirir.
  ///
  /// "Durum eskimiş" sınıfındaki hatalar (aşama/sıra kaymış) KULLANICI HATASI
  /// DEĞİLDİR: ekran o an sunucunun gerisinde kalmıştır. Bunlarda uyarı
  /// göstermek yerine sessizce tazeleriz — kullanıcı zaten doğru olanı
  /// yapmaya çalışıyordu.
  Future<void> _handleActionError(Object e) async {
    final raw = '$e';

    const staleMarkers = [
      'APP:wrong_phase',
      'APP:not_your_turn',
      'APP:stale_turn',
    ];
    if (staleMarkers.any(raw.contains)) {
      await refresh(silent: true);
      return;
    }

    _error = _friendlyError(raw);
    _sound.play(OkeySound.error);
    _notify();
  }

  /// `APP:` kodlarını Türkçe, eyleme dönük mesajlara çevirir.
  String _friendlyError(String raw) {
    if (raw.contains('APP:tile_not_in_hand')) {
      return 'O taş elinde değil.';
    }
    if (raw.contains('APP:discard_pile_empty')) {
      return 'Alınacak taş yok — ıskarta boş.';
    }
    if (raw.contains('APP:discard_tile_not_usable')) {
      // ARTIK SUNUCUDAN GELMEZ (2026-09-05): yandan çekme kapısı kaldırıldı,
      // yerini tur sonu cezası aldı (bkz. 20260905000001 migration'ı ve
      // RULES.md §4). Çeviri, ŞEMASI HENÜZ GÜNCELLENMEMİŞ bir sunucuya
      // bağlanan eski bir istemci ham `APP:` kodunu ekrana basmasın diye
      // duruyor.
      return 'Bu taşı şu an kullanamazsın — elinde işine yaramıyor. '
          'İstersen desteden çek.';
    }
    if (raw.contains('APP:points_below_threshold')) {
      return 'Açmak için yeterli puanın yok.';
    }
    if (raw.contains('APP:pairs_below_threshold')) {
      return 'Açmak için yeterli çiftin yok.';
    }
    if (raw.contains('APP:invalid_meld')) {
      return 'Geçersiz per — taşları kontrol et.';
    }
    if (raw.contains('APP:invalid_pair')) {
      return 'Geçersiz çift.';
    }
    if (raw.contains('APP:opening_type_mismatch')) {
      return 'Çiftle açtın; seriyle devam edemezsin.';
    }
    if (raw.contains('APP:no_pairs_on_table')) {
      return 'Seri ile açtın: çift indirebilmen için masada çift açmış bir '
          'oyuncu olmalı.';
    }
    if (raw.contains('APP:series_pairs_limit')) {
      return 'Seri ile açan oyuncu bir turda en çok $seriesPairsLimit çift '
          'indirebilir.';
    }
    if (raw.contains('APP:must_keep_discard_tile')) {
      return _keepOneTileHint;
    }
    if (raw.contains('APP:pairs_declaration_required')) {
      return 'Çiftle açmak için önce "Çifte gidiyorum" demelisin.';
    }
    if (raw.contains('APP:pairs_declaration_locked')) {
      return 'Çifte gitme kararı bu el için geri alınamaz.';
    }
    if (raw.contains('APP:no_stealable_joker')) {
      return 'Bu perde senin taşının yerine geçeceği bir okey yok.';
    }
    if (raw.contains('APP:opening_required')) {
      return 'Önce elini açmalısın.';
    }
    if (raw.contains('APP:side_draw_undone')) {
      return 'Bu taşı geri koydun; aynı turda yeniden alamazsın — desteden çek.';
    }
    if (raw.contains('APP:gosterge_pair_not_processable')) {
      return 'Gösterge çiftine işleme yapılamaz — tek taştır, tamamlanamaz.';
    }
    if (raw.contains('APP:pair_not_processable')) {
      return 'Çiftlere işleme yapılamaz; yalnızca seri ve gruplara yapılır.';
    }
    if (raw.contains('APP:match_finished')) {
      return 'El bitti.';
    }
    if (raw.contains('APP:not_seated')) {
      return 'Bu masada oturmuyorsun.';
    }
    if (raw.contains('APP:okey_banned')) {
      return 'Okey oynaman kısıtlanmış.';
    }
    // Tanımadığımız bir hata: ham metni göstermek yerine kısalt
    final m = RegExp(r'APP:([a-z_]+)').firstMatch(raw);
    if (m != null) return 'İşlem yapılamadı (${m.group(1)}).';
    return 'İşlem yapılamadı, tekrar dene.';
  }

  // Çekme/atma öncesi yerel aşama kontrolü: sunucuya boşuna gidip
  // `wrong_phase` yememek için. Sunucu yine de son sözü söyler.
  /// [toSlot] verilirse çekilen taş ıstakada O SLOTA yerleşir.
  /// (Oyuncu taşı nereye bıraktıysa oraya gelmeli — önce "ilk boş slota"
  ///  konuyordu ve taş rastgele bir yere gidiyor gibi görünüyordu.)
  Future<void> drawFromDeck({int? toSlot}) => _runAction(() async {
    if (!canDraw) return;
    _pendingDrawSlot = toSlot;
    final rev = _handRevision;
    _applyDraw(await _service.drawFromDeck(matchId), rev);
  });

  /// YANDAN ÇEKME — TAŞ ZATEN GÖRÜNÜYOR, BEKLEMEYE GEREK YOK.
  ///
  /// Soldakinin ıskartasının en üstündeki taş masada AÇIK duruyor: hangi taşı
  /// alacağımı sunucuya sormama gerek yok, elimdeki maç satırında yazıyor.
  /// Bu yüzden taş ıstakaya HEMEN konur; RPC arkada tamamlanır ve maç
  /// satırını (dolayısıyla ıskartayı ve aşamayı) sunucunun gerçeğiyle ezer.
  Future<void> drawFromDiscard({int? toSlot}) => _runAction(() async {
    // GERİ KOYDUĞUM TAŞI TEKRAR ALAMAM (RULES.md §4). Sunucu da reddeder
    // (APP:side_draw_undone); burada susarak durmak, oyuncuya anlamsız bir
    // hata bandı göstermekten iyidir — düğme/hedef zaten sönük.
    if (!canDrawFromSide) return;
    _pendingDrawSlot = toSlot;
    final rev = _handRevision;
    final rollback = _applyLocalSideDraw();
    if (rollback != null) {
      unawaited(_sound.play(OkeySound.drawTile));
      _notify();
    }
    try {
      _applyDraw(
        await _service.drawFromDiscard(matchId),
        rev,
        playSound: rollback == null,
      );
    } catch (_) {
      rollback?.call();
      rethrow;
    }
  });

  /// Yandan çekmeyi YEREL olarak uygular; geri alma işlevini döndürür.
  /// Kaynak ıskarta boşsa (ya da koltuk/maç bilinmiyorsa) null döner ve
  /// çekme eskisi gibi sunucunun cevabıyla görünür.
  ///
  /// [_handRevision] BİLEREK artırılır: [_applyDraw] böylece "el bu arada
  /// değişmiş" deyip taşı BİR KEZ DAHA eklemez.
  VoidCallback? _applyLocalSideDraw() {
    final match = _match;
    final seat = mySeatNo;
    if (match == null || seat == null) return null;
    final sourceSeat = (seat + 3) % 4;
    final pile = match.discardPiles[sourceSeat] ?? const <OkeyTile>[];
    if (pile.isEmpty) return null;
    final tile = pile.last;

    final prevHand = _myHand;
    final prevSlots = _rackSlots;
    final prevPendingSlot = _pendingDrawSlot;

    _myHand = [..._myHand, tile];
    _handRevision++;
    _localHandOps++;
    final piles = <int, List<OkeyTile>>{...match.discardPiles};
    piles[sourceSeat] = pile.sublist(0, pile.length - 1);
    _match = match.copyWith(discardPiles: piles, turnPhase: 'discard');
    _syncRackSlots();

    return () {
      _myHand = prevHand;
      _handRevision++;
      _localHandOps++;
      _setRackSlots(prevSlots);
      _match = match;
      _pendingDrawSlot = prevPendingSlot;
      _notify();
    };
  }

  /// Çekme sonucunu yerel duruma yazar.
  ///
  /// SUNUCU ÇEKİLEN TAŞI DA DÖNDÜRÜYORSA (v2, bkz. OkeyGameService._turnAction)
  /// taş ıstakaya HEMEN konur: eli yeniden okumak için ağ turunun dönmesini
  /// beklemek, oyuncunun çektiği taşın gözle görülür bir gecikmeyle
  /// belirmesi demekti. Ardından gelen `refresh` zaten aynı eli sunucudan
  /// getirir ve yerel tahmini onaylar (ya da düzeltir) — yani bu yalnızca
  /// GÖRÜNTÜYÜ öne alır, doğruluk sunucuda kalır.
  ///
  /// Sunucu eski sürümdeyse [OkeyGameService] `drawn: null` döndürür ve
  /// davranış eskisi gibi olur: taş, tazeleme dönünce görünür.
  ///
  /// [handRevisionBefore] çağrı ÖNCESİNDEKİ el sürümüdür. Çağrı sürerken el
  /// sunucudan yeniden okunduysa (realtime `onHandChanged` tazelemesi tam o
  /// sırada düşebilir) taş EKLENMEZ: o okuma taşı ya zaten içeriyordur, ya
  /// da bir sonraki tazeleme getirir. Buradaki kontrol sürüm üzerindendir,
  /// "bu taş elimde var mı" üzerinden DEĞİL — okeyde her taştan iki tane
  /// vardır ve elde zaten olan bir taşı çekmek olağandır; taşın varlığına
  /// bakan bir kontrol o durumda ikinci kopyayı sessizce yutardı.
  void _applyDraw(
    ({OkeyMatch match, OkeyTile? drawn}) result,
    int handRevisionBefore, {
    bool playSound = true,
  }) {
    _match = result.match;
    // SES, TAŞ GÖRÜNÜR OLURKEN (bkz. _playMoveSound: kendi çekmem orada
    // atlanır). Yandan çekmede ses ZATEN çalındı — taş oraya sunucu cevabı
    // beklenmeden konmuştu.
    if (playSound) unawaited(_sound.play(OkeySound.drawTile));
    // El bu arada başka bir yoldan güncellendiyse (yerel iyimser yazma ya da
    // araya giren bir sunucu okuması) dokunma: taş ya zaten geldi, ya da
    // hamleden SONRA başlayan tazeleme getirecek.
    if (_handRevision != handRevisionBefore) return;
    final drawn = result.drawn;
    if (drawn == null) {
      // ESKİ SUNUCU: çekilen taş cevapta yok. Tam tazelemeyi (5 sorgu +
      // 120 ms debounce) beklemek yerine YALNIZCA eli oku — taşın ekranda
      // belirmesi için gereken tek şey o.
      unawaited(_refreshHandOnly());
      return;
    }
    _myHand = [..._myHand, drawn];
    _localHandOps++;
    // Taşı oyuncunun bıraktığı slota yerleştirir ve _pendingDrawSlot'u
    // tüketir; sonraki tazeleme rafı olduğu gibi korur.
    _syncRackSlots();
  }

  /// YALNIZCA KENDİ ELİMİ yeniden okur (performans, 2026-09-08).
  ///
  /// Tam tazeleme beş sorgu ve bir debounce penceresi demek; oysa çektiğim
  /// taşın ıstakada belirmesi için gereken tek satır kendi elim. Masanın
  /// geri kalanı (perler, sayaçlar, ıskartalar) zaten sırada olan tazelemeyle
  /// gelir. Hata olursa sessizce geçilir: bu bir HIZLANDIRMA, doğruluk yolu
  /// değil.
  Future<void> _refreshHandOnly() async {
    final requestedMatchId = _matchId;
    final requestedHandOps = _localHandOps;
    try {
      final hand = await _service.getMyHand(requestedMatchId);
      if (_disposed || requestedMatchId != _matchId) return;
      if (_localHandOps != requestedHandOps) return;
      _myHand = hand.tiles;
      _handRevision++;
      _isOpeningDone = hand.isOpeningDone;
      _openedWithPairs = hand.openedWithPairs;
      _wentForPairs = hand.wentForPairs;
      _myPenaltyPoints = hand.penaltyPoints;
      _seriesPairsTurnToken = hand.seriesPairsTurnToken;
      _seriesPairsTurnCount = hand.seriesPairsTurnCount;
      _sideDrawUndoneToken = hand.sideDrawUndoneToken;
      _syncRackSlots();
      _notify();
    } catch (_) {
      // Kuyruktaki tam tazeleme zaten doğru durumu getirecek.
    }
  }

  /// Eli tamamen yere sermeye çalışan oyuncuya NE YAPACAĞINI söyleyen mesaj.
  ///
  /// Bu, kazanmaya bir adım kala yaşanır: oyuncunun rafındaki her taş geçerli
  /// bir perdedir ve "SERİ AÇ"a basar. Kural gereği bir taş atmak zorundadır
  /// (RULES.md §6), ama bunu hata koduyla söylemek anlamsız olurdu — nasıl
  /// düzelteceğini anlatmak gerekir.
  static const _keepOneTileHint =
      'Bitirmek için elinde atacak bir taş kalmalı. Bir taşı ıstakada '
      'boşlukla ayır, kalanları aç ve o taşı at.';

  /// RULES.md §3 — hazırlanan grupları seri/grup olarak masaya aç.
  Future<void> laySeries() => _runAction(() async {
    final groups = openingCandidateGroups;
    if (groups.isEmpty) {
      throw 'Istakada geçerli bir per/grup yok. Taşları yan yana diz.';
    }
    if (!_leavesDiscardTile(groups)) throw _keepOneTileHint;
    await _service.layMeld(matchId, groups, isPairs: false);
    _stagedGroups.clear();
    _selectedIndices.clear();
  });

  /// RULES.md §3 — ıstakadaki çiftleri masaya aç (en az 5 çift).
  ///
  /// Seri ile açmış oyuncu için liste [seriesPairsLimit] hakkına göre
  /// budanmış gelir (bkz. [pairGroupsToLay]).
  Future<void> layPairs() => _runAction(() async {
    final groups = pairGroupsToLay;
    if (groups.isEmpty) {
      throw 'Istakada geçerli bir çift yok. Aynı taşları yan yana diz.';
    }
    if (!_leavesDiscardTile(groups)) throw _keepOneTileHint;
    if (!_isOpeningDone && !_wentForPairs) {
      throw 'Çiftle açmak için önce "Çifte gidiyorum" demelisin.';
    }
    await _service.layMeld(matchId, groups, isPairs: true);
    _stagedGroups.clear();
    _selectedIndices.clear();
  });

  /// RULES.md §7 — "çifte gidiyorum" beyanı.
  ///
  /// TEK YÖNLÜDÜR: bir kez beyan edilince o el içinde geri alınamaz (sunucu
  /// `APP:pairs_declaration_locked` ile reddeder). Geri alınabilseydi 404
  /// cezası hiçbir zaman uygulanamaz, beyan da anlamsız kalırdı — nitekim
  /// eskiden tam olarak öyleydi.
  Future<void> declareGoingForPairs() => _runAction(() async {
    if (_wentForPairs) return;
    await _service.setWentForPairs(matchId, true);
    _wentForPairs = true;
  });

  /// Akış: rafta tam olarak 1 taş seç, sonra eklemek istediğin masa
  /// grubuna dokun.
  bool get canAddSelectedToMeld => canActOnHand && _selectedIndices.length == 1;

  /// Belirli bir slottaki taşı masadaki bir pere işler (sürükle-bırak).
  Future<void> addSlotTileToMeld(int meldId, int slotIndex) =>
      _runAction(() async {
        if (slotIndex < 0 || slotIndex >= _rackSlots.length) {
          throw 'Geçersiz taş.';
        }
        final tile = _rackSlots[slotIndex];
        if (tile == null) throw 'Boş slot işlenemez.';
        await _addOrStealOnMeld(meldId, tile);
        _selectedIndices.clear();
      });

  Future<void> addSelectedTileToMeld(int meldId) => _runAction(() async {
    if (_selectedIndices.length != 1) {
      throw 'Gruba eklemek için tam olarak 1 taş seç.';
    }
    final tile = selectedTiles.first;
    await _addOrStealOnMeld(meldId, tile);
    _selectedIndices.clear();
  });

  /// YANDAN ALDIĞIM TAŞI GERİ KOYABİLİR MİYİM?
  ///
  /// Soldakinin ıskartasından taş almak eskiden geri alınamazdı: fikir
  /// değiştiren oyuncunun tek çıkışı taşı geri ATMAKTI, o da "yandan aldığın
  /// taşı kullanmadın" cezası (+101) demekti. Yani bir yanlış dokunuşun
  /// bedeli elin tamamı olabiliyordu (kullanıcı isteği, 2026-09-05).
  bool get canUndoSideDraw => canActOnHand && _canUndoSideDraw;

  /// Yandan alınan taşı ıskartanın üstüne geri koyar; sıra 'çekme'
  /// aşamasına döner ve oyuncu desteden çekebilir.
  Future<void> undoSideDraw() => _runAction(() async {
    if (!canUndoSideDraw) return;
    _match = await _service.undoSideDraw(matchId);
    // Geri alınan taş artık elimde değil: seçim ve hazırlanan gruplar
    // ona dayanıyor olabilir.
    _selectedIndices.clear();
    _stagedGroups.clear();
    _canUndoSideDraw = false;
    // YAN ARTIK KAPALI — tazelemeyi beklemeden. Sunucu bu turda ikinci bir
    // yandan çekmeyi zaten reddediyor; ıskartanın sönmesi için bir ağ turu
    // beklemek, oyuncuya reddedilecek bir hedef göstermek demekti.
    _sideDrawUndoneToken = _match?.turnToken;
    await refresh(silent: true);
  });

  /// Akış: rafta tam olarak 1 taş seç, sonra kendi atma alanına dokun
  /// (veya doğrudan aşağıdaki "Taşı At" butonuna dokun).
  bool get canDiscardSelected => canActOnHand && _selectedIndices.length == 1;

  /// Belirli bir slottaki taşı atar (sürükle-bırak ile atma).
  Future<void> discardTileAtSlot(int slotIndex) => _runAction(() async {
    // Aşama uygun değilse SESSİZCE YUTMA — kullanıcı neden bir şey
    // olmadığını anlayamıyordu. Sırası ondaysa ne yapması gerektiğini
    // söyle; sırası değilse zaten arayüz atmaya izin vermez.
    if (!canActOnHand) {
      if (isMyTurn && _match?.turnPhase == 'draw') {
        _error = 'Önce taş çek.';
        _notify();
      }
      return;
    }
    if (slotIndex < 0 || slotIndex >= _rackSlots.length) {
      throw 'Geçersiz taş.';
    }
    final tile = _rackSlots[slotIndex];
    if (tile == null) throw 'Boş slot atılamaz.';
    await _discard(tile, fromSlot: slotIndex);
  });

  Future<void> discardSelectedTile() => _runAction(() async {
    if (_selectedIndices.length != 1) {
      throw 'Atmak için tam olarak 1 taş seç.';
    }
    await _discard(selectedTiles.first, fromSlot: _selectedIndices.first);
  });

  /// TAŞ ATMA — MASAYA ÖNCE, SUNUCUYA SONRA (performans, 2026-09-08).
  ///
  /// ## Neden iyimser
  ///
  /// Atma eskiden yalnızca `okey_take_turn_action` cevabıyla masaya
  /// yansıyordu; el satırı ise ancak ONDAN SONRAKİ tazelemeyle okunuyordu.
  /// Yani atılan taş, İKİ ağ turu boyunca hem ıstakada hem ıskartada duruyor,
  /// oyuncu "taş atılmadı" sanıp tekrar deniyordu. Oysa atmanın sonucu
  /// tamamen ÖNGÖRÜLEBİLİR: taş elimden çıkar, kendi ıskartamın üstüne gider,
  /// sıra sağımdakine geçer. Bunları beklemenin hiçbir bilgi değeri yok.
  ///
  /// Doğruluk sunucuda kalır: RPC'nin döndürdüğü maç satırı yerel tahmini
  /// EZER, ardından gelen tazeleme eli sunucudan okur. Hata olursa
  /// [_applyLocalDiscard]'ın döndürdüğü geri alma çalışır ve masa hamleden
  /// önceki haline döner.
  Future<void> _discard(OkeyTile tile, {required int fromSlot}) async {
    // HATA UYARISI: bu taş aslında masadaki bir pere işlenebilirdi ama
    // oyuncu onun yerine atmayı seçti — kısa bir kırmızı yanıp-sönmeyle
    // uyar (bkz. discardMistakeTick).
    if (_isTileProcessableOntoTable(tile)) discardMistakeTick.value++;
    final rollback = _applyLocalDiscard(tile, fromSlot);
    _stagedGroups.clear();
    _selectedIndices.clear();
    // SES DE ANINDA: dokunsal geri bildirim hamlenin kendisiyle aynı anda
    // gelmeli. Hamle sesleri normalde `okey_moves`'tan tetiklenir; KENDİ
    // atma/çekmem orada bilerek atlanır (bkz. _playMoveSound).
    unawaited(_sound.play(OkeySound.discardTile));
    _notify();
    try {
      _match = await _service.discard(matchId, tile);
    } catch (_) {
      rollback();
      rethrow;
    }
  }

  /// Atmayı YEREL olarak uygular; hamleden önceki hale döndüren işlevi verir.
  VoidCallback _applyLocalDiscard(OkeyTile tile, int fromSlot) {
    final prevHand = _myHand;
    final prevSlots = _rackSlots;
    final prevMatch = _match;

    final hand = List<OkeyTile>.from(_myHand)..remove(tile);
    _myHand = hand;
    _localHandOps++;
    // Oyuncunun ATTIĞI slot boşaltılır. Sadece ele bakan birleştirme, aynı
    // taştan iki kopya varken İLK kopyanın slotunu siler — oyuncu bambaşka
    // bir taşın kalktığını görürdü.
    if (fromSlot >= 0 &&
        fromSlot < prevSlots.length &&
        prevSlots[fromSlot] == tile) {
      final slots = List<OkeyTile?>.from(prevSlots);
      slots[fromSlot] = null;
      _setRackSlots(slots);
    }
    _syncRackSlots();

    final match = prevMatch;
    final seat = mySeatNo;
    if (match != null && seat != null) {
      final piles = <int, List<OkeyTile>>{...match.discardPiles};
      piles[seat] = [...(piles[seat] ?? const <OkeyTile>[]), tile];
      _match = match.copyWith(
        discardPiles: piles,
        turnSeat: (seat + 1) % 4,
        turnPhase: 'draw',
        turnDeadline: DateTime.now().add(
          Duration(seconds: _room?.turnSeconds ?? 20),
        ),
      );
      secondsLeftNotifier.value = secondsLeft;
    }

    return () {
      _myHand = prevHand;
      _localHandOps++;
      _setRackSlots(prevSlots);
      _match = prevMatch;
      secondsLeftNotifier.value = secondsLeft;
      _notify();
    };
  }
}
