import 'package:flutter/material.dart';

import 'okey_ui.dart';
import '../services/okey_sound_service.dart';

/// "SALON" tasarım dilinin ortak parçaları (2026-09-20).
///
/// [OkeyUI] renk/yazı/boşluk sabitlerini ve temel kartı/düğmeyi taşır; bu
/// dosya lobinin ve masanın paylaştığı ÖZEL parçaları taşır: çip simgesi,
/// bakiye hapı, masanın kuş bakışı, alt gezinme çubuğu. `okey_ui.dart`
/// bunları yeniden dışa aktarır — ekranlar tek import ile hepsine ulaşır.

/// Pirinç çip simgesi — çip bakiyesi ve bahis yazan her yerde aynı işaret.
class OkeyCoin extends StatelessWidget {
  final double size;

  const OkeyCoin({super.key, this.size = 18});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          center: Alignment(-0.35, -0.4),
          colors: [Color(0xFFFFE08A), Color(0xFFD89A22)],
        ),
        border: Border.all(color: const Color(0xFFB87A12), width: size * 0.1),
      ),
      child: Center(
        child: Container(
          width: size * 0.52,
          height: size * 0.52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: const Color(0x99FFECAA),
              width: size * 0.07,
            ),
          ),
        ),
      ),
    );
  }
}

/// Çip bakiyesi hapı: `[çip] 12.450 [+]`.
///
/// [onTap] verilirse "+" düğmesi görünür ve hap dokunulabilir olur (çip
/// kazanma yollarına gider). Sayı `FittedBox` ile ölçeklenir: yedi haneli
/// bakiye de hapı büyütmez.
class OkeyChipsPill extends StatelessWidget {
  final int points;
  final VoidCallback? onTap;

  /// "+" düğmesinde kırmızı nokta (ör. saatlik hediye hazır).
  final bool showDot;

  const OkeyChipsPill({
    super.key,
    required this.points,
    this.onTap,
    this.showDot = false,
  });

  /// 12450 → "12.450" (Türkçe binlik ayracı).
  static String format(int n) {
    final s = n.abs().toString();
    final b = StringBuffer(n < 0 ? '−' : '');
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
      b.write(s[i]);
    }
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    final pill = Container(
      height: 38,
      padding: EdgeInsets.fromLTRB(10, 0, onTap == null ? 12 : 5, 0),
      decoration: BoxDecoration(
        color: const Color(0x99120C09),
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: const Color(0x80E4B04C)),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const OkeyCoin(size: 20),
            const SizedBox(width: 7),
            Text(
              format(points),
              maxLines: 1,
              style: OkeyUI.display(size: 16, color: OkeyUI.chipText),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 7),
              Container(
                width: 28,
                height: 28,
                decoration: const BoxDecoration(
                  color: Color(0xFFE4B04C),
                  shape: BoxShape.circle,
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    const Icon(Icons.add, size: 17, color: OkeyUI.onGold),
                    if (showDot)
                      const Positioned(
                        right: 3,
                        top: 3,
                        child: SizedBox(
                          width: 8,
                          height: 8,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Color(0xFFD32F2F),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
    if (onTap == null) return pill;
    return Semantics(
      button: true,
      label: 'Çip bakiyesi ${format(points)}, çip kazan',
      child: GestureDetector(onTap: withOkeyTapSound(onTap), child: pill),
    );
  }
}

/// Masanın kuş bakışı: çuha daire, ceviz halka, dört koltuk noktası.
///
/// Lobideki masa kartında "kaç koltuk dolu" bilgisini bir bakışta verir;
/// sayı yazmaktan hızlı okunur. Dolu koltuk pirinç, boş koltuk içi boş halka.
class OkeySeatMini extends StatelessWidget {
  final int occupied;
  final double size;

  const OkeySeatMini({super.key, required this.occupied, this.size = 48});

  @override
  Widget build(BuildContext context) {
    final dot = size * 0.25;
    Widget seat(int i, Alignment a) {
      final filled = i < occupied;
      return Align(
        alignment: a,
        child: Container(
          width: dot,
          height: dot,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled ? const Color(0xFFE4B04C) : Colors.transparent,
            border: Border.all(
              color: filled ? const Color(0xFFE4B04C) : const Color(0x73F5EBD8),
              width: 2,
            ),
          ),
        ),
      );
    }

    return Semantics(
      label: '$occupied / 4 koltuk dolu',
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          children: [
            Center(
              child: Container(
                width: size * 0.66,
                height: size * 0.66,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF17705F),
                  border: Border.all(
                    color: const Color(0xFF5B3A22),
                    width: size * 0.06,
                  ),
                ),
              ),
            ),
            seat(0, Alignment.topCenter),
            seat(1, Alignment.centerRight),
            seat(2, Alignment.bottomCenter),
            seat(3, Alignment.centerLeft),
          ],
        ),
      ),
    );
  }
}

/// Alt gezinme çubuğunun tek öğesi.
class OkeyNavItem {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;

  const OkeyNavItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
  });
}

/// Lobinin alt gezinme çubuğu: dört öğe, seçili olan pirinç hap içinde.
///
/// Öğeler ayrı ekranları AÇAR (puan, sıralama); çubuk bir sekme kabuğu
/// değildir, bu yüzden lobinin durumu (kaydırma, filtre) geri dönüşte
/// kaybolmaz.
class OkeyBottomNav extends StatelessWidget {
  final List<OkeyNavItem> items;

  const OkeyBottomNav({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Color(0xFF0D0806),
        border: Border(top: BorderSide(color: OkeyUI.cardBorder)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              for (final it in items)
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: it.selected,
                    label: it.label,
                    child: InkWell(
                      onTap: withOkeyTapSound(it.onTap),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 52,
                            height: 28,
                            decoration: BoxDecoration(
                              color: it.selected
                                  ? const Color(0x33E4B04C)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              it.icon,
                              size: 21,
                              color: it.selected
                                  ? OkeyUI.chipText
                                  : OkeyUI.textDim,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            it.label,
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: it.selected
                                  ? FontWeight.w800
                                  : FontWeight.w700,
                              color: it.selected
                                  ? OkeyUI.chipText
                                  : OkeyUI.textDim,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
