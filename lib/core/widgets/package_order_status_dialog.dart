import 'package:flutter/material.dart';

import '../models/digital_order_model.dart';
import '../services/smm_service.dart';

/// Paket (manuel teslim) dijital siparişini kapatma akışı — satıcı ve
/// yönetici ekranları ortak kullanır.
///
/// Onay penceresi açar, seçilen kararı `digital-package-order-status`'a
/// gönderir ve sonucu SnackBar ile bildirir. Durum değiştiyse true döner.
/// - Teslim edildi → satıcıya net kazanç (dijital komisyon düşülür)
/// - İptal → müşteriye tam iade (puan puana, TL TL bakiyeye)
Future<bool> closePackageOrderFlow(
  BuildContext context, {
  required DigitalOrder order,
  required SmmService service,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  if (!order.awaitingSellerDelivery) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Bu paket siparişi zaten kapanmış')),
    );
    return false;
  }

  final selected = await showDialog<String>(
    context: context,
    builder: (context) => _PackageOrderStatusDialog(order: order),
  );
  if (selected == null) return false;

  try {
    final result = await service.setPackageOrderStatus(
      digitalOrderId: order.id,
      newStatus: selected,
    );
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          selected == 'completed'
              ? 'Paket teslim edildi olarak işaretlendi'
              : 'Sipariş iptal edildi. İade: ${result.pointsRefunded} puan + '
                    '${result.cashRefundedTry.toStringAsFixed(2)} TL',
        ),
        backgroundColor: Colors.green,
      ),
    );
    return true;
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Güncellenemedi: $e')));
    return false;
  }
}

class _PackageOrderStatusDialog extends StatefulWidget {
  const _PackageOrderStatusDialog({required this.order});

  final DigitalOrder order;

  @override
  State<_PackageOrderStatusDialog> createState() =>
      _PackageOrderStatusDialogState();
}

class _PackageOrderStatusDialogState extends State<_PackageOrderStatusDialog> {
  String _selected = 'completed';

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    return AlertDialog(
      title: const Text('Paket Siparişi'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${order.productName ?? 'Dijital paket'} · '
            '₺${order.grossTotalTry.toStringAsFixed(2)}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          SelectableText(
            order.targetUrl,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 8),
          RadioListTile<String>(
            contentPadding: EdgeInsets.zero,
            title: const Text('Teslim edildi'),
            subtitle: const Text('Kazancınız bakiyenize eklenir'),
            value: 'completed',
            // ignore: deprecated_member_use
            groupValue: _selected,
            // ignore: deprecated_member_use
            onChanged: (v) => setState(() => _selected = v!),
          ),
          RadioListTile<String>(
            contentPadding: EdgeInsets.zero,
            title: const Text('İptal et'),
            subtitle: const Text('Müşteriye tam iade (puan/TL kaynağına)'),
            value: 'canceled',
            // ignore: deprecated_member_use
            groupValue: _selected,
            // ignore: deprecated_member_use
            onChanged: (v) => setState(() => _selected = v!),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _selected),
          child: const Text('Kaydet'),
        ),
      ],
    );
  }
}
