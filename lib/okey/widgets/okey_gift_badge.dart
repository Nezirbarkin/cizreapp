import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/okey_gift_service.dart';

/// Bir hediye ikonunun MASADA NASIL OYNAYACAĞI.
///
/// Hareket ikonun kendisinde değil — emoji her platformda hazır ve
/// ölçeklenir; hareketi veren şey onu çizen widget. Bu sayede yeni bir
/// "hareketli ikon" eklemek bir GIF/Lottie dosyası, bir depolama kovası ve
/// bir CDN yolu değil, katalogda tek bir metin alanı demektir.
enum OkeyGiftAnim {
  /// Zıplayarak büyüyüp küçülür — genel amaçlı (çay, kahve, dondurma).
  bounce,

  /// Hızlıca sağa sola sallanır — GÜLME ve ALKIŞ'ın ritmi.
  shake,

  /// Kalp atışı: iki vuruşta şişip söner (kalp, gül, ateş).
  beat,

  /// Bir tam tur döner (yıldız, havai fişek).
  spin,

  /// Yavaşça yükselir (çiçek, balon).
  float;

  /// Sunucudan gelen metni çözer.
  ///
  /// TANIMADIĞI DEĞER HATA DEĞİLDİR: admin panelinden yarın 'confetti'
  /// yazılabilir ve o hediyenin uygulamayı çökertmesi ya da hiç
  /// görünmemesi kabul edilemez — bilinmeyen hareket [bounce] olarak oynar.
  static OkeyGiftAnim parse(String? raw) {
    switch (raw?.trim().toLowerCase()) {
      case 'shake':
        return OkeyGiftAnim.shake;
      case 'beat':
        return OkeyGiftAnim.beat;
      case 'spin':
        return OkeyGiftAnim.spin;
      case 'float':
        return OkeyGiftAnim.float;
      default:
        return OkeyGiftAnim.bounce;
    }
  }

  /// Panelde/ipuçlarında görünen ad.
  String get label => switch (this) {
    OkeyGiftAnim.bounce => 'Zıpla',
    OkeyGiftAnim.shake => 'Salla',
    OkeyGiftAnim.beat => 'Kalp atışı',
    OkeyGiftAnim.spin => 'Dön',
    OkeyGiftAnim.float => 'Yüksel',
  };

  /// Sunucuya yazılan değer.
  String get code => name;
}

/// HAREKETLİ HEDİYE İKONU — emoji, kendi hareketiyle.
///
/// Sürekli döner ([repeat] kez) ve sonra durur. Sonsuz döngü BİLEREK
/// kullanılmıyor: `pumpAndSettle` kullanan widget testleri asla ayarlanmayan
/// bir animasyonla zaman aşımına düşerdi (bkz. OkeyCornerPileWidget'taki
/// _Pulse'ta aynı karar) ve masada sürekli oynayan bir ikon gözü yorar.
class OkeyAnimatedGiftIcon extends StatefulWidget {
  final String icon;
  final OkeyGiftAnim anim;
  final double size;

  /// Kaç tur oynayıp duracağı.
  final int repeat;

  const OkeyAnimatedGiftIcon({
    super.key,
    required this.icon,
    required this.anim,
    this.size = 26,
    this.repeat = 4,
  });

  @override
  State<OkeyAnimatedGiftIcon> createState() => _OkeyAnimatedGiftIconState();
}

