import 'package:flutter/material.dart';

/// 101 Okey admin panelinde paylaşılan küçük görsel bileşenler.
///
/// Dashboard'un geri kalanıyla aynı görsel dili kurmak için:
/// `_part_users.dart`'taki gradyanlı istatistik kartı ve rozet/chip
/// deseniyle eşleşen genel (public) eşdeğerler. O dosyadaki yardımcılar
/// `_` ile private olduğu için buradan import edilemiyor; bu yüzden aynı
/// görünümde yeniden, ama Okey modülü içinde herkese açık olarak yazıldı.

/// Gradyanlı KPI/istatistik kartı — ikon + etiket + değer.
///
/// [onTap] verilirse kart tıklanabilir olur (ör. filtre uygulamak için).
class OkeyStatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final List<Color> gradient;
  final VoidCallback? onTap;

  const OkeyStatCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.gradient,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          constraints: const BoxConstraints(minWidth: 120),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: gradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: gradient.last.withValues(alpha: 0.35),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(icon, color: Colors.white, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // DEĞER KIRPILMAZ, KÜÇÜLÜR.
              //
              // Eskiden `ellipsis` vardı: yedi haneli bir toplam kazanç
              // "1234…" diye kesiliyordu — yani kart, göstermek için var
              // olduğu sayıyı okunamaz hale getiriyordu. FittedBox ile sayı
              // kutuya sığacak kadar küçülür ama TAM görünür.
              SizedBox(
                width: double.infinity,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    maxLines: 1,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
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

/// Küçük renkli rozet/etiket: ikon + kısa metin.
///
/// `_part_users.dart`'taki `_statChip`/`_buildRoleBadge` desenine karşılık
/// gelir: %8-10 opaklıkta dolgu, %20-30 opaklıkta kenarlık.
class OkeyBadgeChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const OkeyBadgeChip({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          // Flexible + ellipsis: rozet bir `Row` içine konduğunda uzun bir
          // etiket (ör. bot adı) satırı taşırıyordu. `mainAxisSize.min`
          // taşmayı ÖNLEMEZ — yalnızca rozetin doğal genişliğini alır.
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Admin sekmelerinde tekrar eden BAŞLIKLI KART.
///
/// Ayarlar sekmesi bunun bir kopyasını kendi içinde tutuyordu; puanlar ve
/// botlar sekmeleri ise hiç kullanmıyor, her bölümü elle kuruyordu. Tek
/// yerden gelince üç sekme de aynı görünür.
class OkeyAdminSection extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final List<Widget> children;
  final Widget? trailing;

  const OkeyAdminSection({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.children,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                // Başlık ESNER: uzun bir başlık + sağdaki aksiyon birlikte
                // satırı taşırabilirdi.
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.bold, color: color),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// İstatistik kartları şeridi — SARMALI değil, YATAY KAYDIRMALI.
///
/// `Wrap` ile beş kart dar bir ekranda üç satıra iniyor ve sekmenin üstünü
/// yiyordu; kaydırma yüksekliği SABİT tutar ve hiçbir kart gizlenmez.
class OkeyStatStrip extends StatelessWidget {
  final List<Widget> cards;

  const OkeyStatStrip({super.key, required this.cards});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 76,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        itemCount: cards.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, i) => cards[i],
      ),
    );
  }
}
