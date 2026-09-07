import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../models/okey_models.dart';
import '../services/okey_room_service.dart';
import '../widgets/okey_profile_sheet.dart';
import '../theme/okey_theme.dart';
import '../theme/okey_ui.dart';

/// Maç bitince gösterilen SKOR TABLOSU.
///
/// NEDEN VAR: Maç bitince oyuncu `popUntil(isFirst)` ile doğrudan uygulamanın
/// en başına fırlatılıyordu — "oyundan atılmış" gibi. Artık maç bitince bu
/// ekran açılır; oyuncu sonucu profillerle birlikte görür ve NEREYE gideceğine
/// kendisi karar verir.
///
/// ## Yeniden tasarım (2026-09)
///
/// Başlık, takım kartları ve sıralama tek bir kaydırma alanında; aksiyonlar
/// sabit alt çubukta. Eski hali sabit `Column` idi: kupa + başlık + takım
/// kartları + dört oyuncu satırı + butonlar, kısa ekranlarda sıralamayı
/// birkaç piksellik bir şeride eziyordu.
class OkeyMatchResultScreen extends StatefulWidget {
  /// Koltuk sırasına göre oyuncular (boş koltuk null).
  final List<OkeyRoomSeat?> seats;

  /// Odanın kimliği — ÖDEME ÖZETİNİ (kim ne kazandı) çekmek için.
  ///
  /// Null ise ödeme bölümü hiç çizilmez: skor tablosu, ödeme bilgisi
  /// alınamadı diye eksik gösterilmemeli.
  final String? roomId;

  /// Koltuk → kümülatif skor.
  final Map<int, int> scores;

  /// Benim koltuğum (vurgulamak için).
  final int mySeat;

  /// 'esli' ise takım skorları da gösterilir.
  final String teamMode;

  /// Oynanan el sayısı.
  final int handsPlayed;

  /// "Lobiye dön" seçildiğinde.
  final VoidCallback onLeave;

  /// "Aynı masayla yeniden oyna" seçildiğinde, KURULAN/KATILINAN odanın
  /// kimliğiyle çağrılır (null ise düğme gizlenir).
  ///
  /// Odayı ekranın kendisi kurar (bkz. _rematchPressed): "hangi oda"
  /// sorusunun cevabı sunucudadır ve çağıran tarafın onu yeniden
  /// hesaplaması, iki farklı odaya gitme riski demek olurdu.
  ///
  /// ## Neden BuildContext de geçiyor
  ///
  /// Gezinme, çağıranın YAKALADIĞI bir context ile yapılamaz. Bu dosyada
  /// aynı hata bir kez yaşandı (bkz. okey_game_screen'deki "onLeave OYUN
  /// EKRANININ context'ini yakalıyordu" notu): yakalanan context ölünce
  /// düğme hiçbir şey yapmıyor ve HİÇBİR HATA da vermiyordu. Burada
  /// gezinmenin kullanacağı context, çağrının yapıldığı anda kesinlikle
  /// canlı olan EKRANIN KENDİ context'idir.
  final void Function(BuildContext context, String newRoomId)? onRematch;

  /// Oda servisi — verilmezse gerçeği kullanılır.
  ///
  /// Enjekte edilebilir olması bir tercih değil zorunluluk: "düğmeye basınca
  /// oda ekranı açılıyor mu" sorusu, Supabase'e bağlı bir servisle widget
  /// testinde HİÇ sorulamıyordu. Kullanıcının bildirdiği hata da tam olarak
  /// o soruydu.
  final OkeyRoomService? service;

  const OkeyMatchResultScreen({
    super.key,
    required this.seats,
    required this.scores,
    required this.mySeat,
    required this.onLeave,
    this.roomId,
    this.teamMode = 'essiz',
    this.handsPlayed = 0,
    this.onRematch,
    this.service,
  });

  @override
  State<OkeyMatchResultScreen> createState() => _OkeyMatchResultScreenState();
}

