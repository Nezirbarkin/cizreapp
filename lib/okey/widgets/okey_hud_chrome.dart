/// Masanın ÜST ŞERİDİNDEKİ ve kenarlarındaki kabuk parçaları: altın sayacı,
/// bonus/mağaza düğmeleri, yuvarlak ikon düğmeleri, skor balonu ve hediye
/// çipi.
///
/// ## Neden ayrı bir dosya
///
/// Bunların hiçbiri oyun kuralı bilmez; hepsi SAF GÖRSEL kabuktur. Oyun
/// masasının yerleşimi ([OkeyTableScaffold]) ve ekranı zaten yeterince
/// kalabalık — bu parçalar orada tanımlansaydı, bir düğmenin köşe yarıçapını
/// değiştirmek 1100 satırlık ekran dosyasını açmayı gerektirirdi.
///
/// ## Ortak dil
///
/// Referans masadaki her kabuk parçası aynı üç şeyi paylaşır:
///  1. Koyu, neredeyse siyah gövde (zemin ne olursa olsun okunur kalsın).
///  2. İnce açık bir kenar çizgisi (parçayı zeminden "kaldıran" ışık).
///  3. Altında dar ve koyu bir temas gölgesi.
/// Bu üçü [_HudSurface] içinde bir kez yazılır; her parça onu kullanır.
library;

import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// ORTAK YÜZEY
// ---------------------------------------------------------------------------

/// HUD parçalarının ortak koyu gövdesi.
class _HudSurface extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final List<Color>? gradient;
  final Color? borderColor;
  final VoidCallback? onTap;

  const _HudSurface({
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    this.radius = 9,
    this.gradient,
    this.borderColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final body = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: gradient == null ? const Color(0xF00A2733) : null,
        gradient: gradient == null
            ? null
            : LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: gradient!,
              ),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: borderColor ?? const Color(0x3DFFFFFF),
          width: 1.1,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x73000000),
            blurRadius: 5,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );

    if (onTap == null) return body;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: body,
    );
  }
}

// ---------------------------------------------------------------------------
// ALTIN SAYACI
// ---------------------------------------------------------------------------

/// Sol üstteki altın/puan sayacı: yığılmış paralar + biçimlenmiş sayı.
class OkeyCoinPill extends StatelessWidget {
  final int amount;
  final double height;
  final VoidCallback? onTap;

  const OkeyCoinPill({
    super.key,
    required this.amount,
    this.height = 26,
    this.onTap,
  });

