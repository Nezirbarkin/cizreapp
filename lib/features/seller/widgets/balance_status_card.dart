// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import '../services/payout_service.dart';

/// Satıcının borç/alacak durumunu gösteren card widget
/// 
/// YENİ MANTIK:
/// - Kuryesi OLAN: Kapıda ödeme kazancı + Online alacak - Komisyon borcu
/// - Kuryesi OLMAYAN: Online alacak (teslimat ve komisyon zaten düşülmüş)
class BalanceStatusCard extends StatelessWidget {
  final String shopId;
  final PayoutService payoutService;

  const BalanceStatusCard({
    super.key,
    required this.shopId,
    required this.payoutService,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _loadBalanceData(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: SizedBox(
                  width: 30,
                  height: 30,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.orange.shade700),
                  ),
                ),
              ),
            ),
          );
        }

        if (snapshot.hasError) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Bilgi yüklenemedi: ${snapshot.error}',
                style: TextStyle(color: Colors.red.shade600),
              ),
            ),
          );
        }

        final data = snapshot.data ?? {};
        final hasCourier = data['has_courier'] as bool? ?? false;
        final commissionDebt = data['commission_debt'] as double? ?? 0;
        final adminCredit = data['admin_credit'] as double? ?? 0;
        final cashRevenue = data['cash_revenue'] as double? ?? 0;
        final onlineRevenue = data['online_revenue'] as double? ?? 0;
        final netPayable = data['net_payable'] as double? ?? 0;
        final totalPaid = data['total_paid'] as double? ?? 0;

        return Card(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Başlık
                Row(
                  children: [
                    Icon(
                      Icons.account_balance_wallet,
                      color: Colors.orange.shade700,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Ödeme Durumu',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 16),

                // Şimdiye kadar toplam kazanç
                if (totalPaid > 0)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.purple.shade700, Colors.purple.shade500],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.purple.withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Şimdiye Kadar Toplam Kazanç',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white.withOpacity(0.9),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '₺${totalPaid.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                        Icon(Icons.history, color: Colors.white.withOpacity(0.9), size: 32),
                      ],
                    ),
                  ),

                if (totalPaid > 0) const SizedBox(height: 16),
                if (totalPaid > 0) const Divider(),
                if (totalPaid > 0) const SizedBox(height: 16),

                // Kuryesi durumu bilgisi
                if (hasCourier)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.local_shipping, color: Colors.blue.shade700, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '✓ Kendi kuriyeniz var',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.blue.shade700,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.purple.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.purple.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.delivery_dining, color: Colors.purple.shade700, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Platform kargosunu kullanıyorsunuz',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.purple.shade700,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 16),

                // Gelir Dağılımı
                if (cashRevenue > 0 || onlineRevenue > 0) ...[
                  Text(
                    'Gelir Dağılımı',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (cashRevenue > 0)
                    _buildRevenueRow(
                      hasCourier ? 'Kapıda Ödeme Kazancı' : 'Kapıda Kazanç',
                      cashRevenue,
                      Colors.green,
                      Icons.money,
                    ),
                  if (onlineRevenue > 0) const SizedBox(height: 8),
                  if (onlineRevenue > 0)
                    _buildRevenueRow(
                      hasCourier ? 'Online Ödeme Kazancı' : 'Online Alacak',
                      onlineRevenue,
                      Colors.blue,
                      Icons.credit_card,
                    ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 16),
                ],

                // Alacak durumu
                if (adminCredit > 0)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Admin\'den Alacak',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.green.shade700,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '₺${adminCredit.toStringAsFixed(2)}',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.green.shade700,
                              ),
                            ),
                          ],
                        ),
                        Icon(Icons.trending_up, color: Colors.green.shade700, size: 28),
                      ],
                    ),
                  ),

                if (adminCredit > 0 && commissionDebt > 0) const SizedBox(height: 12),

                // Komisyon borcu (sadece kuryesi olan için)
                if (hasCourier && commissionDebt > 0)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Komisyon Borcu',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.orange.shade700,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '₺${commissionDebt.toStringAsFixed(2)}',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.orange.shade700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Kapıda ödemelerden',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.orange.shade600,
                              ),
                            ),
                          ],
                        ),
                        Icon(Icons.trending_down, color: Colors.orange.shade700, size: 28),
                      ],
                    ),
                  ),

                if ((adminCredit > 0 || (hasCourier && commissionDebt > 0)))
                  const SizedBox(height: 16),

                if ((adminCredit > 0 || (hasCourier && commissionDebt > 0)))
                  const Divider(),

                if ((adminCredit > 0 || (hasCourier && commissionDebt > 0)))
                  const SizedBox(height: 16),

                // Net ödeme tutarı
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: netPayable > 0
                          ? [Colors.blue.shade700, Colors.blue.shade500]
                          : [Colors.grey.shade600, Colors.grey.shade400],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: (netPayable > 0 ? Colors.blue : Colors.grey).withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              'Ödeme İsteğinde Alacağınız',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.white.withOpacity(0.9),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          Icon(
                            netPayable > 0 ? Icons.check_circle : Icons.info,
                            color: Colors.white,
                            size: 20,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '₺${netPayable.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      if (hasCourier && commissionDebt > 0) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Alacak - Borç = Net tutar',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.white.withOpacity(0.8),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // Açıklama mesajı
                if (netPayable <= 0) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline, color: Colors.red.shade700, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            hasCourier
                                ? 'Komisyon borcunuz olduğu için şu an ödeme isteği oluşturamazsınız. Online ödemeler ile borç kapatıldıkça ödeme alabilirsiniz.'
                                : 'Henüz ödenebilir bakiyeniz bulunmuyor. Siparişleriniz teslim edildikçe bakiyeniz artacaktır.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.red.shade700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else if (hasCourier) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.lightbulb_outline, color: Colors.blue.shade700, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Online ödemelerden gelen alacak, kapıda ödemelerden oluşan komisyon borcunuzu karşılar.',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.blue.shade700,
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
      },
    );
  }

  Widget _buildRevenueRow(String label, double amount, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: color.withOpacity(0.8),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Text(
            '₺${amount.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Future<Map<String, dynamic>> _loadBalanceData() async {
    final summary = await payoutService.getRevenueSummary(shopId);
    final netPayable = await payoutService.getNetPayableAmount(shopId);
    final totalPaid = await payoutService.getTotalPaidAmount(shopId);

    return {
      'has_courier': summary['has_courier'],
      'commission_debt': summary['commission_debt'],
      'admin_credit': summary['admin_credit'],
      'cash_revenue': summary['cash_payment_revenue'],
      'online_revenue': summary['online_payment_revenue'],
      'net_payable': netPayable,
      'total_paid': totalPaid,
    };
  }
}
