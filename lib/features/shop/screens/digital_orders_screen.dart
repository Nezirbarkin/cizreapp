// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/models/digital_order_model.dart';
import '../../../core/services/smm_service.dart';
import 'digital_order_detail_screen.dart';

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.blue.shade700),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 12, color: Colors.blue.shade800, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class DigitalOrdersContent extends StatefulWidget {
  const DigitalOrdersContent({super.key});

  @override
  State<DigitalOrdersContent> createState() => _DigitalOrdersContentState();
}

class _DigitalOrdersContentState extends State<DigitalOrdersContent> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final _smmService = SmmService();
  bool _isLoading = true;
  List<DigitalOrder> _orders = [];
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  Future<void> _loadOrders() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final orders = await _smmService.getMyDigitalOrders();
      if (mounted) setState(() => _orders = orders);
    } catch (e) {
      if (mounted) setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _refresh() async {
    await _smmService.refreshDigitalOrdersStatus();
    await _loadOrders();
  }

  Color _statusColor(DigitalOrderStatus status) {
    switch (status) {
      case DigitalOrderStatus.completed:
        return Colors.green;
      case DigitalOrderStatus.inProgress:
      case DigitalOrderStatus.pending:
        return Colors.orange;
      case DigitalOrderStatus.partial:
        return Colors.amber;
      case DigitalOrderStatus.canceled:
      case DigitalOrderStatus.failed:
        return Colors.red;
      case DigitalOrderStatus.refunded:
        return Colors.blueGrey;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline, size: 48, color: Colors.red.shade400),
                        const SizedBox(height: 16),
                        Text(
                          'Siparişler yüklenemedi:\n$_errorMessage',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.red.shade700),
                        ),
                        const SizedBox(height: 16),
                        FilledButton(onPressed: _loadOrders, child: const Text('Tekrar Dene')),
                      ],
                    ),
                  ),
                )
              : _orders.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.smart_toy_outlined, size: 48, color: Colors.grey.shade400),
                      const SizedBox(height: 16),
                      const Text('Henüz dijital siparişiniz yok'),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _orders.length,
                    itemBuilder: (context, index) {
                      final order = _orders[index];
                      final statusColor = _statusColor(order.status);
                      return Container(
                        margin: const EdgeInsets.only(bottom: 14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey.shade200),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => DigitalOrderDetailScreen(order: order)),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [statusColor.withOpacity(0.85), statusColor],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Icon(Icons.bolt, color: Colors.white, size: 20),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        order.productName ?? 'Dijital Ürün',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                      decoration: BoxDecoration(
                                        color: statusColor.withOpacity(0.12),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        order.status.label,
                                        style: TextStyle(
                                          color: statusColor,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade50,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.link, size: 14, color: Colors.grey.shade500),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          order.targetUrl,
                                          style: TextStyle(color: Colors.grey.shade700, fontSize: 12.5),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    _InfoChip(icon: Icons.format_list_numbered, label: '${order.quantity} adet'),
                                    const SizedBox(width: 8),
                                    _InfoChip(icon: Icons.payments_outlined, label: '₺${order.totalPrice.toStringAsFixed(2)}'),
                                    if (order.remains != null) ...[
                                      const SizedBox(width: 8),
                                      _InfoChip(icon: Icons.hourglass_bottom, label: 'Kalan ${order.remains}'),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  DateFormat('dd.MM.yyyy HH:mm').format(order.createdAt.toLocal()),
                                  style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                );
  }
}
