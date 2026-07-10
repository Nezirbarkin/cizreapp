import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../shop/services/cancellation_request_service.dart';

/// Admin "İptal Talepleri" sekmesi.
///
/// cancellation_requests tablosundaki pending kayıtları listeler.
/// Onayla/Reddet butonları ile admin karar verir.
///
/// İşlem (DB tarafında atomik RPC):
/// - Onayla: CancellationRequestService.approve → approve_cancellation_request RPC
///     ├─ orders.status = 'cancelled', payment_status = 'refunded' (iade varsa)
///     ├─ refund_method='balance' ise add_to_balance RPC ile bakiyeye iade
///     ├─ restore_product_stock trigger'ı stokları geri yükler (confirmed->cancelled)
///     └─ müşteriye notification ('cancellation_approved')
/// - Reddet: CancellationRequestService.reject → reject_cancellation_request RPC
///     └─ status=rejected + müşteriye notification ('cancellation_rejected')
class CancellationRequestsTabWidget extends StatefulWidget {
  const CancellationRequestsTabWidget({super.key});

  @override
  State<CancellationRequestsTabWidget> createState() =>
      _CancellationRequestsTabWidgetState();
}

class _CancellationRequestsTabWidgetState
    extends State<CancellationRequestsTabWidget> {
  final CancellationRequestService _service = CancellationRequestService();
  final NumberFormat _tl = NumberFormat.currency(
    locale: 'tr_TR',
    symbol: '₺',
    decimalDigits: 2,
  );
  final DateFormat _date = DateFormat('dd.MM.yyyy HH:mm');

  bool _isLoading = true;
  List<CancellationRequest> _pending = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final list = await _service.getPendingRequests();
      if (!mounted) return;
      setState(() {
        _pending = list;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('İptal talepleri yüklenemedi: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _approve(CancellationRequest req) async {
    // Onay öncesi son uyarı
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('İptal Talebini Onayla'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Sipariş #${_orderLabel(req)} iptal edilecek.'),
            const SizedBox(height: 8),
            if (req.hasRefund)
              Text(
                'Onaylandığında ₺${req.refundAmount.toStringAsFixed(2)} '
                'kullanıcının bakiyesine OTOMATİK eklenecek ve bildirim gönderilecek.',
                style: TextStyle(color: Colors.green.shade700),
              )
            else
              Text(
                'Bu siparişte iade yok (${_paymentLabel(req.paymentMethod)}). '
                'Sipariş iptal edilecek ve kullanıcı bilgilendirilecek.',
                style: TextStyle(color: Colors.grey.shade700),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Onayla'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    try {
      await _service.approve(requestId: req.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            req.hasRefund
                ? 'Onaylandı. ₺${req.refundAmount.toStringAsFixed(2)} bakiyeye iade edildi.'
                : 'Onaylandı. Sipariş iptal edildi.',
          ),
          backgroundColor: Colors.green,
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Onay başarısız: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  Future<void> _reject(CancellationRequest req) async {
    final adminNote = await showDialog<String?>(
      context: context,
      builder: (ctx) {
        final ctrl = TextEditingController();
        return AlertDialog(
          title: const Text('İptal Talebini Reddet'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Sipariş #${_orderLabel(req)} için iptal talebi reddedilecek. '
                  'Kullanıcıya bildirim gidecek.'),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                maxLines: 3,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Red Gerekçesi (kullanıcıya iletilecek)',
                  hintText: 'Örn: Sipariş hazırlanmış durumda, iptal edilemez',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Vazgeç'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () {
                final note = ctrl.text.trim();
                if (note.length < 3) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(
                      content: Text('Red gerekçesi en az 3 karakter olmalı'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  return;
                }
                Navigator.pop(ctx, note);
              },
              child: const Text('Reddet'),
            ),
          ],
        );
      },
    );
    if (adminNote == null || !mounted) return;

    try {
      await _service.reject(
        requestId: req.id,
        adminResponse: adminNote,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Reddedildi. Kullanıcıya bildirim gönderildi.'),
          backgroundColor: Colors.orange,
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Red başarısız: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  String _orderLabel(CancellationRequest req) {
    return req.orderNumber ?? req.orderId.substring(0, 8).toUpperCase();
  }

  String _paymentLabel(String method) {
    switch (method) {
      case 'balance':
        return 'Bakiye ile Ödeme';
      case 'online':
        return 'Online Ödeme';
      case 'cash':
        return 'Kapıda Nakit';
      case 'card_on_delivery':
        return 'Kapıda Kart';
      default:
        return method;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_pending.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            const Text(
              'Bekleyen iptal talebi yok',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('Yenile'),
              onPressed: _load,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _pending.length,
        itemBuilder: (context, i) {
          final req = _pending[i];
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Başlık: sipariş no + müşteri + iade tutarı
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: Colors.orange.shade100,
                        child: Icon(Icons.cancel_outlined,
                            color: Colors.orange.shade800),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Sipariş #${_orderLabel(req)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                            Text(
                              req.customerName ?? 'Müşteri',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (req.hasRefund)
                        Text(
                          _tl.format(req.refundAmount),
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade700,
                          ),
                        )
                      else
                        Text(
                          'İade Yok',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Meta satırı: mağaza + ödeme yöntemi + zaman
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      _metaChip(Icons.store, req.shopName ?? '-'),
                      _metaChip(Icons.payment, _paymentLabel(req.paymentMethod)),
                      _metaChip(
                        Icons.access_time,
                        _date.format(req.createdAt.toLocal()),
                      ),
                    ],
                  ),

                  // İptal sebebi
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.note, size: 14, color: Colors.grey.shade700),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            req.reason,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // İade önizlemesi (varsa)
                  if (req.hasRefund) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.account_balance_wallet,
                              size: 14, color: Colors.green.shade700),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Onayda ${_tl.format(req.refundAmount)} bakiyeye iade',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.green.shade800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Aksiyon butonları
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _reject(req),
                          icon: const Icon(Icons.close, size: 16),
                          label: const Text('Reddet'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _approve(req),
                          icon: const Icon(Icons.check, size: 16),
                          label: const Text('Onayla'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 10),
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
    );
  }

  Widget _metaChip(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.grey.shade600),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
      ],
    );
  }
}