import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../core/models/seller_announcement_model.dart';
import '../common/seller_stat_card.dart';
import '../seller_announcements_section.dart';

/// Satıcı panelinin "Genel Bakış" sekmesi (sunum katmanı).
///
/// Tüm veri çekme/mutasyon mantığı `SellerDashboardScreen`'de kalır; bu
/// widget yalnızca gelen veriyi çizer ve etkileşimleri callback'lerle
/// yukarı iletir.
class SellerOverviewTab extends StatelessWidget {
  const SellerOverviewTab({
    super.key,
    required this.shopInfo,
    required this.isAcceptingOrders,
    required this.onToggleAcceptingOrders,
    required this.hasOwnCourier,
    required this.ordersCount,
    required this.productsCount,
    required this.cashPaymentRevenue,
    required this.onlinePaymentRevenue,
    required this.adminCredit,
    required this.commissionDebt,
    required this.recentOrders,
    required this.topProducts,
    required this.totalViews,
    required this.totalFavorites,
    required this.onAnnouncementAction,
    required this.onOpenProducts,
    required this.onRefresh,
  });

  final Map<String, dynamic>? shopInfo;
  final bool isAcceptingOrders;
  final ValueChanged<bool> onToggleAcceptingOrders;
  final bool hasOwnCourier;
  final int ordersCount;
  final int productsCount;
  final double cashPaymentRevenue;
  final double onlinePaymentRevenue;
  final double adminCredit;
  final double commissionDebt;
  final List<Map<String, dynamic>> recentOrders;
  final List<Map<String, dynamic>> topProducts;
  final int totalViews;
  final int totalFavorites;
  final Future<void> Function(SellerAnnouncement) onAnnouncementAction;
  final VoidCallback onOpenProducts;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Yönetimden duyurular: giriş yapar yapmaz en üstte görünür
            SellerAnnouncementsSection(onAction: onAnnouncementAction),

