import 'package:flutter/material.dart';

/// Siparişin iade durumu rozeti (orders.return_status, DB tetikleyicisi
/// doldurur). Satıcı, yönetici ve müşteri sipariş listelerinde ortak.
///
/// requested          → yönetici incelemesinde
/// approved           → onaylandı, satıcının ürünü teslim alması bekleniyor
/// partially_returned → bazı ürünler iade edildi
/// returned           → siparişin tamamı iade edildi
class OrderReturnBadge extends StatelessWidget {
  final String? returnStatus;
  final double returnedAmount;
  final VoidCallback? onTap;

  const OrderReturnBadge({
    super.key,
    required this.returnStatus,
    this.returnedAmount = 0,
    this.onTap,
  });

  static ({Color color, IconData icon, String label})? styleOf(
    String? returnStatus, {
    double returnedAmount = 0,
  }) {
    final amount = returnedAmount > 0 ? ' · ₺${returnedAmount.toStringAsFixed(2)}' : '';
    switch (returnStatus) {
      case 'requested':
        return (color: Colors.orange.shade800, icon: Icons.hourglass_top, label: 'İade talebi var');
      case 'approved':
        return (
          color: Colors.blue.shade700,
          icon: Icons.inventory_2_outlined,
          label: returnedAmount > 0
              ? 'İade yapıldı$amount · ürün teslim bekleniyor'
              : 'İade onaylandı · ürün teslim bekleniyor',
        );
      case 'partially_returned':
        return (color: Colors.purple.shade700, icon: Icons.assignment_return, label: 'Kısmi iade$amount');
      case 'returned':
        return (color: Colors.red.shade700, icon: Icons.assignment_return, label: 'İade edildi$amount');
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final style = styleOf(returnStatus, returnedAmount: returnedAmount);
    if (style == null) return const SizedBox.shrink();

    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: style.color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: style.color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(style.icon, size: 14, color: style.color),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              style.label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: style.color,
              ),
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 2),
            Icon(Icons.chevron_right, size: 16, color: style.color),
          ],
        ],
      ),
    );

    if (onTap == null) return chip;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: chip,
    );
  }
}
