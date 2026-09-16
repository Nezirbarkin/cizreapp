import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/okey_points_provider.dart';

/// Kazanç anında ekrana dökülen ÇİP YAĞMURU.
///
/// Kullanıcı isteği (2026-09-08): "bonus al basınca çip yağmuru olsun".
///
/// ## Neden bir SARMALAYICI, düğmenin içinde bir efekt değil
///
/// Bonus üç ayrı yerden alınabiliyor (masa üstü şeridi, lobi kartı, çip
/// ekranı) ve reklam ödülünün hiç düğmesi yok. Efekt düğmeye bağlansaydı ya
/// üç kez kopyalanır ya da dördüncü yol sessiz kalırdı. Bunun yerine ekranın
/// gövdesi bu katmanla sarılır, tetik [OkeyPointsProvider.coinRainSignal]
/// değişiminden gelir: kazancın NEREDEN geldiğinin önemi kalmaz.
///
/// ## Neden tetik SUNUCU ONAYINDAN SONRA
///
/// Sinyal, cüzdan gerçekten arttığında artar (bkz. provider). Dokunuşa
/// bağlansaydı, süre dolmadığı için reddedilen bir bonusta da çipler yağardı
/// — kazanılmamış bir ödülü kutlamak olurdu. Aynı gerekçe çip sesi için de
/// geçerli ve ikisi aynı anda tetiklenir.
///
/// ## Neden dokunuşu geçirir
///
/// Yağmur [IgnorePointer] içindedir: iki saniye boyunca masaya dokunulamamak,
/// sırası gelen oyuncunun taş atmasını geciktirirdi. Kutlama oyunun önüne
/// geçmez.
class OkeyCoinRain extends StatefulWidget {
  /// Yağmurun üstüne serileceği ekran gövdesi.
  final Widget child;

  /// Yağmur katmanının anahtarı — YALNIZCA çipler düşerken ağaçtadır.
  ///
  /// Boyacı özel bir sınıf olduğu için testler onu tipiyle arayamıyordu;
  /// bu anahtar "şu an yağıyor mu" sorusunun tek yanıtı.
  @visibleForTesting
  static const Key rainKey = ValueKey('okey-coin-rain');

  const OkeyCoinRain({super.key, required this.child});

  @override
  State<OkeyCoinRain> createState() => _OkeyCoinRainState();
}