class _OkeyAnimatedGiftIconState extends State<OkeyAnimatedGiftIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _durationFor(widget.anim),
  );

  static Duration _durationFor(OkeyGiftAnim a) => switch (a) {
    OkeyGiftAnim.shake => const Duration(milliseconds: 380),
    OkeyGiftAnim.beat => const Duration(milliseconds: 620),
    OkeyGiftAnim.spin => const Duration(milliseconds: 900),
    OkeyGiftAnim.float => const Duration(milliseconds: 1100),
    OkeyGiftAnim.bounce => const Duration(milliseconds: 520),
  };

  @override
  void initState() {
    super.initState();
    _play();
  }

  @override
  void didUpdateWidget(OkeyAnimatedGiftIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Aynı koltuğa arka arkaya hediye gelirse animasyon BAŞTAN oynar;
    // kuyruğa alınmaz. Üst üste beş alkışta beşincisi hemen görünsün.
    if (oldWidget.icon != widget.icon || oldWidget.anim != widget.anim) {
      _controller.duration = _durationFor(widget.anim);
      _play();
    }
  }

  void _play() {
    _controller.stop();
    _controller.value = 0;
    _controller.repeat(count: widget.repeat);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Emoji sistem yazı tipi ayarıyla BÜYÜMEZ: ikon sabit ölçülü bir
    // rozetin içinde duruyor, büyüyen bir emoji rozeti taşırırdı.
    final glyph = MediaQuery.withNoTextScaling(
      child: Text(
        widget.icon,
        style: TextStyle(fontSize: widget.size, height: 1.0),
      ),
    );

    // REPAINT SINIRI — ikon saniyede 60 kare kendini çizer; masanın geri
    // kalanını (keçe, taşlar, kimlik levhaları) çizmeye zorlamasın.
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        child: glyph,
        builder: (context, child) => _transform(_controller.value, child!),
      ),
    );
  }

  Widget _transform(double t, Widget child) {
    switch (widget.anim) {
      case OkeyGiftAnim.shake:
        // ±14°, tam bir sinüs turu: sağa-sola-sağa. Kahkahanın ve alkışın
        // ritmi bu; ölçek değişmez, yoksa "zıplama"dan ayırt edilemezdi.
        return Transform.rotate(
          angle: math.sin(t * math.pi * 2) * 0.24,
          child: child,
        );

      case OkeyGiftAnim.beat:
        // İKİ vuruş (kalp gibi): asıl vuruş güçlü, ikincisi zayıf.
        final beat =
            math.sin(t * math.pi * 2).abs() * 0.22 +
            math.sin(t * math.pi * 4).abs() * 0.08;
        return Transform.scale(scale: 1.0 + beat, child: child);

      case OkeyGiftAnim.spin:
        return Transform.rotate(angle: t * math.pi * 2, child: child);

      case OkeyGiftAnim.float:
        // Yükselirken hafifçe sağa sola süzülür — düz bir yukarı kayma
        // asansör gibi görünüyordu.
        return Transform.translate(
          offset: Offset(
            math.sin(t * math.pi * 2) * widget.size * 0.12,
            -math.sin(t * math.pi) * widget.size * 0.35,
          ),
          child: child,
        );

      case OkeyGiftAnim.bounce:
        final lift = math.sin(t * math.pi);
        return Transform.translate(
          offset: Offset(0, -lift * widget.size * 0.30),
          child: Transform.scale(scale: 1.0 + lift * 0.14, child: child),
        );
    }
  }
}

/// BİR KOLTUĞA GELEN HEDİYELER — oyuncunun kimlik levhasının YANINDA,
/// ASILI KALIR.
///
/// ## Neden masanın ortasında bir bant değil (kullanıcı isteği, 2026-09-05:
/// "iconlar okey masasında profillerin yanında belirsin")
///
/// Hediyenin tek bilgisi var: KİME gitti. Masanın ortasındaki bir bant bunu
/// ancak yazıyla söyleyebilir ("Ayşe → Mehmet"); levhanın yanında beliren bir
/// ikon ise okumadan gösterir. Üstelik masanın ortası perlerin yeri — oyunun
/// en yoğun bakılan bölgesini bir kutlama için kapatmak, hamlenin kendisini
/// gizlemek olurdu.
///
/// ## Neden KAYBOLMUYOR (kullanıcı isteği, 2026-09-05: "atılan hediyeler
/// sabitlensin")
///
/// Rozet önce üç saniye görünüp siliniyordu. Masaya o an bakmayan herkes için
/// hediye hiç olmamış sayılıyordu: gönderen puanını harcıyor, alıcı çoğu
/// zaman görmüyordu. Artık o koltuğa gelen son birkaç hediye levhanın
/// yanında ASILI KALIR (kaçı asılı kalacağını OkeyGameProvider belirler) ve
/// masaya sonradan oturan da onları görür.
///
/// GÖNDERENİN ADI ise geçicidir ve bu kasıtlı: "kim gönderdi" tazeyken bir
/// haberdir, beş dakika sonra yalnızca yer kaplar. Birkaç saniye sonra rozet
/// yalnızca ikonlara iner.
///
/// ## Dokunma olaylarını YUTMAZ
///
/// [IgnorePointer] içinde durur: levhaya dokunup profil açmak, taş sürüklemek
/// engellenmez. Bir animasyonun hamleyi kaçırtması hediyeden çok daha
/// pahalıya mal olurdu.
class OkeySeatGiftBadge extends StatefulWidget {
  /// Bu rozetin ait olduğu koltuk.
  final int seatNo;

  /// Koltuk → o koltuğa asılı hediyeler, en yenisi başta
  /// (bkz. OkeyGameProvider.seatGifts).
  final ValueListenable<Map<int, List<OkeyGiftEvent>>> gifts;

  /// İkonun çizim ölçüsü — dar kenar sütunlarında küçülür.
  final double size;

  const OkeySeatGiftBadge({
    super.key,
    required this.seatNo,
    required this.gifts,
    this.size = 26,
  });

  /// Gönderenin adının ve animasyonun "taze" sayıldığı süre.
  static const Duration freshFor = Duration(milliseconds: 3600);

  @override
  State<OkeySeatGiftBadge> createState() => _OkeySeatGiftBadgeState();
}

class _OkeySeatGiftBadgeState extends State<OkeySeatGiftBadge> {
  /// En yeni hediye AZ ÖNCE mi geldi? Yalnızca o zaman gönderenin adı
  /// yazılır ve ikon oynar.
  bool _fresh = false;

