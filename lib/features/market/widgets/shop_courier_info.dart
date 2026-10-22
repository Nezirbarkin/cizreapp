import 'package:flutter/material.dart';

import 'shop_card.dart' show shopCourierLabel;

/// Dükkan sayfasında "Teslimatı kim yapıyor?" şeridi: dükkanın kendi kuryesi
/// mi, CizreApp (platform) kuryesi mi. Dokununca kısa açıklama açılır.
class ShopCourierInfoStrip extends StatelessWidget {
  const ShopCourierInfoStrip({
    super.key,
    required this.ownCourier,
    required this.shopName,
    this.pickupEnabled = false,
  });

  final bool ownCourier;
  final String shopName;
  final bool pickupEnabled;

  MaterialColor get _color => ownCourier ? Colors.teal : Colors.indigo;

  IconData get _icon =>
      ownCourier ? Icons.two_wheeler_rounded : Icons.verified_user_rounded;

  String get _headline => ownCourier
      ? 'Bu dükkan siparişleri kendi kuryesiyle teslim ediyor'
      : 'Siparişin CizreApp kuryesiyle teslim edilir';

  void _showDetails(BuildContext context) {
    final points = ownCourier
        ? <(IconData, String)>[
            (Icons.two_wheeler_rounded, 'Siparişini $shopName\'nin kendi kuryesi getirir.'),
            (Icons.payments_outlined, 'Teslimat ücreti ve tahmini süre dükkan tarafından belirlenir.'),
            (Icons.notifications_active_outlined, 'Sipariş yola çıkınca bildirim alırsın.'),
          ]
        : <(IconData, String)>[
            (Icons.verified_user_rounded, 'Siparişini evrakları onaylanmış CizreApp kuryeleri getirir.'),
            (Icons.inventory_2_outlined, 'Dükkan siparişi hazırlayınca kurye dükkandan teslim alır.'),
            (Icons.notifications_active_outlined, 'Kurye yola çıkınca bildirim alırsın.'),
          ];

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _color.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(_icon, color: _color.shade700),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      shopCourierLabel(ownCourier),
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              for (final p in points)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(p.$1, size: 20, color: Colors.grey.shade700),
                      const SizedBox(width: 10),
                      Expanded(child: Text(p.$2, style: const TextStyle(height: 1.35))),
                    ],
                  ),
                ),
              if (pickupEnabled)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '🏪 İstersen "Gel Al" ile kurye beklemeden mağazadan da teslim alabilirsin.',
                    style: TextStyle(color: Colors.blue.shade800, fontSize: 13),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _color.shade50,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _showDetails(context),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _color.shade100),
          ),
          child: Row(
            children: [
              Icon(_icon, size: 18, color: _color.shade700),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _headline,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: _color.shade800,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(Icons.info_outline_rounded, size: 18, color: _color.shade400),
            ],
          ),
        ),
      ),
    );
  }
}
