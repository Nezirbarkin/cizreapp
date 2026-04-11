import 'package:flutter/material.dart';
// ignore: unnecessary_import
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/order_model.dart';
import '../services/order_service.dart';
import '../../market/widgets/pending_review_dialog.dart';
import '../../market/services/shop_review_service.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> with TickerProviderStateMixin {
  final OrderService _orderService = OrderService();
  final ShopReviewService _reviewService = ShopReviewService();
  late TabController _tabController;
  
  List<Order> _allOrders = [];
  bool _isLoading = true;
  Set<String> _reviewedOrders = {}; // Değerlendirilmiş siparişleri takip et
  
  final List<OrderStatus> _statuses = [
    OrderStatus.pending,
    OrderStatus.confirmed,
    OrderStatus.preparing,
    OrderStatus.ready,
    OrderStatus.onTheWay,
    OrderStatus.delivered,
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _statuses.length + 1, vsync: this);
    _loadOrders();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadOrders() async {
    setState(() => _isLoading = true);
    
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      debugPrint('📦 ORDERS: Kullanıcı giriş yapmamış');
      setState(() => _isLoading = false);
      return;
    }

    try {
      debugPrint('📦 ORDERS: Siparişler yükleniyor... userId: $userId');
      final orders = await _orderService.getUserOrders(userId);
      
      setState(() {
        _allOrders = orders;
        _isLoading = false;
      });
      
      debugPrint('✅ ORDERS: ${orders.length} sipariş yüklendi');
    } catch (e) {
      debugPrint('❌ ORDERS: Siparişler yüklenirken hata: $e');
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Siparişler yüklenirken hata: $e')),
        );
      }
    }
  }

  List<Order> _getFilteredOrders(OrderStatus? status) {
    if (status == null) {
      return _allOrders;
    }
    return _allOrders.where((order) => order.status == status).toList();
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final formatter = DateTime(dateTime.year, dateTime.month, dateTime.day);
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    String dayLabel = '';
    if (formatter == today) {
      dayLabel = 'Bugün';
    } else if (formatter == yesterday) {
      dayLabel = 'Dün';
    } else {
      dayLabel =
          '${dateTime.day.toString().padLeft(2, '0')}.${dateTime.month.toString().padLeft(2, '0')}.${dateTime.year}';
    }

    final timeStr =
        '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';

    return '$dayLabel $timeStr';
  }

  Color _getStatusColor(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending:
        return Colors.orange;
      case OrderStatus.confirmed:
        return Colors.blue;
      case OrderStatus.preparing:
        return Colors.deepPurple;
      case OrderStatus.ready:
        return Colors.green.shade600;
      case OrderStatus.onTheWay:
        return Colors.indigo;
      case OrderStatus.delivered:
        return Colors.green;
      case OrderStatus.cancelled:
        return Colors.red;
    }
  }

  IconData _getStatusIcon(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending:
        return Icons.schedule_rounded;
      case OrderStatus.confirmed:
        return Icons.check_circle_outline_rounded;
      case OrderStatus.preparing:
        return Icons.restaurant_rounded;
      case OrderStatus.ready:
        return Icons.done_all_rounded;
      case OrderStatus.onTheWay:
        return Icons.local_shipping_rounded;
      case OrderStatus.delivered:
        return Icons.home_rounded;
      case OrderStatus.cancelled:
        return Icons.cancel_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Siparişlerim'),
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: [
            const Tab(text: 'Tümü'),
            Tab(text: _statuses[0].label),
            Tab(text: _statuses[1].label),
            Tab(text: _statuses[2].label),
            Tab(text: _statuses[3].label),
            Tab(text: _statuses[4].label),
            Tab(text: _statuses[5].label),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                // Tümü
                _buildOrdersList(null),
                // Her status için bir tab
                ..._statuses.map((status) => _buildOrdersList(status)),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loadOrders,
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('Yenile'),
      ),
    );
  }

  Widget _buildOrdersList(OrderStatus? filterStatus) {
    final orders = _getFilteredOrders(filterStatus);

    if (orders.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.shopping_bag_outlined,
              size: 80,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              'Sipariş bulunamadı',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: orders.length,
      itemBuilder: (context, index) {
        final order = orders[index];
        return _buildOrderCard(order, index);
      },
    );
  }

  Widget _buildOrderCard(Order order, int index) {
    final theme = Theme.of(context);
    final statusColor = _getStatusColor(order.status);
    final statusIcon = _getStatusIcon(order.status);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            // ignore: deprecated_member_use
            color: statusColor.withOpacity(0.2),
            width: 2,
          ),
        ),
        child: Dismissible(
          key: Key(order.id),
          direction: DismissDirection.horizontal,
          background: Container(
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(16),
            ),
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.only(left: 20),
            child: Icon(Icons.check_circle_outline, color: Colors.blue.shade700),
          ),
          secondaryBackground: Container(
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(16),
            ),
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            child: Icon(Icons.cancel_outlined, color: Colors.red.shade700),
          ),
          onDismissed: (direction) {
            if (direction == DismissDirection.startToEnd) {
              // Sağa kaydı - Onay
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('İşlem: Sipariş onaylandı')),
              );
            } else {
              // Sola kaydı - İptal
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('İşlem: Sipariş iptal edildi')),
              );
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Başlık ve Status
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Sipariş #${order.id.substring(0, 8).toUpperCase()}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _formatDateTime(order.createdAt),
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        // ignore: deprecated_member_use
                        color: statusColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(statusIcon, size: 16, color: statusColor),
                          const SizedBox(width: 6),
                          Text(
                            order.status.label,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: statusColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                
                // Detaylar
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Ara Toplam:',
                            style: TextStyle(
                              color: Colors.grey.shade700,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            '₺${order.subtotal.toStringAsFixed(2)}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Teslimat:',
                            style: TextStyle(
                              color: Colors.grey.shade700,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            '₺${order.deliveryFee.toStringAsFixed(2)}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                      if (order.discountAmount > 0) ...[
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'İndirim:',
                              style: TextStyle(
                                color: Colors.green.shade700,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              '-₺${order.discountAmount.toStringAsFixed(2)}',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Colors.green.shade700,
                              ),
                            ),
                          ],
                        ),
                      ],
                      Divider(color: Colors.grey.shade300, height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Toplam:',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            '₺${order.totalAmount.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                
                // Ürün sayısı
                Text(
                  '${order.items.length} ürün',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
                
                // Değerlendir Butonu - Sadece teslim edilmiş siparişler için
                if (order.status == OrderStatus.delivered && !_reviewedOrders.contains(order.id)) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _showReviewDialog(order),
                      icon: const Icon(Icons.star_outline, size: 18),
                      label: const Text('Değerlendir'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
                
                // Swipe hint
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.swipe, size: 12, color: Colors.blue.shade700),
                      const SizedBox(width: 4),
                      Text(
                        'Sağa/Sola kaydırarak işlem yapabilirsiniz',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.blue.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Değerlendirme dialog'unu göster
  Future<void> _showReviewDialog(Order order) async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      // Sipariş için değerlendirme yapılabilir mi kontrol et
      final firstItem = order.items.first;
      final canReview = await _reviewService.canReviewOrder(
        orderId: order.id,
        userId: userId,
        shopId: firstItem.shopId ?? '',
      );

      if (!canReview) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Bu sipariş için zaten değerlendirme yaptınız')),
          );
          setState(() => _reviewedOrders.add(order.id));
        }
        return;
      }

      // Değerlendirilebilir siparişleri al
      final pendingReviews = await _reviewService.getPendingReviews(userId);
      final targetReview = pendingReviews.firstWhere(
        (r) => r.orderId == order.id,
        orElse: () => PendingReview(
          orderId: order.id,
          shopId: firstItem.shopId ?? '',
          shopName: firstItem.shopName ?? 'Mağaza',
          productId: firstItem.productId,
          productName: firstItem.productName,
          orderDate: order.createdAt,
          deliveredAt: order.deliveredAt ?? DateTime.now(),
        ),
      );

      if (!mounted) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => PendingReviewDialog(
          pendingReview: targetReview,
          onReviewSubmitted: () async {
            setState(() => _reviewedOrders.add(order.id));
            Navigator.of(context).pop();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Değerlendirmeniz için teşekkür ederiz!')),
              );
            }
          },
          onSkipped: () async {
            Navigator.of(context).pop();
          },
        ),
      );
    } catch (e) {
      debugPrint('❌ Değerlendirme açılırken hata: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Değerlendirme açılırken hata: $e')),
        );
      }
    }
  }
}