  /// "4500" -> "4.500". Türkçe binlik ayırıcı NOKTADIR; `intl` paketini bu
  /// tek biçimlendirme için masaya taşımak gereksiz bir bağımlılık olurdu.
  static String format(int v) {
    final s = v.abs().toString();
    final b = StringBuffer(v < 0 ? '-' : '');
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
      b.write(s[i]);
    }
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    return MediaQuery.withNoTextScaling(
      child: _HudSurface(
        onTap: onTap,
        radius: height * 0.34,
        padding: EdgeInsets.symmetric(
          horizontal: height * 0.24,
          vertical: height * 0.12,
        ),
        borderColor: const Color(0x52FFD976),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: height * 0.82,
              height: height * 0.62,
              child: const CustomPaint(painter: _CoinStackPainter()),
            ),
            SizedBox(width: height * 0.24),
            Text(
              format(amount),
              maxLines: 1,
              style: TextStyle(
                fontSize: height * 0.46,
                height: 1.0,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.3,
                color: const Color(0xFFFFF6E0),
                shadows: const [
                  Shadow(color: Color(0xCC000000), offset: Offset(0, 1)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Üst üste binmiş üç altın para. Işık yukarıdan-soldan.
class _CoinStackPainter extends CustomPainter {
  const _CoinStackPainter();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final r = size.height * 0.30;
    final cx = size.width * 0.5;

    for (var i = 2; i >= 0; i--) {
      final cy = size.height * 0.72 - i * size.height * 0.20;
      final rect = Rect.fromCenter(
        center: Offset(cx, cy),
        width: r * 2.2,
        height: r * 1.55,
      );
      canvas.drawOval(
        rect,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFFE9A0), Color(0xFFE2A21C)],
          ).createShader(rect),
      );
      canvas.drawOval(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.9
          ..color = const Color(0xFF8A5A0C),
      );
    }
  }

  @override
  bool shouldRepaint(_CoinStackPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// AKSİYON DÜĞMELERİ (bonus / mağaza)
// ---------------------------------------------------------------------------

/// Üst şeritteki renkli düğme: solda bir ikon, sağında etiket.
///
/// Yeşil = "sana bir şey VERİYORUM" (saatlik bonus), altın = "buradan satın
/// alırsın". Renk anlam taşır; ikisi de aynı gövdeyi kullanır ki masadaki
/// diğer kontrollerle aynı malzemeden görünsünler.
class OkeyHudActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final List<Color> gradient;
  final Color textColor;
  final double height;
  final bool enabled;
  final VoidCallback? onTap;

  const OkeyHudActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.gradient,
    required this.height,
    this.textColor = Colors.white,
    this.enabled = true,
    this.onTap,
  });

  /// Saatlik hediye — referanstaki yeşil "Bonus Al".
  factory OkeyHudActionButton.bonus({
    required String label,
    required double height,
    required bool enabled,
    VoidCallback? onTap,
  }) => OkeyHudActionButton(
    label: label,
    icon: Icons.card_giftcard,
    height: height,
    enabled: enabled,
    onTap: onTap,
    gradient: enabled
        ? const [Color(0xFF6FE05A), Color(0xFF1F9A2E)]
        : const [Color(0xFF3A5560), Color(0xFF22323A)],
    textColor: enabled ? const Color(0xFF08300F) : const Color(0x8AFFFFFF),
  );

  @override
  Widget build(BuildContext context) {
    return MediaQuery.withNoTextScaling(
      child: SizedBox(
        height: height,
        child: _HudSurface(
          onTap: enabled ? onTap : null,
          radius: height * 0.28,
          gradient: gradient,
          borderColor: const Color(0x66FFFFFF),
          padding: EdgeInsets.symmetric(horizontal: height * 0.30),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: height * 0.52, color: textColor),
                  SizedBox(width: height * 0.20),
                  Text(
                    label,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: height * 0.40,
                      height: 1.0,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.4,
                      color: textColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// YUVARLAK İKON DÜĞMESİ
// ---------------------------------------------------------------------------

/// Sağ üstteki kare-yuvarlak ikon düğmesi (sohbet, menü, ses...).
class OkeyRoundIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final double size;
  final Color? accent;
  final VoidCallback onTap;

  const OkeyRoundIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.size = 30,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: size,
        height: size,
        child: _HudSurface(
          onTap: onTap,
          radius: size * 0.30,
          padding: EdgeInsets.zero,
          gradient: const [Color(0xFF1E6C8C), Color(0xFF0D3B50)],
          borderColor: const Color(0x59FFFFFF),
          child: Center(
            child: Icon(
              icon,
              size: size * 0.55,
              color: accent ?? const Color(0xFFEFF8FB),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// SKOR BALONU
// ---------------------------------------------------------------------------

/// Kendi kartımın yanındaki skor balonu — altına doğru bir sivri uç taşır.
///
/// Sivri uç kozmetik değil: balonun HANGİ karta ait olduğunu söyler. Yalnız
/// bir sayı, masadaki dört sayaçtan biriyle karıştırılabilirdi.
class OkeyScoreBubble extends StatelessWidget {
  final int score;

  /// BU ELDE biriken, henüz skora yazılmamış ceza (işlek taş atma, okey
  /// atma, kullanılmayan yandan çekme — RULES.md §7/§8).
  ///
  /// ## Neden balonun İÇİNDE, ayrı bir rozette değil
  ///
  /// Aynı büyüklüğün iki parçası: biri kesinleşmiş skor, diğeri bu el
  /// sonunda ona eklenecek olan. Ayrı bir rozete konsaydı konsolda üçüncü
  /// bir sayı olur ve "hangisi benim skorum" sorusu doğardı. `44 +101`
  /// biçimi ise tek bir cümle gibi okunur.
  final int pendingPenalty;

  final double height;

  const OkeyScoreBubble({
    super.key,
    required this.score,
    this.pendingPenalty = 0,
    this.height = 24,
  });

  @override
  Widget build(BuildContext context) {
    return MediaQuery.withNoTextScaling(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: height,
            constraints: BoxConstraints(minWidth: height * 1.9),
            alignment: Alignment.center,
            padding: EdgeInsets.symmetric(horizontal: height * 0.34),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF2C6FA8), Color(0xFF13324F)],
              ),
              borderRadius: BorderRadius.circular(height * 0.42),
              border: Border.all(color: const Color(0x8AA9D8F5), width: 1.2),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x73000000),
                  blurRadius: 5,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  '$score',
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: height * 0.52,
                    height: 1.0,
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFFF2FAFF),
                  ),
                ),
                // CEZA ANINDA GÖRÜNÜR. El sonuna kadar saklansaydı oyuncu
                // +101'lik hatayı ancak düzeltemeyeceği anda öğrenirdi.
                if (pendingPenalty > 0) ...[
                  SizedBox(width: height * 0.16),
                  Text(
                    '+$pendingPenalty',
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: height * 0.40,
                      height: 1.0,
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFFFF8A80),
                    ),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(
            width: height * 0.46,
            height: height * 0.24,
            child: const CustomPaint(painter: _BubbleTailPainter()),
          ),
        ],
      ),
    );
  }
}

