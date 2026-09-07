import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Istakanın hemen ÜSTÜNDEKİ ince süre çizgisi.
///
/// Sıra süresi ilerledikçe çizgi kısalır; son saniyelerde kırmızıya döner.
/// Sıra bende değilken soluk gri kalır.
///
/// PERFORMANS NOTU: Bu widget, saniyede bir güncellenen [secondsLeft]
/// değerini bir [ValueListenableBuilder] üzerinden alır. Provider'ın
/// notifyListeners()'ı BİLEREK kullanılmaz — saniyede bir tüm masayı
/// (sürüklenebilir taşlar ve DragTarget'lar dahil) yeniden kurmak, aktif bir
/// sürükleme sırasında Flutter'ın Element ağacını bozan bir çökmeye yol
/// açıyordu.
class OkeyTurnTimerBar extends StatelessWidget {
  final ValueListenable<int> secondsLeftListenable;

  /// Sıranın toplam süresi (saniye) — admin panelinden ayarlanır.
  final int totalSeconds;

  final bool isMyTurn;

  /// Çizginin kalınlığı.
  final double height;

  const OkeyTurnTimerBar({
    super.key,
    required this.secondsLeftListenable,
    required this.totalSeconds,
    required this.isMyTurn,
    this.height = 5,
  });

  @override
  Widget build(BuildContext context) {
    // REPAINT SINIRI — süre çizgisi saniyede bir (ve AnimatedContainer
    // yüzünden 350 ms boyunca her karede) kendini yeniden çizer. Sınırsız
    // halde bu, çizginin bulunduğu katmanı — ıstakayı ve masayı — her
    // saniye yeniden boyamaya zorluyordu.
    return RepaintBoundary(
      child: ValueListenableBuilder<int>(
        valueListenable: secondsLeftListenable,
        builder: (context, secondsLeft, _) {
          final total = totalSeconds <= 0 ? 1 : totalSeconds;
          final ratio = (secondsLeft / total).clamp(0.0, 1.0);

          final Color color;
          if (!isMyTurn) {
            color = Colors.white24;
          } else if (secondsLeft <= 5) {
            color = const Color(0xFFE53935); // son saniyeler: kırmızı
          } else if (ratio < 0.4) {
            color = const Color(0xFFFFA000); // yarıdan az: turuncu
          } else {
            color = const Color(0xFF43A047); // bol süre: yeşil
          }

          // Son saniyelerde kırmızıya dönüp parlaklığı artan gölge zaten bir
          // aciliyet hissi veriyor (bkz. yukarıdaki renk seçimi). Ayrıca
          // sonsuz döngülü bir nabız denendi ama flutter_animate paketinin iç
          // Timer'ı, bu widget'ı tek bir pump ile kurup hemen bırakan
          // testlerde "Timer is still pending" hatasına yol açtı — bu yüzden
          // saf Flutter'ın kendi AnimatedContainer'ıyla (aşağıda) yetinildi.
          return SizedBox(
            height: height,
            child: Stack(
              children: [
                // Zemin (tükenen kısım)
                Positioned.fill(
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.35),
                  ),
                ),
                // Kalan süre — genişliği oranla birlikte kısalır
                FractionallySizedBox(
                  widthFactor: ratio,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 350),
                    decoration: BoxDecoration(
                      color: color,
                      boxShadow: [
                        BoxShadow(
                          color: color.withValues(alpha: 0.6),
                          blurRadius: isMyTurn && secondsLeft <= 5 ? 8 : 4,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
