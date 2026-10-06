import 'package:flutter/material.dart';

import 'seller_menu.dart';

/// Satıcı panelinin "Diğer" sekmesi — satıcı menüsü (Görev 2.4).
///
/// Eski yan menünün (Drawer) Genel Bakış/Ürünler/Siparişler/Ödemeler dışındaki
/// öğeleri burada, yeni tasarımla ([SellerMenu]) durur; aynı menü panelin
/// sağdan açılan yan menüsünde de gösterilir. Öğeler bu sekmenin iç
/// Navigator'ında açılır (alt bar görünür kalır). Dönüşte tazeleme davranışı
/// eski Drawer'la birebir aynıdır (ör. Kuponlar/İade/Yorumlar/Mağaza
/// Ayarları tazeler; SMM/Dijital/Flash Satış/Canlı Yayın tazelemez).
class SellerMoreTab extends StatelessWidget {
  const SellerMoreTab({
    super.key,
    required this.shopInfo,
    required this.onManageCategories,
    required this.onReturnRefresh,
    this.isAcceptingOrders = true,
  });

  /// Sekme kurulurken bilinen değerler; panel [SellerPanelInfo] veriyorsa
  /// onun CANLI değerleri kullanılır (iç yığındaki sayfa yeniden kurulmaz).
  final Map<String, dynamic>? shopInfo;
  final bool isAcceptingOrders;
  final VoidCallback onManageCategories;
  final VoidCallback onReturnRefresh;

  @override
  Widget build(BuildContext context) {
    final live = SellerPanelInfo.maybeOf(context);
    final shop = live?.shopInfo ?? shopInfo;
    return ColoredBox(
      color: const Color(0xFFF6F5FA),
      child: SellerMenu(
        shopInfo: shop,
        isAcceptingOrders: live?.isAcceptingOrders ?? isAcceptingOrders,
        content: SellerMenuContent.forShop(
          shopInfo: shop,
          onManageCategories: onManageCategories,
        ),
        onOpen: (menuContext, entry) => openSellerMenuEntry(
          context: menuContext,
          navigator: Navigator.of(menuContext),
          entry: entry,
          onReturnRefresh: onReturnRefresh,
        ),
      ),
    );
  }
}