  /// "Taze" damgasını kaldıracak olan bekleyiş — yerine yenisi gelirse
  /// iptal edilir. Bir Timer DEĞİL: `Future.delayed` iptal edilemez ve
  /// widget söküldükten sonra ateşlenip `setState` çağırırdı; jeton
  /// karşılaştırması bunu ikisini de çözer.
  Object? _freshToken;

  int? _lastId;

  @override
  void initState() {
    super.initState();
    widget.gifts.addListener(_onGifts);
    // İLK KURULUŞ TAZE DEĞİLDİR: masaya girerken zaten asılı olan
    // hediyeler için gönderen adı gösterip animasyon oynatmak, az önce
    // gelmiş gibi yanlış bir izlenim verirdi.
    _lastId = _latest?.id;
  }

  @override
  void didUpdateWidget(OkeySeatGiftBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.gifts != widget.gifts) {
      oldWidget.gifts.removeListener(_onGifts);
      widget.gifts.addListener(_onGifts);
    }
  }

  List<OkeyGiftEvent> get _mine =>
      widget.gifts.value[widget.seatNo] ?? const <OkeyGiftEvent>[];

  OkeyGiftEvent? get _latest => _mine.isEmpty ? null : _mine.first;

  void _onGifts() {
    final latest = _latest;
    // BAŞKA bir koltuğa gelen hediye bu rozeti hiç ilgilendirmez.
    if (latest == null || latest.id == _lastId) {
      // Yine de asılı liste değişmiş olabilir (ör. ilk toplu yükleme).
      if (mounted) setState(() {});
      return;
    }
    _lastId = latest.id;

    final token = Object();
    _freshToken = token;
    setState(() => _fresh = true);

    Future<void>.delayed(OkeySeatGiftBadge.freshFor, () {
      if (!mounted || _freshToken != token) return;
      setState(() => _fresh = false);
    });
  }

  @override
  void dispose() {
    _freshToken = null;
    widget.gifts.removeListener(_onGifts);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pinned = _mine;
    if (pinned.isEmpty) return const SizedBox.shrink();

    final latest = pinned.first;

    return IgnorePointer(
      child: MediaQuery.withNoTextScaling(
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: widget.size * 0.22,
            vertical: widget.size * 0.12,
          ),
          decoration: BoxDecoration(
            color: const Color(0xF00B3446),
            borderRadius: BorderRadius.circular(widget.size * 0.42),
            border: Border.all(color: const Color(0xB3FFD54F), width: 1.2),
            boxShadow: const [
              BoxShadow(
                color: Color(0x99000000),
                blurRadius: 8,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < pinned.length; i++) ...[
                if (i > 0) SizedBox(width: widget.size * 0.12),
                _PinnedIcon(
                  // id ile keylenmiş: yeni bir hediye başa geçtiğinde
                  // eskilerin State'i korunur, animasyon yalnızca yeni gelen
                  // için baştan oynar.
                  key: ValueKey(pinned[i].id),
                  gift: pinned[i],
                  // ESKİ hediyeler DURUR: üç ikon birden oynasa rozet
                  // masadaki en gürültülü şey olurdu.
                  animate: i == 0 && _fresh,
                  // Eskiler biraz küçük ve soluk: hangisinin AZ ÖNCE
                  // geldiği ölçüden okunur.
                  size: i == 0 ? widget.size : widget.size * 0.78,
                  faded: i > 0,
                ),
              ],
              // GÖNDEREN yalnızca hediye tazeyken yazılır (bkz. sınıf yorumu).
              //
              // Flexible + ellipsis: rozet dar kenar sütunlarında bir üst
              // genişlik sınırıyla kuruluyor (bkz. OkeyGameScreen). Sabit
              // genişlikli bir ad orada rozeti taşırır ve masanın üstüne
              // sarkardı; burada ad KISALIR, rozet sınırın içinde kalır.
              if (_fresh) ...[
                SizedBox(width: widget.size * 0.20),
                Flexible(
                  child: Text(
                    latest.senderName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    style: TextStyle(
                      color: const Color(0xFFFFE9A8),
                      fontSize: widget.size * 0.40,
                      height: 1.0,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Rozetteki tek bir hediye ikonu.
class _PinnedIcon extends StatelessWidget {
  final OkeyGiftEvent gift;
  final bool animate;
  final bool faded;
  final double size;

  const _PinnedIcon({
    super.key,
    required this.gift,
    required this.animate,
    required this.faded,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final Widget icon = animate
        ? OkeyAnimatedGiftIcon(
            icon: gift.giftIcon,
            anim: OkeyGiftAnim.parse(gift.giftAnim),
            size: size,
          )
        // DURAN ikon bir AnimationController kurmaz: masada dört rozet ve
        // her birinde üç ikon olabilir; hepsi için ticker açmak, hiç
        // oynamayacak animasyonların bedelini ödemek olurdu.
        : MediaQuery.withNoTextScaling(
            child: Text(
              gift.giftIcon,
              style: TextStyle(fontSize: size, height: 1.0),
            ),
          );

    return faded ? Opacity(opacity: 0.72, child: icon) : icon;
  }
}
