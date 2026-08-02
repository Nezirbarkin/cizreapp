part of '../admin_dashboard_screen.dart';

extension on _AdminDashboardScreenState {
  // ==========================================================================
  // Siparisler + kart + durum dialoglari
  // ==========================================================================

  // --- _buildOrdersContent ---
  Widget _buildOrdersContent() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _loadOrders(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Hata: ${snapshot.error}'));
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.receipt_long_outlined,
                  size: 64,
                  color: Colors.grey.shade400,
                ),
                const SizedBox(height: 16),
                Text(
                  'Sipariş bulunamadı',
                  style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                ),
              ],
            ),
          );
        }

        final orders = snapshot.data!;

        // Toplam istatistikler
        double totalRevenue = 0;
        double totalAdminCommission = 0;
        double totalSellerEarnings = 0;
        int completedOrders = 0;
        int pendingOrders = 0;
        int processingOrders = 0;
        int cancelledOrders = 0;

        for (var order in orders) {
          if (order['status'] != 'cancelled') {
            totalRevenue += (order['total'] as num?)?.toDouble() ?? 0;
            totalAdminCommission +=
                (order['admin_commission'] as num?)?.toDouble() ?? 0;
            totalSellerEarnings +=
                (order['seller_earnings'] as num?)?.toDouble() ?? 0;
          }
          switch (order['status']) {
            case 'delivered':
              completedOrders++;
              break;
            case 'pending':
              pendingOrders++;
              break;
            case 'preparing':
            case 'confirmed':
            case 'on_the_way':
              processingOrders++;
              break;
            case 'cancelled':
              cancelledOrders++;
              break;
          }
        }

        return RefreshIndicator(
          onRefresh: () async {
            setState(() {});
          },
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Başlık
                const Text(
                  'Sipariş Yönetimi',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),

                // Dükkan Filtresi
                FutureBuilder<List<Map<String, dynamic>>>(
                  future: _loadShopsForFilter(),
                  builder: (context, shopSnapshot) {
                    if (shopSnapshot.hasData) {
                      final shops = shopSnapshot.data!;
                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.store,
                              size: 20,
                              color: Colors.orange,
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Dükkan:',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String?>(
                                  value: _selectedShopFilter,
                                  isExpanded: true,
                                  hint: const Text('Tüm Dükkanlar'),
                                  items: [
                                    const DropdownMenuItem<String?>(
                                      value: null,
                                      child: Text('Tüm Dükkanlar'),
                                    ),
                                    ...shops.map(
                                      (shop) => DropdownMenuItem<String?>(
                                        value: shop['id'] as String,
                                        child: Text(
                                          shop['name'] as String? ??
                                              'Bilinmeyen',
                                        ),
                                      ),
                                    ),
                                  ],
                                  onChanged: (value) {
                                    setState(() {
                                      _selectedShopFilter = value;
                                    });
                                  },
                                ),
                              ),
                            ),
                            if (_selectedShopFilter != null)
                              IconButton(
                                icon: const Icon(Icons.clear, size: 20),
                                onPressed: () {
                                  setState(() {
                                    _selectedShopFilter = null;
                                  });
                                },
                                tooltip: 'Filtreyi temizle',
                              ),
                          ],
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
                const SizedBox(height: 12),

                // Durum İstatistikleri
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildOrderStatChip(
                        icon: Icons.pending_actions,
                        label: 'Bekleyen',
                        count: pendingOrders,
                        color: Colors.orange,
                      ),
                      const SizedBox(width: 8),
                      _buildOrderStatChip(
                        icon: Icons.autorenew,
                        label: 'İşleniyor',
                        count: processingOrders,
                        color: Colors.blue,
                      ),
                      const SizedBox(width: 8),
                      _buildOrderStatChip(
                        icon: Icons.check_circle,
                        label: 'Tamamlanan',
                        count: completedOrders,
                        color: Colors.green,
                      ),
                      const SizedBox(width: 8),
                      _buildOrderStatChip(
                        icon: Icons.cancel,
                        label: 'İptal',
                        count: cancelledOrders,
                        color: Colors.red,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Kazanç Kartları
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.analytics,
                              color: Colors.purple.shade600,
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Kazanç Özeti',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 24),
                        Row(
                          children: [
                            Expanded(
                              child: _buildEarningsItem(
                                title: 'Toplam Ciro',
                                amount: totalRevenue,
                                color: Colors.blue,
                                icon: Icons.attach_money,
                              ),
                            ),
                            Expanded(
                              child: _buildEarningsItem(
                                title: 'Admin Komisyon',
                                amount: totalAdminCommission,
                                color: Colors.purple,
                                icon: Icons.admin_panel_settings,
                              ),
                            ),
                            Expanded(
                              child: _buildEarningsItem(
                                title: 'Satıcı Kazanç',
                                amount: totalSellerEarnings,
                                color: Colors.green,
                                icon: Icons.store,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Siparişler Listesi
                Text(
                  'Tüm Siparişler (${orders.length})',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),

                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: orders.length,
                  itemBuilder: (context, index) {
                    final order = orders[index];
                    return _buildOrderCard(order);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // --- _buildOrderStatChip ---
  Widget _buildOrderStatChip({
    required IconData icon,
    required String label,
    required int count,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 6),
          Text(
            '$count $label',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // --- _buildEarningsItem ---
  Widget _buildEarningsItem({
    required String title,
    required double amount,
    required Color color,
    required IconData icon,
  }) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(height: 8),
        Text(
          '₺${amount.toStringAsFixed(2)}',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          title,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  // --- _buildOrderCard ---
  Widget _buildOrderCard(Map<String, dynamic> order) {
    final profile = order['profiles'] as Map<String, dynamic>?;
    final shop = order['shops'] as Map<String, dynamic>?;
    final status = order['status'] as String? ?? 'pending';
    final totalAmount = (order['total'] as num?)?.toDouble() ?? 0;
    final adminCommission =
        (order['admin_commission'] as num?)?.toDouble() ?? 0;
    final sellerEarnings = (order['seller_earnings'] as num?)?.toDouble() ?? 0;
    final commissionRate = (order['commission_rate'] as num?)?.toDouble() ?? 10;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showOrderDetailDialog(order),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Üst Kısım: Sipariş No ve Durum
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Sipariş #${(order['id'] as String?)?.substring(0, 8) ?? '-'}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _formatDate(order['created_at']),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _buildStatusBadge(status),
                  const SizedBox(width: 8),
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert, color: Colors.grey.shade700),
                    onSelected: (value) {
                      switch (value) {
                        case 'edit':
                          _showEditOrderDialog(order);
                          break;
                        case 'delete':
                          _showDeleteOrderDialog(order);
                          break;
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit, size: 18),
                            SizedBox(width: 8),
                            Text('Durumu Değiştir'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete, size: 18, color: Colors.red),
                            SizedBox(width: 8),
                            Text('Sil', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const Divider(height: 16),

              // Müşteri Bilgisi
              Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: Colors.blue.shade100,
                    backgroundImage: profile?['avatar_url'] != null
                        ? NetworkImage(profile!['avatar_url'])
                        : null,
                    child: profile?['avatar_url'] == null
                        ? Text(
                            (profile?['username'] as String?)
                                    ?.substring(0, 1)
                                    .toUpperCase() ??
                                '?',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade700,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          profile?['full_name'] ??
                              profile?['username'] ??
                              'Bilinmeyen Müşteri',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          profile?['email'] ?? '-',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Müşteri Telefonu ve Adres
              Builder(
                builder: (context) {
                  final customerPhone =
                      order['customer_phone'] as String? ??
                      profile?['phone'] as String?;
                  final addressDisplay = order['address_display'] as String?;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (customerPhone != null && customerPhone.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.green.shade200),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.phone,
                                size: 14,
                                color: Colors.green.shade700,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  customerPhone,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.green.shade700,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (addressDisplay != null && addressDisplay.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.blue.shade200),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.location_on,
                                size: 14,
                                color: Colors.blue.shade700,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  addressDisplay,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.blue.shade700,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 2,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  );
                },
              ),

              // Dükkan Bilgisi
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.store, size: 14, color: Colors.orange.shade700),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        shop?['name'] ?? 'Bilinmeyen Dükkan',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.orange.shade700,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // Kurye Teslim Bilgisi - Kurye atanmış siparişlerde her zaman gösterilir.
              // Teslim edilen siparişlerde kurye adı + telefon + teslim zamanı gösterilir.
              Builder(
                builder: (context) {
                  final courierInfo =
                      order['courier_info'] as Map<String, dynamic>?;
                  if (courierInfo == null) {
                    final hasOwnCourier =
                        shop?['has_own_courier'] as bool? ?? false;
                    // Teslim edildi ama kurye atanmamış: kendi kuryesi olan satıcı kendi
                    // teslim etmiş olabilir. Kuryesi olmayan satıcı için bekleyen durum.
                    if (status == 'delivered' && hasOwnCourier) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.green.shade200),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.storefront,
                              size: 14,
                              color: Colors.green.shade700,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Satıcı tarafından teslim edildi',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.green.shade700,
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                    if (!hasOwnCourier &&
                        status != 'delivered' &&
                        status != 'cancelled') {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.local_shipping,
                              size: 14,
                              color: Colors.grey.shade600,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Platform Kuryesi Atanacak',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  }

                  final courierName =
                      courierInfo['courier_name'] as String? ?? 'Bilinmeyen';
                  final courierPhone =
                      courierInfo['courier_phone'] as String? ?? '';
                  final courierStatus =
                      courierInfo['status'] as String? ?? 'pending';
                  final deliveredAt = courierInfo['delivered_at'] as String?;

                  Color statusColor;
                  IconData statusIcon;
                  String statusText;

                  switch (courierStatus) {
                    case 'delivered':
                      statusColor = Colors.green;
                      statusIcon = Icons.check_circle;
                      statusText = 'Kurye Teslim Etti';
                      break;
                    case 'on_the_way':
                      statusColor = Colors.blue;
                      statusIcon = Icons.delivery_dining;
                      statusText = 'Kuryede (Yolda)';
                      break;
                    case 'picked_up':
                      statusColor = Colors.teal;
                      statusIcon = Icons.inventory_2;
                      statusText = 'Kurye Teslim Aldı';
                      break;
                    case 'accepted':
                      statusColor = Colors.orange;
                      statusIcon = Icons.check;
                      statusText = 'Kurye Kabul Etti';
                      break;
                    default:
                      statusColor = Colors.grey;
                      statusIcon = Icons.hourglass_empty;
                      statusText = 'Kurye Atandı';
                  }

                  // Teslim edildiğinde kurye adı + telefon + teslim zamanı gösterilir.
                  final isDelivered = courierStatus == 'delivered';

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: statusColor.withOpacity(0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(statusIcon, size: 14, color: statusColor),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                courierName,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: statusColor,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: statusColor.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                statusText,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: statusColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (isDelivered) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(Icons.phone, size: 12, color: statusColor),
                              const SizedBox(width: 4),
                              Text(
                                courierPhone.isNotEmpty
                                    ? courierPhone
                                    : 'Telefon yok',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: statusColor,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Icon(
                                Icons.access_time,
                                size: 12,
                                color: statusColor,
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  deliveredAt != null
                                      ? _formatDate(deliveredAt)
                                      : 'Zaman bilinmiyor',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: statusColor,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),

              // Ürün Görselleri ve Bilgileri
              Builder(
                builder: (context) {
                  final orderItems = order['order_items'] as List? ?? [];
                  if (orderItems.isEmpty) return const SizedBox.shrink();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        height: 60,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: orderItems.length > 5
                              ? 5
                              : orderItems.length,
                          itemBuilder: (context, index) {
                            final item =
                                orderItems[index] as Map<String, dynamic>;
                            final imageUrl =
                                item['product_image_url'] as String?;
                            final quantity = item['quantity'] as int? ?? 1;
                            return Container(
                              margin: const EdgeInsets.only(right: 8),
                              child: Stack(
                                children: [
                                  Container(
                                    width: 52,
                                    height: 52,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(10),
                                      color: Colors.grey.shade100,
                                      border: Border.all(
                                        color: Colors.grey.shade200,
                                      ),
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child:
                                          imageUrl != null &&
                                              imageUrl.isNotEmpty
                                          ? CachedNetworkImage(
                                              imageUrl: imageUrl,
                                              fit: BoxFit.cover,
                                              errorWidget: (_, __, ___) => Icon(
                                                Icons.image,
                                                size: 24,
                                                color: Colors.grey.shade400,
                                              ),
                                            )
                                          : Icon(
                                              Icons.shopping_bag,
                                              size: 24,
                                              color: Colors.grey.shade400,
                                            ),
                                    ),
                                  ),
                                  if (quantity > 1)
                                    Positioned(
                                      right: 0,
                                      top: 0,
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF97316),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: Text(
                                          'x$quantity',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                      if (orderItems.length > 5)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '+${orderItems.length - 5} ürün daha',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade500,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),

              const Divider(height: 16),

              // Kazanç Bilgileri
              Row(
                children: [
                  Expanded(
                    child: _buildOrderAmountItem(
                      label: 'Toplam',
                      amount: totalAmount,
                      color: Colors.blue.shade700,
                      isBold: true,
                    ),
                  ),
                  Container(width: 1, height: 30, color: Colors.grey.shade300),
                  Expanded(
                    child: _buildOrderAmountItem(
                      label: 'Komisyon (%${commissionRate.toStringAsFixed(0)})',
                      amount: adminCommission,
                      color: Colors.purple.shade700,
                    ),
                  ),
                  Container(width: 1, height: 30, color: Colors.grey.shade300),
                  Expanded(
                    child: _buildOrderAmountItem(
                      label: 'Satıcı',
                      amount: sellerEarnings,
                      color: Colors.green.shade700,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- _buildOrderAmountItem ---
  Widget _buildOrderAmountItem({
    required String label,
    required double amount,
    required Color color,
    bool isBold = false,
  }) {
    return Column(
      children: [
        Text(
          '₺${amount.toStringAsFixed(2)}',
          style: TextStyle(
            fontSize: isBold ? 14 : 13,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  // --- _buildStatusBadge ---
  Widget _buildStatusBadge(String status) {
    Color color;
    IconData icon;
    String label;

    switch (status) {
      case 'pending':
        color = Colors.orange;
        icon = Icons.pending_actions;
        label = 'Bekliyor';
        break;
      case 'processing':
        color = Colors.blue;
        icon = Icons.autorenew;
        label = 'İşleniyor';
        break;
      case 'completed':
      case 'delivered':
        color = Colors.green;
        icon = Icons.check_circle;
        label = 'Tamamlandı';
        break;
      case 'cancelled':
        color = Colors.red;
        icon = Icons.cancel;
        label = 'İptal';
        break;
      default:
        color = Colors.grey;
        icon = Icons.help;
        label = status;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // --- _showOrderDetailDialog ---
  void _showOrderDetailDialog(Map<String, dynamic> order) {
    final profile = order['profiles'] as Map<String, dynamic>?;
    final shop = order['shops'] as Map<String, dynamic>?;
    final status = order['status'] as String? ?? 'pending';
    final totalAmount = (order['total'] as num?)?.toDouble() ?? 0;
    final adminCommission =
        (order['admin_commission'] as num?)?.toDouble() ?? 0;
    final sellerEarnings = (order['seller_earnings'] as num?)?.toDouble() ?? 0;
    final commissionRate = (order['commission_rate'] as num?)?.toDouble() ?? 10;

    // Adres bilgisini asenkron olarak yükle
    final addressId = order['address_id'] as String?;
    Future<Map<String, dynamic>?> addressFuture;
    if (addressId != null && addressId.isNotEmpty) {
      addressFuture = Supabase.instance.client
          .from('addresses')
          .select(
            'id, title, full_name, phone, address_line1, address_line2, city, district, postal_code',
          )
          .eq('id', addressId)
          .maybeSingle();
    } else {
      addressFuture = Future.value(null);
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.purple.shade400, Colors.purple.shade600],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.receipt_long,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Sipariş #${(order['id'] as String?)?.substring(0, 8) ?? '-'}',
                    style: const TextStyle(fontSize: 16),
                  ),
                  Text(
                    _formatDate(order['created_at']),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Durum
                Center(child: _buildStatusBadge(status)),
                const SizedBox(height: 16),

                // Müşteri Bilgisi
                const Text(
                  'Müşteri Bilgisi',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Card(
                  color: Colors.blue.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: Colors.blue.shade200,
                          backgroundImage: profile?['avatar_url'] != null
                              ? NetworkImage(profile!['avatar_url'])
                              : null,
                          child: profile?['avatar_url'] == null
                              ? Text(
                                  (profile?['username'] as String?)
                                          ?.substring(0, 1)
                                          .toUpperCase() ??
                                      '?',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue.shade800,
                                  ),
                                )
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                profile?['full_name'] ??
                                    profile?['username'] ??
                                    'Bilinmeyen',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                profile?['email'] ?? '-',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Dükkan Bilgisi
                const Text(
                  'Dükkan Bilgisi',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Card(
                  color: Colors.orange.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade200,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.store,
                            color: Colors.orange.shade800,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                shop?['name'] ?? 'Bilinmeyen Dükkan',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                'Komisyon Oranı: %${commissionRate.toStringAsFixed(1)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Kazanç Detayları
                const Text(
                  'Kazanç Detayları',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Card(
                  color: Colors.grey.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        _buildDetailRow(
                          'Sipariş Tutarı',
                          '₺${totalAmount.toStringAsFixed(2)}',
                          Colors.blue,
                        ),
                        const Divider(),
                        _buildDetailRow(
                          'Admin Komisyonu (%${commissionRate.toStringAsFixed(0)})',
                          '₺${adminCommission.toStringAsFixed(2)}',
                          Colors.purple,
                        ),
                        const Divider(),
                        _buildDetailRow(
                          'Satıcı Kazancı',
                          '₺${sellerEarnings.toStringAsFixed(2)}',
                          Colors.green,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Ödeme Bilgileri
                const Text(
                  'Ödeme Bilgileri',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Builder(
                  builder: (context) {
                    final paymentMethod =
                        order['payment_method'] as String? ?? 'cash';
                    final paymentStatus =
                        order['payment_status'] as String? ?? 'pending';
                    // Bakiye veya online ödeme ise otomatik ödendi kabul et
                    final isAutoPaid =
                        paymentMethod == 'balance' || paymentMethod == 'online';
                    final isPaid =
                        isAutoPaid ||
                        paymentStatus == 'completed' ||
                        paymentStatus == 'paid';
                    final methodLabel = paymentMethod == 'balance'
                        ? 'Bakiye'
                        : paymentMethod == 'online'
                        ? 'Online Ödeme'
                        : paymentMethod == 'card_on_delivery'
                        ? 'Kapıda Kart'
                        : 'Kapıda Nakit';

                    return Card(
                      color: isPaid
                          ? Colors.green.shade50
                          : Colors.orange.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          children: [
                            _buildDetailRow(
                              'Ödeme Yöntemi',
                              methodLabel,
                              Colors.blue,
                            ),
                            const Divider(),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Ödeme Durumu',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isPaid
                                        ? Colors.green.shade100
                                        : Colors.orange.shade100,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    isPaid ? 'Yapıldı' : 'Bekleniyor',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: isPaid
                                          ? Colors.green.shade700
                                          : Colors.orange.shade700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),

                // Teslimat Adresi ve Telefon
                const SizedBox(height: 16),
                const Text(
                  'Teslimat Bilgileri',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Card(
                  color: Colors.green.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Adres - asenkron olarak yükle
                        FutureBuilder<Map<String, dynamic>?>(
                          future: addressFuture,
                          builder: (context, addressSnapshot) {
                            // Önce address_display alanını kontrol et
                            String displayAddress =
                                order['address_display']?.toString() ?? '';
                            String addressPhone = '';

                            // Eğer address_display boşsa ve addresses tablosundan veri geldiyse
                            if (addressSnapshot.hasData &&
                                addressSnapshot.data != null) {
                              final address = addressSnapshot.data!;
                              if (displayAddress.isEmpty) {
                                final parts = <String>[
                                  address['address_line1'] as String? ?? '',
                                  if (address['address_line2'] != null &&
                                      (address['address_line2'] as String)
                                          .isNotEmpty)
                                    address['address_line2'] as String,
                                  if (address['district'] != null &&
                                      (address['district'] as String)
                                          .isNotEmpty)
                                    address['district'] as String,
                                  address['city'] as String? ?? '',
                                ];
                                displayAddress = parts
                                    .where((p) => p.isNotEmpty)
                                    .join(', ');
                              }
                              addressPhone = address['phone'] as String? ?? '';
                            }

                            if (addressSnapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 8),
                                child: Center(
                                  child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                ),
                              );
                            }

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (displayAddress.isNotEmpty) ...[
                                  InkWell(
                                    onTap: () =>
                                        _openAddressInMap(displayAddress),
                                    borderRadius: BorderRadius.circular(8),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.location_on,
                                          color: Colors.green.shade700,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            displayAddress,
                                            style: const TextStyle(
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                        Icon(
                                          Icons.open_in_new,
                                          color: Colors.green.shade700,
                                          size: 16,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                ],
                                // Adresteki telefon bilgisi
                                if (addressPhone.isNotEmpty) ...[
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.phone_android,
                                        color: Colors.green.shade700,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Adres Tel: $addressPhone',
                                          style: const TextStyle(fontSize: 13),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                ],
                                if (displayAddress.isEmpty &&
                                    !addressSnapshot.hasData)
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.location_off,
                                        color: Colors.grey.shade500,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Adres bilgisi bulunamadı',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
                              ],
                            );
                          },
                        ),
                        // Telefon - orders tablosundan veya profilinden al
                        Builder(
                          builder: (context) {
                            final customerPhone =
                                order['customer_phone'] as String? ??
                                profile?['phone'] as String?;
                            if (customerPhone != null &&
                                customerPhone.isNotEmpty) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.phone,
                                        color: Colors.green.shade700,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          customerPhone,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  SizedBox(
                                    width: double.infinity,
                                    child: ElevatedButton.icon(
                                      onPressed: () =>
                                          _callCustomerFromAdmin(customerPhone),
                                      icon: const Icon(Icons.call, size: 16),
                                      label: const Text('Müşteriyi Ara'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.green,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 10,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            }
                            // Telefon yoksa hiçbir şey gösterme
                            return const SizedBox.shrink();
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Kapat'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _showEditOrderDialog(order);
            },
            icon: const Icon(Icons.edit),
            label: const Text('Durumu Değiştir'),
          ),
        ],
      ),
    );
  }

  // --- _buildDetailRow ---
  Widget _buildDetailRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // --- _showEditOrderDialog ---
  void _showEditOrderDialog(Map<String, dynamic> order) {
    String selectedStatus = order['status'] ?? 'pending';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Sipariş Durumunu Değiştir'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Sipariş #${(order['id'] as String?)?.substring(0, 8) ?? '-'}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              const Text('Yeni durum seçin:'),
              const SizedBox(height: 12),
              _buildStatusOption(
                status: 'pending',
                label: 'Beklemede',
                icon: Icons.access_time,
                color: Colors.orange,
                selectedStatus: selectedStatus,
                onTap: () => setDialogState(() => selectedStatus = 'pending'),
              ),
              const SizedBox(height: 8),
              _buildStatusOption(
                status: 'confirmed',
                label: 'Onaylandı',
                icon: Icons.check_circle_outline,
                color: Colors.blue,
                selectedStatus: selectedStatus,
                onTap: () => setDialogState(() => selectedStatus = 'confirmed'),
              ),
              const SizedBox(height: 8),
              _buildStatusOption(
                status: 'preparing',
                label: 'Hazırlanıyor',
                icon: Icons.restaurant_menu,
                color: Colors.purple,
                selectedStatus: selectedStatus,
                onTap: () => setDialogState(() => selectedStatus = 'preparing'),
              ),
              const SizedBox(height: 8),
              _buildStatusOption(
                status: 'ready',
                label: 'Hazır',
                icon: Icons.inventory_2,
                color: Colors.teal,
                selectedStatus: selectedStatus,
                onTap: () => setDialogState(() => selectedStatus = 'ready'),
              ),
              const SizedBox(height: 8),
              _buildStatusOption(
                status: 'on_the_way',
                label: 'Yolda',
                icon: Icons.two_wheeler,
                color: Colors.indigo,
                selectedStatus: selectedStatus,
                onTap: () =>
                    setDialogState(() => selectedStatus = 'on_the_way'),
              ),
              const SizedBox(height: 8),
              _buildStatusOption(
                status: 'delivered',
                label: 'Teslim Edildi',
                icon: Icons.task_alt,
                color: Colors.green,
                selectedStatus: selectedStatus,
                onTap: () => setDialogState(() => selectedStatus = 'delivered'),
              ),
              const SizedBox(height: 8),
              _buildStatusOption(
                status: 'cancelled',
                label: 'İptal Edildi',
                icon: Icons.cancel,
                color: Colors.red,
                selectedStatus: selectedStatus,
                onTap: () => setDialogState(() => selectedStatus = 'cancelled'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('İptal'),
            ),
            ElevatedButton(
              onPressed: () async {
                // İptal seçilirse: iade onay diyaloğu + admin_cancel_with_refund RPC
                if (selectedStatus == 'cancelled') {
                  await _confirmAdminCancel(order);
                  return;
                }

                try {
                  debugPrint(
                    '📝 Sipariş durumu güncelleniyor: ${order['id']} -> $selectedStatus',
                  );

                  await Supabase.instance.client
                      .from('orders')
                      .update({'status': selectedStatus})
                      .eq('id', order['id']);

                  debugPrint('✅ Sipariş durumu başarıyla güncellendi');

                  if (mounted) {
                    Navigator.pop(context);
                    setState(() {});
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Sipariş durumu güncellendi: $selectedStatus',
                        ),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  debugPrint('❌ Sipariş güncellenirken hata: $e');
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Sipariş güncellenirken hata: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              child: const Text('Güncelle'),
            ),
          ],
        ),
      ),
    );
  }

  // --- _confirmAdminCancel ---
  Future<void> _confirmAdminCancel(Map<String, dynamic> order) async {
    final orderId = order['id'] as String;
    final paymentMethod = order['payment_method'] as String? ?? 'cash';
    final total = (order['total'] as num?)?.toDouble() ?? 0;
    final hasRefund = paymentMethod == 'balance' || paymentMethod == 'online';

    final reasonController = TextEditingController(
      text: 'Admin tarafından iptal edildi',
    );

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red),
            SizedBox(width: 8),
            Text('Sipariş İptal + İade'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sipariş #${orderId.substring(0, 8).toUpperCase()} iptal edilecek.',
            ),
            const SizedBox(height: 8),
            if (hasRefund)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.account_balance_wallet,
                      size: 18,
                      color: Colors.green.shade700,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Onayladığınızda ₺${total.toStringAsFixed(2)} '
                        'müşterinin CizreApp bakiyesine otomatik iade edilecek.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.green.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 18,
                      color: Colors.grey.shade700,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Bu siparişte iade yok ($paymentMethod). '
                        'Sadece sipariş iptal edilecek.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'İptal sebebi (müşteriye bildirilecek)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('İptal Et + İade Yap'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final reason = reasonController.text.trim();
    if (reason.length < 3) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('İptal sebebi en az 3 karakter olmalı'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    try {
      final result = await _cancellationService.adminCancelWithRefund(
        orderId: orderId,
        reason: reason,
      );

      // Durum dialogunu kapat (status seçim dialogu hâlâ açık)
      if (mounted) Navigator.pop(context);

      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.hasRefund
                  ? 'İptal edildi. ₺${result.refundAmount.toStringAsFixed(2)} bakiyeye iade edildi.'
                  : 'Sipariş iptal edildi (iade yok).',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('İptal başarısız: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  // --- _buildStatusOption ---
  Widget _buildStatusOption({
    required String status,
    required String label,
    required IconData icon,
    required Color color,
    required String selectedStatus,
    required VoidCallback onTap,
  }) {
    final isSelected = status == selectedStatus;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.15) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: isSelected ? color : Colors.grey.shade600),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? color : Colors.grey.shade700,
                ),
              ),
            ),
            if (isSelected) Icon(Icons.check, color: color),
          ],
        ),
      ),
    );
  }

  // --- _showDeleteOrderDialog ---
  void _showDeleteOrderDialog(Map<String, dynamic> order) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Siparişi Sil'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sipariş #${(order['id'] as String?)?.substring(0, 8) ?? '-'} silinecek.',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade300),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning, color: Colors.red.shade700, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Bu işlem geri alınamaz. Sipariş ve ilişkili tüm veriler silinecektir.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.red.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              try {
                final orderId = order['id'];
                debugPrint('Siparis siliniyor: $orderId');

                // Once iliskili verileri manuel sil
                try {
                  await Supabase.instance.client
                      .from('courier_assignments')
                      .delete()
                      .eq('order_id', orderId);
                } catch (e) {
                  debugPrint('Courier assignments silinemedi: $e');
                }

                try {
                  await Supabase.instance.client
                      .from('order_items')
                      .delete()
                      .eq('order_id', orderId);
                } catch (e) {
                  debugPrint('Order items silinemedi: $e');
                }

                // Siparisi sil - select() ile silinen kaydin dondugunu kontrol et
                final result = await Supabase.instance.client
                    .from('orders')
                    .delete()
                    .eq('id', orderId)
                    .select();

                debugPrint('Siparis silme sonucu: $result');

                if (result.isEmpty) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Siparis silinemedi. Yetkiniz olmayabilir.',
                        ),
                        backgroundColor: Colors.red,
                        duration: Duration(seconds: 3),
                      ),
                    );
                  }
                  return;
                }

                debugPrint('Siparis silme basarili: $result');

                if (mounted) {
                  Navigator.pop(context);
                  setState(() {});

                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Siparis basariyla silindi'),
                      backgroundColor: Colors.green,
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              } on PostgrestException catch (e) {
                debugPrint('PostgreSQL Hatasi: ${e.message}');
                debugPrint('Hata kodu: ${e.code}');
                debugPrint('Detay: ${e.details}');

                if (mounted) {
                  String errorMessage = 'Bilinmeyen hata';

                  if (e.code == '42501' || e.message.contains('policy')) {
                    errorMessage =
                        'Yetkilendirme hatasi. Admin oldugunuzu kontrol edin.';
                  } else if (e.code == '23503') {
                    errorMessage = 'Siparis iliskili verilere sahip';
                  } else {
                    errorMessage = e.message;
                  }

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Hata: $errorMessage'),
                      backgroundColor: Colors.red,
                      duration: const Duration(seconds: 3),
                    ),
                  );
                }
              } catch (e, stackTrace) {
                debugPrint('Siparis silinirken hata: $e');
                debugPrint('Stack trace: $stackTrace');

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Hata: ${e.toString()}'),
                      backgroundColor: Colors.red,
                      duration: const Duration(seconds: 3),
                    ),
                  );
                }
              }
            },
            child: const Text('Sil'),
          ),
        ],
      ),
    );
  }
}