class _OkeyCoinRainState extends State<OkeyCoinRain>
    with SingleTickerProviderStateMixin {
  static const _duration = Duration(milliseconds: 2300);

  /// Aynı anda düşen çip sayısı.
  ///
  /// Az sayıda çip "yağmur" değil "birkaç şey düştü" gibi görünüyor; çok
  /// sayıda çip ise masayı kapatıyor ve zayıf cihazda kare düşürüyor.
  static const _coinCount = 34;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _duration,
  );

  final math.Random _random = math.Random();
  List<_Coin> _coins = const [];

  /// En son görülen sinyal.
  ///
  /// İlk değer ekrana girerken okunur ki YAĞMUR BAŞLAMASIN: sayaç oturum
  /// boyunca artıyor ve lobiye geri dönen oyuncu, dakikalar önce aldığı
  /// bonusun yağmurunu ikinci kez görmemeli.
  int? _lastSignal;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Yağmuru başlat — KARE BİTTİKTEN SONRA.
  ///
  /// Sinyal build sırasında okunuyor; animasyonu orada başlatmak, o karede
  /// zaten çizilmekte olan ağacın içinden yeniden çizim istemek olurdu.
  void _start() {
    if (!mounted) return;
    setState(() {
      _coins = List<_Coin>.generate(_coinCount, (_) => _Coin.random(_random));
    });
    _controller
      ..reset()
      ..forward();
  }

  @override
  Widget build(BuildContext context) {
    final signal = context.watch<OkeyPointsProvider>().coinRainSignal;
    if (_lastSignal == null) {
      _lastSignal = signal;
    } else if (signal != _lastSignal) {
      _lastSignal = signal;
      WidgetsBinding.instance.addPostFrameCallback((_) => _start());
    }

    return Stack(
      children: [
        widget.child,
        // RepaintBoundary: yağmur her karede yeniden çizilir, altındaki masa
        // çizilmez. Sınır olmasaydı animasyon boyunca tüm masa katmanı
        // yeniden boyanırdı.
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  // BİTİNCE AĞAÇTAN ÇEKİLİR. `isDismissed` tek başına
                  // yetmiyordu: forward() bitince değer 1,0'da KALIR, yani
                  // katman görünmez bir kare çizerek masanın üstünde asılı
                  // duruyordu. `isCompleted` de sorulunca son karede düşüyor
                  // — o karede zaten bütün çipler sönmüş ve ekranın altında.
                  if (_controller.isDismissed ||
                      _controller.isCompleted ||
                      _coins.isEmpty) {
                    return const SizedBox.expand();
                  }
                  return CustomPaint(
                    key: OkeyCoinRain.rainKey,
                    painter: _CoinRainPainter(
                      coins: _coins,
                      progress: _controller.value,
                    ),
                    size: Size.infinite,
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Tek bir çipin düşüş tarifi — animasyon başında BİR KEZ üretilir.
///
/// Değerler her karede rastgele üretilseydi çipler yerinde titrer, düşmezdi.
class _Coin {
  /// Yatay konum (ekran genişliğinin oranı).
  final double x;

  /// Düşüşün başlama gecikmesi (toplam sürenin oranı).
  final double delay;

  /// Düşüş hızı çarpanı — büyüğü daha çabuk yere iner.
  final double speed;

  /// Çip çapı çarpanı.
  final double scale;

  /// Yatay salınımın genliği ve fazı — dümdüz düşen çip taş gibi görünüyor.
  final double swayAmplitude;
  final double swayPhase;

  /// Kendi ekseninde dönme hızı (yatayda incelip kalınlaşır).
  final double spin;

  const _Coin({
    required this.x,
    required this.delay,
    required this.speed,
    required this.scale,
    required this.swayAmplitude,
    required this.swayPhase,
    required this.spin,
  });

  factory _Coin.random(math.Random r) => _Coin(
    x: r.nextDouble(),
    // Gecikme yalnız ilk yarıya dağıtılır: sona yakın başlayan bir çip
    // animasyon bitince ekranın ortasında kaybolurdu.
    delay: r.nextDouble() * 0.45,
    speed: 0.85 + r.nextDouble() * 0.6,
    scale: 0.6 + r.nextDouble() * 0.75,
    swayAmplitude: 6 + r.nextDouble() * 26,
    swayPhase: r.nextDouble() * math.pi * 2,
    spin: 1.5 + r.nextDouble() * 3.5,
  );
}

class _CoinRainPainter extends CustomPainter {
  final List<_Coin> coins;
  final double progress;

  const _CoinRainPainter({required this.coins, required this.progress});

  // Referans çip rengi: dıştan içe koyu altından parlak altına.
  static const _rim = Color(0xFFB8791A);
  static const _face = Color(0xFFFFD264);
  static const _faceInner = Color(0xFFFFF0B8);
  static const _engrave = Color(0xFF8A5A12);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final short = math.min(size.width, size.height);
    final baseRadius = (short * 0.035).clamp(9.0, 26.0);

    for (final coin in coins) {
      // Kendi zaman ekseni: gecikmesi dolmadan düşmez, hızlıysa erken biter.
      final t = ((progress - coin.delay) * coin.speed).clamp(0.0, 1.0);
      if (t <= 0) continue;

      final radius = baseRadius * coin.scale;

      // DÜŞÜŞ HIZLANARAK: t² yerçekimi eğrisi. Doğrusal düşüş, çipi asansör
      // gibi indiriyordu.
      final travel = size.height + radius * 4;
      final y = -radius * 2 + travel * (t * t);
      if (y - radius > size.height) continue;

      final x =
          coin.x * size.width +
          math.sin(coin.swayPhase + t * math.pi * 2.4) * coin.swayAmplitude;

      // SON ÇEYREKTE SÖNER: ekranın dibinde birden kaybolan çip, çizimin
      // kesildiğini hissettiriyordu.
      final fade = t > 0.78 ? (1 - (t - 0.78) / 0.22).clamp(0.0, 1.0) : 1.0;

      // DÖNME: çipin yatay yarıçapı daralıp genişler — üç boyutlu dönüş
      // hissi, üç boyutlu çizim yapmadan. Alt sınır olmasa çip bazı karelerde
      // sıfır genişliğe inip yanıp sönüyormuş gibi görünürdü.
      final squash = math.cos(coin.swayPhase + t * math.pi * 2 * coin.spin);
      final rx = math.max(radius * squash.abs(), radius * 0.16);

      _paintCoin(canvas, Offset(x, y), rx, radius, fade);
    }
  }

  void _paintCoin(
    Canvas canvas,
    Offset center,
    double rx,
    double ry,
    double opacity,
  ) {
    final outer = Rect.fromCenter(
      center: center,
      width: rx * 2,
      height: ry * 2,
    );

    // SÖNME GRADYANIN İÇİNDE: Paint'e hem shader hem color verilseydi renk
    // yok sayılır, çipler hiç solmadan kaybolurdu.
    canvas.drawOval(
      outer,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            _faceInner.withValues(alpha: opacity),
            _face.withValues(alpha: opacity),
            _rim.withValues(alpha: opacity),
          ],
          stops: const [0.0, 0.45, 1.0],
        ).createShader(outer),
    );

    // Kenar halkası — çipi zeminden ayıran tek şey; koyu masada olmazsa
    // çipler ışık lekesine benziyor.
    canvas.drawOval(
      outer.deflate(math.min(rx, ry) * 0.06),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(ry * 0.10, 1.0)
        ..color = _rim.withValues(alpha: opacity),
    );

    // İç göbek kazıması: uzaktan bakınca "para" okunur.
    canvas.drawOval(
      Rect.fromCenter(center: center, width: rx * 1.06, height: ry * 1.06),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(ry * 0.07, 0.8)
        ..color = _engrave.withValues(alpha: opacity * 0.55),
    );

    // Parlama: sol üstte ince bir hilal. Çok incelmiş (yandan dönen) çipte
    // çizilmez — orada sadece bir ışık çizgisine dönüşürdü.
    if (rx > 2.5) {
      canvas.drawOval(
        Rect.fromCenter(
          center: center.translate(-rx * 0.22, -ry * 0.26),
          width: rx * 0.7,
          height: ry * 0.5,
        ),
        Paint()..color = _faceInner.withValues(alpha: opacity * 0.55),
      );
    }
  }

  @override
  bool shouldRepaint(_CoinRainPainter oldDelegate) =>
      oldDelegate.progress != progress || !identical(oldDelegate.coins, coins);
}
