import 'package:flutter/material.dart';

import '../services/return_request_service.dart';

/// Kartı kimin gördüğü: hangi tutarın/kimin adının gösterileceğini belirler.
enum ReturnCardViewer { customer, seller, admin }

/// Müşteri, satıcı ve yönetici iade listelerinin ortak kartı.
/// Eylem düğmeleri [actions] ile dışarıdan verilir.
class ReturnRequestCard extends StatelessWidget {
  final ReturnRequest request;
  final ReturnCardViewer viewer;
  final List<Widget> actions;

  const ReturnRequestCard({
    super.key,
    required this.request,
    required this.viewer,
    this.actions = const [],
  });

  static ({Color color, IconData icon}) statusStyle(ReturnRequestStatus s) {
    switch (s) {
      case ReturnRequestStatus.pending:
        return (color: Colors.orange, icon: Icons.hourglass_top);
      case ReturnRequestStatus.approved:
        return (color: Colors.green, icon: Icons.check_circle);
      case ReturnRequestStatus.rejected:
        return (color: Colors.red, icon: Icons.cancel);
      case ReturnRequestStatus.completed:
        return (color: Colors.blue, icon: Icons.task_alt);
      case ReturnRequestStatus.cancelled:
        return (color: Colors.grey, icon: Icons.undo);
    }
  }

  /// Duruma göre bir satırlık açıklama (kime ne yapması gerektiği).
  String? _statusHint() {
    switch (request.status) {
      case ReturnRequestStatus.pending:
        return viewer == ReturnCardViewer.admin
            ? null
            : 'Yönetici incelemesinde.';
      case ReturnRequestStatus.approved:
        switch (viewer) {
          case ReturnCardViewer.customer:
            if (request.isRefunded) {
              return 'Tutar bakiyenize eklendi. Ürünleri satıcıya teslim edin.';
            }
            return request.isSellerCashRefund
                ? 'Ürünleri teslim ederken iade tutarını satıcıdan nakit alacaksınız.'
                : 'Ürünleri satıcıya teslim edin; satıcı teslim aldığını onaylayınca '
                    'tutar bakiyenize eklenecek.';
          case ReturnCardViewer.seller:
            if (request.isRefunded) {
              return 'Yönetici müşteriye bakiyeden iade etti; nakit vermeyin. Ürünleri '
                  'teslim alınca "Teslim Aldım" deyin.';
            }
            return request.isSellerCashRefund
                ? 'Ürünleri teslim alırken müşteriye iade tutarını nakit verin, sonra "Teslim Aldım" deyin.'
                : 'Ürünleri müşteriden teslim alınca "Teslim Aldım" deyin; onayınızla '
                    'tutar müşterinin bakiyesine iade edilir.';
          case ReturnCardViewer.admin:
            return request.isRefunded
                ? 'Para iade edildi; satıcının ürünleri teslim alması bekleniyor.'
                : 'Satıcının ürünleri teslim alması bekleniyor; para iadesi teslimde yapılır.';
        }
      case ReturnRequestStatus.completed:
        final paid = request.isSellerCashRefund
            ? 'Tutar satıcı tarafından nakit iade edildi.'
            : 'Tutar müşterinin bakiyesine iade edildi.';
        return request.restocked
            ? 'Ürünler satıcıya ulaştı ve stoğa geri eklendi. $paid'
            : 'Ürünler satıcıya ulaştı. $paid';
      case ReturnRequestStatus.rejected:
      case ReturnRequestStatus.cancelled:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = statusStyle(request.status);
    final hint = _statusHint();
    final orderLabel =
        request.orderNumber ?? (request.orderId.length > 8 ? request.orderId.substring(0, 8) : request.orderId).toUpperCase();
    final subtitle = switch (viewer) {
      ReturnCardViewer.customer => request.shopName ?? 'Mağaza',
      ReturnCardViewer.seller => request.customerName ?? 'Müşteri',
      ReturnCardViewer.admin =>
        '${request.customerName ?? 'Müşteri'} · ${request.shopName ?? 'Mağaza'}',
    };
    final showSellerAmount =
        viewer != ReturnCardViewer.customer && request.sellerDebitAmount > 0;
    final showCommission = viewer != ReturnCardViewer.customer &&
        request.isSellerCashRefund &&
        request.commissionRefundAmount > 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Sipariş #$orderLabel',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: style.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(style.icon, size: 14, color: style.color),
                      const SizedBox(width: 4),
                      Text(
                        request.status.label,
                        style: TextStyle(
                          color: style.color,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              request.isFullReturn
                  ? 'Tüm sipariş iadesi · ${request.totalQuantity} ürün'
                  : 'Seçili ürün iadesi · ${request.totalQuantity} ürün',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 6),
            for (final item in request.items)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Icon(Icons.subdirectory_arrow_right,
                        size: 16, color: Colors.grey.shade500),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        '${item.quantity} × ${item.productName}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    Text(
                      '₺${item.lineTotal.toStringAsFixed(2)}',
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            _box(
              color: Colors.amber,
              icon: Icons.report_problem_outlined,
              title: 'İade Sebebi',
              text: request.reason,
            ),
            if (request.adminResponse != null && request.adminResponse!.isNotEmpty) ...[
              const SizedBox(height: 8),
              _box(
                color: request.status == ReturnRequestStatus.rejected
                    ? Colors.red
                    : Colors.blue,
                icon: Icons.admin_panel_settings_outlined,
                title: 'Yönetici Yanıtı',
                text: request.adminResponse!,
              ),
            ],
            if (hint != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: style.color),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      hint,
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(
                    _formatDate(request.createdAt),
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      request.isSellerCashRefund
                          ? 'Satıcı nakit iade eder'
                          : (viewer == ReturnCardViewer.seller ? 'Müşteriye iade' : 'İade tutarı'),
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    ),
                    Text(
                      '₺${request.refundAmount.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.green.shade700,
                      ),
                    ),
                    if (showSellerAmount)
                      Text(
                        viewer == ReturnCardViewer.seller
                            ? 'Hesabınızdan düşülen: ₺${request.sellerDebitAmount.toStringAsFixed(2)}'
                            : 'Satıcıdan düşülen: ₺${request.sellerDebitAmount.toStringAsFixed(2)}',
                        style: TextStyle(fontSize: 11, color: Colors.red.shade700),
                      ),
                    if (showCommission)
                      Text(
                        viewer == ReturnCardViewer.seller
                            ? 'Komisyon borcunuzdan düşülen: ₺${request.commissionRefundAmount.toStringAsFixed(2)}'
                            : 'Komisyon borcundan düşülen: ₺${request.commissionRefundAmount.toStringAsFixed(2)}',
                        style: TextStyle(fontSize: 11, color: Colors.green.shade800),
                      ),
                  ],
                ),
              ],
            ),
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  for (var i = 0; i < actions.length; i++) ...[
                    if (i > 0) const SizedBox(width: 12),
                    Expanded(child: actions[i]),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _box({
    required MaterialColor color,
    required IconData icon,
    required String title,
    required String text,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color.shade700, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: color.shade900,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(text, style: TextStyle(fontSize: 13, color: Colors.grey.shade800)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _formatDate(DateTime d) {
    final l = d.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(l.day)}.${two(l.month)}.${l.year} ${two(l.hour)}:${two(l.minute)}';
  }
}
