import 'package:flutter/material.dart';

import '../theme/okey_ui.dart';
import 'okey_turn_ring.dart';

/// "AÇ" düğmesine dokununca açılan SEÇİM KARTI: seri mi, çift mi.
///
/// ## Neden iki ayrı düğme yerine tek düğme + kart
///
/// v4'te masada SERİ AÇ ve ÇİFT AÇ ayrı iki düğmeydi ve ikisi de konsolun
/// dörtte birini kaplıyordu. Oysa:
///
///  * İkisi **aynı anda asla** yapılamaz — seriyle açan çiftle açamaz, tersi
///    de doğru. Yani masada her zaman en az biri ölü duruyordu.
///  * Elde **bir kez** yapılır. Her turda görünen bir düğmenin, elde yalnızca
///    bir kez basılacak bir hamleyi taşıması, dock'un en kıt kaynağını
///    (parmağa yakın yüzey) boşa harcıyordu.
///
/// Tek "AÇ" düğmesi, hangisinin hazır olduğunu rozetiyle söyler; kart ise
/// ikisini YAN YANA, sayılarıyla gösterir. Oyuncu ilk kez "seriyle mi çiftle
/// mi açsam" sorusunu iki rakamı karşılaştırarak yanıtlayabiliyor.
///
/// ## Kapalıyken de açılır
///
/// Baraj geçilmemişken de kart açılabilir; o zaman iki seçenek de sönüktür
/// ve üstte ölçer "ne kadar kaldı"yı gösterir. "Neden açamıyorum" sorusunun
/// cevabı, düğmenin kendisindedir.
abstract final class OkeyOpenSheet {
  static Future<void> show(
    BuildContext context, {
    required bool seriesReady,
    required String seriesBadge,
    required String? seriesBlockedReason,
    required VoidCallback onSeries,
    required bool pairsReady,
    required String pairsBadge,
    required String? pairsBlockedReason,
    required VoidCallback onPairs,
    required int points,
    required int requiredPoints,
    required bool isOpen,
  }) {
    return showDialog<void>(
      context: context,
      barrierColor: const Color(0xB3060402),
      builder: (context) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: OkeyUI.cardFillRaised,
                borderRadius: BorderRadius.circular(OkeyUI.radiusLg),
                border: Border.all(color: const Color(0x57E4B04C)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0xBF000000),
                    blurRadius: 30,
                    offset: Offset(0, 14),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Text('ELİ AÇ', style: OkeyUI.sectionLabel),
                      const Spacer(),
                      // Kapatma: ikon düğmesi, dokunma hedefi 40x40.
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => Navigator.of(context).pop(),
                        child: const SizedBox(
                          width: 40,
                          height: 40,
                          child: Icon(
                            Icons.close_rounded,
                            size: 20,
                            color: OkeyUI.textDim,
                          ),
                        ),
                      ),
                    ],
                  ),
                  // BARAJ ÖLÇERİ — iki seçeneğin de ORTAK koşulu. Kartın en
                  // üstünde durur çünkü ikisi de ona bağlıdır.
                  if (!isOpen) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('$points', style: OkeyUI.display(size: 26)),
                        const SizedBox(width: 5),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: Text(
                            '/ $requiredPoints puan',
                            style: OkeyUI.caption,
                          ),
                        ),
                        const Spacer(),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: Text(
                            points >= requiredPoints
                                ? 'Baraj geçildi'
                                : '${requiredPoints - points} puan kaldı',
                            style: OkeyUI.caption.copyWith(
                              color: OkeyUI.brass,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: OkeyUI.gapSm),
                    OkeyBarajMeter(
                      points: points,
                      required: requiredPoints,
                      isOpen: false,
                      height: 8,
                    ),
                    const SizedBox(height: OkeyUI.gapLg),
                  ] else
                    const SizedBox(height: OkeyUI.gapSm),
                  // IntrinsicHeight ŞART: bu Column bir SingleChildScrollView
                  // içinde, yani yükseklik SINIRSIZ. `stretch` sınırsız
                  // yükseklikte çocuklara minHeight=∞ verir ("BoxConstraints
                  // forces an infinite height" + "RenderBox was not laid out")
                  // ve kart hiç çizilmezdi. İki seçenek yine eşit boyda kalır.
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: _OpenChoice(
                            title: 'SERİ AÇ',
                            hint: 'Sıralı ve gruplu perlerle',
                            badge: seriesBadge,
                            icon: Icons.view_week_rounded,
                            ready: seriesReady,
                            blockedReason: seriesBlockedReason,
                            onPressed: () {
                              Navigator.of(context).pop();
                              onSeries();
                            },
                          ),
                        ),
                        const SizedBox(width: OkeyUI.gap),
                        Expanded(
                          child: _OpenChoice(
                            title: 'ÇİFT AÇ',
                            hint: 'Sadece çiftlerle',
                            badge: pairsBadge,
                            icon: Icons.filter_2_rounded,
                            ready: pairsReady,
                            blockedReason: pairsBlockedReason,
                            onPressed: () {
                              Navigator.of(context).pop();
                              onPairs();
                            },
                          ),
                        ),
                      ],
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

/// Karttaki iki seçenekten biri. Kapalıyken KAYBOLMAZ, söner ve altında
/// sebebini yazar.
class _OpenChoice extends StatelessWidget {
  final String title;
  final String hint;
  final String badge;
  final IconData icon;
  final bool ready;
  final String? blockedReason;
  final VoidCallback onPressed;

  const _OpenChoice({
    required this.title,
    required this.hint,
    required this.badge,
    required this.icon,
    required this.ready,
    required this.blockedReason,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final fg = ready ? OkeyUI.onGold : OkeyUI.text;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: ready ? onPressed : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        decoration: BoxDecoration(
          color: ready ? null : OkeyUI.cardFill,
          gradient: ready
              ? const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: OkeyUI.goldGradient,
                )
              : null,
          borderRadius: BorderRadius.circular(OkeyUI.radius),
          border: Border.all(
            color: ready ? const Color(0x00000000) : OkeyUI.cardBorder,
          ),
          boxShadow: ready
              ? const [
                  BoxShadow(color: Color(0xFF9A6A17), offset: Offset(0, 3)),
                ]
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: ready ? fg : OkeyUI.brass),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.1,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.4,
                      color: fg,
                    ),
                  ),
                ),
                Text(
                  badge,
                  style: OkeyUI.display(
                    size: 14,
                    color: ready ? fg : OkeyUI.chipText,
                  ),
                ),
              ],
            ),
            const SizedBox(height: OkeyUI.gapXs),
            Text(
              ready ? hint : (blockedReason ?? hint),
              maxLines: 3,
              style: OkeyUI.caption.copyWith(
                color: ready ? fg.withValues(alpha: 0.78) : OkeyUI.textFaint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
