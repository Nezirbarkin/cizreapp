import 'package:flutter/material.dart';

import '../utils/shop_contact_requirements.dart';

/// Satıcı panelinde kalıcı "Eksik bilgi" şeridi (Görev 3.7).
///
/// Kapatılamaz; telefon ve haritadan konum girilene kadar Genel Bakış'ın en
/// üstünde durur. Dokununca mağaza ayarları açılır ([onTap]).
class ShopMissingInfoBanner extends StatelessWidget {
  const ShopMissingInfoBanner({super.key, required this.missing, required this.onTap});

  final List<ShopMissingInfo> missing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (missing.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Semantics(
        button: true,
        label: 'Eksik mağaza bilgisi: ${missing.map(ShopContactRequirements.label).join(', ')}. Tamamlamak için dokun.',
        child: Material(
          color: const Color(0xFFFFF4E5),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFF59E0B)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(Icons.warning_amber_rounded, color: Color(0xFFB45309), size: 26),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Eksik mağaza bilgisi',
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Color(0xFF92400E)),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          ShopContactRequirements.bannerText(missing),
                          style: const TextStyle(fontSize: 12.5, height: 1.35, color: Color(0xFF78350F)),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final item in missing)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFDE68A),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      item == ShopMissingInfo.phone ? Icons.phone_outlined : Icons.map_outlined,
                                      size: 13,
                                      color: const Color(0xFF92400E),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      item == ShopMissingInfo.phone ? 'Telefon' : 'Harita konumu',
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF92400E),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Şimdi tamamla ›',
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Color(0xFFB45309)),
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