class _OkeyMatchResultScreenState extends State<OkeyMatchResultScreen> {
  OkeyRoomService get _service => widget.service ?? OkeyRoomService();

  /// Koltuk → maç sonu puan hareketi. Boş kalırsa bölüm çizilmez.
  Map<int, OkeyMatchPayout> _payouts = const {};

  /// Bu masa için ZATEN kurulmuş bir "yeniden oyna" odası (varsa).
  ///
  /// Düğmenin ne diyeceğini belirler: kimse kurmadıysa "YENİDEN OYNA",
  /// biri kurduysa "MASAYA KATIL (2/4)". Basmadan önce öğrenilmezse herkes
  /// oda kurduğunu sanır — oysa buluşma noktası tektir.
  ({String roomId, String status, int seated})? _rematch;

  bool _rematchBusy = false;

  @override
  void initState() {
    super.initState();
    _loadPayouts();
    _loadRematch();
  }

  Future<void> _loadRematch() async {
    final roomId = widget.roomId;
    if (roomId == null || widget.onRematch == null) return;
    try {
      final r = await _service.rematchRoomOf(roomId);
      if (!mounted) return;
      setState(() => _rematch = r);
    } catch (_) {
      // Sessizce geç: düğme yine çalışır, yalnızca etiketi "YENİDEN OYNA"
      // kalır ve basınca sunucu doğru odaya yönlendirir.
    }
  }

