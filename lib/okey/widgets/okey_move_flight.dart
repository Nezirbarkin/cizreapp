import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../engine/okey_tile.dart';
import 'okey_tile_widget.dart';

/// Masada AZ ÖNCE OYNANMIŞ bir hamle — uçan taşın tarifi.
///
/// Provider bunu bir [ValueNotifier] üzerinden yayar; masa durumunun kendisi
/// değil, yalnızca "şu taş şuradan şuraya gitti" haberidir.
@immutable
class OkeyMoveFlash {
  /// okey_moves satırının kimliği — aynı hamle iki kez uçmasın diye.
  final int id;

  /// Hamleyi yapan koltuk.
  final int seatNo;

  /// draw_deck | draw_discard | discard | timeout_auto_discard |
  /// lay_meld | add_to_meld | steal_okey
  final String action;

  /// Taş bilinmiyorsa (ya da GİZLİYSE) null — o zaman KAPALI taş uçar.
  final OkeyTile? tile;

  const OkeyMoveFlash({
    required this.id,
    required this.seatNo,
    required this.action,
    this.tile,
  });
}

/// Masadaki bir noktanın kimliği — uçuşun nereden nereye olduğunu söyler.
enum OkeyAnchor {
  /// Gösterge/okey/deste sütunu.
  deck,

  /// Açılan perlerin serildiği tabla.
  melds,

  /// Bir koltuğun ıskarta kutusu (seatNo ile birlikte kullanılır).
  discard,

  /// Bir koltuğun kimlik levhası (seatNo ile birlikte kullanılır).
  seat,
}

/// Bir çapanın ekrandaki dikdörtgenini çözer. Çapa henüz çizilmediyse null.
typedef OkeyAnchorResolver = Rect? Function(OkeyAnchor anchor, int seatNo);

/// UÇAN TAŞ — hamlenin nereden nereye olduğunu GÖSTERİR.
///
/// ## Neden gerekli (kullanıcı isteği, 2026-09-06: "taş atma veya taş çekme,
/// taş işletme vs ekranda taş belli olsun, kaydığını")
///
/// Masada bir hamle olduğunda ekranda değişen tek şey son durumdu: ıskartada
/// bir taş beliriveriyor, destenin sayacı bir azalıyor, perin sonuna bir taş
/// ekleniveriyordu. Hangi taşın nereden nereye gittiği HİÇ görünmüyordu —
/// özellikle üç bot arka arkaya oynadığında masa kendi kendine değişen bir
/// tabloya dönüşüyor, oyuncu "az önce ne oldu" diye bakakalıyordu.
///
/// Hareket bunu tek başına anlatır: göz, yer değiştiren bir nesneyi okumak
/// için düşünmez.
///
/// ## YALNIZCA BAŞKALARININ HAMLESİ UÇAR (kullanıcı isteği, 2026-09-06:
/// "benim taş çekmede uçan taş olmasın ama karşı tarafta öyle görsün")
///
/// Kendi hamlemi zaten BEN yaptım: desteye ben dokundum, taşı ben sürükledim,
/// atacağım taşı ben seçtim. Üstüne bir de animasyon oynatmak bilgi vermez,
/// sadece elimin önünü kapatır — üstelik tam hamleyi bitirdiğim anda, sıradaki
/// hamleye bakmak istediğim yerde.
///
/// Rakibin eli ise görünmez; onun hamlesinde uçan taş TEK sinyaldir. Kural bu
/// yüzden asimetrik ve bu asimetri kasıtlı: masadaki herkes DİĞERLERİNİN
/// hamlesini uçarken görür, kendininkini görmez.
///
/// Kural HER hamle için geçerlidir (çekme, atma, işleme, açma, okey çalma) —
/// "bazısında uçsun bazısında uçmasın" ayrımı, oyuncunun kafasında bir kural
/// daha tutması demek olurdu.
///
/// ## Gizlilik: KAPALI UÇAR
///
/// Başka bir oyuncunun DESTEDEN çektiği taş gizlidir; arkası dönük çizilir.
/// Animasyon hiçbir koşulda bir bilgi sızıntısı kanalı olamaz.
///
/// ## Dokunma olaylarını YUTMAZ
///
/// [IgnorePointer] içinde durur. Uçan bir taşın parmağın altına denk gelip
/// hamleyi yutması, animasyonun anlattığı her şeyden pahalıya mal olurdu.
class OkeyMoveFlightOverlay extends StatefulWidget {
  final ValueListenable<OkeyMoveFlash?> move;