            // Komisyon Oranı Kartı
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.purple.shade100,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.percent,
                            color: Colors.purple.shade700,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Komisyon Oranı',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '%${(shopInfo?['commission_rate'] ?? 10.0).toStringAsFixed(1)}',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.purple,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          'Her satıştan',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                    // Kuryesi olmayanlar için teslimat ücreti bilgisi
                    if (shopInfo?['has_own_courier'] == false) ...[
                      const Divider(height: 24),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.local_shipping,
                              color: primary,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Teslimat Ücreti',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '₺${(shopInfo?['delivery_fee'] ?? 0).toStringAsFixed(2)}',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            'Her siparişten',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: primary.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline, size: 14, color: primary),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Admin kurye ile teslimat yapılır',
                                style: TextStyle(fontSize: 11, color: primary),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Sipariş Alma Kontrol Kartı
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isAcceptingOrders ? Colors.green.shade100 : Colors.red.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        isAcceptingOrders ? Icons.store_outlined : Icons.store_mall_directory_outlined,
                        color: isAcceptingOrders ? Colors.green.shade700 : Colors.red.shade700,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isAcceptingOrders ? 'Sipariş Alıyor' : 'Sipariş Kapalı',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: isAcceptingOrders ? Colors.green.shade700 : Colors.red.shade700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            isAcceptingOrders
                                ? 'Müşteriler sipariş verebilir'
                                : 'Müşteriler sipariş veremez (Geçici Kapalı)',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: isAcceptingOrders,
                      onChanged: onToggleAcceptingOrders,
                      activeTrackColor: Colors.green.shade700,
                      activeThumbColor: Colors.white,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // İstatistik Kartları
            Row(
              children: [
                Expanded(
                  child: SellerStatCard(
                    title: 'Toplam Sipariş',
                    value: '$ordersCount',
                    icon: Icons.shopping_bag_outlined,
                    color: Colors.blue,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: SellerStatCard(
                    title: 'Ürün Sayısı',
                    value: '$productsCount',
                    icon: Icons.inventory_2_outlined,
                    color: Colors.green,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: SellerStatCard(
                    title: 'Toplam Görüntülenme',
                    value: '$totalViews',
                    icon: Icons.visibility_outlined,
                    color: Colors.indigo,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: SellerStatCard(
                    title: 'Toplam Beğeni',
                    value: '$totalFavorites',
                    icon: Icons.favorite_rounded,
                    color: Colors.pink,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: SellerStatCard(
                    title: hasOwnCourier ? 'Kapıda Ödeme Kazancı' : 'Kapıda Kazanç',
                    value: '₺${cashPaymentRevenue.toStringAsFixed(2)}',
                    icon: Icons.money,
                    color: Colors.green,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: SellerStatCard(
                    title: hasOwnCourier ? 'Online Ödeme Kazancı' : 'Online Alacak',
                    value: '₺${onlinePaymentRevenue.toStringAsFixed(2)}',
                    icon: Icons.credit_card,
                    color: Colors.blue,
                  ),
                ),
              ],
            ),
            if (hasOwnCourier) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: SellerStatCard(
                      title: 'Admin\'den Alacak',
                      value: '₺${adminCredit.toStringAsFixed(2)}',
                      icon: Icons.account_balance,
                      color: Colors.teal,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: SellerStatCard(
                      title: 'Komisyon Borcu',
                      value: '₺${commissionDebt.toStringAsFixed(2)}',
                      icon: Icons.trending_down,
                      color: Colors.orange,
                    ),
                  ),
                ],
              ),
            ],
            if (!hasOwnCourier) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: SellerStatCard(
                      title: 'Admin\'den Alacak',
                      value: '₺${adminCredit.toStringAsFixed(2)}',
                      icon: Icons.account_balance,
                      color: Colors.teal,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: SellerStatCard(
                      title: 'Kurye Durumu',
                      value: 'Platform Kargo',
                      icon: Icons.local_shipping,
                      color: Colors.purple,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 32),

            // Son Siparişler
            Text(
              'Son Siparişler',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            if (recentOrders.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Center(
                    child: Text('Henüz sipariş yok', style: TextStyle(color: Colors.grey.shade600)),
                  ),
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: recentOrders.length,
                itemBuilder: (context, index) {
                  final order = recentOrders[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: primary.withValues(alpha: 0.12),
                        child: Icon(Icons.shopping_cart, color: primary),
                      ),
                      title: Text(
                        'Sipariş #${order['id'].toString().substring(0, 8)}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(order['profiles']?['full_name'] ?? 'Bilinmeyen'),
                      trailing: Chip(
                        label: Text(
                          _statusLabel(order['status']),
                          style: const TextStyle(fontSize: 12),
                        ),
                        backgroundColor: _statusColor(order['status']),
                      ),
                    ),
                  );
                },
              ),
            const SizedBox(height: 32),

            // Ürünlerim
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Ürünlerim',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                TextButton.icon(
                  onPressed: onOpenProducts,
                  icon: const Icon(Icons.arrow_forward, size: 18),
                  label: const Text('Tümünü Gör'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (topProducts.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Center(
                    child: Text('Henüz ürün eklenmemiş', style: TextStyle(color: Colors.grey.shade600)),
                  ),
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: topProducts.length,
                itemBuilder: (context, index) {
                  final product = topProducts[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: product['image_url'] != null
                            ? CachedNetworkImage(
                                memCacheWidth: 200,
                                imageUrl: product['image_url'],
                                width: 56,
                                height: 56,
                                fit: BoxFit.cover,
                                errorWidget: (context, url, error) => Container(
                                  width: 56,
                                  height: 56,
                                  color: Colors.grey.shade300,
                                  child: const Icon(Icons.image),
                                ),
                              )
                            : Container(
                                width: 56,
                                height: 56,
                                color: Colors.grey.shade300,
                                child: const Icon(Icons.image),
                              ),
                      ),
                      title: Text(
                        product['name'] ?? '',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        '₺${product['price'] ?? 0}',
                        style: TextStyle(color: primary),
                      ),
                      trailing: Text(
                        'Stok: ${product['stock_quantity'] ?? product['stock'] ?? 0}',
                        style: TextStyle(
                          color: (product['stock_quantity'] ?? product['stock'] ?? 0) > 0
                              ? Colors.green
                              : Colors.red,
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Color _statusColor(String? status) {
    switch (status) {
      case 'delivered':
      case 'completed':
        return Colors.green.shade100;
      case 'cancelled':
        return Colors.red.shade100;
      case 'confirmed':
      case 'processing':
        return Colors.blue.shade100;
      case 'preparing':
        return Colors.purple.shade100;
      case 'ready':
        return Colors.indigo.shade100;
      case 'on_the_way':
        return Colors.orange.shade100;
      default:
        return Colors.amber.shade100;
    }
  }

  String _statusLabel(String? status) {
    switch (status) {
      case 'pending':
        return 'Beklemede';
      case 'confirmed':
        return 'Onaylandı';
      case 'preparing':
        return 'Hazırlanıyor';
      case 'ready':
        return 'Hazır';
      case 'on_the_way':
        return 'Yolda';
      case 'delivered':
        return 'Teslim Edildi';
      case 'cancelled':
        return 'İptal Edildi';
      case 'completed':
        return 'Tamamlandı';
      case 'processing':
        return 'İşlemde';
      default:
        return status ?? 'Bilinmiyor';
    }
  }
}
