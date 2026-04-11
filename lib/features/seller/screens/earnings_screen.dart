import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/widgets/commission_info_widget.dart';
import '../../admin/services/commission_service.dart';

/// Satıcı Kazanç Ekranı
/// Komisyon özeti ve ödeme bilgilerini gösterir
class EarningsScreen extends StatefulWidget {
  const EarningsScreen({super.key});

  @override
  State<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends State<EarningsScreen> {
  final CommissionService _commissionService = CommissionService(Supabase.instance.client);
  
  bool _isLoading = true;
  SellerCommissionSummary? _summary;
  double _totalDebt = 0;
  String _selectedPeriod = '30';
  DateTime? _startDate;
  DateTime? _endDate;
  
  String? _sellerId;

  @override
  void initState() {
    super.initState();
    _sellerId = Supabase.instance.client.auth.currentUser?.id;
    _loadData();
  }

  Future<void> _loadData() async {
    if (_sellerId == null) return;
    
    setState(() => _isLoading = true);
    
    try {
      final summary = await _commissionService.getSellerCommissionSummary(
        _sellerId!,
        startDate: _startDate,
        endDate: _endDate,
      );
      
      final debt = await _commissionService.getTotalDebtAmount(sellerId: _sellerId);
      
      setState(() {
        _summary = summary;
        _totalDebt = debt;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Veriler yüklenemedi: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kazançlarım'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildPeriodSelector(),
                    const SizedBox(height: 16),
                    if (_summary != null) ...[
                      _buildNetEarningsCard(),
                      const SizedBox(height: 16),
                      _buildCommissionBreakdown(),
                      const SizedBox(height: 16),
                      if (_totalDebt > 0) _buildDebtWarning(),
                      const SizedBox(height: 16),
                      _buildPayoutInfo(),
                    ],
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildPeriodSelector() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Tarih Aralığı', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                _PeriodChip(
                  label: 'Son 7 Gün',
                  value: '7',
                  selectedValue: _selectedPeriod,
                  onTap: () => _selectPeriod('7'),
                ),
                _PeriodChip(
                  label: 'Son 30 Gün',
                  value: '30',
                  selectedValue: _selectedPeriod,
                  onTap: () => _selectPeriod('30'),
                ),
                _PeriodChip(
                  label: 'Bu Ay',
                  value: 'month',
                  selectedValue: _selectedPeriod,
                  onTap: () => _selectPeriod('month'),
                ),
                _PeriodChip(
                  label: 'Bu Yıl',
                  value: 'year',
                  selectedValue: _selectedPeriod,
                  onTap: () => _selectPeriod('year'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _selectPeriod(String period) {
    setState(() {
      _selectedPeriod = period;
      final now = DateTime.now();
      
      switch (period) {
        case '7':
          _startDate = now.subtract(const Duration(days: 7));
          _endDate = now;
          break;
        case '30':
          _startDate = now.subtract(const Duration(days: 30));
          _endDate = now;
          break;
        case 'month':
          _startDate = DateTime(now.year, now.month, 1);
          _endDate = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
          break;
        case 'year':
          _startDate = DateTime(now.year, 1, 1);
          _endDate = DateTime(now.year, 12, 31, 23, 59, 59);
          break;
      }
    });
    _loadData();
  }

  Widget _buildNetEarningsCard() {
    return SellerEarningsCard(
      totalSales: _summary!.totalSales,
      commissionAmount: _summary!.totalCommission,
      netEarnings: _summary!.netEarnings,
      debtAmount: _totalDebt,
    );
  }

  Widget _buildCommissionBreakdown() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Komisyon Detayları',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            _buildDetailRow('Toplam Sipariş', '${_summary!.totalOrders} adet'),
            _buildDetailRow('Toplam Satış', '₺${_summary!.totalSales.toStringAsFixed(2)}'),
            _buildDetailRow(
              'Toplam Komisyon',
              '₺${_summary!.totalCommission.toStringAsFixed(2)}',
              color: Colors.red,
            ),
            _buildDetailRow(
              'Tahsil Edilen',
              '₺${_summary!.collectedCommission.toStringAsFixed(2)}',
              color: Colors.green,
            ),
            _buildDetailRow(
              'Borç Bekleyen',
              '₺${_summary!.debtCommission.toStringAsFixed(2)}',
              color: Colors.orange,
            ),
            const Divider(height: 24),
            _buildDetailRow(
              'Net Kazanç',
              '₺${_summary!.netEarnings.toStringAsFixed(2)}',
              color: Colors.green,
              bold: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {Color? color, bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDebtWarning() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning, color: Colors.orange),
              const SizedBox(width: 12),
              Text(
                'Borç Uyarısı',
                style: TextStyle(
                  color: Colors.orange,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Kapıda ödemeli siparişler için tahsil edilecek ₺${_totalDebt.toStringAsFixed(2)} komisyon borcunuz bulunmaktadır.',
            style: const TextStyle(color: Colors.orange),
          ),
          const SizedBox(height: 12),
          const Text(
            'Bu borç, bir sonraki ödeme talebinizden düşülecektir.',
            style: TextStyle(
              fontSize: 12,
              color: Colors.orange,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPayoutInfo() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.account_balance_wallet,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                const Text(
                  'Ödeme Bilgileri',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            _buildPayoutRow(
              'Bekleyen Ödeme',
              '₺${_summary!.pendingPayout.toStringAsFixed(2)}',
              Colors.blue,
            ),
            const SizedBox(height: 8),
            Text(
              'Minimum ödeme tutarı: ₺100.00',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _summary!.pendingPayout >= 100
                    ? () {
                        // Ödeme talep sayfasına git
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Ödeme talebi oluşturuluyor...')),
                        );
                      }
                    : null,
                icon: const Icon(Icons.payment),
                label: const Text('Ödeme Talep Et'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPayoutRow(String label, String value, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ],
    );
  }
}

class _PeriodChip extends StatelessWidget {
  final String label;
  final String value;
  final String selectedValue;
  final VoidCallback onTap;

  const _PeriodChip({
    required this.label,
    required this.value,
    required this.selectedValue,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = value == selectedValue;
    
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => onTap(),
      selectedColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
      checkmarkColor: Theme.of(context).colorScheme.primary,
    );
  }
}