class _BubbleTailPainter extends CustomPainter {
  const _BubbleTailPainter();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = const Color(0xFF1B4368));
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..color = const Color(0x8AA9D8F5),
    );
  }

  @override
  bool shouldRepaint(_BubbleTailPainter oldDelegate) => false;
}

// ---------------------------------------------------------------------------
// ANLIK PER PUANI
// ---------------------------------------------------------------------------

/// Bir koltuğun BU ELDEKİ açık puanı — arttığı anda kısa bir parlama.
///
/// ## Neden animasyon
///
/// Bu sayı yalnızca bir HAMLENİN sonucunda değişir: oyuncu per açtı ya da
/// masadaki bir pere taş işledi. Kullanıcının istediği de tam olarak buydu
/// ("oyuncu işlek attığında puanına göster"). Sessizce değişen bir sayı,
/// masada dört levha varken fark edilmez; kısa bir büyüme + parlama, hangi
/// oyuncunun az önce puan aldığını söyler.
///
/// AZALIŞ animasyonlu değildir: puan yalnızca artar, bir azalma ancak yeni
/// bir elin başlaması demektir ve orada kutlanacak bir şey yoktur.
class OkeyOpenPointsText extends StatefulWidget {
  final int points;
  final double fontSize;
  final Color color;

  const OkeyOpenPointsText({
    super.key,
    required this.points,
    required this.color,
    this.fontSize = 10,
  });

  @override
  State<OkeyOpenPointsText> createState() => _OkeyOpenPointsTextState();
}

class _OkeyOpenPointsTextState extends State<OkeyOpenPointsText>
    with SingleTickerProviderStateMixin {
  // Saf AnimationController (flutter_animate DEĞİL): tek seferlik forward,
  // dispose'ta Ticker temiz kapanır — pumpAndSettle kullanan widget
  // testlerinde asılı kalan bir zamanlayıcı bırakmaz.
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );

  @override
  void didUpdateWidget(covariant OkeyOpenPointsText old) {
    super.didUpdateWidget(old);
    if (widget.points > old.points) _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Text(
      '${widget.points}',
      maxLines: 1,
      style: TextStyle(
        fontSize: widget.fontSize,
        height: 1.0,
        fontWeight: FontWeight.w900,
        color: widget.color,
      ),
    );

    return AnimatedBuilder(
      animation: _controller,
      child: text,
      builder: (context, child) {
        // 0 -> 1 -> 0 arasında gidip gelen bir vurgu payı.
        final t = _controller.value;
        final pop = t == 0 ? 0.0 : (t < 0.35 ? t / 0.35 : (1 - t) / 0.65);
        return Transform.scale(
          scale: 1 + 0.5 * pop,
          child: DecoratedBox(
            decoration: BoxDecoration(
              boxShadow: pop == 0
                  ? const []
                  : [
                      BoxShadow(
                        color: widget.color.withValues(alpha: 0.55 * pop),
                        blurRadius: 10 * pop,
                      ),
                    ],
            ),
            child: child,
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// MASA PUANI
// ---------------------------------------------------------------------------

/// Üst şeritteki MASA PUANI çipi: `MASA 1.500` ve altında `500 × 3 el`.
///
/// ## Neden çarpımı da yazıyor
///
/// Masa puanı artık el sayısıyla ÇARPILIYOR (kullanıcı isteği, 2026-09-05).
/// Yalnız sonucu göstermek, oyuncunun cüzdanından neden 1.500 düştüğünü
/// açıklamaz — üstelik lobide "500 puan" yazan bir masaya girip 1.500
/// ödemek, hata gibi okunur. Çarpanı yanına yazmak bu soruyu baştan siler.
class OkeyStakePill extends StatelessWidget {
  /// Toplam masa puanı (el başına puan × el sayısı).
  final int stake;

  /// El başına puan — çarpımı yazabilmek için.
  final int perHand;

  /// Oynanacak el sayısı.
  final int hands;

  final double height;
  final VoidCallback? onTap;

  const OkeyStakePill({
    super.key,
    required this.stake,
    required this.perHand,
    required this.hands,
    this.height = 26,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MediaQuery.withNoTextScaling(
      child: _HudSurface(
        onTap: onTap,
        radius: height * 0.30,
        padding: EdgeInsets.symmetric(
          horizontal: height * 0.26,
          vertical: height * 0.10,
        ),
        borderColor: const Color(0x669BE87C),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.savings,
              size: height * 0.46,
              color: const Color(0xFF9BE87C),
            ),
            SizedBox(width: height * 0.20),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'MASA ${OkeyCoinPill.format(stake)}',
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: height * 0.38,
                    height: 1.0,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.3,
                    color: const Color(0xFFEAF6FA),
                  ),
                ),
                SizedBox(height: height * 0.08),
                Text(
                  '${OkeyCoinPill.format(perHand)} × $hands el',
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: height * 0.26,
                    height: 1.0,
                    fontWeight: FontWeight.w600,
                    color: const Color(0x99FFFFFF),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
