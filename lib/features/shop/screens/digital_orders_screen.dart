// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/models/digital_order_model.dart';
import '../../../core/services/smm_service.dart';
import 'digital_order_detail_screen.dart';

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
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
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
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      order.productName ?? 'Dijital Ürün',
                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: _statusColor(order.status).withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      order.status.label,
                                      style: TextStyle(
                                        color: _statusColor(order.status),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(order.targetUrl, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Text('Miktar: ${order.quantity}', style: const TextStyle(fontSize: 13)),
                                  const SizedBox(width: 16),
                                  Text(
                                    'Tutar: ₺${order.totalPrice.toStringAsFixed(2)}',
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ],
                              ),
                              if (order.remains != null) ...[
                                const SizedBox(height: 4),
                                Text('Kalan: ${order.remains}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                              ],
                              const SizedBox(height: 4),
                              Text(
                                'Oluşturulma: ${DateFormat('dd.MM.yyyy HH:mm').format(order.createdAt)}',
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
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