  Future<void> _rematchPressed() async {
    final roomId = widget.roomId;
    final onRematch = widget.onRematch;
    if (roomId == null || onRematch == null || _rematchBusy) return;

    setState(() => _rematchBusy = true);
    try {
      final newRoomId = await _service.rematch(roomId);
      if (!mounted) return;
      // Gezinme de try'ın İÇİNDE: dışarıda kalsaydı, gezinme sırasında atılan
      // bir hata (ölü context, kurulamayan ekran) hiçbir yere düşmez ve düğme
      // "hiçbir şey yapmıyor" gibi görünürdü.
      onRematch(context, newRoomId);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_rematchError('$e'))));
    } finally {
      // DÜĞME ASLA KİLİTLİ KALMAZ.
      //
      // Önce yalnızca hata yolunda sıfırlanıyordu; başarı yolunda gezinme
      // sessizce başarısız olursa düğme sonsuza kadar "meşgul" kalıyor ve
      // sonraki her basış hiçbir şey yapmıyordu — dışarıdan tam olarak
      // "açılmıyor" gibi görünen durum budur.
      if (mounted) setState(() => _rematchBusy = false);
    }
  }

  /// Sunucu hatasını masaya uygun bir cümleye çevirir.
  String _rematchError(String raw) {
    if (raw.contains('rematch_already_started')) {
      return 'Yeni masa çoktan başladı — lobiden yeni bir masa kurabilirsin.';
    }
    if (raw.contains('insufficient_points')) {
      return 'Yeni masa için çipin yetmiyor.';
    }
    if (raw.contains('room_full')) return 'Yeni masa doldu.';
    return 'Yeni masa kurulamadı.';
  }

  /// ÖDEME ÖZETİ SESSİZCE BAŞARISIZ OLUR.
  ///
  /// Skor tablosu maçın asıl sonucudur ve elde zaten var; ödeme özeti onun
  /// üstüne gelen bir ayrıntı. Ağ hatası yüzünden bir hata kartı gösterip
  /// oyuncuyu skoruna bakmaktan alıkoymak, kazanılan bilgiyle
  /// orantısız olurdu.
  Future<void> _loadPayouts() async {
    final roomId = widget.roomId;
    if (roomId == null) return;
    try {
      final rows = await _service.matchPayouts(roomId);
      if (!mounted) return;
      setState(() {
        _payouts = {for (final r in rows) r.seatNo: r};
      });
    } catch (_) {
      // yut — bkz. yukarıdaki gerekçe
    }
  }

  Map<int, int> get scores => widget.scores;
  int get mySeat => widget.mySeat;

  /// 101 Okey'de DÜŞÜK skor kazanır (skorlar cezadır).
  List<int> get _rankedSeats {
    final list = [0, 1, 2, 3];
    list.sort((a, b) => (scores[a] ?? 0).compareTo(scores[b] ?? 0));
    return list;
  }

  bool get _isTeams => widget.teamMode == 'esli';

  int get _teamA => (scores[0] ?? 0) + (scores[2] ?? 0);
  int get _teamB => (scores[1] ?? 0) + (scores[3] ?? 0);

  bool get _iWon {
    if (_isTeams) {
      final myTeamIsA = mySeat == 0 || mySeat == 2;
      return myTeamIsA ? _teamA <= _teamB : _teamB < _teamA;
    }
    return _winnerSeats.contains(mySeat);
  }

  /// KAZANAN KOLTUK(LAR) — en düşük ceza. Beraberlikte HEPSİ kazanır.
  ///
  /// Sunucudaki okey_internal_award_match ile AYNI kural: potu da bu ölçüt
  /// dağıtıyor. İki yerde iki farklı "kazanan" tanımı olsaydı, ekranda
  /// kazanan görünen oyuncu puanını alamayabilirdi.
  List<int> get _winnerSeats {
    // Boş koltuk yarışmaz: dolmamış bir koltuğun skoru 0'dır ve hiç
    // oynamadığı için her zaman "en düşük" çıkardı.
    final playing = [
      for (var i = 0; i < 4; i++)
        if (i < widget.seats.length && widget.seats[i] != null) i,
    ];
    if (playing.isEmpty) return const [];

    var best = scores[playing.first] ?? 0;
    for (final s in playing) {
      final v = scores[s] ?? 0;
      if (v < best) best = v;
    }
    return [
      for (final s in playing)
        if ((scores[s] ?? 0) == best) s,
    ];
  }

  /// Maçın sonucu tek bir cümlede — KİM kazandı, KAÇ puanla.
  ///
  /// KULLANICI İSTEĞİ (2026-09-05): "oyun bittiğinde direkt puanla birlikte
  /// kazananı belirle." Başlık eskiden yalnızca iki şey diyebiliyordu:
  /// "KAZANDIN!" ya da "Maç bitti". İkincisi kaybedene sonucun YARISINI
  /// söylüyordu — kazananı öğrenmek için aşağıdaki sıralamayı okuyup en
  /// düşük sayıyı kendi bulması gerekiyordu.
  ({String title, String detail, bool tie}) get _outcome {
    final hands = widget.handsPlayed;
    final suffix = hands > 0 ? '$hands el · ' : '';

    if (_isTeams) {
      if (_teamA == _teamB) {
        return (
          title: 'Berabere',
          detail:
              '$suffix'
              'iki takım da $_teamA puan',
          tie: true,
        );
      }
      final aWon = _teamA < _teamB;
      final label = aWon ? 'Takım 1' : 'Takım 2';
      final score = aWon ? _teamA : _teamB;
      return (
        title: _iWon ? 'KAZANDIN!' : '$label kazandı',
        detail: '$suffix$label · $score puan',
        tie: false,
      );
    }

    final winners = _winnerSeats;
    if (winners.isEmpty) {
      return (title: 'Maç bitti', detail: '${suffix}sonuç yok', tie: false);
    }

    final score = scores[winners.first] ?? 0;
    if (winners.length > 1) {
      final names = winners.map(_nameOf).join(' · ');
      return (
        title: 'Berabere',
        detail: '$suffix$names · $score puan',
        tie: true,
      );
    }

    final name = _nameOf(winners.first);
    return (
      title: _iWon ? 'KAZANDIN!' : '$name kazandı',
      detail: '$suffix$name · $score puan',
      tie: false,
    );
  }

  /// Koltuktaki oyuncunun masada GÖRÜNEN adı (bot olduğunu ele vermez).
  String _nameOf(int seatNo) {
    final seat = seatNo < widget.seats.length ? widget.seats[seatNo] : null;
    if (seat == null) return '${seatNo + 1}. koltuk';
    return seat.displayLabel;
  }

  @override
  Widget build(BuildContext context) {
    final ranked = _rankedSeats;
    final seats = widget.seats;

    return Scaffold(
      backgroundColor: OkeyColors.screenBackground,
      body: Container(
        decoration: const BoxDecoration(gradient: OkeyUI.screenGradient),
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(14, 18, 14, 8),
                  children: [
                    _Header(
                      iWon: _iWon,
                      title: _outcome.title,
                      detail: _outcome.detail,
                      tie: _outcome.tie,
                    ),
                    if (_isTeams) ...[
                      const SizedBox(height: OkeyUI.gapLg),
                      Row(
                        children: [
                          Expanded(
                            child: _TeamCard(
                              title: 'Takım 1',
                              subtitle: '1. + 3. koltuk',
                              score: _teamA,
                              won: _teamA <= _teamB,
                              mine: mySeat == 0 || mySeat == 2,
                            ),
                          ),
                          const SizedBox(width: OkeyUI.gapSm),
                          Expanded(
                            child: _TeamCard(
                              title: 'Takım 2',
                              subtitle: '2. + 4. koltuk',
                              score: _teamB,
                              won: _teamB < _teamA,
                              mine: mySeat == 1 || mySeat == 3,
                            ),
                          ),
                        ],
                      ),
                    ],
                    const OkeySectionHeader(label: 'Sıralama'),
                    for (var i = 0; i < ranked.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: _PlayerRow(
                          rank: i + 1,
                          seat: seats.length > ranked[i]
                              ? seats[ranked[i]]
                              : null,
                          seatNo: ranked[i],
                          score: scores[ranked[i]] ?? 0,
                          isMe: ranked[i] == mySeat,
                          payout: _payouts[ranked[i]],
                        ),
                      ),
                  ],
                ),
              ),
              // AKSİYONLAR — oyuncu nereye gideceğine KENDİSİ karar verir.
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: OkeyButton(
                        label: 'Lobiye dön',
                        icon: Icons.list,
                        tone: OkeyButtonTone.ghost,
                        onPressed: widget.onLeave,
                      ),
                    ),
                    if (widget.onRematch != null && widget.roomId != null) ...[
                      const SizedBox(width: OkeyUI.gapSm),
                      Expanded(
                        flex: 2,
                        child: OkeyButton(
                          // BİRİ ZATEN KURDUYSA davet gibi okunur: "yeniden
                          // oyna" yazsaydı ikinci oyuncu ikinci bir masa
                          // açtığını sanırdı (oysa aynı odaya katılıyor).
                          label: _rematch == null
                              ? 'Aynı masayla yeniden oyna'
                              : 'Masaya katıl (${_rematch!.seated}/4)',
                          icon: _rematch == null ? Icons.replay : Icons.login,
                          tone: OkeyButtonTone.primary,
                          busy: _rematchBusy,
                          onPressed: _rematchBusy ? null : _rematchPressed,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final bool iWon;

  /// "KAZANDIN!" / "Ayşe kazandı" / "Berabere".
  final String title;

  /// "3 el · Ayşe · 118 puan" — kazananın adı ve TOPLAM cezası.
  final String detail;

  final bool tie;

  const _Header({
    required this.iWon,
    required this.title,
    required this.detail,
    required this.tie,
  });

  @override
  Widget build(BuildContext context) {
    // Berabere ayrı bir ikon ister: kupa da bayrak da yanlış olurdu.
    final trophy = Icon(
      tie
          ? Icons.balance
          : (iWon ? Icons.emoji_events : Icons.emoji_events_outlined),
      size: 46,
      color: iWon ? OkeyColors.accentGold : OkeyUI.textFaint,
    );

    return Column(
      children: [
        // Kazanınca kupa hafif bir "pop" ile büyüyerek belirir — anı, düz bir
        // ikondan daha fazla kutlar hissettirir.
        if (!iWon)
          trophy
        else
          trophy
              .animate()
              .scaleXY(
                begin: 0.3,
                end: 1,
                duration: 450.ms,
                curve: Curves.elasticOut,
              )
              .then()
              .shimmer(
                duration: 900.ms,
                color: OkeyColors.accentGold.withValues(alpha: 0.6),
              ),
        const SizedBox(height: OkeyUI.gapSm),
        // Başlık FittedBox içinde: büyütülmüş yazı tipiyle 24px'lik metin dar
        // ekranda satırı taşırıyordu. Kazananın adı da buraya girdiği için
        // (uzun adlar) küçülme artık kural, istisna değil.
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            title,
            maxLines: 1,
            style: TextStyle(
              fontSize: 26,
              height: 1.1,
              fontWeight: FontWeight.w900,
              color: iWon ? OkeyColors.accentGold : OkeyUI.text,
              letterSpacing: 0.5,
            ),
          ),
        ).animate().fadeIn(delay: 200.ms, duration: 300.ms),
        const SizedBox(height: 4),
        // KAZANANIN PUANI BAŞLIKLA BİRLİKTE: "kim kazandı" ile "kaç puanla"
        // aynı cümlede olmazsa oyuncu ikincisini aşağıdaki sıralamadan
        // kendisi çıkarmak zorunda kalıyordu.
        Text(
          detail,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: OkeyUI.caption,
        ),
        const SizedBox(height: 2),
        const Text(
          'en düşük ceza kazanır',
          textAlign: TextAlign.center,
          maxLines: 1,
          style: TextStyle(color: OkeyUI.textFaint, fontSize: 11),
        ),
      ],
    );
  }
}

