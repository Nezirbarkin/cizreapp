import 'package:flutter/material.dart';

import '../../../shop/services/return_request_service.dart';
import '../../screens/seller_return_requests_screen.dart';

/// Satıcı "Genel Bakış" iade kartı: incelemede / teslim bekleyen /
/// tamamlanan iade sayıları, iade edilen toplam ve hesaptan düşülen tutar.
/// Dokununca İade Talepleri ekranı açılır; dönüşte yenilenir.
///
/// Veri `seller_return_summary` RPC'sinden kendi başına yüklenir
/// (Genel Bakış'ın geri kalanı SellerDashboardScreen'den beslenir).
class SellerReturnsSummaryCard extends StatefulWidget {
  const SellerReturnsSummaryCard({super.key, this.summaryLoader});

  /// Testlerde sahte veri vermek için; varsayılan RPC'dir.
  final Future<Map<String, dynamic>> Function()? summaryLoader;

  @override
  State<SellerReturnsSummaryCard> createState() => _SellerReturnsSummaryCardState();
}

class _SellerReturnsSummaryCardState extends State<SellerReturnsSummaryCard> {
  Map<String, dynamic>? _summary;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await (widget.summaryLoader ?? ReturnRequestService().getSellerSummary)();
      if (!mounted) return;
      setState(() => _summary = data);
    } catch (e) {
      debugPrint('⚠️ İade özeti yüklenemedi: $e');
    }
  }

  int _int(String key) => (_summary?[key] as num?)?.toInt() ?? 0;
  double _double(String key) => (_summary?[key] as num?)?.toDouble() ?? 0;

  Future<void> _open() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SellerReturnRequestsScreen()),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final pending = _int('pending');
    final awaiting = _int('awaiting_receipt');
    final completed = _int('completed');
    final refunded = _double('refunded_total');
    final debit = _double('seller_debit_total');
    final needsAction = awaiting > 0;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _open,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.teal.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.assignment_return, color: Colors.teal.shade700),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'İade Edilen Ürünler',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                  Icon(Icons.chevron_right, color: Colors.grey.shade500),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  _metric('İncelemede', '$pending', Colors.orange.shade800),
                  _metric('Teslim bekleyen', '$awaiting', Colors.blue.shade700),
                  _metric('Tamamlanan', '$completed', Colors.green.shade700),
                ],
              ),
              const Divider(height: 24),
              Row(
                children: [
                  Expanded(
                    child: _amount('Müşteriye iade edilen', refunded, Colors.grey.shade800),
                  ),
                  Expanded(
                    child: _amount('Hesabınızdan düşülen', debit, Colors.red.shade700),
                  ),
                ],
              ),
              if (needsAction) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.inventory_2_outlined, size: 18, color: Colors.blue.shade700),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '$awaiting iadede ürünleri teslim alınca "Teslim Aldım" deyin.',
                          style: TextStyle(fontSize: 12, color: Colors.blue.shade900),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _metric(String label, String value, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _amount(String label, double value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        const SizedBox(height: 2),
        Text(
          '₺${value.toStringAsFixed(2)}',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color),
        ),
      ],
    );
  }
}
