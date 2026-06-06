// ignore_for_file: deprecated_member_use, unnecessary_underscores

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../shop/services/order_service.dart';
import '../../../core/models/order_model.dart';
import '../../../core/services/courier_notification_service.dart';
import '../../../core/services/email_service.dart';

/// Satıcı Sipariş Yönetimi Ekranı - Yenilenmiş Modern Tasarım
class SellerOrdersScreen extends StatefulWidget {
  const SellerOrdersScreen({super.key});

  @override
  State<SellerOrdersScreen> createState() => _SellerOrdersScreenState();
}

class _SellerOrdersScreenState extends State<SellerOrdersScreen>
    with SingleTickerProviderStateMixin {
  /// Supabase client'ı güvenli şekilde al (lazy)
  SupabaseClient get _supabase {
    try {
      return Supabase.instance.client;
    } catch (e) {
      debugPrint('⚠️ Supabase henüz başlatılmadı: $e');
      rethrow;
    }
  }
  late final OrderService _orderService;

  bool _isLoading = true;
  List<Order> _orders = [];
  String? _shopId;
  bool _hasOwnCourier = true; // Varsayılan olarak true, bilgi yüklenene kadar kurye çağırma butonu gizli
  
  // Kuryesi olmayan satıcının siparişlerinde müşteri bilgilerini gizleme
  // Bu bilgiler platform kuryesi tarafından teslim edileceği için satıcı görmesin
  bool _hideCustomerInfo = true;

  late TabController _tabController;

  final List<OrderStatus?> _statusFilters = [
    null, // Tümü
    OrderStatus.pending,
    OrderStatus.confirmed,
    OrderStatus.preparing,
    OrderStatus.ready,
    OrderStatus.onTheWay,
    null, // Geçmiş (delivered + cancelled)
  ];
  
  bool _isHistoryTab(int index) => index == 6; // Geçmiş tab index

  @override
  void initState() {
    super.initState();
    _orderService = OrderService();
    _tabController = TabController(length: _statusFilters.length, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        _loadOrders();
      }
    });
    _loadShopAndOrders();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadShopAndOrders() async {
    setState(() => _isLoading = true);

    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      final shopResponse = await _supabase
          .from('shops')
          .select('id, has_own_courier, hide_customer_info')
          .eq('owner_id', userId)
          .maybeSingle();

      if (shopResponse == null) {
        setState(() => _isLoading = false);
        return;
      }

      _shopId = shopResponse['id'];
      _hasOwnCourier = shopResponse['has_own_courier'] as bool? ?? true;
      // Kuryesi olmayan satıcıda müşteri bilgilerini gizle (admin toggle edebilir)
      _hideCustomerInfo = shopResponse['hide_customer_info'] as bool? ?? (!_hasOwnCourier);
      await _loadOrders();
    } catch (e) {
      debugPrint('Hata: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadOrders() async {
    if (_shopId == null) return;

    setState(() => _isLoading = true);

    try {
      // Kurye durumunu ve gizleme ayarını her yükleme sırasında güncelle
      // (admin değişiklik yapmış olabilir)
      try {
        final shopData = await _supabase
            .from('shops')
            .select('has_own_courier, hide_customer_info')
            .eq('id', _shopId!)
            .maybeSingle();
        if (shopData != null) {
          _hasOwnCourier = shopData['has_own_courier'] as bool? ?? true;
          _hideCustomerInfo = shopData['hide_customer_info'] as bool? ?? (!_hasOwnCourier);
        }
      } catch (e) {
        debugPrint('Kurye durumu güncellenemedi: $e');
      }

      List<Order> orders;
      final currentTabIndex = _tabController.index;

      // Tüm siparişleri çek
      orders = await _orderService.getShopOrders(_shopId!);

      // Tab'a göre filtrele
      if (currentTabIndex == 0) {
        // Tümü - filter yok
      } else if (_isHistoryTab(currentTabIndex)) {
        // Geçmiş tab - delivered + cancelled
        orders = orders.where((o) => o.status == OrderStatus.delivered || o.status == OrderStatus.cancelled).toList();
      } else if (_statusFilters[currentTabIndex] != null) {
        // Belirli bir durum
        orders = orders.where((o) => o.status == _statusFilters[currentTabIndex]).toList();
      }

      if (mounted) {
        setState(() {
          _orders = orders;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Siparişler yüklenirken hata: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _updateOrderStatus(Order order, OrderStatus newStatus) async {
    // Kapıda ödeme (nakit/kart) siparişlerini onaylarken ek onay dialogu göster
    if (newStatus == OrderStatus.confirmed &&
        (order.paymentMethod == PaymentMethod.cash ||
         order.paymentMethod == PaymentMethod.cardOnDelivery)) {
      final confirmed = await _showCashPaymentConfirmDialog(order);
      if (confirmed != true) return;
    }

    try {
      debugPrint('🔄 Sipariş durumu güncelleniyor: ${order.id} -> ${newStatus.name}');
      await _orderService.updateOrderStatus(order.id, newStatus);
      debugPrint('✅ Sipariş durumu güncellendi: ${order.id} -> ${newStatus.name}');
      
      // NOT: Kurye bildirimi ve atama işlemi artık satıcı "Kurye Çağır"
      // butonuna bastığında yapılıyor - otomatik atama kaldırıldı
      
      await _loadOrders();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sipariş durumu "${_getStatusText(newStatus)}" olarak güncellendi'),
            backgroundColor: Colors.green.shade600,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red.shade400),
        );
      }
    }
  }

  /// Sipariş confirmed veya ready olduğunda kuryelere bildirim gönder
  Future<void> _notifyCouriersForNewOrder(Order order, {String orderStatus = 'ready'}) async {
    try {
      debugPrint('📤 _notifyCouriersForNewOrder başladı - orderId: ${order.id}, shopId: ${order.shopId}, status: $orderStatus');
      
      final courierNotificationService = CourierNotificationService();
      
      // Dükkan bilgilerini al
      final shopResponse = await _supabase
          .from('shops')
          .select('id, name, has_own_courier')
          .eq('id', order.shopId)
          .maybeSingle();
      
      debugPrint('📤 Dükkan bilgisi: $shopResponse');
      
      if (shopResponse == null) {
        debugPrint('❌ Dükkan bulunamadı: ${order.shopId}');
        return;
      }
      
      // Dükkanın kendi kuryesi varsa bildirim gönderme
      if (shopResponse['has_own_courier'] == true) {
        debugPrint('📦 Dükkanın kendi kuryesi var, kurye bildirimi gönderilmedi');
        return;
      }
      
      final shopName = shopResponse['name'] ?? 'Dükkan';
      debugPrint('📤 Bildirim gönderiliyor - Dükkan: $shopName, Tutar: ${order.totalAmount}');
      
      await courierNotificationService.notifyCouriersForNewOrder(
        orderId: order.id,
        shopId: order.shopId,
        shopName: shopName,
        totalAmount: order.totalAmount,
        orderStatus: orderStatus,
      );
      
      debugPrint('✅ Kuryelere bildirim gönderildi (durum: $orderStatus)');
    } catch (e, stackTrace) {
      debugPrint('❌ Kurye bildirimi hatası: $e');
      debugPrint('❌ Stack trace: $stackTrace');
      // Sipariş durumu güncellendi, bildirim hatası kritik değil
    }
  }

  /// Kuryesi olmayan satıcıların siparişlerini otomatik kuryeye ata
  Future<void> _autoAssignCourierToOrder(Order order) async {
    try {
      final courierNotificationService = CourierNotificationService();
      
      await courierNotificationService.autoAssignCourierToOrder(
        orderId: order.id,
        shopId: order.shopId,
        orderTotal: order.totalAmount,
        orderStatus: order.status.name,
      );
      
      debugPrint('✅ Otomatik kurye ataması tamamlandı');
    } catch (e) {
      debugPrint('❌ Otomatik kurye atama hatası: $e');
      // Sipariş durumu güncellendi, atama hatası kritik değil
    }
  }

  /// Kapıda ödeme siparişlerinde onaylama öncesi ek dialog
  Future<bool?> _showCashPaymentConfirmDialog(Order order) {
    final isCash = order.paymentMethod == PaymentMethod.cash;
    final paymentLabel = isCash ? 'Kapıda Nakit' : 'Kapıda Kart';
    final paymentIcon = isCash ? Icons.money : Icons.credit_card;
    final paymentColor = isCash ? Colors.green.shade700 : Colors.blue.shade700;

    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700, size: 28),
            const SizedBox(width: 10),
            const Expanded(child: Text('Sipariş Onayı', style: TextStyle(fontSize: 18))),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Ödeme yöntemi bilgisi
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: paymentColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: paymentColor.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(paymentIcon, color: paymentColor, size: 24),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Ödeme Yöntemi: $paymentLabel',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: paymentColor,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Tutar: ₺${order.totalAmount.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: paymentColor,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Bu siparişi onaylamak istediğinize emin misiniz?',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isCash
                  ? 'Ödeme teslimat sırasında nakit olarak tahsil edilecektir.'
                  : 'Ödeme teslimat sırasında kartla tahsil edilecektir.',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('İptal', style: TextStyle(color: Colors.grey.shade600)),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.check_circle, size: 18),
            label: const Text('Onayla'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _cancelOrder(Order order) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.cancel_outlined, color: Colors.red.shade600, size: 24),
            ),
            const SizedBox(width: 12),
            const Text('Siparişi İptal Et'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sipariş #${order.orderNumberInt ?? order.id.substring(0, 8)} iptal edilecek.',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              'Bu işlem geri alınamaz. Devam etmek istiyor musunuz?',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Vazgeç', style: TextStyle(color: Colors.grey.shade600)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
            ),
            child: const Text('İptal Et'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Önce order detail dialog'unu kapat
    if (mounted) Navigator.pop(context);

    try {
      await _orderService.updateOrderStatus(order.id, OrderStatus.cancelled);
      await _loadOrders();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Text('Sipariş iptal edildi'),
              ],
            ),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('İptal edilemedi: $e'),
            backgroundColor: Colors.red.shade400,
          ),
        );
      }
    }
  }

  String _getStatusText(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending:
        return 'Beklemede';
      case OrderStatus.confirmed:
        return 'Onaylandı';
      case OrderStatus.preparing:
        return 'Hazırlanıyor';
      case OrderStatus.ready:
        return 'Hazır';
      case OrderStatus.onTheWay:
        return 'Yolda';
      case OrderStatus.delivered:
        return 'Teslim Edildi';
      case OrderStatus.cancelled:
        return 'İptal Edildi';
    }
  }

  Color _getStatusColor(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending:
        return const Color(0xFFF59E0B);
      case OrderStatus.confirmed:
        return const Color(0xFF3B82F6);
      case OrderStatus.preparing:
        return const Color(0xFF8B5CF6);
      case OrderStatus.ready:
        return const Color(0xFF14B8A6);
      case OrderStatus.onTheWay:
        return const Color(0xFF6366F1);
      case OrderStatus.delivered:
        return const Color(0xFF10B981);
      case OrderStatus.cancelled:
        return const Color(0xFFEF4444);
    }
  }

  IconData _getStatusIcon(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending:
        return Icons.access_time_rounded;
      case OrderStatus.confirmed:
        return Icons.check_circle;
      case OrderStatus.preparing:
        return Icons.restaurant_menu;
      case OrderStatus.ready:
        return Icons.inventory_2;
      case OrderStatus.onTheWay:
        return Icons.two_wheeler;
      case OrderStatus.delivered:
        return Icons.task_alt;
      case OrderStatus.cancelled:
        return Icons.cancel;
    }
  }

  void _showOrderDetailDialog(Order order) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 450),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [_getStatusColor(order.status), _getStatusColor(order.status).withOpacity(0.8)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(24),
                      topRight: Radius.circular(24),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(_getStatusIcon(order.status), color: Colors.white, size: 32),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Sipariş #${order.id.substring(0, 8)}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.3),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                _getStatusText(order.status),
                                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Content
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Özet Bilgiler
                      Row(
                        children: [
                          Expanded(
                            child: _buildInfoCard(
                              icon: Icons.receipt_long,
                              label: 'Toplam',
                              value: '₺${order.totalAmount.toStringAsFixed(2)}',
                              color: Colors.green,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildInfoCard(
                              icon: Icons.shopping_bag,
                              label: 'Ürün',
                              value: '${order.items.length} adet',
                              color: Colors.blue,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      
                      Row(
                        children: [
                          Expanded(
                            child: _buildInfoCard(
                              icon: Icons.payment,
                              label: 'Ödeme',
                              value: _getPaymentMethodText(order.paymentMethod),
                              color: Colors.purple,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildInfoCard(
                              icon: Icons.local_shipping,
                              label: 'Teslimat',
                              value: '₺${order.deliveryFee.toStringAsFixed(2)}',
                              color: Colors.teal,
                            ),
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 16),
                      
                      Row(
                        children: [
                          Expanded(
                            child: _buildInfoCard(
                              icon: Icons.calendar_today,
                              label: 'Tarih',
                              value: '${order.createdAt.day}/${order.createdAt.month}/${order.createdAt.year}',
                              color: Colors.orange,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildInfoCard(
                              icon: Icons.access_time,
                              label: 'Saat',
                              value: '${order.createdAt.hour.toString().padLeft(2, '0')}:${order.createdAt.minute.toString().padLeft(2, '0')}',
                              color: Colors.indigo,
                            ),
                          ),
                        ],
                      ),
                      
                      // Kupon Bilgisi
                      if (order.couponDiscount > 0) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Colors.orange.shade50, Colors.orange.shade100],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.orange.shade300, width: 2),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.confirmation_number, color: Colors.orange.shade700),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Kupon Uygulandı',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: Colors.orange.shade700,
                                    ),
                                  ),
                                  const Spacer(),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Colors.green,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      '- ₺${order.couponDiscount.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              if (order.couponId != null)
                                FutureBuilder<Map<String, dynamic>?>(
                                  future: _getCouponDetails(order.couponId!),
                                  builder: (context, snapshot) {
                                    if (snapshot.hasData && snapshot.data != null) {
                                      final coupon = snapshot.data!;
                                      final originalTotal = order.totalAmount + order.couponDiscount;
                                      return Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Icon(Icons.label, size: 16, color: Colors.grey.shade600),
                                              const SizedBox(width: 4),
                                              Text(
                                                'Kod: ${coupon['code'] ?? '-'}',
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  color: Colors.grey.shade700,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              Icon(Icons.info_outline, size: 16, color: Colors.grey.shade600),
                                              const SizedBox(width: 4),
                                              Text(
                                                coupon['title'] ?? 'İndirim',
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  color: Colors.grey.shade700,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          Container(
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Text(
                                                  'Orijinal Tutar:',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.grey.shade600,
                                                  ),
                                                ),
                                                Text(
                                                  '₺${originalTotal.toStringAsFixed(2)}',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    decoration: TextDecoration.lineThrough,
                                                    color: Colors.grey.shade600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      );
                                    }
                                    return const SizedBox.shrink();
                                  },
                                ),
                            ],
                          ),
                        ),
                      ],
                      
                      // Teslimat Adresi - kuryesi olmayan satıcıda gizli
                      if (!_hideCustomerInfo) ...[
                        if (order.addressDisplay != null && order.addressDisplay!.isNotEmpty) ...[
                          const SizedBox(height: 24),
                          const Text(
                            'Teslimat Adresi',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          const SizedBox(height: 12),
                          InkWell(
                            onTap: () => _openAddressInMap(order.addressDisplay!),
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.blue.shade200),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.shade100,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(Icons.location_on, color: Colors.blue.shade700, size: 24),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      order.addressDisplay!,
                                      style: TextStyle(color: Colors.blue.shade900, fontSize: 14),
                                    ),
                                  ),
                                  Icon(Icons.open_in_new, color: Colors.blue.shade700, size: 16),
                                ],
                              ),
                            ),
                          ),
                        ],
                        // Müşteri Telefonu ve Ara Butonu - kuryesi olmayan satıcıda gizli
                        if (!_hideCustomerInfo && order.customerPhone != null && order.customerPhone!.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.green.shade200),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: Colors.green.shade100,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Icon(Icons.phone, color: Colors.green.shade700, size: 24),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Müşteri Telefonu',
                                            style: TextStyle(
                                              color: Colors.green.shade600,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            order.customerPhone!,
                                            style: TextStyle(
                                              color: Colors.green.shade900,
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed: () => _callCustomer(order.customerPhone!),
                                    icon: const Icon(Icons.call, size: 18),
                                    label: const Text('Müşteriyi Ara'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ] else ...[
                        // Bilgiler gizli uyarı
                        const SizedBox(height: 24),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.orange.shade200),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.visibility_off, color: Colors.orange.shade700, size: 28),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Müşteri Bilgileri Gizli',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.orange.shade800,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Bu sipariş platform kuryesi tarafından teslim edileceği için müşteri bilgileri gizlidir.',
                                      style: TextStyle(
                                        color: Colors.orange.shade700,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      // Sipariş Notları
                      if (order.deliveryNotes != null && order.deliveryNotes!.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        const Text(
                          'Sipariş Notu',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade50,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.amber.shade200),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.note, color: Colors.amber.shade700, size: 20),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  order.deliveryNotes!,
                                  style: TextStyle(color: Colors.amber.shade900, fontSize: 14),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      // Ürünler
                      const SizedBox(height: 24),
                      const Text(
                        'Ürünler',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 12),
                      ...order.items.map((item) => Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF97316).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(Icons.fastfood, color: const Color(0xFFF97316), size: 20),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.productName,
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '₺${item.price.toStringAsFixed(2)} x ${item.quantity}',
                                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              '₺${item.subtotal.toStringAsFixed(2)}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFFF97316)),
                            ),
                          ],
                        ),
                      )),

                      const SizedBox(height: 24),
                      
                      // İptal butonu kaldırıldı - Sadece müşteri ve admin sipariş iptal edebilir
                      
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(context),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFF97316),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            elevation: 0,
                          ),
                          child: const Text('Kapat', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
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

  Widget _buildInfoCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(color: color.withOpacity(0.8), fontSize: 11, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  String _getPaymentMethodText(PaymentMethod method) {
    switch (method) {
      case PaymentMethod.cash:
        return 'Nakit';
      case PaymentMethod.cardOnDelivery:
        return 'Kapıda Kart';
      case PaymentMethod.online:
        return 'Online Ödeme';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1E293B),
        title: const Text('Siparişler', style: TextStyle(fontWeight: FontWeight.bold)),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          indicatorColor: const Color(0xFFF97316),
          labelColor: const Color(0xFFF97316),
          unselectedLabelColor: const Color(0xFF64748B),
          indicatorWeight: 3,
          tabs: const [
            Tab(text: 'Tümü'),
            Tab(text: 'Bekleyen'),
            Tab(text: 'Onaylı'),
            Tab(text: 'Hazırlanıyor'),
            Tab(text: 'Hazır'),
            Tab(text: 'Yolda'),
            Tab(text: 'Geçmiş'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFF97316)))
          : _orders.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF97316).withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.receipt_long, size: 50, color: Color(0xFFF97316)),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Henüz sipariş yok',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Siparişler burada görünecek',
                        style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadOrders,
                  color: const Color(0xFFF97316),
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _orders.length,
                    itemBuilder: (context, index) => _buildOrderCard(_orders[index]),
                  ),
                ),
    );
  }

  Widget _buildOrderCard(Order order) {
    final statusColor = _getStatusColor(order.status);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: statusColor.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showOrderDetailDialog(order),
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: statusColor.withOpacity(0.2), width: 2),
            ),
            child: Column(
              children: [
                // Header Row
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [statusColor, statusColor.withOpacity(0.7)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: statusColor.withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Icon(_getStatusIcon(order.status), color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '#${order.id.substring(0, 8).toUpperCase()}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 0.5),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${order.createdAt.day}.${order.createdAt.month}.${order.createdAt.year} ${order.createdAt.hour}:${order.createdAt.minute.toString().padLeft(2, '0')}',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _getStatusText(order.status),
                        style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 16),
                Container(height: 1, color: Colors.grey.shade200),
                const SizedBox(height: 16),

                // Müşteri Telefonu ve Adres - kuryesi olmayan satıcıda gizli
                if (!_hideCustomerInfo) ...[
                  if (order.customerPhone != null && order.customerPhone!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.green.shade200),
                            ),
                            child: Icon(Icons.phone, size: 14, color: Colors.green.shade700),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              order.customerPhone!,
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.green.shade700),
                            ),
                          ),
                        ],
                      ),
                    ),
                  
                  if (order.addressDisplay != null && order.addressDisplay!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.blue.shade200),
                            ),
                            child: Icon(Icons.location_on, size: 14, color: Colors.blue.shade700),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              order.addressDisplay!,
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.blue.shade700),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                ] else ...[
                  // Bilgiler gizli uyarı
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.visibility_off, size: 16, color: Colors.orange.shade700),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Müşteri bilgileri platform kuryesi tarafından teslim edileceği için gizlidir',
                            style: TextStyle(fontSize: 11, color: Colors.orange.shade700),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 12),
                Container(height: 1, color: Colors.grey.shade200),
                const SizedBox(height: 12),

                // Content Row
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.shopping_bag, size: 16, color: Colors.grey.shade600),
                              const SizedBox(width: 6),
                              Text(
                                '${order.items.length} ürün',
                                style: TextStyle(fontSize: 13, color: Colors.grey.shade700, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          // Ürün görselleri yatay liste
                          SizedBox(
                            height: 52,
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              itemCount: order.items.length > 5 ? 5 : order.items.length,
                              itemBuilder: (context, index) {
                                final item = order.items[index];
                                return Container(
                                  margin: const EdgeInsets.only(right: 6),
                                  child: Stack(
                                    children: [
                                      Container(
                                        width: 48,
                                        height: 48,
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(10),
                                          color: Colors.grey.shade100,
                                          border: Border.all(color: Colors.grey.shade200),
                                        ),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(10),
                                          child: item.productImageUrl != null && item.productImageUrl!.isNotEmpty
                                              ? Image.network(
                                                  item.productImageUrl!,
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (_, __, ___) => Icon(Icons.shopping_bag_outlined, size: 22, color: Colors.grey.shade400),
                                                )
                                              : Icon(Icons.shopping_bag_outlined, size: 22, color: Colors.grey.shade400),
                                        ),
                                      ),
                                      if (item.quantity > 1)
                                        Positioned(
                                          right: 0,
                                          top: 0,
                                          child: Container(
                                            padding: const EdgeInsets.all(3),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFF97316),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              'x${item.quantity}',
                                              style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                          if (order.items.length > 5)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                '+${order.items.length - 5} ürün daha',
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontStyle: FontStyle.italic),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FittedBox(
                          child: Text(
                            '₺${order.totalAmount.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFF97316),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildStatusActions(order),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusActions(Order order) {
    // Kuryesi olmayan satıcılar için kurye çağır butonu (sadece hazır durumunda)
    final showCallCourierButton = !_hasOwnCourier &&
        order.status == OrderStatus.ready;

    switch (order.status) {
      case OrderStatus.pending:
        return _buildActionButton(
          icon: Icons.check_circle,
          label: 'Onayla',
          color: const Color(0xFF10B981),
          onTap: () => _updateOrderStatus(order, OrderStatus.confirmed),
        );

      case OrderStatus.confirmed:
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.end,
          children: [
            _buildActionButton(
              icon: Icons.restaurant_menu,
              label: 'Hazırla',
              color: const Color(0xFF8B5CF6),
              onTap: () => _updateOrderStatus(order, OrderStatus.preparing),
            ),
          ],
        );

      case OrderStatus.preparing:
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.end,
          children: [
            _buildActionButton(
              icon: Icons.inventory_2,
              label: 'Hazır',
              color: const Color(0xFF14B8A6),
              onTap: () => _updateOrderStatus(order, OrderStatus.ready),
            ),
            if (showCallCourierButton)
              _buildCallCourierButton(order),
          ],
        );

      case OrderStatus.ready:
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.end,
          children: [
            _buildActionButton(
              icon: Icons.two_wheeler,
              label: 'Yola Çıkar',
              color: const Color(0xFF6366F1),
              onTap: () => _updateOrderStatus(order, OrderStatus.onTheWay),
            ),
            if (showCallCourierButton)
              _buildCallCourierButton(order),
          ],
        );

      case OrderStatus.onTheWay:
        if (!_hasOwnCourier) {
          // Kuryesi olmayan satıcı: sipariş kuryede, buton gösterme
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.teal.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.teal.shade200),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.two_wheeler, size: 16, color: Colors.teal.shade700),
                const SizedBox(width: 6),
                Text(
                  'Kuryede',
                  style: TextStyle(
                    color: Colors.teal.shade700,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          );
        }
        // Kendi kuryesi olan satıcı: Teslim Et butonu
        return _buildActionButton(
          icon: Icons.task_alt,
          label: 'Teslim Et',
          color: const Color(0xFF10B981),
          onTap: () => _updateOrderStatus(order, OrderStatus.delivered),
        );

      case OrderStatus.delivered:
        // Teslim edilmiş siparişte sadece teslim edildi bilgisi
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.green.shade200),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle, size: 16, color: Colors.green.shade700),
              const SizedBox(width: 6),
              Text(
                'Teslim Edildi',
                style: TextStyle(
                  color: Colors.green.shade700,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        );

      default:
        return const SizedBox.shrink();
    }
  }

  /// Kurye çağır butonu - kuryesi olmayan satıcılar için
  Widget _buildCallCourierButton(Order order) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _callCourierForOrder(order),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.orange, Colors.orange.shade700],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.orange.withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.two_wheeler, size: 18, color: Colors.white),
              const SizedBox(width: 8),
              Text(
                'Kurye Çağır',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Kurye çağırma işlemi - siparişi otomatik olarak kuryeye atar
  Future<void> _callCourierForOrder(Order order) async {
    try {
      final shopName = (await _supabase.from('shops').select('name').eq('id', order.shopId).maybeSingle())?['name'] ?? 'Dükkan';

      // 1. Online olan bir kurye bul (aktif siparişi olmayan)
      final availableCouriers = await _supabase
          .from('profiles')
          .select('id, username, full_name, avatar_url, phone, email')
          .eq('role', 'courier')
          .eq('is_online', true)
          .limit(10);

      if (availableCouriers.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.warning, color: Colors.white),
                  SizedBox(width: 8),
                  Text('Şu an uygun kurye yok. Lütfen tekrar deneyin.'),
                ],
              ),
              backgroundColor: Colors.orange.shade600,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      // İlk müsait kuryeyi seç (daha sonra round-robin veya başka bir yöntem eklenebilir)
      final selectedCourier = availableCouriers.first;
      final courierId = selectedCourier['id'] as String;
      final courierName = selectedCourier['full_name'] ?? selectedCourier['username'] ?? 'Kurye';
      final courierPhone = selectedCourier['phone'] as String?;

      // 2. Kurye ücretini al
      final settings = await _supabase
          .from('courier_settings')
          .select('fee_per_delivery')
          .order('updated_at', ascending: false)
          .limit(1)
          .maybeSingle();
      final fee = (settings?['fee_per_delivery'] as num?)?.toDouble() ?? 15.0;

      debugPrint('📦 Sipariş atanıyor: ${order.id} → kurye: $courierId ($courierName), ücret: $fee');

      // 3. Önce bu siparişin zaten atanmış olup olmadığını kontrol et
      final existingAssignment = await _supabase
          .from('courier_assignments')
          .select('id')
          .eq('order_id', order.id)
          .maybeSingle();

      if (existingAssignment != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Bu sipariş zaten bir kuryeye atanmış'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // 4. Kurye ataması oluştur
      await _supabase.from('courier_assignments').insert({
        'order_id': order.id,
        'courier_id': courierId,
        'status': 'assigned',
        'fee_amount': fee,
        'assigned_at': DateTime.now().toIso8601String(),
      });

      // 4. Sipariş durumunu on_the_way yap
      await _supabase.from('orders').update({
        'status': 'on_the_way',
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', order.id);

      // 5. Kuryeye özel bildirim gönder
      await _supabase.from('notifications').insert({
        'user_id': courierId,
        'type': 'courier_new_order',
        'title': '📦 Yeni Sipariş Atandı!',
        'content': '$shopName mağazasından ₺${order.totalAmount.toStringAsFixed(2)} tutarında sipariş sizin atandı. Hemen teslim alın!',
        'data': {
          'order_id': order.id,
          'type': 'courier_assignment',
        },
        'is_read': false,
        'created_at': DateTime.now().toIso8601String(),
      });

      // 6. Kuryeye email bildirimi gönder
      try {
        final courierEmail = selectedCourier['email'] as String?;
        if (courierEmail != null && courierEmail.isNotEmpty) {
          final emailService = EmailService();
          await emailService.sendCourierNewOrderEmail(
            courierEmail: courierEmail,
            courierName: courierName,
            shopName: shopName,
            totalAmount: order.totalAmount,
            deliveryAddress: order.addressDisplay ?? 'Belirtilmedi',
            orderNumber: order.id.substring(0, 8),
          );
        }
      } catch (e) {
        debugPrint('⚠️ Kurye email gönderme hatası: $e');
      }

      // NOT: Müşteriye "Yolda" bildirimi kurye siparişi aldığında gönderilecek
      // (Kurye panelinde _acceptDelivery metodunda)

      if (mounted) {
        _loadOrders(); // Sipariş listesini yenile
        // Kurye bilgilerini gösteren dialog
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.teal.shade50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.two_wheeler, color: Colors.teal.shade700, size: 28),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text('Kurye Atandı!', style: TextStyle(fontSize: 18)),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Siparişiniz bir kuryeye atandı:',
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.teal.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.teal.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.person, color: Colors.teal.shade700, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              courierName,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Colors.teal.shade800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (courierPhone != null && courierPhone.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Icon(Icons.phone, color: Colors.teal.shade700, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                courierPhone,
                                style: TextStyle(
                                  fontSize: 15,
                                  color: Colors.teal.shade800,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.call, color: Colors.green),
                              onPressed: () {
                                Navigator.pop(ctx);
                                _callCustomer(courierPhone);
                              },
                              tooltip: 'Ara',
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              if (courierPhone != null && courierPhone.isNotEmpty)
                TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _callCustomer(courierPhone);
                  },
                  child: const Text('Kuryeyi Ara'),
                ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Tamam'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Kurye çağırma hatası: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Kurye çağırma hatası: $e'),
            backgroundColor: Colors.red.shade400,
          ),
        );
      }
    }
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [color, color.withOpacity(0.8)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: Colors.white),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Kupon detaylarını çek
  Future<Map<String, dynamic>?> _getCouponDetails(String couponId) async {
    try {
      final response = await _supabase
          .from('shop_coupons')
          .select('code, title, discount_type, discount_value, minimum_order_amount, usage_count')
          .eq('id', couponId)
          .maybeSingle();
      
      return response;
    } catch (e) {
      debugPrint('Kupon detayları alınırken hata: $e');
    }
    return null;
  }

  // Kullanıcı ID'sinden telefon numarasını çek (profiles tablosundan)
  Future<String?> _getCustomerPhone(String userId) async {
    try {
      final response = await _supabase
          .from('profiles')
          .select('phone')
          .eq('id', userId)
          .maybeSingle();
      
      if (response != null) {
        return response['phone'] as String?;
      }
    } catch (e) {
      debugPrint('Telefon numarası alınırken hata: $e');
    }
    return null;
  }

  // Müşteriyi ara
  Future<void> _callCustomer(String phoneNumber) async {
    try {
      final uri = Uri(scheme: 'tel', path: phoneNumber);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Arama yapılamadı'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Arama hatası: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Hata: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Adresi haritada aç
  Future<void> _openAddressInMap(String address) async {
    try {
      // Google Maps ile adresi aç
      final encodedAddress = Uri.encodeComponent(address);
      final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$encodedAddress');
      
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Harita uygulaması açılamadı'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Harita açma hatası: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Harita açılırken hata: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