class _TeamCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final int score;
  final bool won;
  final bool mine;

  const _TeamCard({
    required this.title,
    required this.subtitle,
    required this.score,
    required this.won,
    required this.mine,
  });

  @override
  Widget build(BuildContext context) {
    return OkeyCard(
      highlighted: won,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: OkeyUI.title,
                ),
              ),
              if (mine) const OkeyPill(text: 'Sen'),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: OkeyUI.caption,
          ),
          const SizedBox(height: OkeyUI.gapSm),
          SizedBox(
            width: double.infinity,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                '$score',
                maxLines: 1,
                style: TextStyle(
                  color: won ? OkeyColors.accentGold : OkeyUI.text,
                  fontSize: 26,
                  height: 1.1,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlayerRow extends StatelessWidget {
  final int rank;
  final OkeyRoomSeat? seat;
  final int seatNo;
  final int score;
  final bool isMe;

  /// Bu koltuğun maç sonu puan hareketi (yoksa satır yalnızca skoru gösterir).
  final OkeyMatchPayout? payout;

  const _PlayerRow({
    required this.rank,
    required this.seat,
    required this.seatNo,
    required this.score,
    required this.isMe,
    this.payout,
  });

  Color get _rankColor => switch (rank) {
    1 => OkeyColors.accentGold,
    2 => const Color(0xFFB0BEC5),
    3 => const Color(0xFFA1887F),
    _ => OkeyUI.textFaint,
  };

  @override
  Widget build(BuildContext context) {
    final s = seat;
    final name = s == null ? 'Boş koltuk' : s.displayLabel;

    // SATIRA DOKUNUNCA PROFİL KARTI (kullanıcı isteği: "diğer kişilerin
    // profiline tıklamasına izin verilsin"). Masadaki levhalarla aynı
    // davranış: skor tablosunda bir isim görüp kim olduğuna bakmak,
    // masadakine bakmak kadar doğal bir istek.
    final card = OkeyCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      highlighted: isMe,
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _rankColor.withValues(alpha: 0.22),
              shape: BoxShape.circle,
              border: Border.all(color: _rankColor),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '$rank',
                maxLines: 1,
                style: TextStyle(
                  color: _rankColor,
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                ),
              ),
            ),
          ),
          const SizedBox(width: OkeyUI.gapSm),
          OkeyAvatar(url: s?.avatarUrl, size: 38, highlighted: isMe),
          const SizedBox(width: OkeyUI.gap),
          // Ad ESNER, skor sabit kalır: tersi olsaydı uzun bir ad skoru
          // ekran dışına iterdi.
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isMe ? '$name (Sen)' : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: OkeyUI.title.copyWith(
                    color: isMe ? OkeyColors.accentGold : OkeyUI.text,
                  ),
                ),
                const SizedBox(height: 2),
                // KAZANÇ SATIRI — kullanıcı isteği: "oyun bittiğinde kim ne
                // puan kazandığını göster".
                //
                // Skorun (ceza) yanında DEĞİL, adın altında duruyor: ikisi
                // farklı büyüklükler ve aynı hizada yan yana konsaydı hangi
                // sayının ceza hangisinin puan olduğu karışırdı. Ödeme henüz
                // yüklenmediyse (ya da bot koltuğu) koltuk numarası kalır.
                if (payout == null)
                  Text(
                    '${seatNo + 1}. koltuk',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: OkeyUI.caption,
                  )
                else
                  _PayoutLine(payout: payout!),
              ],
            ),
          ),
          const SizedBox(width: OkeyUI.gapSm),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 86),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                '$score',
                maxLines: 1,
                style: TextStyle(
                  color: rank == 1 ? OkeyColors.accentGold : OkeyUI.textDim,
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                ),
              ),
            ),
          ),
        ],
      ),
    );

    // Boş koltuğun profili yoktur; dokunma da olmaz.
    if (s == null) return card;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => OkeyProfileSheet.show(
        context,
        userId: s.userId,
        botProfileId: s.botProfileId,
        name: s.displayLabel,
        avatarUrl: s.avatarUrl,
      ),
      child: card,
    );
  }
}

