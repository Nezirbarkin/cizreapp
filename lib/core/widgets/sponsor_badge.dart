import 'package:flutter/material.dart';

/// Ürün kartı görselinin köşesindeki küçük amber "Sponsor" rozeti.
///
/// Uygulamanın geri kalanındaki (hikâye, Ürünler sayfası, dükkan kartı
/// şeridi) amber "Sponsor" diliyle aynı. Admin sabitlemesi ve ücretli öne
/// çıkarma (Görev 3.2) aynı rozetle gösterilir.
class SponsorBadge extends StatelessWidget {
  const SponsorBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Sponsorlu',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.amber.shade700,
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.star_rounded, size: 10, color: Colors.white),
            SizedBox(width: 2),
            Text(
              'Sponsor',
              style: TextStyle(
                color: Colors.white,
                fontSize: 8.5,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
