import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/order_model.dart';
import '../../shop/services/order_service.dart';
import 'order_detail_screen.dart';

class OrderHistoryScreen extends StatefulWidget {
  const OrderHistoryScreen({super.key});

  @override
  State<OrderHistoryScreen> createState() => _OrderHistoryScreenState();
}

class _OrderHistoryScreenState extends State<OrderHistoryScreen> {
  final OrderService _orderService = OrderService();
  late String userId;
  OrderStatus? _selectedFilter;

  @override
  void initState() {
    super.initState();
    userId = Supabase.instance.client.auth.currentUser?.id ?? '';
  }

  @override
  Widget build(BuildContext context) {
    if (userId.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Siparişlerim')),
        body: const Center(child: Text('Lütfen giriş yapın')),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Siparişlerim'),
        elevation: 0,
      ),
      body: Column(
        children: [
          // Filtre Butonları
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                _buildFilterChip(
                  label: 'Tümü',
                  isSelected: _selectedFilter == null,
                  onTap: () => setState(() => _selectedFilter = null),
                ),
                const SizedBox(width: 8),
                _buildFilterChip(
                  label: 'Bekleniyor',
                  isSelected: _selectedFilter == OrderStatus.pending,
                  onTap: () => setState(() => _selectedFilter = OrderStatus.pending),
                ),
                const SizedBox(width: 8),
                _buildFilterChip(
                  label: 'Onaylandı',
                  isSelected: _selectedFilter == OrderStatus.confirmed,
                  onTap: () => setState(() => _selectedFilter = OrderStatus.confirmed),
                ),
                const SizedBox(width: 8),
                _buildFilterChip(
                  label: 'Hazırlanıyor',
                  isSelected: _selectedFilter == OrderStatus.preparing,
                  onTap: () => setState(() => _selectedFilter = OrderStatus.preparing),
                ),
                const SizedBox(width: 8),
                _buildFilterChip(
                  label: 'Yolda',
                  isSelected: _selectedFilter == OrderStatus.onTheWay,
                  onTap: () => setState(() => _selectedFilter = OrderStatus.onTheWay),
                ),
                const SizedBox(width: 8),
                _buildFilterChip(
                  label: 'Teslim Edildi',
                  isSelected: _selectedFilter == OrderStatus.delivered,
                  onTap: () => setState(() => _selectedFilter = OrderStatus.delivered),
                ),
              ],
            ),
          ),
          // Siparişler Listesi
          Expanded(
            child: FutureBuilder<List<Order>>(
              future: _orderService.getUserOrders(userId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return _buildEmptyState();
                }

                final allOrders = snapshot.data!;
                final filteredOrders = _selectedFilter == null
                    ? allOrders
                    : allOrders.where((order) => order.status == _selectedFilter).toList();

                if (filteredOrders.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.shopping_cart_checkout,
                          size: 80,
                          color: Colors.grey.shade300,
                        ),
                        const SizedBox(height: 16),
                        const Text('Bu durumda sipariş bulunamadı'),
                      ],
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async {
                    setState(() {});
                  },
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: filteredOrders.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final order = filteredOrders[index];
                      return _buildOrderCard(context, order);
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => onTap(),
      backgroundColor: Colors.white,
      // ignore: deprecated_member_use
      selectedColor: Theme.of(context).colorScheme.primary.withOpacity(0.2),
      side: BorderSide(
        color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey.shade300,
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.shopping_bag_outlined,
            size: 80,
            color: Colors.grey.shade300,
          ),
          const SizedBox(height: 24),
          Text(
            'Henüz sipariş yok',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'İlk siparişinizi vermek için Market\'e gidin',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade500,
            ),
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.store),
            label: const Text('Market\'e Git'),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderCard(BuildContext context, Order order) {
    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => OrderDetailScreen(order: order),
        ),
      ).then((_) => setState(() {})),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              // ignore: deprecated_member_use
              // ignore: deprecated_member_use
              // ignore: deprecated_member_use
              // ignore: deprecated_member_use
              // ignore: deprecated_member_use
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Başlık: Sipariş ID ve Durum
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          order.orderNumberInt != null
                              ? 'Sipariş #${order.orderNumberInt}'
                              : 'Sipariş #${order.id.substring(0, 8).toUpperCase()}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _formatDate(order.createdAt),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _buildStatusBadge(order.status),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),

              // Dükkan Adı
              Row(
                children: [
                  Icon(Icons.store, size: 16, color: Colors.grey.shade600),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      order.shopName ?? 'Dükkan',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Ürünler Özeti
              Text(
                '${order.items.length} ürün',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 8),

              // Toplam Fiyat
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Toplam:',
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    '₺${order.totalAmount.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Alt Bilgi: Teslimat Adresi ve İleri Ok
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Icon(Icons.location_on_outlined, size: 14, color: Colors.grey.shade600),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            order.addressDisplay ?? 'Adres bilgisi yok',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    color: Colors.grey.shade400,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(OrderStatus status) {
    final colors = {
      OrderStatus.pending: (Colors.amber, Colors.amber.shade900),
      OrderStatus.confirmed: (Colors.blue, Colors.blue.shade900),
      OrderStatus.preparing: (Colors.purple, Colors.purple.shade900),
      OrderStatus.ready: (Colors.indigo, Colors.indigo.shade900),
      OrderStatus.onTheWay: (Colors.orange, Colors.orange.shade900),
      OrderStatus.delivered: (Colors.green, Colors.green.shade900),
      OrderStatus.cancelled: (Colors.red, Colors.red.shade900),
    };

    final statusTexts = {
      OrderStatus.pending: 'Bekleniyor',
      OrderStatus.confirmed: 'Onaylandı',
      OrderStatus.preparing: 'Hazırlanıyor',
      OrderStatus.ready: 'Hazır',
      OrderStatus.onTheWay: 'Yolda',
      OrderStatus.delivered: 'Teslim Edildi',
      OrderStatus.cancelled: 'İptal Edildi',
    };

    final (bgColor, textColor) = colors[status] ?? (Colors.grey, Colors.grey.shade900);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        // ignore: deprecated_member_use
        color: bgColor.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        statusTexts[status] ?? 'Bilinmiyor',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: textColor,
        ),
      ),
    );
  }

  String _formatDate(DateTime dateTime) {
    // Tam tarih ve saat göster: "25/01/2026 14:30"
    final day = dateTime.day.toString().padLeft(2, '0');
    final month = dateTime.month.toString().padLeft(2, '0');
    final year = dateTime.year;
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$day/$month/$year $hour:$minute';
  }
}
