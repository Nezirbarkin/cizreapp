import 'package:flutter/material.dart';

/// Tek bir alt navigasyon öğesinin tanımı.
class SellerNavItem {
  const SellerNavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
}

/// Satıcı panelinin alt navigasyonu.
///
/// Yeni bir bottom-nav deseni icat etmez: uygulamanın ana kabuğu
/// (`MainScreen._buildNavItem`) ile birebir aynı görsel dili kullanır — düz
/// `BottomAppBar` (çentiksiz, satıcı panelinde merkezi bir FAB yok) + ikon
/// (seçiliyse marka rengi, değilse gri) + etiket dikey sütunu.
class SellerBottomNav extends StatelessWidget {
  const SellerBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<SellerNavItem> items;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return BottomAppBar(
      elevation: 8,
      color: Colors.white,
      child: SizedBox(
        height: 60,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            for (var i = 0; i < items.length; i++)
              _SellerNavItemWidget(
                item: items[i],
                selected: i == currentIndex,
                primaryColor: primary,
                onTap: () => onTap(i),
              ),
          ],
        ),
      ),
    );
  }
}

class _SellerNavItemWidget extends StatelessWidget {
  const _SellerNavItemWidget({
    required this.item,
    required this.selected,
    required this.primaryColor,
    required this.onTap,
  });

  final SellerNavItem item;
  final bool selected;
  final Color primaryColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              selected ? item.activeIcon : item.icon,
              color: selected ? primaryColor : Colors.grey.shade400,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              item.label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? primaryColor : Colors.grey.shade400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