  /// Masadaki çapaların yerini çözer (bkz. [OkeyAnchorResolver]).
  final OkeyAnchorResolver resolve;

  /// Benim koltuğum — BU koltuğun hamleleri hiç uçmaz (bkz. sınıf yorumu).
  ///
  /// İzleyicide null: masada oturmayan biri için her hamle "başkasının"
  /// hamlesidir, dolayısıyla dördü de uçar.
  final int? mySeatNo;

  /// Uçan taşın genişliği.
  final double tileWidth;

  const OkeyMoveFlightOverlay({
    super.key,
    required this.move,
    required this.resolve,
    required this.mySeatNo,
    this.tileWidth = 30,
  });

  /// Uçuş süresi. Bir hamleyi anlatacak kadar uzun, sıradaki hamleyi
  /// geciktirmeyecek kadar kısa: botlar 2–4 sn'de bir oynuyor.
  static const Duration duration = Duration(milliseconds: 460);

  @override
  State<OkeyMoveFlightOverlay> createState() => _OkeyMoveFlightOverlayState();
}

class _OkeyMoveFlightOverlayState extends State<OkeyMoveFlightOverlay>
    with SingleTickerProviderStateMixin {
  /// DENETLEYİCİ initState'te KURULUR, `late final` ile tembel DEĞİL.
  ///
  /// Tembel kurulumda ticker ilk erişimde yaratılır. Kendi hamlelerim hiç
  /// uçmadığı için (bkz. sınıf yorumu), masada tek bir rakip hamlesi
  /// görmeden ekranı kapatan bir oyuncuda denetleyiciye İLK erişim
  /// `dispose()` oluyordu — ticker o anda, widget ağaçtan çıkarılmışken
  /// kurulmaya çalışılıyor ve "Looking up a deactivated widget's ancestor is
  /// unsafe" ile patlıyordu.
  late final AnimationController _controller;

  OkeyMoveFlash? _current;
  Rect? _from;
  Rect? _to;
  int? _lastId;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: OkeyMoveFlightOverlay.duration,
    );
    widget.move.addListener(_onMove);
    // İLK KURULUŞTA UÇURMA: masaya girerken en son hamle zaten olmuş bitmiş.
    _lastId = widget.move.value?.id;
  }

  @override
  void didUpdateWidget(OkeyMoveFlightOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.move != widget.move) {
      oldWidget.move.removeListener(_onMove);
      widget.move.addListener(_onMove);
    }
  }

  @override
  void dispose() {
    widget.move.removeListener(_onMove);
    _controller.dispose();
    super.dispose();
  }

  void _onMove() {
    final m = widget.move.value;
    if (m == null || m.id == _lastId) return;
    // Kimliği yine de işaretle: kendi hamlem uçmasa bile "görülmüş" sayılır,
    // yoksa sonraki bir yeniden kurulumda geriye dönük uçardı.
    _lastId = m.id;

    // KENDİ HAMLEM UÇMAZ — onu zaten ben yaptım (bkz. sınıf yorumu).
    if (widget.mySeatNo != null && m.seatNo == widget.mySeatNo) return;

    final route = _routeOf(m);
    if (route == null) return; // çapası çözülemeyen hamle sessizce atlanır

    setState(() {
      _current = m;
      _from = route.$1;
      _to = route.$2;
    });
    _controller.forward(from: 0);
  }

  /// Hamlenin NEREDEN NEREYE olduğunu çözer.
  ///
  /// "El" her zaman o koltuğun KİMLİK LEVHASIDIR: rakibin taşları görünmez,
  /// ekranda onun eli levhasıdır. (Kendi hamlem hiç uçmadığı için ıstaka bir
  /// uçuş ucu olarak hiç kullanılmaz.)
  (Rect, Rect)? _routeOf(OkeyMoveFlash m) {
    final hand = widget.resolve(OkeyAnchor.seat, m.seatNo);
    if (hand == null) return null;

    switch (m.action) {
      case 'draw_deck':
        final deck = widget.resolve(OkeyAnchor.deck, m.seatNo);
        return deck == null ? null : (deck, hand);

      case 'draw_discard':
        // Yandan çekme: SOLDAKİ oyuncunun ıskartasından.
        final prev = widget.resolve(OkeyAnchor.discard, (m.seatNo + 3) % 4);
        return prev == null ? null : (prev, hand);

      case 'discard':
      case 'timeout_auto_discard':
        final pile = widget.resolve(OkeyAnchor.discard, m.seatNo);
        return pile == null ? null : (hand, pile);

      case 'lay_meld':
      case 'add_to_meld':
        final melds = widget.resolve(OkeyAnchor.melds, m.seatNo);
        return melds == null ? null : (hand, melds);

      case 'steal_okey':
        // Okey ÇALMA ters yönde akar: masadan ele.
        final melds = widget.resolve(OkeyAnchor.melds, m.seatNo);
        return melds == null ? null : (melds, hand);

      default:
        return null;
    }
  }

  /// Uçan taş AÇIK mı çizilecek?
  ///
  /// DESTEDEN çekilen taş gizlidir ve buraya yalnızca BAŞKASININ hamlesi
  /// geldiği için (kendi hamlem hiç uçmaz) her deste çekişi kapalı uçar.
  /// Iskartaya atılan ve masaya işlenen taş ise zaten herkesin gözü önünde.
  bool _faceUp(OkeyMoveFlash m) {
    if (m.tile == null) return false;
    if (m.action == 'draw_deck') return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final m = _current;
    final from = _from;
    final to = _to;
    if (m == null || from == null || to == null) {
      return const SizedBox.shrink();
    }

    final w = widget.tileWidth;
    final h = w / 0.74;

    return IgnorePointer(
      // REPAINT SINIRI — uçuş 60 kare boyunca çizilir; masanın tamamını
      // (keçe, perler, ıstaka) yeniden boyamaya zorlamasın.
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final t = _controller.value;
            if (t >= 1) return const SizedBox.shrink();

            // Yumuşak giriş/çıkış: taş fırlamaz, "kayar".
            final e = Curves.easeInOutCubic.transform(t);
            final center = Offset.lerp(from.center, to.center, e)!;

            // HAFİF KAVİS: düz bir çizgi mekanik görünüyordu. Yay, yolun
            // ortasında en yüksek; iki ucunda sıfır.
            final lift =
                math.sin(e * math.pi) *
                (from.center - to.center).distance *
                0.10;

            // Sonda küçülerek yerine oturur; başta hafif büyük "kalkar".
            final scale = 1.0 + 0.16 * math.sin(e * math.pi);
            // Yalnızca son çeyrekte söner: yol boyunca net kalsın.
            final opacity = t < 0.75 ? 1.0 : (1 - (t - 0.75) / 0.25);

            return Stack(
              children: [
                Positioned(
                  left: center.dx - w / 2,
                  top: center.dy - h / 2 - lift,
                  child: Opacity(
                    opacity: opacity.clamp(0.0, 1.0),
                    child: Transform.scale(
                      scale: scale,
                      child: OkeyTileWidget(
                        tile: m.tile ?? OkeyTile.falseJoker(),
                        faceDown: !_faceUp(m),
                        width: w,
                        height: h,
                        tight: true,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