/// Bir koltuğun maç sonu puan hareketi: `-1.500 masa · +4.500 pot`.
///
/// ## Neden üç sayı değil iki
///
/// Net değişim (kazanç − masa puanı) ayrıca yazılmıyor: iki sayı zaten yan
/// yana ve okuyan kişi farkı kafasından alıyor. Üçüncü bir sayı, satırı
/// bir muhasebe fişine çevirirdi. Kazanmayan oyuncuda pot kısmı hiç
/// çizilmez — "+0" bir bilgi değil, gürültüdür.
class _PayoutLine extends StatelessWidget {
  final OkeyMatchPayout payout;

  const _PayoutLine({required this.payout});

  static String _fmt(int v) {
    final digits = v.abs().toString();
    final b = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) b.write('.');
      b.write(digits[i]);
    }
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    final won = payout.won > 0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (payout.stake > 0) ...[
          Text(
            '-${_fmt(payout.stake)} masa',
            maxLines: 1,
            style: OkeyUI.caption,
          ),
          if (won) const SizedBox(width: 6),
        ],
        // MASA PUANI İADESİ — kazanandan masa ücreti alınmadığının kanıtı.
        //
        // Kazanan için "-300 masa" satırı artık hiç çizilmiyor (ödediği 0);
        // yerine hiçbir şey koymamak, ücretsiz bir masada oynamışla aynı
        // görüntüyü verirdi. İade satırı farkı söyler: masa puanın geri geldi.
        if (payout.refund > 0) ...[
          Text(
            '+${_fmt(payout.refund)} masa iadesi',
            maxLines: 1,
            style: OkeyUI.caption.copyWith(color: const Color(0xFFB9F6CA)),
          ),
          if (won) const SizedBox(width: 6),
        ],
        if (won)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.stars, size: 12, color: OkeyColors.accentGold),
              const SizedBox(width: 3),
              Text(
                '+${_fmt(payout.won)} kazandı',
                maxLines: 1,
                style: OkeyUI.caption.copyWith(
                  color: OkeyColors.accentGold,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
      ],
    );
  }
}
