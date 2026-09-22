import 'package:flutter/material.dart';

import '../../../market/widgets/shop_card.dart';
import '../../screens/coupons_screen.dart';
import '../../screens/seller_digital_orders_screen.dart';
import '../../screens/seller_flash_sales_screen.dart';
import '../../screens/seller_return_requests_screen.dart';
import '../../screens/seller_reviews_screen.dart';
import '../../screens/shop_settings_screen.dart';
import '../../screens/smm_provider_settings_screen.dart';
import '../common/seller_section_card.dart';
import '../../../market/screens/live_host_screen.dart';

/// Satıcı panelinin "Diğer" sekmesi: eski Drawer'ın, artık alt navigasyona
/// taşınan Genel Bakış/Ürünler/Siparişler/Ödemeler dışındaki tüm öğeleri.
///
/// Her öğenin geri dönüşte panoyu tazeleyip tazelemediği ESKİ Drawer
/// davranışıyla birebir aynıdır (ör. Kuponlar/İade/Yorumlar/Mağaza Ayarları
/// tazeler; SMM/Dijital/Flash Satış/Canlı Yayın tazelemez).
class SellerMoreTab extends StatelessWidget {
  const SellerMoreTab({
    super.key,
    required this.shopInfo,
    required this.onManageCategories,
    required this.onReturnRefresh,
  });

  final Map<String, dynamic>? shopInfo;
  final VoidCallback onManageCategories;
  final VoidCallback onReturnRefresh;

  void _requireShop(BuildContext context, VoidCallback action) {
    if (shopInfo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Önce mağaza oluşturmalısınız')),
      );
      return;
    }
    action();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ShopLogoTile(
                name: (shopInfo?['name'] as String?) ?? 'Mağaza',
                logoUrl: shopInfo?['logo_url'] as String?,
                size: 52,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (shopInfo?['name'] as String?) ?? 'Mağaza Adı',
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Diğer araçlar ve ayarlar',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          SellerSectionCard(
            title: 'Ürün & Kategori',
            child: _tile(
              icon: Icons.category_outlined,
              title: 'Kategori Ekle',
              onTap: onManageCategories,
            ),
          ),

          SellerSectionCard(
            title: 'Satış Araçları',
            child: Column(
              children: [
                _tile(
                  icon: Icons.confirmation_number_outlined,
                  title: 'Kuponlar',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const CouponsScreen()),
                  ).then((_) => onReturnRefresh()),
                ),
                const Divider(height: 1),
                _tile(
                  icon: Icons.flash_on,
                  title: 'Flash Satış Yönetimi',
                  onTap: () => _requireShop(
                    context,
                    () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => SellerFlashSalesScreen(shopId: shopInfo!['id'] as String),
                      ),
                    ),
                  ),
                ),
                const Divider(height: 1),
                _tile(
                  icon: Icons.live_tv,
                  title: 'Canlı Yayın Başlat',
                  onTap: () => _requireShop(
                    context,
                    () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => LiveHostScreen(
                          shopId: shopInfo!['id'] as String,
                          shopName: (shopInfo!['name'] ?? 'Mağazam') as String,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          SellerSectionCard(
            title: 'Dijital & SMM',
            child: Column(
              children: [
                _tile(
                  icon: Icons.smart_toy_outlined,
                  title: 'SMM Ayarları',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const SmmProviderSettingsScreen()),
                  ),
                ),
                const Divider(height: 1),
                _tile(
                  icon: Icons.list_alt_outlined,
                  title: 'Dijital Siparişler',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const SellerDigitalOrdersScreen()),
                  ),
                ),
              ],
            ),
          ),

          SellerSectionCard(
            title: 'Müşteri İlişkileri',
            child: Column(
              children: [
                _tile(
                  icon: Icons.assignment_return_outlined,
                  title: 'İade Talepleri',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const SellerReturnRequestsScreen()),
                  ).then((_) => onReturnRefresh()),
                ),
                const Divider(height: 1),
                _tile(
                  icon: Icons.rate_review_outlined,
                  title: 'Yorumlar',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const SellerReviewsScreen()),
                  ).then((_) => onReturnRefresh()),
                ),
              ],
            ),
          ),

          SellerSectionCard(
            title: 'Mağaza',
            child: Column(
              children: [
                _tile(
                  icon: Icons.settings_outlined,
                  title: 'Mağaza Ayarları',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const ShopSettingsScreen()),
                  ).then((_) => onReturnRefresh()),
                ),
                const Divider(height: 1),
                _tile(
                  icon: Icons.help_outline,
                  title: 'Yardım',
                  onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Yardım ekranı yakında eklenecek')),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile({required IconData icon, required String title, required VoidCallback onTap}) {
    return Builder(
      builder: (context) => ListTile(
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(title),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
        onTap: onTap,
      ),
    );
  }
}
