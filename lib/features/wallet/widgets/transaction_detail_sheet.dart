import 'package:flutter/material.dart';
import '../../../core/models/balance_transaction_model.dart';

/// İşlem detayını modal bottom sheet olarak gösterir.
/// Son İşlemler ve İşlem Geçmişi ekranları ortak kullanır.
void showTransactionDetailSheet(
  BuildContext context,
  BalanceTransaction transaction,
) {
  final isPositive = transaction.isPositive;
  final amountColor = isPositive ? Colors.green : Colors.red;
  final hasBankInfo =
      transaction.bankName != null || transaction.bankAccountName != null;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return DraggableScrollableSheet(
        initialChildSize: 0.55,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) {
          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: amountColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        transaction.type.icon,
                        color: amountColor,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            transaction.type.label,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            transaction.formattedDate,
                            style: TextStyle(
                              color: Colors.grey.shade500,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      _detailRow(
                        'Tutar',
                        '${isPositive ? '+' : '-'}₺${transaction.absoluteAmount.toStringAsFixed(2)}',
                        valueColor: amountColor,
                        bold: true,
                      ),
                      if (transaction.fee > 0) ...[
                        const Divider(height: 20),
                        _detailRow(
                          'Ücret',
                          '₺${transaction.fee.toStringAsFixed(2)}',
                        ),
                        const Divider(height: 20),
                        _detailRow(
                          'Net Tutar',
                          '₺${transaction.netAmount.toStringAsFixed(2)}',
                          bold: true,
                        ),
                      ],
                      const Divider(height: 20),
                      _detailRow(
                        'İşlem Öncesi Bakiye',
                        '₺${transaction.balanceBefore.toStringAsFixed(2)}',
                      ),
                      const Divider(height: 20),
                      _detailRow(
                        'İşlem Sonrası Bakiye',
                        '₺${transaction.balanceAfter.toStringAsFixed(2)}',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _statusRow(transaction.status),
                if (transaction.description != null &&
                    transaction.description!.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Açıklama',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    transaction.description!,
                    style: const TextStyle(fontSize: 14),
                  ),
                ],
                if (hasBankInfo) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.account_balance_rounded,
                                size: 16, color: Colors.blue.shade700),
                            const SizedBox(width: 8),
                            Text(
                              'Banka Bilgileri',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.blue.shade700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (transaction.bankName != null)
                          Text('Banka: ${transaction.bankName}',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.blue.shade700)),
                        if (transaction.bankAccountName != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                                'Hesap: ${transaction.bankAccountName}',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.blue.shade700)),
                          ),
                        if (transaction.bankIban != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                                'IBAN: ${_maskIban(transaction.bankIban!)}',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.blue.shade700)),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      );
    },
  );
}

String _maskIban(String iban) {
  if (iban.length <= 8) return iban;
  return '${iban.substring(0, 4)}****${iban.substring(iban.length - 4)}';
}

Widget _detailRow(String label, String value,
    {Color? valueColor, bool bold = false}) {
  return Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(
        label,
        style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
      ),
      Text(
        value,
        style: TextStyle(
          color: valueColor,
          fontSize: bold ? 15 : 13,
          fontWeight: bold ? FontWeight.bold : FontWeight.w500,
        ),
      ),
    ],
  );
}

Widget _statusRow(BalanceTransactionStatus status) {
  Color color;
  String text;
  IconData icon;

  switch (status) {
    case BalanceTransactionStatus.completed:
      color = Colors.green;
      text = 'Tamamlandı';
      icon = Icons.check_circle_outline_rounded;
      break;
    case BalanceTransactionStatus.pending:
      color = Colors.orange;
      text = 'Beklemede';
      icon = Icons.schedule_rounded;
      break;
    case BalanceTransactionStatus.failed:
      color = Colors.red;
      text = 'Başarısız';
      icon = Icons.cancel_outlined;
      break;
    case BalanceTransactionStatus.cancelled:
      color = Colors.grey;
      text = 'İptal Edildi';
      icon = Icons.block_rounded;
      break;
  }

  return Row(
    children: [
      Icon(icon, size: 16, color: color),
      const SizedBox(width: 6),
      Text(
        'Durum: $text',
        style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600),
      ),
    ],
  );
}
