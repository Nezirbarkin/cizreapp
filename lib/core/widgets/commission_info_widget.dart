import 'package:flutter/material.dart';
import '../models/order_model.dart';

/// Komisyon Bilgisi Widget - Sipariş detayında gösterilir
class CommissionInfoWidget extends StatelessWidget {
  final Order order;
  final bool isAdmin;

  const CommissionInfoWidget({
    super.key,
    required this.order,
    this.isAdmin = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    // Eğer komisyon bilgisi yoksa gösterme
    if (order.adminCommission == null && order.adminDeliveryFee == null) {
      return const SizedBox.shrink();
    }
    
    return Card(
      margin: const EdgeInsets.all(16),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: theme.colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.receipt_long,
                  color: theme.colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Komisyon Detayları',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            
            // Sipariş tutarı
            _buildRow(
              context,
              'Sipariş Tutarı',
              '₺${order.subtotal.toStringAsFixed(2)}',
            ),
            
            // Admin komisyonu
            if (order.adminCommission != null && order.adminCommission! > 0)
              _buildRow(
                context,
                isAdmin ? 'Admin Komisyonu' : 'Platform Komisyonu',
                '-₺${order.adminCommission!.toStringAsFixed(2)}',
                color: Colors.red,
              ),
            
            // Admin teslimat ücreti
            if (order.adminDeliveryFee != null && order.adminDeliveryFee! > 0)
              _buildRow(
                context,
                isAdmin ? 'Admin Teslimat Ücreti' : 'Teslimat Ücreti Kesintisi',
                '-₺${order.adminDeliveryFee!.toStringAsFixed(2)}',
                color: Colors.red,
              ),
            
            const Divider(height: 16),
            
            // Net ödeme
            if (order.sellerNetAmount != null)
              _buildRow(
                context,
                isAdmin ? 'Satıcı Net Ödeme' : 'Net Ödeme',
                '₺${order.sellerNetAmount!.toStringAsFixed(2)}',
                color: Colors.green,
                bold: true,
              ),
            
            const SizedBox(height: 8),
            
            // Komisyon durumu
            if (order.commissionStatus != null)
              _buildStatusBadge(context, order.commissionStatus!),
            
            // Borç uyarısı
            if (order.hasDebt)
              _buildDebtWarning(context, order.commissionDebt ?? 0),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(
    BuildContext context,
    String label,
    String value, {
    Color? color,
    bool bold = false,
  }) {
    final theme = Theme.of(context);
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.grey[700],
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: color,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(BuildContext context, CommissionStatus status) {
    Color badgeColor;
    IconData icon;
    
    switch (status) {
      case CommissionStatus.collected:
        badgeColor = Colors.green;
        icon = Icons.check_circle;
        break;
      case CommissionStatus.debt:
        badgeColor = Colors.orange;
        icon = Icons.warning;
        break;
      case CommissionStatus.waived:
        badgeColor = Colors.grey;
        icon = Icons.block;
        break;
      default:
        badgeColor = Colors.grey;
        icon = Icons.pending;
    }

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: badgeColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: badgeColor),
          const SizedBox(width: 8),
          Text(
            'Durum: ${status.label}',
            style: TextStyle(
              color: badgeColor,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDebtWarning(BuildContext context, double debtAmount) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning, color: Colors.orange),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isAdmin 
                      ? 'Satıcıdan Tahsil Edilecek Komisyon Borcu'
                      : 'Tahsil Edilecek Komisyon Borcu',
                  style: const TextStyle(
                    color: Colors.orange,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '₺${debtAmount.toStringAsFixed(2)}',
                  style: const TextStyle(color: Colors.orange),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Basit Komisyon Kartı - Dashboard vb. yerlerde kullanılır
class CommissionCard extends StatelessWidget {
  final String title;
  final double amount;
  final Color? color;
  final IconData icon;
  final String? subtitle;

  const CommissionCard({
    super.key,
    required this.title,
    required this.amount,
    this.color,
    required this.icon,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cardColor = color ?? theme.colorScheme.primary;
    
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: cardColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    icon,
                    color: cardColor,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.grey[600],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '₺${amount.toStringAsFixed(2)}',
              style: theme.textTheme.headlineSmall?.copyWith(
                color: cardColor,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.grey[600],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Satıcı Kazanç Kartı
class SellerEarningsCard extends StatelessWidget {
  final double totalSales;
  final double commissionAmount;
  final double netEarnings;
  final double debtAmount;

  const SellerEarningsCard({
    super.key,
    required this.totalSales,
    required this.commissionAmount,
    required this.netEarnings,
    this.debtAmount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.account_balance_wallet,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Kazanç Özeti',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            
            _buildRow('Toplam Satış', totalSales, Colors.grey),
            _buildRow('Platform Komisyonu', -commissionAmount, Colors.red),
            const Divider(),
            _buildRow('Net Kazanç', netEarnings, Colors.green, bold: true),
            
            if (debtAmount > 0) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning, color: Colors.orange, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Tahsil Edilecek Borç: ₺${debtAmount.toStringAsFixed(2)}',
                      style: const TextStyle(color: Colors.orange),
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

  Widget _buildRow(String label, double amount, Color color, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            '₺${amount.toStringAsFixed(2)}',
            style: TextStyle(
              color: color,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}
