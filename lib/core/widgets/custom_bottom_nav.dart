import 'package:flutter/material.dart';

class CustomBottomNav extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;
  final int cartItemCount;

  const CustomBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.cartItemCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {}, // Boş tap handler - boşluğa tıklamayı engeller
      child: Container(
        height: 80 + bottomPadding,
        padding: EdgeInsets.only(bottom: bottomPadding),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              // ignore: deprecated_member_use
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: Stack(
        children: [
          // Alt navigasyon butonları
          Positioned.fill(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem(
                  context: context,
                  icon: Icons.store_outlined,
                  activeIcon: Icons.store,
                  label: 'Market',
                  index: 0,
                  primaryColor: primaryColor,
                ),
                _buildNavItem(
                  context: context,
                  icon: Icons.shopping_bag_outlined,
                  activeIcon: Icons.shopping_bag,
                  label: 'Ürünler',
                  index: 1,
                  primaryColor: primaryColor,
                ),
                const SizedBox(width: 80), // Ortadaki sepet butonu için boşluk
                _buildNavItem(
                  context: context,
                  icon: Icons.public_outlined,
                  activeIcon: Icons.public,
                  label: 'Sosyal',
                  index: 3,
                  primaryColor: primaryColor,
                ),
                _buildNavItem(
                  context: context,
                  icon: Icons.person_outline,
                  activeIcon: Icons.person,
                  label: 'Profil',
                  index: 4,
                  primaryColor: primaryColor,
                ),
              ],
            ),
          ),
          
          // Ortadaki yükseltilmiş sepet butonu
          Positioned(
            left: MediaQuery.of(context).size.width / 2 - 32,
            top: -10,
            child: GestureDetector(
              onTap: () => onTap(2),
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: primaryColor,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      // ignore: deprecated_member_use
                      color: primaryColor.withOpacity(0.4),
                      blurRadius: 15,
                      offset: const Offset(0, 8),
                    ),
                  ],
                  border: Border.all(
                    color: const Color(0xFFF5F7FA),
                    width: 4,
                  ),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(
                      currentIndex == 2
                          ? Icons.shopping_cart
                          : Icons.shopping_cart_outlined,
                      color: Colors.white,
                      size: 28,
                    ),
                    if (cartItemCount > 0)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF3D00),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(0xFFF5F7FA),
                              width: 2,
                            ),
                          ),
                          constraints: const BoxConstraints(
                            minWidth: 18,
                            minHeight: 18,
                          ),
                          child: Text(
                            cartItemCount > 9 ? '9+' : '$cartItemCount',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
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
    );
  }

  Widget _buildNavItem({
    required BuildContext context,
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required int index,
    required Color primaryColor,
  }) {
    final isActive = currentIndex == index;
    
    return GestureDetector(
      onTap: () => onTap(index),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isActive
                    // ignore: deprecated_member_use
                    ? primaryColor.withOpacity(0.1)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                isActive ? activeIcon : icon,
                color: isActive ? primaryColor : Colors.grey.shade400,
                size: 24,
              ),
            ),
            const SizedBox(height: 4),
            // Label'ı kaldırdık, sadece ikonlar
          ],
        ),
      ),
    );
  }
}
