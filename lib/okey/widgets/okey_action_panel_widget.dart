import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../services/okey_sound_service.dart';

import '../theme/okey_rack_style.dart';
import '../theme/okey_theme.dart';

/// HUD ikon düğmesinin gövdesi: cam yüzey + kenar + gölge + tık sesi.
///
/// ## Neden hâlâ ayrı bir sınıf, tek çağıranı kalmışken
///
/// v2–v4'te masadaki BÜTÜN düğmeler (aksiyonlar, DİZ, HUD) buradan
/// çıkıyordu; ortak gövde, üç ayrı görsel dilin aynı şeritte yan yana
/// durmasını bitirmişti. v5'te hamle düğmeleri dikey dock'a taşındı ve
/// kendi gövdelerini aldılar ([OkeyActionDock]), DİZ başlığı ise ıstakanın
/// ahşabına boyandı ([OkeyDizCapButton]). Geriye tek çağıran kaldı:
/// [OkeyHudIconButton].
///
/// Gövde yine de ayrı duruyor çünkü taşıdığı şey biçim değil DAVRANIŞ:
/// dokunma geri bildirimi (Material + InkWell) ve tık sesi. Bunu çağıranın
/// içine gömmek, bir sonraki HUD düğmesinin sessiz çıkmasına davetiye olurdu.
class _Control extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double radius;
  final EdgeInsets padding;

  const _Control({
    required this.child,
    this.onTap,
    this.radius = OkeyV3.radius,
    this.padding = const EdgeInsets.symmetric(horizontal: 5),
  });

  @override
  Widget build(BuildContext context) {
    final on = onTap != null;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: on ? OkeyV3.surface : OkeyV3.surfaceDisabled,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: on ? OkeyV3.border : OkeyV3.borderDisabled),
        boxShadow: OkeyV3.lift,
      ),
      // Dokunma geri bildirimi modülün geri kalanıyla aynı: Material+InkWell.
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(radius),
        child: InkWell(
          onTap: on ? withOkeyTapSound(onTap!) : null,
          borderRadius: BorderRadius.circular(radius),
          child: Padding(
            padding: padding,
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}

/// Masanın sol üstündeki mod rozeti (Eşli / Katlamalı / Yardımlı / 3. El).
///
/// Tur boyunca DEĞİŞMEYEN referans bilgidir: küçük, sakin ve tek satır.
/// v2'de aksiyon düğmeleriyle benzer ağırlıktaydı ve gözü boşuna çekiyordu.
class OkeyModeBadge extends StatelessWidget {
  final String text;
  final Color color;

  const OkeyModeBadge({super.key, required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return MediaQuery.withNoTextScaling(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
        decoration: BoxDecoration(
          color: OkeyV3.surface,
          borderRadius: BorderRadius.circular(OkeyV3.radiusSm),
          border: Border.all(color: color.withValues(alpha: 0.38)),
        ),
        // ORTALANIR: rozetler [OkeyModeBadgeStack] içinde en uzun rozetin
        // genişliğine gerilir; içerik sola yaslı kalsaydı dört rozetin
        // metinleri düzensiz bir merdiven gibi görünürdü.
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 8.5,
                  height: 1.0,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: OkeyV3.textDim,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Mod rozetlerinin DİKEY sütunu — per alanının sağındaki bilgi sütunu.
///
/// ## Neden ayrı bir widget
///
/// Rozetler tek tek bir [Column]'a konsaydı her biri kendi metni kadar
/// genişlerdi ve sütun kenarı testere dişi gibi görünürdü. [IntrinsicWidth]
/// hepsini EN UZUN rozetin genişliğine hizalar: dört rozet tek bir blok
/// olarak okunur, referans masadaki gibi.
class OkeyModeBadgeStack extends StatelessWidget {
  /// (etiket, vurgu rengi) çiftleri — sırası oyunun sabit bilgisidir:
  /// eşleşme türü → oyun türü → yardım → kaçıncı el.
  final List<(String, Color)> items;
  final double gap;

  const OkeyModeBadgeStack({super.key, required this.items, this.gap = 3});

  @override
  Widget build(BuildContext context) {
    return IntrinsicWidth(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) SizedBox(height: gap),
            OkeyModeBadge(text: items[i].$1, color: items[i].$2),
          ],
        ],
      ),
    );
  }
}

/// Istakanın İKİ UCUNDAKİ dizme düğmesi: ÇİFT DİZ (sol) / SERİ DİZ (sağ).
///
/// ## Neden ıstakanın ucunda ve neden bu biçimde
///
/// v3'te bunlar konsolda, hamle düğmelerinin arasındaydı. Oysa dizmek bir
/// hamle değil, ISTAKAYI yeniden düzenlemektir — düğmenin düzenlediği
/// nesneye bitişik durması, ne yaptığını hiç okumadan anlatır. Referans
/// masada da tam olarak orada dururlar.
///
/// Düğmenin üstündeki minik taşlar etiketten daha hızlı okunur: iki eş taş
/// = çift, ardışık üç taş = seri. Etiket yalnızca doğrulama içindir.
class OkeyDizCapButton extends StatelessWidget {
  /// İki satıra bölünmüş etiket ("ÇİFT" / "DİZ").
  final String titleTop;
  final String titleBottom;

  /// Üstteki minik taşların üzerindeki rakamlar.
  final List<String> sampleTiles;

  /// Minik taşların rakam renkleri (sampleTiles ile aynı uzunlukta).
  final List<Color> sampleColors;

  final bool active;
  final VoidCallback onPressed;

  const OkeyDizCapButton({
    super.key,
    required this.titleTop,
    required this.titleBottom,
    required this.sampleTiles,
    required this.sampleColors,
    required this.onPressed,
    this.active = false,
  });

  /// ÇİFT DİZ — iki eş taş.
  factory OkeyDizCapButton.pairs({
    required bool active,
    required VoidCallback onPressed,
  }) => OkeyDizCapButton(
    titleTop: 'ÇİFT',
    titleBottom: 'DİZ',
    sampleTiles: const ['5', '5'],
    sampleColors: const [OkeyColors.tileRed, OkeyColors.tileRed],
    active: active,
    onPressed: onPressed,
  );

  /// SERİ DİZ — ardışık üç taş.
  factory OkeyDizCapButton.series({
    required bool active,
    required VoidCallback onPressed,
  }) => OkeyDizCapButton(
    titleTop: 'SERİ',
    titleBottom: 'DİZ',
    sampleTiles: const ['1', '2', '3'],
    sampleColors: const [
      OkeyColors.tileRed,
      OkeyColors.tileBlack,
      OkeyColors.tileBlue,
    ],
    active: active,
    onPressed: onPressed,
  );

  @override
  Widget build(BuildContext context) {
    return MediaQuery.withNoTextScaling(
      child: LayoutBuilder(
        builder: (context, c) {
          final w = c.hasBoundedWidth ? c.maxWidth : 60.0;
          final h = c.hasBoundedHeight && c.maxHeight.isFinite
              ? c.maxHeight
              : 90.0;
          final font = (w * 0.24).clamp(8.0, 15.0).toDouble();
          final tileH = (h * 0.26).clamp(10.0, 34.0).toDouble();

          // BAŞLIK ISTAKANIN KENDİ AHŞABINDANDIR (düzen v5).
          //
          // v4'te bu düğmeler parlak MAVİ bloklardı ve masadaki hiçbir
          // malzemeye benzemiyorlardı: ıstakanın ucuna vidalanmış iki
          // plastik parça gibi duruyorlardı. Oysa anlattıkları şey tam
          // tersi — bunlar ıstakanın PARÇASIDIR, bir hamle değil.
          //
          // Artık gövde ıstakanın ahşabıyla aynı, vurgu ise kazınmış pirinç.
          // Pirinç DOLGU bilerek kullanılmadı: dolu pirinç masada "hamle"
          // demek (bkz. OkeyActionDock), bu ise araç.
          final rack = OkeyRackStylePrefs.instance.current.value;
          final brass = OkeyColors.accentGold;

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: withOkeyTapSound(onPressed),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: rack.body,
                ),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: brass.withValues(alpha: active ? 0.95 : 0.4),
                  width: active ? 1.8 : 1,
                ),
                boxShadow: [
                  const BoxShadow(
                    color: Color(0x8A000000),
                    blurRadius: 6,
                    offset: Offset(0, 2),
                  ),
                  if (active)
                    BoxShadow(
                      color: brass.withValues(alpha: 0.35),
                      blurRadius: 14,
                    ),
                ],
              ),
              padding: EdgeInsets.symmetric(
                horizontal: w * 0.06,
                vertical: h * 0.06,
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _MiniTiles(
                      labels: sampleTiles,
                      colors: sampleColors,
                      height: tileH,
                    ),
                    SizedBox(height: h * 0.06),
                    Text(
                      titleTop,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: font,
                        height: 1.05,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.4,
                        // Etiket de kazınmış: pirinç, altında bir piksellik
                        // koyu gölge. Beyaz yazı ahşabın üstünde "yapıştırma"
                        // gibi duruyordu.
                        color: active ? brass : const Color(0xFFF5EBD8),
                        shadows: const [
                          Shadow(
                            color: Color(0x99000000),
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      titleBottom,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: font,
                        height: 1.05,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.4,
                        color: active ? brass : const Color(0xFFF5EBD8),
                        shadows: const [
                          Shadow(
                            color: Color(0x99000000),
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Dizme düğmesinin üstündeki minik örnek taşlar.
class _MiniTiles extends StatelessWidget {
  final List<String> labels;
  final List<Color> colors;
  final double height;

  const _MiniTiles({
    required this.labels,
    required this.colors,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    final w = height * OkeyTableMetricsTileAspect.value;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < labels.length; i++) ...[
          if (i > 0) SizedBox(width: height * 0.06),
          Container(
            width: w,
            height: height,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: OkeyColors.tileGradient,
              borderRadius: BorderRadius.circular(height * 0.14),
              border: Border.all(color: const Color(0x40000000), width: 0.6),
            ),
            child: Text(
              labels[i],
              style: TextStyle(
                fontSize: height * 0.58,
                height: 1.0,
                fontWeight: FontWeight.w900,
                color: colors[i % colors.length],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Taş oranının minik taşlar için kopyası.
///
/// [OkeyTableMetrics]'i buraya import etmek, saf bir düğme dosyasını masa
/// ölçü sözleşmesine bağlardı; oran tek bir sabit olduğu için burada
/// tekrarlanır ve testte iki değerin eşitliği doğrulanır.
abstract final class OkeyTableMetricsTileAspect {
  static const double value = 0.74;
}

/// HUD'daki kare ikon düğmesi (ses / müzik / ayarlar).
///
/// 26px'ten 32px'e büyütüldü: dokunma hedefinin altında kalan her düğme,
/// gerçek cihazda "bazen çalışmıyor" olarak yaşanır.
class OkeyHudIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  /// Dikkat çekmesi gereken düğme (ör. kapalı ses) için vurgu rengi.
  final Color? accent;

  const OkeyHudIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.accent,
  });

  static const double size = 32;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: size,
        height: size,
        child: _Control(
          onTap: onTap,
          radius: OkeyV3.radiusSm + 2,
          padding: EdgeInsets.zero,
          child: Icon(icon, size: 16, color: accent ?? OkeyV3.text),
        ),
      ),
    );
  }
}
