import 'package:flutter/material.dart';

/// Bir oyuncunun yaptığı BARAJIN TÜRÜ.
///
/// Sunucudan metin olarak gelir (bkz. okey_match_barajs). Tanınmayan bir
/// değer rozeti hiç göstermez: eşikler ileride değişse bile masada anlamı
/// belirsiz bir rozet belirmemeli.
enum OkeyBarajKind {
  /// Açılışta 6+ çift.
  pairs,

  /// Açılışta 151+ puanlık per.
  series;

  static OkeyBarajKind? parse(String? raw) => switch (raw?.trim()) {
    'pairs' => OkeyBarajKind.pairs,
    'series' => OkeyBarajKind.series,
    _ => null,
  };

  /// Rozetin üstündeki tek kelime.
  String get label => switch (this) {
    OkeyBarajKind.pairs => 'ÇİFT BARAJ',
    OkeyBarajKind.series => 'PER BARAJ',
  };

  /// SERİ AÇ / ÇİFT AÇ düğmeleriyle AYNI ikonlar: oyuncu barajı hangi
  /// düğmeyle yaptığını ikondan hatırlar.
  IconData get icon => switch (this) {
    OkeyBarajKind.pairs => Icons.filter_2,
    OkeyBarajKind.series => Icons.view_week,
  };
}

/// BARAJ ROZETİ — oyuncunun kimlik levhasına iliştirilen küçük altın şerit.
///
/// ## Neden gerekli (kullanıcı isteği, 2026-09-06)
///
/// Baraj ödülü el sonunda cezadan 101 (bitirene 202) düşüyordu ama masada
/// bunun hiçbir izi yoktu: oyuncu skorunun düştüğünü görüyor, NEDEN düştüğünü
/// göremiyordu. Bir kural, sonucu görünüp sebebi görünmediğinde kural değil
/// sürpriz olur.
///
/// ## Neden ALTIN ve neden bu kadar küçük
///
/// Altın, masadaki "kazanç" rengi (bkz. OkeyColors.accentGold — açık puan
/// rozeti, kupa, çip sayacı). Baraj da bir kazançtır, o aileye ait.
///
/// Küçük çünkü kimlik levhası zaten ad, avatar, sıra vurgusu, skor ve açık
/// puan taşıyor. Rozet o yığının önüne geçmemeli: elin başında bir kez
/// okunup arka plana düşen bir işaret, sürekli bağıran bir etiket değil.
class OkeyBarajBadge extends StatelessWidget {
  final OkeyBarajKind kind;

  /// Rozetin ölçüsü — dar kenar sütunlarında küçülür.
  final double size;

  const OkeyBarajBadge({super.key, required this.kind, this.size = 20});

  @override
  Widget build(BuildContext context) {
    // Emoji/yazı sistem yazı tipiyle büyümez: rozet sabit ölçülü bir levhanın
    // köşesinde duruyor, büyüyen bir yazı onu taşırırdı.
    return MediaQuery.withNoTextScaling(
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: size * 0.26,
          vertical: size * 0.13,
        ),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFFD54F), Color(0xFFE0A013)],
          ),
          borderRadius: BorderRadius.circular(size * 0.40),
          border: Border.all(color: const Color(0x73FFF3D6), width: 1),
          boxShadow: const [
            BoxShadow(
              color: Color(0x99000000),
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(kind.icon, size: size * 0.58, color: const Color(0xFF2A1C05)),
            SizedBox(width: size * 0.16),
            Text(
              kind.label,
              maxLines: 1,
              style: TextStyle(
                color: const Color(0xFF2A1C05),
                fontSize: size * 0.42,
                height: 1.0,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
