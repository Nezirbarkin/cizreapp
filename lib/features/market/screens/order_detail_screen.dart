import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/order_model.dart';
import '../../shop/services/order_service.dart';
import '../../shop/services/return_request_service.dart';

class OrderDetailScreen extends StatefulWidget {
  final Order order;

  const OrderDetailScreen({
    super.key,
    required this.order,
  });

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  late Order _currentOrder;
  final OrderService _orderService = OrderService();
  final ReturnRequestService _returnRequestService = ReturnRequestService();
  RealtimeChannel? _orderChannel;
  bool _hasReturnRequest = false;

  @override
  void initState() {
    super.initState();
    _currentOrder = widget.order;
    _setupRealtimeSubscription();
    _checkReturnRequest();
  }

  Future<void> _checkReturnRequest() async {
    final returnRequest = await _returnRequestService.getReturnRequestByOrderId(_currentOrder.id);
    if (mounted) {
      setState(() {
        _hasReturnRequest = returnRequest != null;
      });
    }
  }

  @override
  void dispose() {
    _orderChannel?.unsubscribe();
    super.dispose();
  }

  void _setupRealtimeSubscription() {
    _orderChannel = Supabase.instance.client
        .channel('order_${_currentOrder.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'orders',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: _currentOrder.id,
          ),
          callback: (payload) {
            debugPrint('Sipariş güncellendi: ${payload.newRecord}');
            // Sipariş güncellendiğinde veriyi yeniden yükle
            _loadOrderDetails();
          },
        )
        .subscribe();
  }

  Future<void> _loadOrderDetails() async {

    try {
      final updatedOrder = await _orderService.getOrderById(_currentOrder.id);
      if (updatedOrder != null && mounted) {
        setState(() {
          _currentOrder = updatedOrder;
        });
      }
    } catch (e) {
      debugPrint('Sipariş yüklenirken hata: $e');
      if (mounted) {
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Text('Sipariş #${_currentOrder.id.substring(0, 8).toUpperCase()}'),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Durum Takibi
            _buildStatusTimeline(),
            const SizedBox(height: 24),

            // Sipariş Bilgileri
            _buildOrderInfoCard(),
            const SizedBox(height: 16),

            // Ürünler
            _buildOrderItemsCard(),
            const SizedBox(height: 16),

            // Ödeme ve Fiyat Detayları
            _buildPricingCard(),
            const SizedBox(height: 16),

            // Teslimat Bilgileri
            _buildDeliveryInfoCard(),
            const SizedBox(height: 16),

            // Ödeme Yöntemi
            _buildPaymentMethodCard(),
            const SizedBox(height: 16),

            // İptal ve İade Butonları
            _buildActionButtons(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    // Sadece belirli durumlarda butonları göster
    final canCancel = _currentOrder.status == OrderStatus.pending ||
                      _currentOrder.status == OrderStatus.confirmed;
    final canReturn = _currentOrder.status == OrderStatus.delivered && !_hasReturnRequest;

    if (!canCancel && !canReturn) {
      return const SizedBox.shrink();
    }

    // Eğer iade talebi varsa bilgi göster
    if (_hasReturnRequest && _currentOrder.status == OrderStatus.delivered) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.blue.shade200),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline, color: Colors.blue.shade700),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Bu sipariş için iade talebi oluşturuldu. Satıcı tarafından değerlendiriliyor.',
                style: TextStyle(
                  color: Colors.blue.shade900,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // İptal Butonu
        if (canCancel)
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _showCancelDialog(),
              icon: const Icon(Icons.cancel_outlined, color: Colors.red),
              label: const Text('Siparişi İptal Et'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        
        // İade Butonu
        if (canReturn) ...[
          if (canCancel) const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _showReturnDialog(),
              icon: const Icon(Icons.assignment_return_outlined, color: Colors.orange),
              label: const Text('İade Talebi Oluştur'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.orange,
                side: const BorderSide(color: Colors.orange),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _showCancelDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange),
            SizedBox(width: 8),
            Text('Siparişi İptal Et'),
          ],
        ),
        content: const Text(
          'Bu siparişi iptal etmek istediğinizden emin misiniz? Bu işlem geri alınamaz.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('İptal Et'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _orderService.cancelOrder(_currentOrder.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Sipariş başarıyla iptal edildi'),
              backgroundColor: Colors.green,
            ),
          );
          // Sipariş detaylarını yenile
          await _loadOrderDetails();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('İptal işlemi başarısız: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _showReturnDialog() async {
    final reasonController = TextEditingController();
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.assignment_return, color: Colors.orange),
            SizedBox(width: 8),
            Text('İade Talebi'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'İade sebebinizi belirtiniz:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Örn: Ürün hasarlı geldi, yanlış ürün gönderildi...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'İade talebiniz satıcı tarafından değerlendirilecektir.',
                      style: TextStyle(fontSize: 12, color: Colors.blue),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              reasonController.dispose();
              Navigator.pop(context, false);
            },
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            onPressed: () {
              if (reasonController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Lütfen iade sebebini belirtiniz'),
                    backgroundColor: Colors.orange,
                  ),
                );
                return;
              }
              Navigator.pop(context, true);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            child: const Text('İade Talebi Oluştur'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        debugPrint('📦 ORDER DETAIL: İade talebi oluşturuluyor...');
        debugPrint('  └─ orderId: ${_currentOrder.id}');
        debugPrint('  └─ userId: ${_currentOrder.userId}');
        debugPrint('  └─ shopId: ${_currentOrder.shopId}');
        debugPrint('  └─ reason: ${reasonController.text.trim()}');
        
        // İade talebini veritabanına kaydet
        await _returnRequestService.createReturnRequest(
          orderId: _currentOrder.id,
          userId: _currentOrder.userId,
          shopId: _currentOrder.shopId,
          reason: reasonController.text.trim(),
        );

        if (mounted) {
          setState(() {
            _hasReturnRequest = true;
          });
          
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('İade talebiniz başarıyla oluşturuldu. Satıcı ile iletişime geçilecektir.'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('İade talebi oluşturulurken hata: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
    
    reasonController.dispose();
  }

  Widget _buildStatusTimeline() {
    final statuses = [
      OrderStatus.pending,
      OrderStatus.confirmed,
      OrderStatus.preparing,
      OrderStatus.ready,
      OrderStatus.onTheWay,
      OrderStatus.delivered,
    ];

    final currentIndex = statuses.indexOf(_currentOrder.status);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Sipariş Durumu',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: List.generate(
                statuses.length,
                (index) {
                  final status = statuses[index];
                  final isCompleted = index < currentIndex;
                  final isActive = index == currentIndex;

                  return Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: isCompleted || isActive
                                  ? Colors.green
                                  : Colors.grey.shade300,
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: isCompleted
                                  ? const Icon(Icons.check, color: Colors.white)
                                  : Text(
                                      '${index + 1}',
                                      style: TextStyle(
                                        color: isCompleted || isActive
                                            ? Colors.white
                                            : Colors.grey.shade600,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  status.label,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: isActive
                                        ? Theme.of(context).colorScheme.primary
                                        : Colors.black,
                                  ),
                                ),
                                if (isCompleted && status == OrderStatus.delivered && _currentOrder.deliveredAt != null)
                                  Text(
                                    _formatDateTime(_currentOrder.deliveredAt!),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                    ),
                                  )
                                else if (status == OrderStatus.pending)
                                  Text(
                                    _formatDateTime(_currentOrder.createdAt),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (index < statuses.length - 1)
                        Padding(
                          padding: const EdgeInsets.only(left: 20, top: 8, bottom: 8),
                          child: Container(
                            width: 2,
                            height: 20,
                            color: isCompleted
                                ? Colors.green
                                : Colors.grey.shade300,
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOrderInfoCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Sipariş Bilgileri',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 12),
            _buildInfoRow('Sipariş Tarihi', _formatDateTime(_currentOrder.createdAt)),
            const SizedBox(height: 8),
            _buildInfoRow('Sipariş No', _currentOrder.id.substring(0, 12).toUpperCase()),
            const SizedBox(height: 8),
            _buildInfoRow('Dükkan', _currentOrder.shopName ?? 'Bilinmiyor'),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderItemsCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Ürünler',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: List.generate(
                _currentOrder.items.length,
                (index) {
                  final item = _currentOrder.items[index];
                  return Column(
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (item.productImageUrl != null)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(
                                item.productImageUrl!,
                                width: 60,
                                height: 60,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) =>
                                    Container(
                                  width: 60,
                                  height: 60,
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade200,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(Icons.image),
                                ),
                              ),
                            )
                          else
                            Container(
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(
                                color: Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.image),
                            ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.productName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Fiyat: ₺${item.price.toStringAsFixed(2)}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Miktar: ${item.quantity}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '₺${item.subtotal.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      if (index < _currentOrder.items.length - 1)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Divider(color: Colors.grey.shade300),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPricingCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildPricingRow('Ara Toplam', _currentOrder.subtotal),
            if (_currentOrder.discountAmount > 0) ...[
              const SizedBox(height: 8),
              _buildPricingRow(
                'İndirim',
                -_currentOrder.discountAmount,
                isDiscount: true,
              ),
            ],
            const SizedBox(height: 8),
            _buildPricingRow('Teslimat Ücreti', _currentOrder.deliveryFee),
            const Divider(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Toplam Tutarı',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                Text(
                  '₺${_currentOrder.totalAmount.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeliveryInfoCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Teslimat Bilgileri',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 12),
            if (_currentOrder.addressDisplay != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.location_on,
                        color: Theme.of(context).colorScheme.primary,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _currentOrder.addressDisplay!,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            if (_currentOrder.estimatedDeliveryTime != null)
              _buildInfoRow(
                'Tahmini Teslimat',
                _formatDateTime(_currentOrder.estimatedDeliveryTime!),
              ),
            if (_currentOrder.deliveryNotes != null && _currentOrder.deliveryNotes!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Teslimat Notu',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _currentOrder.deliveryNotes!,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentMethodCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Ödeme Bilgileri',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 12),
            _buildInfoRow('Ödeme Yöntemi', _currentOrder.paymentMethod.label),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Ödeme Durumu',
                  style: TextStyle(fontSize: 14),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: _currentOrder.isPaid ? Colors.green.shade100 : Colors.orange.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _currentOrder.isPaid ? 'Ödendi' : 'Bekleniyor',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: _currentOrder.isPaid ? Colors.green.shade700 : Colors.orange.shade700,
                    ),
                  ),
                ),
              ],
            ),
            // Sipariş teslim edildiyse ödeme durumunu vurgula
            if (_currentOrder.status == OrderStatus.delivered) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _currentOrder.isPaid
                      ? Colors.green.shade50
                      : Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _currentOrder.isPaid
                        ? Colors.green.shade200
                        : Colors.orange.shade200,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _currentOrder.isPaid
                          ? Icons.check_circle_outline
                          : Icons.info_outline,
                      color: _currentOrder.isPaid
                          ? Colors.green.shade700
                          : Colors.orange.shade700,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _currentOrder.isPaid
                            ? 'Ödemeniz başarıyla tamamlandı. Siparişiniz teslim edildi.'
                            : 'Ödeme durumu: Bekliyor. Lütfen teslim sırasında ödeme yapınız.',
                        style: TextStyle(
                          fontSize: 12,
                          color: _currentOrder.isPaid
                              ? Colors.green.shade900
                              : Colors.orange.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 14),
        ),
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
      ],
    );
  }

  Widget _buildPricingRow(String label, double value, {bool isDiscount = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 14),
        ),
        Text(
          '${isDiscount ? '-' : ''}₺${value.abs().toStringAsFixed(2)}',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: isDiscount ? Colors.green : Colors.black,
          ),
        ),
      ],
    );
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day.toString().padLeft(2, '0')}/${dateTime.month.toString().padLeft(2, '0')}/${dateTime.year} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }
}
